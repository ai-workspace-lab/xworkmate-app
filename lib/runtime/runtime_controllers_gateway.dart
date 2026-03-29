// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'gateway_runtime.dart';
import 'runtime_models.dart';
import 'secure_config_store.dart';
import 'runtime_controllers_settings.dart';
import 'runtime_controllers_entities.dart';
import 'runtime_controllers_derived_tasks.dart';

class AiGatewayResponseExceptionInternal implements Exception {
  const AiGatewayResponseExceptionInternal({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;
}

class GatewayAgentsController extends ChangeNotifier {
  GatewayAgentsController(this.runtimeInternal);

  final GatewayRuntime runtimeInternal;

  List<GatewayAgentSummary> agentsInternal = const <GatewayAgentSummary>[];
  String selectedAgentIdInternal = '';
  bool loadingInternal = false;
  String? errorInternal;

  List<GatewayAgentSummary> get agents => agentsInternal;
  String get selectedAgentId => selectedAgentIdInternal;
  bool get loading => loadingInternal;
  String? get error => errorInternal;

  GatewayAgentSummary? get selectedAgent {
    final selected = selectedAgentIdInternal.trim();
    if (selected.isEmpty) {
      return null;
    }
    for (final agent in agentsInternal) {
      if (agent.id == selected) {
        return agent;
      }
    }
    return null;
  }

  String get activeAgentName => selectedAgent?.name ?? 'Main';

  void restoreSelection(String agentId) {
    selectedAgentIdInternal = agentId.trim();
    notifyListeners();
  }

  void selectAgent(String? agentId) {
    selectedAgentIdInternal = agentId?.trim() ?? '';
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!runtimeInternal.isConnected) {
      agentsInternal = const <GatewayAgentSummary>[];
      errorInternal = null;
      notifyListeners();
      return;
    }
    loadingInternal = true;
    errorInternal = null;
    notifyListeners();
    try {
      agentsInternal = await runtimeInternal.listAgents();
      if (selectedAgentIdInternal.isNotEmpty &&
          !agentsInternal.any((item) => item.id == selectedAgentIdInternal)) {
        selectedAgentIdInternal = '';
      }
    } catch (error) {
      errorInternal = error.toString();
    } finally {
      loadingInternal = false;
      notifyListeners();
    }
  }
}

class GatewaySessionsController extends ChangeNotifier {
  GatewaySessionsController(this.runtimeInternal);

  final GatewayRuntime runtimeInternal;

  List<GatewaySessionSummary> sessionsInternal =
      const <GatewaySessionSummary>[];
  String currentSessionKeyInternal = 'main';
  String mainSessionBaseKeyInternal = 'main';
  String selectedAgentIdInternal = '';
  String defaultAgentIdInternal = '';
  bool loadingInternal = false;
  String? errorInternal;

  List<GatewaySessionSummary> get sessions => sessionsInternal;
  String get currentSessionKey => currentSessionKeyInternal;
  bool get loading => loadingInternal;
  String? get error => errorInternal;
  String get mainSessionBaseKey => mainSessionBaseKeyInternal;

  void configure({
    required String mainSessionKey,
    required String selectedAgentId,
    required String defaultAgentId,
  }) {
    mainSessionBaseKeyInternal = normalizeMainSessionKey(mainSessionKey);
    selectedAgentIdInternal = selectedAgentId.trim();
    defaultAgentIdInternal = defaultAgentId.trim();
    final preferred = preferredSessionKey;
    if (currentSessionKeyInternal.trim().isEmpty ||
        currentSessionKeyInternal == 'main' ||
        currentSessionKeyInternal == mainSessionBaseKeyInternal ||
        currentSessionKeyInternal.startsWith('agent:')) {
      currentSessionKeyInternal = preferred;
    }
    notifyListeners();
  }

