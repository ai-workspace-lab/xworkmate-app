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
    int recoveryMaxAttempts = 300,
  }) : _client = client,
       _endpointResolver = endpointResolver,
       _taskEndpointResolver = taskEndpointResolver,
       _recoveryPollDelay = recoveryPollDelay,
       _recoveryMaxAttempts = recoveryMaxAttempts;

  final GatewayAcpClient _client;
  final Uri? Function(AssistantExecutionTarget target) _endpointResolver;
  final Uri? Function(GoTaskServiceRequest request)? _taskEndpointResolver;
  final Duration _recoveryPollDelay;
  final int _recoveryMaxAttempts;

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
      if (_isRecoverableTaskStreamClosure(error) &&
          completedResultSnapshot != null) {
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
      if (_isRecoverableTaskStreamClosure(error)) {
        final recovered = await _recoverTaskResultAfterStreamClosure(
          request,
          taskEndpoint: _taskEndpointResolver == null
              ? _endpointResolver(request.target)
              : _taskEndpointResolver.call(request),
          streamedText: streamedText,
          completedMessage: completedMessage,
        );
        if (recovered != null) {
          return recovered;
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
  }) async {
    final endpoint = _sessionSnapshotEndpoint(taskEndpoint);
    if (endpoint == null) {
      return null;
    }
    final attempts = _recoveryMaxAttempts <= 0 ? 1 : _recoveryMaxAttempts;
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      if (attempt > 0) {
        await Future<void>.delayed(_recoveryPollDelay);
      }
      Map<String, dynamic> response;
      try {
        response = await _client.request(
          method: 'xworkmate.sessions.get',
          params: <String, dynamic>{
            'sessionId': request.sessionId,
            'threadId': request.threadId,
          },
          endpointOverride: endpoint,
        );
      } on GatewayAcpException {
        continue;
      } on SocketException {
        continue;
      }
      final snapshot = _castMap(response['result']);
      final task = _castMap(snapshot['task']);
      final status = (task['state'] ?? snapshot['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final terminal =
          status == 'completed' ||
          status == 'failed' ||
          status == 'cancelled' ||
          status == 'canceled';
      if (!terminal) {
        continue;
      }
      final result = _recoveredResultFromSessionSnapshot(snapshot);
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
      if (status == 'failed' || status == 'cancelled' || status == 'canceled') {
        return goTaskServiceResultFromAcpResponse(
          <String, dynamic>{
            'jsonrpc': '2.0',
            'id': 'recovered-from-terminal-session-snapshot',
            'result': _failureResultFromSessionSnapshot(snapshot, status),
          },
          route: request.route,
          streamedText: streamedText,
          completedMessage: completedMessage,
        );
      }
    }
    return null;
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
  }) async {
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

  Map<String, dynamic> _recoveredResultFromSessionSnapshot(
    Map<String, dynamic> snapshot,
  ) {
    final result = <String, dynamic>{..._castMap(snapshot['result'])};
    final artifactRecord = _castMap(snapshot['artifacts']);
    final artifactItems = _listValue(artifactRecord['items']);
    if (artifactItems.isNotEmpty && !_hasArtifactList(result)) {
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

  Map<String, dynamic> _failureResultFromSessionSnapshot(
    Map<String, dynamic> snapshot,
    String status,
  ) {
    final task = _castMap(snapshot['task']);
    final error = _castMap(snapshot['error']);
    final message = _firstNonEmptyDisplayText(
      <String, dynamic>{...error, ...snapshot, 'taskMessage': task['message']},
      const <String>[
        'message',
        'error',
        'errorMessage',
        'reason',
        'taskMessage',
        'code',
      ],
    );
    final code = _firstNonEmptyDisplayText(
      <String, dynamic>{...error, ...snapshot, 'taskCode': task['code']},
      const <String>['code', 'errorCode', 'taskCode'],
    );
    final result = <String, dynamic>{
      'success': false,
      'status': status,
      'turnId': task['turnId']?.toString().trim() ?? '',
      'error': message.isNotEmpty ? message : 'Bridge session ended: $status',
      'message': message.isNotEmpty ? message : 'Bridge session ended: $status',
    };
    if (code.isNotEmpty) {
      result['code'] = code;
    }
    return result;
  }

  bool _hasArtifactList(Map<String, dynamic> result) {
    for (final key in const <String>['artifacts', 'files', 'attachments']) {
      if (_listValue(result[key]).isNotEmpty) {
        return true;
      }
      final recordItems = _listValue(_castMap(result[key])['items']);
      if (recordItems.isNotEmpty) {
        return true;
      }
    }
    for (final key in const <String>['payload', 'result', 'data']) {
      final nested = _castMap(result[key]);
      if (nested.isNotEmpty && _hasArtifactList(nested)) {
        return true;
      }
    }
    return false;
  }

  List<Object?> _listValue(Object? value) {
    return value is List ? value : const <Object?>[];
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
