import 'dart:async';

import '../runtime/gateway_runtime_errors.dart';
import '../runtime/gateway_runtime_helpers.dart';
import '../runtime/go_task_service_client.dart';
import '../runtime/runtime_models.dart';
import 'web_relay_gateway_client.dart';

class WebGoTaskService implements GoTaskServiceClient {
  WebGoTaskService({
    required WebRelayGatewayClient relayClient,
    required ExternalCodeAgentAcpTransport acpTransport,
  }) : _relayClient = relayClient,
       _acpTransport = acpTransport {
    _relayEventsSubscription = _relayClient.events.listen(_handleRelayEvent);
  }

  final WebRelayGatewayClient _relayClient;
  final ExternalCodeAgentAcpTransport _acpTransport;

  late final StreamSubscription<GatewayPushEvent> _relayEventsSubscription;
  final Map<String, _PendingOpenClawTask> _pendingOpenClawTasksByRunId =
      <String, _PendingOpenClawTask>{};
  final Map<String, String> _openClawRunIdsBySession = <String, String>{};

  @override
  Future<void> syncExternalProviders(
    List<ExternalCodeAgentAcpSyncedProvider> providers,
  ) => _acpTransport.syncExternalProviders(providers);

  @override
  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) => _acpTransport.loadExternalAcpCapabilities(
    target: target,
    forceRefresh: forceRefresh,
  );

  @override
  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) async {
    switch (request.route) {
      case GoTaskServiceRoute.openClawTask:
        return _executeOpenClawTask(request, onUpdate: onUpdate);
      case GoTaskServiceRoute.externalAcpSingle:
      case GoTaskServiceRoute.externalAcpMulti:
        return _acpTransport.executeTask(request, onUpdate: onUpdate);
    }
  }

  @override
  Future<void> cancelTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {
    if (route == GoTaskServiceRoute.openClawTask) {
      final runId = _openClawRunIdsBySession[sessionId];
      if (runId == null || runId.trim().isEmpty) {
        return;
      }
      await _relayClient.request(
        'chat.abort',
        params: <String, dynamic>{'sessionKey': sessionId, 'runId': runId},
      );
      return;
    }
    await _acpTransport.cancelTask(
      target: target,
      sessionId: sessionId,
      threadId: threadId,
    );
  }

  @override
  Future<void> closeTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {
    if (route == GoTaskServiceRoute.openClawTask) {
      _openClawRunIdsBySession.remove(sessionId);
      return;
    }
    await _acpTransport.closeTask(
      target: target,
      sessionId: sessionId,
      threadId: threadId,
    );
  }

  @override
  Future<void> dispose() async {
    for (final pending in _pendingOpenClawTasksByRunId.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          GatewayRuntimeException('task service disposed'),
        );
      }
    }
    _pendingOpenClawTasksByRunId.clear();
    _openClawRunIdsBySession.clear();
    await _relayEventsSubscription.cancel();
    await _acpTransport.dispose();
  }

  Future<GoTaskServiceResult> _executeOpenClawTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) async {
    if (!_relayClient.isConnected) {
      throw GatewayRuntimeException('gateway not connected');
    }
    final metadata = <String, dynamic>{
      ...request.metadata,
      if (request.agentId.trim().isNotEmpty &&
          !request.metadata.containsKey('agentId'))
        'agentId': request.agentId.trim(),
    };
    final runId = await _relayClient.sendChat(
      sessionKey: request.sessionId,
      message: request.prompt,
      thinking: request.thinking,
      attachments: request.inlineAttachments,
      metadata: metadata,
    );
    final pending = _PendingOpenClawTask(
      request: request,
      runId: runId,
      onUpdate: onUpdate,
      completer: Completer<GoTaskServiceResult>(),
    );
    _pendingOpenClawTasksByRunId[runId] = pending;
    _openClawRunIdsBySession[request.sessionId] = runId;
    return pending.completer.future;
  }

  void _handleRelayEvent(GatewayPushEvent event) {
    if (event.event == 'chat.run') {
      _handleOpenClawRunPayload(asMap(event.payload));
      return;
    }
    if (event.event == 'chat') {
      final payload = asMap(event.payload);
      final message = asMap(payload['message']);
      _handleOpenClawRunPayload(<String, dynamic>{
        'runId': payload['runId'],
        'sessionKey': payload['sessionKey'],
        'state': payload['state'],
        'assistantText': extractMessageText(message),
        'errorMessage': payload['errorMessage'],
      });
    }
  }

  void _handleOpenClawRunPayload(Map<String, dynamic> payload) {
    final runId = stringValue(payload['runId']) ?? '';
    if (runId.isEmpty) {
      return;
    }
    final pending = _pendingOpenClawTasksByRunId[runId];
    if (pending == null) {
      return;
    }
    final state = stringValue(payload['state']) ?? '';
    final assistantText = stringValue(payload['assistantText']) ?? '';
    final errorMessage = stringValue(payload['errorMessage']) ?? '';
    if (assistantText.isNotEmpty && (state == 'delta' || state == 'final')) {
      pending.streamedText = assistantText;
      pending.onUpdate(
        GoTaskServiceUpdate(
          sessionId: pending.request.sessionId,
          threadId: pending.request.threadId,
          turnId: runId,
          type: 'delta',
          text: assistantText,
          message: '',
          pending: state != 'final',
          error: false,
          route: GoTaskServiceRoute.openClawTask,
          payload: payload,
        ),
      );
    }
    final terminal =
        boolValue(payload['terminal']) ?? false ||
        state == 'final' ||
        state == 'aborted' ||
        state == 'error';
    if (!terminal || pending.completer.isCompleted) {
      return;
    }
    _pendingOpenClawTasksByRunId.remove(runId);
    _openClawRunIdsBySession.remove(pending.request.sessionId);
    final success = state != 'error' && state != 'aborted';
    pending.completer.complete(
      GoTaskServiceResult(
        success: success,
        message: pending.streamedText.trim(),
        turnId: runId,
        raw: payload,
        errorMessage: errorMessage,
        resolvedModel:
            stringValue(payload['model']) ??
            stringValue(payload['resolvedModel']) ??
            '',
        route: GoTaskServiceRoute.openClawTask,
      ),
    );
  }
}

class _PendingOpenClawTask {
  _PendingOpenClawTask({
    required this.request,
    required this.runId,
    required this.onUpdate,
    required this.completer,
  });

  final GoTaskServiceRequest request;
  final String runId;
  final void Function(GoTaskServiceUpdate update) onUpdate;
  final Completer<GoTaskServiceResult> completer;
  String streamedText = '';
}