  String get preferredSessionKey {
    final selected = selectedAgentIdInternal.trim();
    final defaultAgent = defaultAgentIdInternal.trim();
    final base = normalizeMainSessionKey(mainSessionBaseKeyInternal);
    if (selected.isEmpty ||
        (defaultAgent.isNotEmpty && selected == defaultAgent)) {
      return base;
    }
    return makeAgentSessionKey(agentId: selected, baseKey: base);
  }

  Future<void> refresh() async {
    if (!runtimeInternal.isConnected) {
      sessionsInternal = const <GatewaySessionSummary>[];
      errorInternal = null;
      notifyListeners();
      return;
    }
    loadingInternal = true;
    errorInternal = null;
    notifyListeners();
    try {
      sessionsInternal = await runtimeInternal.listSessions(limit: 50);
      if (!sessionsInternal.any(
        (item) => matchesSessionKey(item.key, currentSessionKeyInternal),
      )) {
        currentSessionKeyInternal = preferredSessionKey;
      }
    } catch (error) {
      errorInternal = error.toString();
    } finally {
      loadingInternal = false;
      notifyListeners();
    }
  }

  Future<void> switchSession(String sessionKey) async {
    final trimmed = sessionKey.trim();
    if (trimmed.isEmpty || trimmed == currentSessionKeyInternal) {
      return;
    }
    currentSessionKeyInternal = trimmed;
    notifyListeners();
  }
}

class GatewayChatController extends ChangeNotifier {
  GatewayChatController(this.runtimeInternal);

  final GatewayRuntime runtimeInternal;

  List<GatewayChatMessage> messagesInternal = const <GatewayChatMessage>[];
  String sessionKeyInternal = 'main';
  bool loadingInternal = false;
  bool sendingInternal = false;
  bool abortingInternal = false;
  String? errorInternal;
  String? streamingAssistantTextInternal;
  final Set<String> pendingRunsInternal = <String>{};

  List<GatewayChatMessage> get messages => messagesInternal;
  String get sessionKey => sessionKeyInternal;
  bool get loading => loadingInternal;
  bool get sending => sendingInternal;
  bool get aborting => abortingInternal;
  String? get error => errorInternal;
  String? get streamingAssistantText => streamingAssistantTextInternal;
  bool get hasPendingRun => pendingRunsInternal.isNotEmpty;
  String? get activeRunId =>
      pendingRunsInternal.isEmpty ? null : pendingRunsInternal.first;

