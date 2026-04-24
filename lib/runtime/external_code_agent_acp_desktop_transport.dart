import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gateway_acp_client.dart';
import 'go_task_service_client.dart';
import 'runtime_models.dart';

class ExternalCodeAgentAcpDesktopTransport
    implements ExternalCodeAgentAcpTransport {
  ExternalCodeAgentAcpDesktopTransport({
    required GatewayAcpClient client,
    required Uri? Function(AssistantExecutionTarget target) endpointResolver,
    Uri? Function(GoTaskServiceRequest request)? taskEndpointResolver,
  }) : _client = client,
       _endpointResolver = endpointResolver,
       _taskEndpointResolver = taskEndpointResolver;

  final GatewayAcpClient _client;
  final Uri? Function(AssistantExecutionTarget target) _endpointResolver;
  final Uri? Function(GoTaskServiceRequest request)? _taskEndpointResolver;

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
    } catch (error) {
      throw GatewayAcpException(
        error.toString(),
        code: 'EXTERNAL_ACP_GATEWAY_ERROR',
      );
    }
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
}
