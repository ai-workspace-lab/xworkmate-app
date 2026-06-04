import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'acp_endpoint_paths.dart';
import 'gateway_acp_client.dart';
import 'go_task_service_client.dart';
import 'runtime_models.dart';

class ExternalCodeAgentAcpDesktopTransport
    implements ExternalCodeAgentAcpTransport {
  ExternalCodeAgentAcpDesktopTransport({
    required GatewayAcpClient client,
    required Uri? Function(AssistantExecutionTarget target) endpointResolver,
    Uri? Function(GoTaskServiceRequest request)? taskEndpointResolver,
    Duration recoveryPollDelay = const Duration(seconds: 2),
    int? recoveryMaxAttempts,
  }) : _client = client,
       _endpointResolver = endpointResolver,
       _taskEndpointResolver = taskEndpointResolver,
       _recoveryPollDelay = recoveryPollDelay,
       _recoveryMaxAttempts = recoveryMaxAttempts;

  final GatewayAcpClient _client;
  final Uri? Function(AssistantExecutionTarget target) _endpointResolver;
  final Uri? Function(GoTaskServiceRequest request)? _taskEndpointResolver;
  final Duration _recoveryPollDelay;
  final int? _recoveryMaxAttempts;

  @visibleForTesting
  GatewayAcpClient get clientForTest => _client;

  @override
  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async {
    final response = await _client.request(
      method: 'acp.capabilities',
      params: const <String, dynamic>{},
      endpointOverride: _endpointResolver(target),
    );
    final result = _castMap(response['result']);
    final caps = _castMap(result['capabilities']);
    final providerCatalog = _parseProviderCatalog(
      result['providerCatalog'] ?? caps['providerCatalog'],
      defaultTarget: AssistantExecutionTarget.agent,
    );
    final gatewayProviders = _parseProviderCatalog(
      result['gatewayProviders'] ?? caps['gatewayProviders'],
      defaultTarget: AssistantExecutionTarget.gateway,
    );
    return ExternalCodeAgentAcpCapabilities(
      singleAgent:
          _boolValue(result['singleAgent']) ??
          _boolValue(caps['single_agent']) ??
          providerCatalog.isNotEmpty,
      multiAgent:
          _boolValue(result['multiAgent']) ??
          _boolValue(caps['multi_agent']) ??
          true,
      availableExecutionTargets: _parseAvailableExecutionTargets(
        result['availableExecutionTargets'] ??
            caps['availableExecutionTargets'],
        singleAgent:
            _boolValue(result['singleAgent']) ??
            _boolValue(caps['single_agent']) ??
            providerCatalog.isNotEmpty,
        gatewayProviders: gatewayProviders,
      ),
      providerCatalog: providerCatalog,
      gatewayProviders: gatewayProviders,
      raw: result,
    );
  }

  @override
  Future<ExternalCodeAgentAcpRoutingResolution> resolveExternalAcpRouting({
    required String taskPrompt,
    required String workingDirectory,
    required ExternalCodeAgentAcpRoutingConfig routing,
  }) async {
    final response = await _client.request(
      method: 'xworkmate.routing.resolve',
      params: <String, dynamic>{
        'taskPrompt': taskPrompt,
        'workingDirectory': workingDirectory.trim(),
        'routing': routing.toJson(),
      },
      endpointOverride: _endpointResolver(AssistantExecutionTarget.gateway),
    );
    return ExternalCodeAgentAcpRoutingResolution(
      raw: _castMap(response['result']),
    );
  }

  @override
  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) async {
    var streamedText = '';
    String? completedMessage;
    Map<String, dynamic>? completedResultSnapshot;
    Map<String, dynamic>? runningTaskSnapshot;
    try {
      final endpointOverride = _taskEndpointResolver == null
          ? _endpointResolver(request.target)
          : _taskEndpointResolver.call(request);
      if (endpointOverride == null) {
        throw const GatewayAcpException(
          'xworkmate-bridge is not connected',
          code: 'BRIDGE_NOT_CONNECTED',
        );
      }
      final response = await _client.request(
        method: request.resumeSession ? 'session.message' : 'session.start',
        params: request.toExternalAcpParams(),
        endpointOverride: endpointOverride,
        onNotification: (notification) {
          final update = goTaskServiceUpdateFromAcpNotification(notification);
          if (update == null) {
            return;
          }
          if (update.sessionId != request.sessionId ||
              update.threadId != request.threadId) {
            return;
          }
          if (update.isDelta) {
            streamedText += update.text;
          }
          if (update.isDone && update.message.trim().isNotEmpty) {
            completedMessage = update.message.trim();
            completedResultSnapshot = _completedResultSnapshotFromUpdate(
              update,
            );
          }
          if (update.payload['status']?.toString().trim().toLowerCase() ==
                  'running' &&
              (update.payload['runId']?.toString().trim().isNotEmpty == true)) {
            runningTaskSnapshot = <String, dynamic>{...update.payload};
          }
          onUpdate(update);
        },
      );
      return goTaskServiceResultFromAcpResponse(
        response,
        route: request.route,
        streamedText: streamedText,
        completedMessage: completedMessage,
      );
    } on GatewayAcpException catch (error) {
      if (_isRecoverableTaskStreamClosure(error)) {
        final recovered = await _recoverTaskResultAfterStreamClosure(
          request,
          taskEndpoint: _taskEndpointResolver == null
              ? _endpointResolver(request.target)
              : _taskEndpointResolver.call(request),
          streamedText: streamedText,
          completedMessage: completedMessage,
          fallbackAvailable: completedResultSnapshot != null,
          runningTaskSnapshot: runningTaskSnapshot,
        );
        if (recovered != null) {
          return recovered;
        }
        if (completedResultSnapshot != null) {
          return goTaskServiceResultFromAcpResponse(
            <String, dynamic>{
              'jsonrpc': '2.0',
              'id': 'recovered-from-completed-session-update',
              'result': completedResultSnapshot,
            },
            route: request.route,
            streamedText: streamedText,
            completedMessage: completedMessage,
          );
        }
      }
      rethrow;
    } on SocketException catch (error) {
      final timeout = _socketExceptionLooksLikeConnectTimeout(error);
      throw GatewayAcpException(
        timeout
            ? 'ACP HTTP connection timed out before the request was confirmed'
            : 'ACP HTTP connection failed before the request was confirmed',
        code: timeout
            ? gatewayAcpHttpConnectTimeoutCode
            : gatewayAcpHttpConnectFailedCode,
        details: <String, dynamic>{'originalError': error.toString()},
      );
    } catch (error) {
      throw GatewayAcpException(
        error.toString(),
        code: 'EXTERNAL_ACP_GATEWAY_ERROR',
      );
    }
  }

  bool _isRecoverableTaskStreamClosure(GatewayAcpException error) {
    return error.code == 'ACP_HTTP_CONNECTION_CLOSED' ||
        error.code == 'ACP_SSE_NO_RESULT';
  }

  Future<GoTaskServiceResult?> _recoverTaskResultAfterStreamClosure(
    GoTaskServiceRequest request, {
    required Uri? taskEndpoint,
    required String streamedText,
    required String? completedMessage,
    bool fallbackAvailable = false,
    Map<String, dynamic>? runningTaskSnapshot,
  }) async {
    final endpoint = _sessionSnapshotEndpoint(taskEndpoint);
    if (endpoint == null) {
      return null;
    }
    final association = OpenClawTaskAssociation.fromJsonOrNull(
      runningTaskSnapshot,
    );
    final attempts = _recoveryAttemptsForRequest(request);
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      if (attempt > 0) {
        await Future<void>.delayed(_recoveryPollDelay);
      }
      Map<String, dynamic> response;
      try {
        response = await _client.request(
          method: 'xworkmate.tasks.get',
          params: association?.toTaskGetParams() ??
              <String, dynamic>{
                'sessionId': request.sessionId,
                'threadId': request.threadId,
              },
          endpointOverride: endpoint,
        );
      } on GatewayAcpException {
        if (fallbackAvailable) {
          return null;
        }
        continue;
      } on SocketException {
        continue;
      }
      final snapshot = _castMap(response['result']);
      final status = (snapshot['status'] ?? '').toString().trim().toLowerCase();
      final terminal =
          status == 'completed' ||
          status == 'failed' ||
          status == 'cancelled' ||
          status == 'canceled';
      if (!terminal) {
        continue;
      }
      if (status == 'failed' || status == 'cancelled' || status == 'canceled') {
        return goTaskServiceResultFromAcpResponse(
          <String, dynamic>{
            'jsonrpc': '2.0',
            'id': 'recovered-from-terminal-task-snapshot',
            'result': _failureResultFromTaskSnapshot(snapshot, status),
          },
          route: request.route,
          streamedText: streamedText,
          completedMessage: completedMessage,
        );
      }
      final result = _recoveredResultFromTaskSnapshot(snapshot);
      if (result.isNotEmpty) {
        return goTaskServiceResultFromAcpResponse(
          <String, dynamic>{
            'jsonrpc': '2.0',
            'id': 'recovered-from-session-snapshot',
            'result': result,
          },
          route: request.route,
          streamedText: streamedText,
          completedMessage: completedMessage,
        );
      }
    }
    return null;
  }

  @override
  Future<GoTaskServiceResult> getTask({
    required AssistantExecutionTarget target,
    required OpenClawTaskAssociation association,
    required GoTaskServiceRoute route,
  }) async {
    final endpoint = _sessionSnapshotEndpoint(_endpointResolver(target));
    if (endpoint == null) {
      throw const GatewayAcpException(
        'xworkmate-bridge is not connected',
        code: 'BRIDGE_NOT_CONNECTED',
      );
    }
    final response = await _client.request(
      method: 'xworkmate.tasks.get',
      params: association.toTaskGetParams(),
      endpointOverride: endpoint,
    );
    return goTaskServiceResultFromAcpResponse(response, route: route);
  }

  int _recoveryAttemptsForRequest(GoTaskServiceRequest request) {
    final configured = _recoveryMaxAttempts;
    if (configured != null) {
      return configured <= 0 ? 1 : configured;
    }
    return 1;
  }

  Uri? _sessionSnapshotEndpoint(Uri? taskEndpoint) {
    final controlEndpoint = resolveAcpHttpRpcEndpoint(
      _endpointResolver(AssistantExecutionTarget.gateway),
    );
    if (controlEndpoint != null) {
      return controlEndpoint;
    }
    return resolveAcpHttpRpcEndpoint(taskEndpoint);
  }

  @override
  Future<void> cancelTask({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
    OpenClawTaskAssociation? association,
  }) async {
    if (association != null) {
      final endpoint = _sessionSnapshotEndpoint(_endpointResolver(target));
      if (endpoint != null) {
        await _client.request(
          method: 'xworkmate.tasks.cancel',
          params: association.toTaskGetParams(),
          endpointOverride: endpoint,
        );
        return;
      }
    }
    await _client.cancelSession(
      sessionId: sessionId,
      threadId: threadId,
      endpointOverride: _endpointResolver(target),
    );
  }

  @override
  Future<void> closeTask({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {
    await _client.closeSession(
      sessionId: sessionId,
      threadId: threadId,
      endpointOverride: _endpointResolver(target),
    );
  }

  @override
  Future<void> dispose() => _client.dispose();

  Map<String, dynamic>? _completedResultSnapshotFromUpdate(
    GoTaskServiceUpdate update,
  ) {
    if (!update.isDone) {
      return null;
    }
    final payload = update.payload;
    final embeddedResult = _castMap(payload['result']);
    final snapshot = <String, dynamic>{...embeddedResult, ...payload};
    snapshot.remove('sessionId');
    snapshot.remove('threadId');
    snapshot.remove('type');
    snapshot.remove('event');
    snapshot.remove('pending');
    snapshot.remove('result');
    snapshot['turnId'] = update.turnId;
    snapshot['success'] = !update.error;
    final text = _firstNonEmptyDisplayText(snapshot, const <String>[
      'output',
      'message',
      'summary',
      'text',
      'delta',
    ]);
    if (text.isNotEmpty) {
      snapshot['output'] = text;
      snapshot['message'] = text;
      snapshot['summary'] = text;
    }
    return snapshot;
  }

  Map<String, dynamic> _recoveredResultFromTaskSnapshot(
    Map<String, dynamic> snapshot,
  ) {
    final result = <String, dynamic>{
      ..._castMap(snapshot['result']),
      ...snapshot,
    };
    final artifactRecord = _castMap(snapshot['artifacts']);
    final artifactItems = artifactRecord['items'];
    if (artifactItems is List && result['artifacts'] == artifactRecord) {
      result['artifacts'] = artifactItems;
    }
    for (final entry in <String, String>{
      'remoteWorkingDirectory': 'remoteWorkingDirectory',
      'remoteWorkspaceRefKind': 'remoteWorkspaceRefKind',
      'resultSummary': 'summary',
    }.entries) {
      final value = artifactRecord[entry.key]?.toString().trim() ?? '';
      if (value.isNotEmpty &&
          (result[entry.value]?.toString().trim().isEmpty ?? true)) {
        result[entry.value] = value;
      }
    }
    return result;
  }

  Map<String, dynamic> _failureResultFromTaskSnapshot(
    Map<String, dynamic> snapshot,
    String status,
  ) {
    final error = _castMap(snapshot['error']);
    final message = _firstNonEmptyDisplayText(
      <String, dynamic>{...error, ...snapshot},
      const <String>['message', 'error', 'errorMessage', 'reason', 'code'],
    );
    final code = _firstNonEmptyDisplayText(
      <String, dynamic>{...error, ...snapshot},
      const <String>['code', 'errorCode'],
    );
    final result = <String, dynamic>{
      'success': false,
      'status': status,
      'turnId': snapshot['turnId']?.toString().trim() ?? '',
      'error': message.isNotEmpty ? message : 'Bridge session ended: $status',
      'message': message.isNotEmpty ? message : 'Bridge session ended: $status',
    };
    if (code.isNotEmpty) {
      result['code'] = code;
    }
    return result;
  }

  String _firstNonEmptyDisplayText(
    Map<String, dynamic> values,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = _displayText(values[key]).trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _displayText(Object? value, [Set<Object>? visited]) {
    final seen = visited ?? <Object>{};
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value.trim();
    }
    if (value is Map) {
      if (!seen.add(value)) {
        return '';
      }
      final map = value.cast<String, dynamic>();
      for (final key in const <String>[
        'output',
        'summary',
        'resultSummary',
        'message',
        'content',
        'text',
        'delta',
        'output_text',
      ]) {
        final extracted = _displayText(map[key], seen);
        if (extracted.isNotEmpty) {
          return extracted;
        }
      }
      for (final key in const <String>['result', 'payload', 'data']) {
        final extracted = _displayText(map[key], seen);
        if (extracted.isNotEmpty) {
          return extracted;
        }
      }
      return '';
    }
    if (value is List) {
      if (!seen.add(value)) {
        return '';
      }
      return value
          .map((item) => _displayText(item, seen))
          .where((item) => item.isNotEmpty)
          .join('\n')
          .trim();
    }
    return value.toString().trim();
  }

  Map<String, dynamic> _castMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  List<Object?> _asList(Object? raw) {
    if (raw is List<Object?>) {
      return raw;
    }
    if (raw is List) {
      return raw.cast<Object?>();
    }
    return const <Object?>[];
  }

  bool? _boolValue(Object? raw) {
    if (raw is bool) {
      return raw;
    }
    if (raw is num) {
      return raw != 0;
    }
    final text = raw?.toString().trim().toLowerCase();
    if (text == null || text.isEmpty) {
      return null;
    }
    if (text == 'true' || text == '1' || text == 'yes') {
      return true;
    }
    if (text == 'false' || text == '0' || text == 'no') {
      return false;
    }
    return null;
  }

  List<SingleAgentProvider> _parseProviderCatalog(
    Object? raw, {
    required AssistantExecutionTarget defaultTarget,
  }) {
    final providers = <SingleAgentProvider>[];
    for (final item in _asList(raw)) {
      final entry = _castMap(item);
      final providerId = entry['providerId']?.toString().trim() ?? '';
      if (providerId.isEmpty) {
        continue;
      }
      final label = entry['label']?.toString().trim();
      final providerDisplay = _castMap(entry['providerDisplay']);
      final targets = _parseProviderTargets(
        entry['targets'] ?? entry['executionTarget'],
        defaultTarget: defaultTarget,
      );
      final provider = SingleAgentProviderCopy.fromJsonValue(
        providerId,
        label: label?.isNotEmpty == true ? label : null,
        badge: entry['badge']?.toString().trim().isNotEmpty == true
            ? entry['badge']?.toString().trim()
            : providerDisplay['badge']?.toString().trim(),
        logoEmoji: entry['logoEmoji']?.toString().trim().isNotEmpty == true
            ? entry['logoEmoji']?.toString().trim()
            : providerDisplay['logoEmoji']?.toString().trim(),
        supportedTargets: targets,
        enabled: _boolValue(entry['enabled']) ?? true,
        unavailableReason:
            entry['unavailableReason']?.toString().trim().isNotEmpty == true
            ? entry['unavailableReason']?.toString().trim()
            : '',
      );
      if (!provider.isUnspecified) {
        providers.add(provider);
      }
    }
    return normalizeSingleAgentProviderList(providers);
  }

  List<AssistantExecutionTarget> _parseAvailableExecutionTargets(
    Object? raw, {
    required bool singleAgent,
    required List<SingleAgentProvider> gatewayProviders,
  }) {
    final parsed = <AssistantExecutionTarget>[];
    for (final item in _asList(raw)) {
      final normalized = item?.toString().trim().toLowerCase() ?? '';
      if (normalized == 'agent' || normalized == 'single-agent') {
        if (!parsed.contains(AssistantExecutionTarget.agent)) {
          parsed.add(AssistantExecutionTarget.agent);
        }
      } else if (normalized == 'gateway') {
        if (!parsed.contains(AssistantExecutionTarget.gateway)) {
          parsed.add(AssistantExecutionTarget.gateway);
        }
      }
    }
    if (parsed.isNotEmpty) {
      return parsed;
    }
    if (singleAgent) {
      parsed.add(AssistantExecutionTarget.agent);
    }
    if (gatewayProviders.isNotEmpty) {
      parsed.add(AssistantExecutionTarget.gateway);
    }
    return parsed;
  }

  List<AssistantExecutionTarget> _parseProviderTargets(
    Object? raw, {
    required AssistantExecutionTarget defaultTarget,
  }) {
    final parsed = <AssistantExecutionTarget>[];
    final items = raw is List ? raw : <Object?>[raw];
    for (final item in items) {
      final normalized = item?.toString().trim().toLowerCase() ?? '';
      if (normalized == 'agent' || normalized == 'single-agent') {
        if (!parsed.contains(AssistantExecutionTarget.agent)) {
          parsed.add(AssistantExecutionTarget.agent);
        }
      } else if (normalized == 'gateway') {
        if (!parsed.contains(AssistantExecutionTarget.gateway)) {
          parsed.add(AssistantExecutionTarget.gateway);
        }
      }
    }
    if (parsed.isNotEmpty) {
      return parsed;
    }
    return <AssistantExecutionTarget>[defaultTarget];
  }

  bool _socketExceptionLooksLikeConnectTimeout(SocketException error) {
    final lowered = error.toString().toLowerCase();
    return lowered.contains('connection timed out') ||
        lowered.contains('timed out') ||
        lowered.contains('timeout');
  }
}
