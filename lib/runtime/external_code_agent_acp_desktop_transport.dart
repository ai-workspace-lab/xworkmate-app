import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gateway_acp_client.dart';
import 'go_acp_stdio_bridge.dart';
import 'go_task_service_client.dart';
import 'runtime_models.dart';

class ExternalCodeAgentAcpDesktopTransport
    implements ExternalCodeAgentAcpTransport {
  ExternalCodeAgentAcpDesktopTransport({GoAcpStdioBridge? bridge})
    : _bridge = bridge ?? GoAcpStdioBridge();

  final GoAcpStdioBridge _bridge;
  List<ExternalCodeAgentAcpSyncedProvider> _syncedProviders =
      const <ExternalCodeAgentAcpSyncedProvider>[];

  @visibleForTesting
  GoAcpStdioBridge get bridgeForTest => _bridge;

  @override
  Future<void> syncExternalProviders(
    List<ExternalCodeAgentAcpSyncedProvider> providers,
  ) async {
    _syncedProviders = List<ExternalCodeAgentAcpSyncedProvider>.unmodifiable(
      providers,
    );
    await _syncProviders();
  }

  @override
  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async {
    await _syncProviders();
    final response = await _bridge.request(
      method: 'acp.capabilities',
      params: const <String, dynamic>{},
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
    await _syncProviders();
    final response = await _bridge.request(
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
    await _syncProviders();
    late final StreamSubscription<Map<String, dynamic>> subscription;
    var streamedText = '';
    String? completedMessage;
    subscription = _bridge.notifications.listen((notification) {
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
    });
    try {
      final response = await _bridge.request(
        method: request.resumeSession ? 'session.message' : 'session.start',
        params: request.toExternalAcpParams(),
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
        code: 'EXTERNAL_ACP_STDIO_ERROR',
      );
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> cancelTask({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {
    await _bridge.request(
      method: 'session.cancel',
      params: <String, dynamic>{'sessionId': sessionId, 'threadId': threadId},
    );
  }

  @override
  Future<void> closeTask({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {
    await _bridge.request(
      method: 'session.close',
      params: <String, dynamic>{'sessionId': sessionId, 'threadId': threadId},
    );
  }

  @override
  Future<void> dispose() => _bridge.dispose();

  Future<void> _syncProviders() async {
    if (_syncedProviders.isEmpty) {
      return;
    }
    await _bridge.request(
      method: 'xworkmate.providers.sync',
      params: <String, dynamic>{
        'providers': _syncedProviders
            .map(
              (item) => <String, dynamic>{
                'providerId': item.providerId,
                'endpoint': item.endpoint,
                'label': item.label,
                'authorizationHeader': item.authorizationHeader,
                'enabled': item.enabled,
              },
            )
            .toList(growable: false),
      },
    );
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
      if (provider != SingleAgentProvider.auto) {
        providers.add(provider);
      }
    }
    return normalizeSingleAgentProviderList(providers);
  }
}
