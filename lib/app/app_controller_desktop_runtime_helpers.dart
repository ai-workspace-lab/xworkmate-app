// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'app_metadata.dart';
import 'app_capabilities.dart';
import 'app_store_policy.dart';
import 'ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/device_identity_store.dart';

import '../runtime/go_core.dart';
import '../runtime/acp_endpoint_paths.dart';
import '../runtime/runtime_bootstrap.dart';
import '../runtime/desktop_platform_service.dart';
import '../runtime/gateway_runtime.dart';
import '../runtime/runtime_controllers.dart';
import '../runtime/runtime_models.dart';
import '../runtime/secure_config_store.dart';
import '../runtime/embedded_agent_launch_policy.dart';
import '../runtime/runtime_coordinator.dart';
import '../runtime/gateway_acp_client.dart';
import '../runtime/codex_runtime.dart';
import '../runtime/codex_config_bridge.dart';
import '../runtime/code_agent_node_orchestrator.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/desktop_thread_artifact_service.dart';
import '../runtime/go_task_service_client.dart';
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/multi_agent_orchestrator.dart';
import '../runtime/platform_environment.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_coordination_impl.dart';
import 'app_controller_desktop_runtime_exceptions.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopRuntimeHelpers on AppController {
  Future<void> saveAppUiStateInternal(
    AppUiState next, {
    bool notify = false,
  }) async {
    appUiStateInternal = next;
    await storeInternal.saveAppUiState(next);
    if (notify) {
      notifyIfActiveInternal();
    }
  }

  Future<void> persistAssistantLastSessionKeyInternal(String sessionKey) async {
    if (disposedInternal) {
      return;
    }
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (normalizedSessionKey.isEmpty ||
        appUiState.assistantLastSessionKey == normalizedSessionKey) {
      return;
    }
    try {
      await saveAppUiStateInternal(
        appUiState.copyWith(assistantLastSessionKey: normalizedSessionKey),
      );
    } catch (_) {
      // Best effort only during teardown-sensitive transitions.
    }
  }

  void setAiGatewayStreamingTextInternal(String sessionKey, String text) {
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    if (text.trim().isEmpty) {
      aiGatewayStreamingTextBySessionInternal.remove(key);
    } else {
      aiGatewayStreamingTextBySessionInternal[key] = text;
    }
    notifyIfActiveInternal();
  }

  void appendAiGatewayStreamingTextInternal(String sessionKey, String delta) {
    if (delta.isEmpty) {
      return;
    }
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    final current = aiGatewayStreamingTextBySessionInternal[key] ?? '';
    aiGatewayStreamingTextBySessionInternal[key] = '$current$delta';
    notifyIfActiveInternal();
  }

  void clearAiGatewayStreamingTextInternal(String sessionKey) {
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    if (aiGatewayStreamingTextBySessionInternal.remove(key) != null) {
      notifyIfActiveInternal();
    }
  }

  String nextLocalMessageIdInternal() {
    localMessageCounterInternal += 1;
    return 'local-${DateTime.now().microsecondsSinceEpoch}-$localMessageCounterInternal';
  }

  Future<T> enqueueThreadTurnInternal<T>(
    String threadId,
    Future<T> Function() task,
  ) {
    final normalizedThreadId = normalizedAssistantSessionKeyInternal(threadId);
    final previous =
        assistantThreadTurnQueuesInternal[normalizedThreadId] ??
        Future<void>.value();
    final completer = Completer<T>();
    T? result;
    Object? failure;
    StackTrace? failureStackTrace;
    var taskCompleted = false;
    late final Future<void> next;
    next = previous
        .catchError((_) {})
        .then((_) async {
          try {
            result = await task();
            taskCompleted = true;
          } catch (error, stackTrace) {
            failure = error;
            failureStackTrace = stackTrace;
          }
        })
        .whenComplete(() {
          if (identical(
            assistantThreadTurnQueuesInternal[normalizedThreadId],
            next,
          )) {
            assistantThreadTurnQueuesInternal.remove(normalizedThreadId);
          }
          if (completer.isCompleted) {
            return;
          }
          final error = failure;
          if (error != null) {
            completer.completeError(
              error,
              failureStackTrace ?? StackTrace.current,
            );
            return;
          }
          if (taskCompleted) {
            completer.complete(result);
            return;
          }
          completer.completeError(
            StateError('Thread turn did not complete.'),
            StackTrace.current,
          );
        });
    assistantThreadTurnQueuesInternal[normalizedThreadId] = next;
    return completer.future;
  }

  Uri? normalizeAiGatewayBaseUrlInternal(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    final pathSegments = uri.pathSegments.where((item) => item.isNotEmpty);
    return uri.replace(
      pathSegments: pathSegments.isEmpty ? const <String>['v1'] : pathSegments,
      query: null,
      fragment: null,
    );
  }

  Uri aiGatewayChatUriInternal(Uri baseUrl) {
    final pathSegments = baseUrl.pathSegments
        .where((item) => item.isNotEmpty)
        .toList(growable: true);
    if (pathSegments.isEmpty) {
      pathSegments.add('v1');
    }
    if (pathSegments.length >= 2 &&
        pathSegments[pathSegments.length - 2] == 'chat' &&
        pathSegments.last == 'completions') {
      return baseUrl.replace(query: null, fragment: null);
    }
    if (pathSegments.last == 'models') {
      pathSegments.removeLast();
    }
    if (pathSegments.last != 'chat') {
      pathSegments.add('chat');
    }
    pathSegments.add('completions');
    return baseUrl.replace(
      pathSegments: pathSegments,
      query: null,
      fragment: null,
    );
  }

  String aiGatewayHostLabelInternal(String raw) {
    final uri = normalizeAiGatewayBaseUrlInternal(raw);
    if (uri == null) {
      return '';
    }
    if (uri.hasPort) {
      return '${uri.host}:${uri.port}';
    }
    return uri.host;
  }

  String aiGatewayErrorLabelInternal(Object error) {
    if (error is AiGatewayChatExceptionInternal) {
      return error.message;
    }
    if (error is SocketException) {
      return appText('无法连接到 LLM API。', 'Unable to reach the LLM API.');
    }
    if (error is HandshakeException) {
      return appText('LLM API TLS 握手失败。', 'LLM API TLS handshake failed.');
    }
    if (error is TimeoutException) {
      return appText('LLM API 请求超时。', 'LLM API request timed out.');
    }
    if (error is FormatException) {
      return appText(
        'LLM API 返回了无法解析的响应。',
        'LLM API returned an invalid response.',
      );
    }
    return error.toString();
  }

  String gatewayExecutionErrorLabelInternal(
    Object error, {
    required AssistantExecutionTarget target,
  }) {
    final raw = error.toString().trim();
    final lowered = raw.toLowerCase();
    final detailCode = gatewayExecutionDetailCodeInternal(error);
    final primaryCode = gatewayExecutionPrimaryCodeInternal(error);
    final interruptedTransportCode = interruptedAcpHttpTransportCodeInternal(
      error,
    );
    final unconfirmedConnectCode = unconfirmedAcpHttpConnectCodeInternal(error);
    if (unconfirmedConnectCode == gatewayAcpHttpConnectTimeoutCode) {
      return appText(
        'Bridge 连接超时，本轮请求未确认，可重试。错误码：ACP_HTTP_CONNECT_TIMEOUT',
        'Bridge connection timed out; this request was not confirmed and can be retried. Error code: ACP_HTTP_CONNECT_TIMEOUT',
      );
    }
    if (unconfirmedConnectCode == gatewayAcpHttpConnectFailedCode) {
      return appText(
        'Bridge 连接失败，本轮请求未确认，可重试。错误码：ACP_HTTP_CONNECT_FAILED',
        'Bridge connection failed; this request was not confirmed and can be retried. Error code: ACP_HTTP_CONNECT_FAILED',
      );
    }
    if (interruptedTransportCode == 'ACP_HTTP_CONNECTION_CLOSED') {
      return appText(
        'Bridge 响应读取中断，本轮结果未完成。请重新发送请求。错误码：ACP_HTTP_CONNECTION_CLOSED',
        'Bridge response was interrupted and this result did not complete. Send the request again. Error code: ACP_HTTP_CONNECTION_CLOSED',
      );
    }
    if (interruptedTransportCode == 'ACP_HTTP_HANDSHAKE_INTERRUPTED') {
      return appText(
        'Bridge 握手中断，本轮请求未完成。请重新发送请求。错误码：ACP_HTTP_HANDSHAKE_INTERRUPTED',
        'Bridge handshake was interrupted and this request did not complete. Send the request again. Error code: ACP_HTTP_HANDSHAKE_INTERRUPTED',
      );
    }
    final continuationUnavailable =
        primaryCode == 'SESSION_CONTINUATION_UNAVAILABLE' ||
        detailCode == 'SESSION_CONTINUATION_UNAVAILABLE' ||
        raw.contains('SESSION_CONTINUATION_UNAVAILABLE');
    if (continuationUnavailable) {
      return appText(
        '会话状态不可续写；请检查 xworkmate-bridge/provider 会话状态。错误码：SESSION_CONTINUATION_UNAVAILABLE',
        'Session state cannot continue; check the xworkmate-bridge/provider session state. Error code: SESSION_CONTINUATION_UNAVAILABLE',
      );
    }
    final openClawSocketClosed =
        target.isGateway &&
        (detailCode == 'OPENCLAW_GATEWAY_SOCKET_CLOSED' ||
            primaryCode == 'OPENCLAW_GATEWAY_SOCKET_CLOSED' ||
            raw.contains('OPENCLAW_GATEWAY_SOCKET_CLOSED') ||
            lowered.contains('openclaw') && lowered.contains('socket closed'));
    if (openClawSocketClosed) {
      return appText(
        'OpenClaw Gateway 连接在任务执行中断开，请稍后重试；若持续出现，请检查 xworkmate-bridge 主机到 127.0.0.1:18789 的 OpenClaw runtime 连接。',
        'The OpenClaw Gateway connection closed during task execution. Try again later; if it keeps happening, check the OpenClaw runtime connection from the xworkmate-bridge host to 127.0.0.1:18789.',
      );
    }
    if (lowered.contains('gateway not connected') ||
        lowered.contains('code: offline') ||
        lowered.contains('offlin') && lowered.contains('gateway')) {
      if (target.isGateway) {
        return appText(
          'OpenClaw Gateway 当前未连接。请确认 xworkmate-bridge 节点本机 127.0.0.1:18789 可用后重试。',
          'OpenClaw Gateway is not connected. Confirm the xworkmate-bridge host can reach 127.0.0.1:18789, then try again.',
        );
      }
      final profile = gatewayProfileForAssistantExecutionTargetInternal(target);
      final address = gatewayAddressLabelInternal(profile);
      return address == appText('未连接目标', 'No target')
          ? appText(
              '当前 xworkmate-bridge 未连接。请先恢复 bridge 连接后再重试。',
              'xworkmate-bridge is not connected. Restore the bridge connection, then try again.',
            )
          : appText(
              '当前 xworkmate-bridge 未连接：$address。请先恢复 bridge 连接后再重试。',
              'xworkmate-bridge is not connected: $address. Restore the bridge connection, then try again.',
            );
    }
    return raw;
  }

  String? gatewayExecutionPrimaryCodeInternal(Object error) {
    return error is GatewayAcpException
        ? error.code?.trim().toUpperCase()
        : null;
  }

  String? gatewayExecutionDetailCodeInternal(Object error) {
    return error is GatewayAcpException
        ? error.detailCode?.trim().toUpperCase()
        : null;
  }

  bool isOpenClawNoExportedArtifactsGuardResultInternal(
    GoTaskServiceResult result,
  ) {
    if (result.artifacts.isNotEmpty) {
      return false;
    }
    final status = result.status.trim().toLowerCase();
    if (status == 'artifact_missing') {
      return true;
    }
    final code = result.code.trim().toUpperCase();
    if (code == 'OPENCLAW_ARTIFACT_MISSING' ||
        code == 'OPENCLAW_NO_EXPORTED_ARTIFACTS') {
      return true;
    }
    final warnings = result.raw['artifactWarnings'];
    if (warnings is List) {
      return warnings.any((item) {
        final text = item?.toString().toLowerCase() ?? '';
        return text.contains('openclaw artifact export returned no files') ||
            text.contains('no files for a file-delivery request');
      });
    }
    return false;
  }

  String jsonLikeTextForDiagnosticsInternal(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  String? interruptedAcpHttpTransportCodeInternal(Object error) {
    final raw = error.toString().trim();
    final primaryCode = gatewayExecutionPrimaryCodeInternal(error);
    final detailCode = gatewayExecutionDetailCodeInternal(error);
    if (primaryCode == 'ACP_HTTP_CONNECTION_CLOSED' ||
        detailCode == 'ACP_HTTP_CONNECTION_CLOSED' ||
        raw.contains('ACP_HTTP_CONNECTION_CLOSED')) {
      return 'ACP_HTTP_CONNECTION_CLOSED';
    }
    if (primaryCode == 'ACP_HTTP_HANDSHAKE_INTERRUPTED' ||
        detailCode == 'ACP_HTTP_HANDSHAKE_INTERRUPTED' ||
        raw.contains('ACP_HTTP_HANDSHAKE_INTERRUPTED')) {
      return 'ACP_HTTP_HANDSHAKE_INTERRUPTED';
    }
    return null;
  }

  String? unconfirmedAcpHttpConnectCodeInternal(Object error) {
    final raw = error.toString().trim();
    final primaryCode = gatewayExecutionPrimaryCodeInternal(error);
    final detailCode = gatewayExecutionDetailCodeInternal(error);
    if (primaryCode == gatewayAcpHttpConnectTimeoutCode ||
        detailCode == gatewayAcpHttpConnectTimeoutCode ||
        raw.contains(gatewayAcpHttpConnectTimeoutCode)) {
      return gatewayAcpHttpConnectTimeoutCode;
    }
    if (primaryCode == gatewayAcpHttpConnectFailedCode ||
        detailCode == gatewayAcpHttpConnectFailedCode ||
        raw.contains(gatewayAcpHttpConnectFailedCode)) {
      return gatewayAcpHttpConnectFailedCode;
    }
    return null;
  }

  String formatAiGatewayHttpErrorInternal(int statusCode, String detail) {
    final base = switch (statusCode) {
      400 => appText(
        'LLM API 请求无效 (400)',
        'LLM API rejected the request (400)',
      ),
      401 => appText(
        'LLM API 鉴权失败 (401)',
        'LLM API authentication failed (401)',
      ),
      403 => appText('LLM API 拒绝访问 (403)', 'LLM API denied access (403)'),
      404 => appText(
        'LLM API chat 接口不存在 (404)',
        'LLM API chat endpoint was not found (404)',
      ),
      429 => appText(
        'LLM API 限流 (429)',
        'LLM API rate limited the request (429)',
      ),
      >= 500 => appText(
        'LLM API 当前不可用 ($statusCode)',
        'LLM API is unavailable right now ($statusCode)',
      ),
      _ => appText(
        'LLM API 返回状态码 $statusCode',
        'LLM API responded with status $statusCode',
      ),
    };
    final trimmed = detail.trim();
    return trimmed.isEmpty ? base : '$base · $trimmed';
  }

  String extractAiGatewayErrorDetailInternal(String body) {
    if (body.trim().isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(extractFirstJsonDocumentInternal(body));
      final map = asMap(decoded);
      final error = asMap(map['error']);
      return (stringValue(error['message']) ??
              stringValue(map['message']) ??
              stringValue(map['detail']) ??
              '')
          .trim();
    } on FormatException {
      return '';
    }
  }

  String extractAiGatewayAssistantTextInternal(Object? decoded) {
    final map = asMap(decoded);
    final choices = asList(map['choices']);
    if (choices.isNotEmpty) {
      final firstChoice = asMap(choices.first);
      final message = asMap(firstChoice['message']);
      final content = extractAiGatewayContentInternal(message['content']);
      if (content.isNotEmpty) {
        return content;
      }
    }

    final output = asList(map['output']);
    for (final item in output) {
      final entry = asMap(item);
      final content = extractAiGatewayContentInternal(entry['content']);
      if (content.isNotEmpty) {
        return content;
      }
    }

    final direct = extractAiGatewayContentInternal(map['content']);
    if (direct.isNotEmpty) {
      return direct;
    }
    return stringValue(map['output_text'])?.trim() ?? '';
  }

  String extractAiGatewayContentInternal(Object? content) {
    if (content is String) {
      return content.trim();
    }
    final parts = <String>[];
    for (final item in asList(content)) {
      final map = asMap(item);
      final nestedText = stringValue(map['text']);
      if (nestedText != null && nestedText.trim().isNotEmpty) {
        parts.add(nestedText.trim());
        continue;
      }
      final type = stringValue(map['type']) ?? '';
      if (type == 'output_text') {
        final text = stringValue(map['text']) ?? stringValue(map['value']);
        if (text != null && text.trim().isNotEmpty) {
          parts.add(text.trim());
        }
      }
    }
    return parts.join('\n').trim();
  }

  String extractFirstJsonDocumentInternal(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty response body');
    }
    final start = trimmed.indexOf(RegExp(r'[\{\[]'));
    if (start < 0) {
      throw const FormatException('Missing JSON document');
    }
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < trimmed.length; index++) {
      final char = trimmed[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (char == '{' || char == '[') {
        depth += 1;
      } else if (char == '}' || char == ']') {
        depth -= 1;
        if (depth == 0) {
          return trimmed.substring(start, index + 1);
        }
      }
    }
    throw const FormatException('Unterminated JSON document');
  }

  SettingsSnapshot sanitizeCodeAgentSettingsInternal(
    SettingsSnapshot snapshot,
  ) => snapshot;

  Future<void> refreshAcpCapabilitiesInternal({
    bool forceRefresh = false,
    bool persistMountTargets = false,
  }) => refreshAcpCapabilitiesRuntimeInternal(
    this,
    forceRefresh: forceRefresh,
    persistMountTargets: persistMountTargets,
  );

  Future<void> refreshSingleAgentCapabilitiesInternal({
    bool forceRefresh = false,
  }) => refreshSingleAgentCapabilitiesRuntimeInternal(
    this,
    forceRefresh: forceRefresh,
  );

  List<ManagedMountTargetState> mergeAcpCapabilitiesIntoMountTargetsInternal(
    List<ManagedMountTargetState> current,
    GatewayAcpCapabilities capabilities,
  ) => mergeAcpCapabilitiesIntoMountTargetsRuntimeInternal(
    this,
    current,
    capabilities,
  );

  String? assistantWorkingDirectoryForSessionInternal(String sessionKey) =>
      assistantWorkingDirectoryForSessionRuntimeInternal(this, sessionKey);

  String? assistantRemoteWorkingDirectoryHintForSessionInternal(
    String sessionKey,
  ) => assistantRemoteWorkingDirectoryHintForSessionRuntimeInternal(
    this,
    sessionKey,
  );

  String? resolveLocalAssistantWorkingDirectoryForSessionInternal(
    String sessionKey, {
    bool requireLocalExistence = true,
  }) => resolveLocalAssistantWorkingDirectoryForSessionRuntimeInternal(
    this,
    sessionKey,
    requireLocalExistence: requireLocalExistence,
  );

  void registerCodexExternalProviderInternal() {
    runtimeCoordinatorInternal.registerExternalCodeAgent(
      ExternalCodeAgentProvider(
        id: 'codex',
        name: 'Codex ACP',
        command: 'xworkmate-agent-gateway',
        transport: ExternalAgentTransport.websocketJsonRpc,
        endpoint: '',
        defaultArgs: const <String>[],
        capabilities: const <String>[
          'chat',
          'code-edit',
          'gateway-bridge',
          'memory-sync',
          'agent',
          'gateway',
        ],
      ),
    );
  }

  CodeAgentNodeState buildCodeAgentNodeStateInternal({
    AssistantExecutionTarget? executionTarget,
  }) => buildCodeAgentNodeStateRuntimeInternal(
    this,
    executionTarget: executionTarget,
  );

  GatewayMode bridgeGatewayModeInternal() =>
      bridgeGatewayModeRuntimeInternal(this);

  Future<void> ensureCodexGatewayRegistrationInternal() =>
      ensureCodexGatewayRegistrationRuntimeInternal(this);

  void clearCodexGatewayRegistrationInternal() =>
      clearCodexGatewayRegistrationRuntimeInternal(this);

  void recomputeTasksInternal() => recomputeTasksRuntimeInternal(this);

  void attachChildListenersInternal() {
    runtimeCoordinatorInternal.addListener(relayChildChangeInternal);
    settingsControllerInternal.addListener(
      handleSettingsControllerChangeInternal,
    );
    agentsControllerInternal.addListener(relayChildChangeInternal);
    sessionsControllerInternal.addListener(relayChildChangeInternal);
    chatControllerInternal.addListener(relayChildChangeInternal);
    skillsControllerInternal.addListener(relayChildChangeInternal);
    modelsControllerInternal.addListener(relayChildChangeInternal);
    cronJobsControllerInternal.addListener(relayChildChangeInternal);
    devicesControllerInternal.addListener(relayChildChangeInternal);
    tasksControllerInternal.addListener(relayChildChangeInternal);
    multiAgentOrchestratorInternal.addListener(relayChildChangeInternal);
  }

  void detachChildListenersInternal() {
    runtimeCoordinatorInternal.removeListener(relayChildChangeInternal);
    settingsControllerInternal.removeListener(
      handleSettingsControllerChangeInternal,
    );
    agentsControllerInternal.removeListener(relayChildChangeInternal);
    sessionsControllerInternal.removeListener(relayChildChangeInternal);
    chatControllerInternal.removeListener(relayChildChangeInternal);
    skillsControllerInternal.removeListener(relayChildChangeInternal);
    modelsControllerInternal.removeListener(relayChildChangeInternal);
    cronJobsControllerInternal.removeListener(relayChildChangeInternal);
    devicesControllerInternal.removeListener(relayChildChangeInternal);
    tasksControllerInternal.removeListener(relayChildChangeInternal);
    multiAgentOrchestratorInternal.removeListener(relayChildChangeInternal);
  }

  void handleSettingsControllerChangeInternal() {
    final previous = lastObservedSettingsSnapshotInternal;
    final current = settings;
    final previousJson = previous.toJsonString();
    final currentJson = current.toJsonString();
    if (currentJson == previousJson) {
      notifyIfActiveInternal();
      return;
    }
    final hadDraftChanges =
        settingsDraftInitializedInternal &&
        (settingsDraftInternal.toJsonString() != previousJson ||
            draftSecretValuesInternal.isNotEmpty);
    if (!settingsDraftInitializedInternal || !hadDraftChanges) {
      settingsDraftInternal = current;
      settingsDraftInitializedInternal = true;
      settingsDraftStatusMessageInternal = '';
    }
    lastObservedSettingsSnapshotInternal = current;
    settingsObservationQueueInternal = settingsObservationQueueInternal
        .then((_) async {
          await handleObservedSettingsChangeInternal(
            previous: previous,
            current: current,
          );
        })
        .catchError((_) {});
    notifyIfActiveInternal();
  }

  Future<void> handleObservedSettingsChangeInternal({
    required SettingsSnapshot previous,
    required SettingsSnapshot current,
  }) async {
    if (disposedInternal) {
      return;
    }
    setActiveAppLanguage(current.appLanguage);
    multiAgentOrchestratorInternal.updateConfig(current.multiAgent);
    if (previous.codeAgentRuntimeMode != current.codeAgentRuntimeMode) {
      registerCodexExternalProviderInternal();
      if (disposedInternal) {
        return;
      }
    }
    notifyIfActiveInternal();
  }

  void relayChildChangeInternal() {
    notifyIfActiveInternal();
  }

  void notifyIfActiveInternal() {
    if (disposedInternal) {
      return;
    }
    notifyListeners();
  }

  Future<void> persistGoTaskArtifactsForSessionInternal(
    String sessionKey,
    GoTaskServiceResult result,
  ) async {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final syncedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    final existingThread = requireTaskThreadForSessionInternal(
      normalizedSessionKey,
    );
    upsertTaskThreadInternal(
      normalizedSessionKey,
      lastArtifactSyncAtMs: syncedAtMs,
      lastArtifactSyncStatus: 'syncing',
      lastTaskArtifactRelativePaths: const <String>[],
      updatedAtMs: syncedAtMs,
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
    if (existingThread.workspaceBinding.workspaceKind !=
        WorkspaceKind.localFs) {
      upsertTaskThreadInternal(
        normalizedSessionKey,
        lastArtifactSyncAtMs: syncedAtMs,
        lastArtifactSyncStatus: 'skipped-non-local-workspace',
        updatedAtMs: syncedAtMs,
      );
      return;
    }
    final artifacts = result.artifacts;
    if (artifacts.isEmpty) {
      upsertTaskThreadInternal(
        normalizedSessionKey,
        lastArtifactSyncAtMs: syncedAtMs,
        lastArtifactSyncStatus:
            isOpenClawNoExportedArtifactsGuardResultInternal(result)
            ? 'no-exported-artifacts'
            : 'no-artifacts',
        updatedAtMs: syncedAtMs,
      );
      return;
    }
    final root = Directory(existingThread.workspaceBinding.workspacePath);
    await root.create(recursive: true);

    var wroteArtifact = false;
    var failedArtifact = false;
    var skippedArtifact = false;
    final currentTaskArtifactRelativePaths = <String>[];
    for (final artifact in artifacts) {
      final relativePath = _sanitizeArtifactRelativePathInternal(
        artifact.relativePath,
      );
      if (relativePath.isEmpty) {
        skippedArtifact = true;
        continue;
      }
      final bytesResult = await _artifactBytesResultInternal(artifact);
      if (bytesResult.failed) {
        failedArtifact = true;
      }
      final bytes = bytesResult.bytes;
      if (bytes == null) {
        final existingArtifactPaths =
            await _existingWorkspaceArtifactPathsInternal(root, relativePath);
        if (existingArtifactPaths.isEmpty) {
          skippedArtifact = true;
          continue;
        }
        wroteArtifact = true;
        _appendArtifactRelativePathsInternal(
          currentTaskArtifactRelativePaths,
          existingArtifactPaths,
        );
        continue;
      }
      final target = await _nextArtifactTargetFileInternal(root, relativePath);
      await target.parent.create(recursive: true);
      final verified = await _writeVerifiedArtifactBytesInternal(
        target,
        bytes,
        artifact,
      );
      if (!verified) {
        failedArtifact = true;
        continue;
      }
      wroteArtifact = true;
      final writtenRelativePath =
          DesktopThreadArtifactService.relativePathInternal(
            root.path,
            target.path,
          );
      if (writtenRelativePath != null && writtenRelativePath.isNotEmpty) {
        _appendArtifactRelativePathsInternal(
          currentTaskArtifactRelativePaths,
          <String>[writtenRelativePath],
        );
      }
    }

    final syncStatus = wroteArtifact
        ? (failedArtifact || skippedArtifact ? 'partial' : 'synced')
        : failedArtifact
        ? 'download-failed'
        : 'no-artifacts';
    upsertTaskThreadInternal(
      normalizedSessionKey,
      lastArtifactSyncAtMs: syncedAtMs,
      lastArtifactSyncStatus: syncStatus,
      lastTaskArtifactRelativePaths: currentTaskArtifactRelativePaths,
      updatedAtMs: syncedAtMs,
    );
  }

  Future<List<int>?> artifactBytesInternal(
    GoTaskServiceArtifact artifact,
  ) async {
    return (await _artifactBytesResultInternal(artifact)).bytes;
  }

  Future<_ArtifactBytesResult> _artifactBytesResultInternal(
    GoTaskServiceArtifact artifact,
  ) async {
    if (artifact.hasInlineContent) {
      return _ArtifactBytesResult.bytes(
        _decodeArtifactContentInternal(artifact),
      );
    }
    final rawDownloadUrl = artifact.downloadUrl.trim();
    if (rawDownloadUrl.isEmpty) {
      return const _ArtifactBytesResult.skipped();
    }
    final uri = Uri.tryParse(rawDownloadUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return const _ArtifactBytesResult.skipped();
    }
    final bridgeEndpoint = resolveBridgeAcpEndpointInternal();
    final sameBridgeHost =
        bridgeEndpoint != null &&
        uri.host.trim().toLowerCase() ==
            bridgeEndpoint.host.trim().toLowerCase();
    if (!sameBridgeHost) {
      return const _ArtifactBytesResult.skipped();
    }
    final authorization =
        await resolveBridgeArtifactAuthorizationHeaderInternal(uri);
    if (authorization == null || authorization.trim().isEmpty) {
      return const _ArtifactBytesResult.skipped();
    }
    final bytes = await _downloadBridgeArtifactBytesInternal(
      uri,
      authorization,
    );
    if (bytes == null) {
      return const _ArtifactBytesResult.failed();
    }
    return _ArtifactBytesResult.bytes(bytes);
  }

  Future<List<int>?> _downloadBridgeArtifactBytesInternal(
    Uri uri,
    String authorization,
  ) async {
    var bytes = <int>[];
    const maxAttempts = 5;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final result = await _downloadBridgeArtifactBytesOnceInternal(
        uri,
        authorization,
        rangeStart: bytes.length,
      );
      if (result.reset) {
        bytes = <int>[];
      }
      if (result.bytes.isNotEmpty) {
        bytes.addAll(result.bytes);
      }
      if (result.completed) {
        return bytes;
      }
      if (attempt < maxAttempts) {
        final delayMs = math.min(2000, 250 * (1 << (attempt - 1)));
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
    return null;
  }

  Future<_ArtifactDownloadAttemptResult>
  _downloadBridgeArtifactBytesOnceInternal(
    Uri uri,
    String authorization, {
    required int rangeStart,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    var reset = false;
    final bytes = <int>[];
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, authorization);
      if (rangeStart > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$rangeStart-');
      }
      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        reset = rangeStart > 0;
      } else if (response.statusCode == HttpStatus.partialContent) {
        reset = false;
      } else {
        return const _ArtifactDownloadAttemptResult.retry();
      }
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return _ArtifactDownloadAttemptResult(
        bytes: bytes,
        completed: true,
        reset: reset,
      );
    } on HttpException {
      return _ArtifactDownloadAttemptResult(
        bytes: bytes,
        completed: false,
        reset: reset,
      );
    } on SocketException {
      return _ArtifactDownloadAttemptResult(
        bytes: bytes,
        completed: false,
        reset: reset,
      );
    } on TimeoutException {
      return _ArtifactDownloadAttemptResult(
        bytes: bytes,
        completed: false,
        reset: reset,
      );
    } on StateError {
      return _ArtifactDownloadAttemptResult(
        bytes: bytes,
        completed: false,
        reset: reset,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _writeVerifiedArtifactBytesInternal(
    File target,
    List<int> bytes,
    GoTaskServiceArtifact artifact,
  ) async {
    final expectedSize = artifact.sizeBytes;
    if (expectedSize != null && expectedSize != bytes.length) {
      return false;
    }
    final expectedSha256 = artifact.sha256.trim().toLowerCase();
    if (expectedSha256.isNotEmpty &&
        expectedSha256.length == 64 &&
        crypto.sha256.convert(bytes).toString() != expectedSha256) {
      return false;
    }
    final temp = File(
      '${target.path}.xworkmate-sync-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      if (await target.exists()) {
        await target.delete();
      }
      await temp.rename(target.path);
      return true;
    } catch (_) {
      if (await temp.exists()) {
        await temp.delete();
      }
      return false;
    }
  }

  Uri? resolveGatewayAcpEndpointInternal() {
    return resolveBridgeAcpEndpointInternal();
  }

  String? runtimeEnvironmentValueInternal(String key) {
    final override = environmentOverrideInternal?[key]?.trim() ?? '';
    if (override.isNotEmpty) {
      return override;
    }
    if (environmentOverrideInternal != null) {
      return null;
    }
    final value = Platform.environment[key]?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Uri? resolveBridgeAcpEndpointInternal() {
    final uri = Uri.parse(kManagedBridgeServerUrl);
    return uri.replace(query: null, fragment: null);
  }

  Uri? resolveExternalAcpEndpointForTargetInternal(AssistantExecutionTarget _) {
    return resolveBridgeAcpEndpointInternal();
  }

  bool isBridgeAcpRuntimeConfiguredInternal() {
    final bridgeEndpoint = resolveBridgeAcpEndpointInternal();
    if (bridgeEndpoint == null) {
      return false;
    }
    final accountSyncState = settingsControllerInternal.accountSyncState;
    if (settingsControllerInternal.accountSignedIn &&
        accountSyncState?.tokenConfigured.bridge == true) {
      return true;
    }
    final envToken = runtimeEnvironmentValueInternal('BRIDGE_AUTH_TOKEN');
    return envToken != null && envToken.isNotEmpty;
  }

  Uri? resolveExternalAcpEndpointForRequestInternal(
    GoTaskServiceRequest request,
  ) {
    final bridgeEndpoint = resolveBridgeAcpEndpointInternal();
    if (bridgeEndpoint == null) {
      return null;
    }
    return resolveAcpHttpRpcEndpoint(bridgeEndpoint);
  }

  Uri? gatewayProfileBaseUriInternal(GatewayConnectionProfile profile) {
    final host = profile.host.trim();
    if (host.isEmpty || profile.port <= 0) {
      return null;
    }
    return Uri(
      scheme: profile.tls ? 'https' : 'http',
      host: host,
      port: profile.port,
    );
  }

  Future<String?> resolveGatewayAcpAuthorizationHeaderInternal(
    Uri endpoint,
  ) async {
    final normalizedHost = endpoint.host.trim().toLowerCase();
    final bridgeEndpoint = resolveBridgeAcpEndpointInternal();
    final bridgeHost = bridgeEndpoint?.host.trim().toLowerCase() ?? '';
    final bridgePort = bridgeEndpoint?.port ?? 0;
    final matchesBridgeEndpoint =
        bridgeHost.isNotEmpty &&
        normalizedHost == bridgeHost &&
        (bridgePort <= 0 || endpoint.port == bridgePort);
    if (matchesBridgeEndpoint) {
      final bridgeToken = await _resolveManagedBridgeAuthTokenInternal();
      if (bridgeToken != null && bridgeToken.isNotEmpty) {
        return bridgeToken;
      }
    }
    return null;
  }

  Future<String?> resolveBridgeArtifactAuthorizationHeaderInternal(
    Uri endpoint,
  ) async {
    final normalizedHost = endpoint.host.trim().toLowerCase();
    final bridgeEndpoint = resolveBridgeAcpEndpointInternal();
    final bridgeHost = bridgeEndpoint?.host.trim().toLowerCase() ?? '';
    if (bridgeHost.isEmpty || normalizedHost != bridgeHost) {
      return null;
    }

    final bridgeToken = await _resolveManagedBridgeAuthTokenInternal();
    if (bridgeToken != null && bridgeToken.isNotEmpty) {
      return _normalizeAuthorizationHeaderInternal(bridgeToken);
    }
    return null;
  }

  Future<String?> _resolveManagedBridgeAuthTokenInternal() async {
    final accountSyncState = settingsControllerInternal.accountSyncState;
    if (settingsControllerInternal.accountSignedIn &&
        accountSyncState?.tokenConfigured.bridge == true) {
      final bridgeToken = (await storeInternal.loadAccountManagedSecret(
        target: kAccountManagedSecretTargetBridgeAuthToken,
      ))?.trim();
      return bridgeToken?.isNotEmpty == true ? bridgeToken : null;
    }

    final envToken = runtimeEnvironmentValueInternal('BRIDGE_AUTH_TOKEN');
    return envToken?.isNotEmpty == true ? envToken : null;
  }

  int? gatewayProfileIndexMatchingEndpointInternal(Uri endpoint) {
    final normalizedHost = endpoint.host.trim().toLowerCase();
    final normalizedScheme = endpoint.scheme.trim().toLowerCase();
    final gateway = gatewayProfileBaseUriInternal(
      settings.primaryGatewayProfile,
    );
    if (gateway != null &&
        gateway.scheme.trim().toLowerCase() == normalizedScheme &&
        gateway.host.trim().toLowerCase() == normalizedHost &&
        gateway.port == endpoint.port) {
      return kGatewayRemoteProfileIndex;
    }
    return null;
  }

  RuntimeConnectionMode modeFromHostInternal(String host) {
    return RuntimeConnectionMode.remote;
  }

  AssistantExecutionTarget assistantExecutionTargetForModeInternal(
    RuntimeConnectionMode mode,
  ) {
    return AssistantExecutionTarget.gateway;
  }

  GatewayConnectionProfile gatewayProfileForAssistantExecutionTargetInternal(
    AssistantExecutionTarget target,
  ) => settings.primaryGatewayProfile;

  int gatewayProfileIndexForExecutionTargetInternal(
    AssistantExecutionTarget target,
  ) => kGatewayRemoteProfileIndex;
}

void _appendArtifactRelativePathsInternal(
  List<String> target,
  List<String> paths,
) {
  for (final path in paths) {
    if (!target.contains(path)) {
      target.add(path);
    }
  }
}

Future<List<String>> _existingWorkspaceArtifactPathsInternal(
  Directory root,
  String relativePath,
) async {
  final targetPath = DesktopThreadArtifactService.resolveAbsolutePathInternal(
    root.path,
    relativePath,
  );
  final targetType = await FileSystemEntity.type(
    targetPath,
    followLinks: false,
  );
  if (targetType == FileSystemEntityType.file) {
    final resolvedRelativePath =
        DesktopThreadArtifactService.relativePathInternal(
          root.path,
          targetPath,
        );
    return resolvedRelativePath == null || resolvedRelativePath.isEmpty
        ? const <String>[]
        : <String>[resolvedRelativePath];
  }
  if (targetType != FileSystemEntityType.directory) {
    return const <String>[];
  }
  final files = await DesktopThreadArtifactService().collectFilesInternal(
    Directory(targetPath),
  );
  final paths = <String>[];
  for (final file in files) {
    final resolvedRelativePath =
        DesktopThreadArtifactService.relativePathInternal(root.path, file.path);
    if (resolvedRelativePath != null && resolvedRelativePath.isNotEmpty) {
      paths.add(resolvedRelativePath);
    }
  }
  paths.sort();
  return paths;
}

String _normalizeAuthorizationHeaderInternal(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (_looksLikeAuthorizationHeaderInternal(trimmed)) {
    return trimmed;
  }
  return 'Bearer $trimmed';
}

bool _looksLikeAuthorizationHeaderInternal(String raw) {
  final separatorIndex = raw.indexOf(RegExp(r'\s'));
  if (separatorIndex <= 0 || separatorIndex >= raw.length - 1) {
    return false;
  }
  final scheme = raw.substring(0, separatorIndex);
  return RegExp(r"^[A-Za-z][A-Za-z0-9!#$%&'*+.^_`|~-]*$").hasMatch(scheme);
}

String _sanitizeArtifactRelativePathInternal(String raw) {
  final trimmed = raw.trim().replaceAll('\\', '/');
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed
      .split('/')
      .where(
        (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
      )
      .join('/');
}

class _ArtifactBytesResult {
  const _ArtifactBytesResult._({this.bytes, required this.failed});

  const _ArtifactBytesResult.skipped() : this._(failed: false);

  const _ArtifactBytesResult.failed() : this._(failed: true);

  const _ArtifactBytesResult.bytes(List<int> bytes)
    : this._(bytes: bytes, failed: false);

  final List<int>? bytes;
  final bool failed;
}

class _ArtifactDownloadAttemptResult {
  const _ArtifactDownloadAttemptResult({
    required this.bytes,
    required this.completed,
    required this.reset,
  });

  const _ArtifactDownloadAttemptResult.retry()
    : this(bytes: const <int>[], completed: false, reset: false);

  final List<int> bytes;
  final bool completed;
  final bool reset;
}

List<int> _decodeArtifactContentInternal(GoTaskServiceArtifact artifact) {
  final encoding = artifact.encoding.trim().toLowerCase();
  if (encoding == 'base64') {
    return base64Decode(artifact.content);
  }
  return utf8.encode(artifact.content);
}

Future<File> _nextArtifactTargetFileInternal(
  Directory root,
  String relativePath,
) async {
  final segments = relativePath.split('/');
  final fileName = segments.removeLast();
  final parent = segments.isEmpty
      ? root
      : Directory('${root.path}/${segments.join('/')}');
  final dotIndex = fileName.lastIndexOf('.');
  final baseName = dotIndex <= 0 ? fileName : fileName.substring(0, dotIndex);
  final extension = dotIndex <= 0 ? '' : fileName.substring(dotIndex);
  var candidate = File('${parent.path}/$fileName');
  if (!await candidate.exists()) {
    return candidate;
  }
  for (var version = 2; version < 1000; version += 1) {
    candidate = File('${parent.path}/$baseName.v$version$extension');
    if (!await candidate.exists()) {
      return candidate;
    }
  }
  return File(
    '${parent.path}/$baseName.${DateTime.now().millisecondsSinceEpoch}$extension',
  );
}
