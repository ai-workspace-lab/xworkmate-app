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
  }) : _client = client,
       _endpointResolver = endpointResolver;

  final GatewayAcpClient _client;
  final Uri? Function(AssistantExecutionTarget target) _endpointResolver;

  @visibleForTesting
  GatewayAcpClient get clientForTest => _client;

  @override
  Future<void> syncExternalProviders(
    List<ExternalCodeAgentAcpSyncedProvider> providers,
  ) async {}

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
      providerCatalog: providerCatalog,
      raw: result,
    );
  }

  @override
  Future<ExternalCodeAgentAcpRoutingResolution> resolveExternalAcpRouting({
    required String taskPrompt,
    required String workingDirectory,
    required ExternalCodeAgentAcpRoutingConfig routing,
    String aiGatewayBaseUrl = '',
    String aiGatewayApiKey = '',
  }) async {
    final response = await _client.request(
      method: 'xworkmate.routing.resolve',
      params: <String, dynamic>{
        'taskPrompt': taskPrompt,
        'workingDirectory': workingDirectory.trim(),
        if (aiGatewayBaseUrl.trim().isNotEmpty)
          'aiGatewayBaseUrl': aiGatewayBaseUrl.trim(),
        if (aiGatewayApiKey.trim().isNotEmpty)
          'aiGatewayApiKey': aiGatewayApiKey.trim(),
        'routing': routing.toJson(),
      },
      endpointOverride: _endpointResolver(AssistantExecutionTarget.singleAgent),
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
      final response = await _client.request(
        method: request.resumeSession ? 'session.message' : 'session.start',
        params: request.toExternalAcpParams(),
        endpointOverride: _endpointResolver(request.target),
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

  List<SingleAgentProvider> _parseProviderCatalog(Object? raw) {
    final providers = <SingleAgentProvider>[];
    for (final item in _asList(raw)) {
      final entry = _castMap(item);
      final providerId = entry['providerId']?.toString().trim() ?? '';
      if (providerId.isEmpty) {
        continue;
      }
      final label = entry['label']?.toString().trim();
      final provider = SingleAgentProviderCopy.fromJsonValue(
        providerId,
        label: label?.isNotEmpty == true ? label : null,
      );
      if (!provider.isUnspecified) {
        providers.add(provider);
      }
    }
    return normalizeSingleAgentProviderList(providers);
  }
}