  Future<void> loadSession(String sessionKey) async {
    final next = sessionKey.trim().isEmpty ? 'main' : sessionKey.trim();
    sessionKeyInternal = next;
    if (!runtimeInternal.isConnected) {
      messagesInternal = const <GatewayChatMessage>[];
      streamingAssistantTextInternal = null;
      errorInternal = null;
      notifyListeners();
      return;
    }
    loadingInternal = true;
    errorInternal = null;
    notifyListeners();
    try {
      messagesInternal = await runtimeInternal.loadHistory(next);
      streamingAssistantTextInternal = null;
    } catch (error) {
      errorInternal = error.toString();
    } finally {
      loadingInternal = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage({
    required String sessionKey,
    required String message,
    required String thinking,
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    String? agentId,
    Map<String, dynamic>? metadata,
  }) async {
    final trimmed = message.trim();
    if ((trimmed.isEmpty && attachments.isEmpty) ||
        !runtimeInternal.isConnected) {
      return;
    }
    sessionKeyInternal = sessionKey.trim().isEmpty ? 'main' : sessionKey.trim();
    sendingInternal = true;
    errorInternal = null;
    streamingAssistantTextInternal = null;
    messagesInternal = List<GatewayChatMessage>.from(messagesInternal)
      ..add(
        GatewayChatMessage(
          id: ephemeralIdInternal(),
          role: 'user',
          text: trimmed.isEmpty ? 'See attached.' : trimmed,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      );
    notifyListeners();
    try {
      final runId = await runtimeInternal.sendChat(
        sessionKey: sessionKeyInternal,
        message: trimmed.isEmpty ? 'See attached.' : trimmed,
        thinking: thinking,
        attachments: attachments,
        agentId: agentId,
        metadata: metadata,
      );
      pendingRunsInternal.add(runId);
    } catch (error) {
      errorInternal = error.toString();
    } finally {
      sendingInternal = false;
      notifyListeners();
    }
  }

  Future<void> abortRun() async {
    if (pendingRunsInternal.isEmpty || !runtimeInternal.isConnected) {
      return;
    }
    abortingInternal = true;
    notifyListeners();
    try {
      final runIds = pendingRunsInternal.toList(growable: false);
      for (final runId in runIds) {
        await runtimeInternal.abortChat(
          sessionKey: sessionKeyInternal,
          runId: runId,
        );
      }
    } catch (error) {
      errorInternal = error.toString();
    } finally {
      abortingInternal = false;
      notifyListeners();
    }
  }

  void handleEvent(GatewayPushEvent event) {
    if (event.event == 'chat.run') {
      handleChatRunEventInternal(asMap(event.payload));
      return;
    }
    if (event.event == 'chat') {
      handleChatEventInternal(asMap(event.payload));
      return;
    }
    if (event.event == 'agent') {
      handleAgentEventInternal(asMap(event.payload));
    }
  }

  void clear() {
    messagesInternal = const <GatewayChatMessage>[];
    pendingRunsInternal.clear();
    streamingAssistantTextInternal = null;
    errorInternal = null;
    notifyListeners();
  }

  void handleChatRunEventInternal(Map<String, dynamic> payload) {
    final runId = stringValue(payload['runId']);
    final state = stringValue(payload['state']) ?? '';
    final incomingSessionKey =
        stringValue(payload['sessionKey']) ?? sessionKeyInternal;
    final isOurRun = runId != null && pendingRunsInternal.contains(runId);
    if (!matchesSessionKey(incomingSessionKey, sessionKeyInternal) &&
        !isOurRun) {
      return;
    }

    final assistantText = stringValue(payload['assistantText']) ?? '';
    if (assistantText.isNotEmpty &&
        (state == 'delta' || state == 'final')) {
      streamingAssistantTextInternal = assistantText;
    }
    if (state == 'error') {
      errorInternal = stringValue(payload['errorMessage']) ?? 'Chat failed';
    }
    final terminal =
        boolValue(payload['terminal']) ?? false ||
        state == 'final' ||
        state == 'aborted' ||
        state == 'error';
    if (terminal) {
      if (runId != null) {
        pendingRunsInternal.remove(runId);
      } else {
        pendingRunsInternal.clear();
      }
      unawaited(loadSession(sessionKeyInternal));
      notifyListeners();
      return;
    }
    notifyListeners();
  }

  void handleChatEventInternal(Map<String, dynamic> payload) {
    final message = asMap(payload['message']);
    final role = (stringValue(message['role']) ?? '').toLowerCase();
    handleChatRunEventInternal(<String, dynamic>{
      'runId': payload['runId'],
      'sessionKey': payload['sessionKey'],
      'state': payload['state'],
      if (role == 'assistant') 'assistantText': extractMessageText(message),
      'errorMessage': payload['errorMessage'],
      'terminal': false,
    });
  }

  void handleAgentEventInternal(Map<String, dynamic> payload) {
    final runId = stringValue(payload['runId']);
    if (runId == null || !pendingRunsInternal.contains(runId)) {
      return;
    }
    final stream = stringValue(payload['stream']);
    final data = asMap(payload['data']);
    if (stream == 'assistant') {
      final nextText = stringValue(data['text']) ?? extractMessageText(data);
      if (nextText.isNotEmpty) {
        handleChatRunEventInternal(<String, dynamic>{
          'runId': runId,
          'sessionKey': payload['sessionKey'] ?? data['sessionKey'],
          'state': 'delta',
          'assistantText': nextText,
          'source': 'agent',
          'terminal': false,
        });
      }
    }
  }
}
