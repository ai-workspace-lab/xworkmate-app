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

const int kOpenClawArtifactSyncMaxAttempts = 45;
const Duration kOpenClawArtifactSyncMaxDuration = Duration(seconds: 90);
const String kOpenClawArtifactSyncTimeoutCode =
    'OPENCLAW_ARTIFACT_SYNC_TIMEOUT';

// running 轮询（OpenClaw run handle）兜底截止（T3）：
// 当 gateway 始终回 running（例如 bridge↔gateway socket 抖动后 run 态丢失）时，防止客户端无限轮询、
// 进度条永远卡在「任务运行中...」。预算按 taskLoadClass 估算，与 bridge 侧任务预算对齐
// (xworkmate-bridge/internal/acp/openclaw_async_tasks.go: short=10/long=30/complex=60 min)，再加 grace。
const Duration kOpenClawRunningPollGrace = Duration(minutes: 5);
const Duration kOpenClawRunningPollDefaultBudget = Duration(minutes: 30);
const Map<String, Duration> kOpenClawRunningPollBudgets = <String, Duration>{
  'short_task': Duration(minutes: 10),
  'long_task': Duration(minutes: 30),
  'complex_chain_task': Duration(minutes: 60),
  'complex_long_chain_task': Duration(minutes: 60),
};
const String kOpenClawRunningPollTimeoutCode = 'OPENCLAW_RUN_POLL_TIMEOUT';

// T5（docs/cases/06 §5）：轮询期间 App↔bridge 传输瞬断（ACP_HTTP_CONNECTION_CLOSED）时，
// 不直接硬失败，而是有界重试续轮询（降级为「后台续跑·重连中」）。连续瞬断超过该上限才落终态，
// 避免桥/网关真正不可达时无限重连。每次成功 getTask 会重置计数，仅累计「连续」瞬断。
const int kOpenClawPollTransientRetryLimit = 5;

bool openClawArtifactPathHasRequiredExtension(String path, String extension) {
  final normalizedPath = path.trim().toLowerCase();
  final normalizedExtension = extension.trim().toLowerCase().replaceFirst(
    RegExp(r'^\.+'),
    '',
  );
  return normalizedExtension.isNotEmpty &&
      normalizedPath.endsWith('.$normalizedExtension');
}

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
    await saveAppUiStateInternal(
      appUiState.copyWith(assistantLastSessionKey: normalizedSessionKey),
    );
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

  Future<List<String>> recoverGatewayFailureArtifactPathsInternal(
    String sessionKey,
    Object error,
  ) async {
    if (interruptedAcpHttpTransportCodeInternal(error) !=
        'ACP_HTTP_CONNECTION_CLOSED') {
      return const <String>[];
    }
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final thread = taskThreadForSessionInternal(normalizedSessionKey);
    if (thread == null ||
        thread.workspaceBinding.workspaceKind != WorkspaceKind.localFs) {
      return const <String>[];
    }
    final root = Directory(thread.workspaceBinding.workspacePath);
    final policy = await _loadArtifactSyncPolicyInternal(
      root,
      thread.selectedSkillKeys,
    );
    return _workspaceArtifactPathsModifiedSinceInternal(
      root,
      thread.lifecycleState.lastRunAtMs,
      policy,
    );
  }

  String jsonLikeTextForDiagnosticsInternal(Object? value) {
    try {
      return jsonEncode(value);
    } catch (error) {
      debugPrint('JSON diagnostic encoding failed: $error');
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
    modelsControllerInternal.addListener(relayChildChangeInternal);
    cronJobsControllerInternal.addListener(relayChildChangeInternal);
    devicesControllerInternal.addListener(relayChildChangeInternal);
    tasksControllerInternal.addListener(relayChildChangeInternal);
  }

  void detachChildListenersInternal() {
    runtimeCoordinatorInternal.removeListener(relayChildChangeInternal);
    settingsControllerInternal.removeListener(
      handleSettingsControllerChangeInternal,
    );
    agentsControllerInternal.removeListener(relayChildChangeInternal);
    sessionsControllerInternal.removeListener(relayChildChangeInternal);
    chatControllerInternal.removeListener(relayChildChangeInternal);
    modelsControllerInternal.removeListener(relayChildChangeInternal);
    cronJobsControllerInternal.removeListener(relayChildChangeInternal);
    devicesControllerInternal.removeListener(relayChildChangeInternal);
    tasksControllerInternal.removeListener(relayChildChangeInternal);
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
    GoTaskServiceResult result, {
    int artifactSyncAttempts = 0,
    double? artifactSyncStartedAtMs,
  }) async {
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
    final root = Directory(existingThread.workspaceBinding.workspacePath);
    final artifactSyncPolicy = await _loadArtifactSyncPolicyInternal(
      root,
      existingThread.selectedSkillKeys,
    );
    final artifacts = result.artifacts;
    if (artifacts.isEmpty) {
      final association = existingThread.openClawTaskAssociation;
      final waitingForOpenClawArtifacts =
          association != null &&
          (association.requiresArtifactExport ||
              association.requiredArtifactExtensions.isNotEmpty) &&
          (association.artifactScope.trim().isNotEmpty ||
              association.artifactDirectory.trim().isNotEmpty) &&
          result.success;
      if (waitingForOpenClawArtifacts) {
        final firstSyncAtMs =
            artifactSyncStartedAtMs ?? existingThread.lastArtifactSyncAtMs;
        if (openClawArtifactSyncLimitReachedInternal(
          attemptCount: artifactSyncAttempts + 1,
          firstSyncAtMs: firstSyncAtMs,
          nowMs: syncedAtMs,
        )) {
          markOpenClawArtifactSyncTimeoutInternal(
            sessionKey: normalizedSessionKey,
            association: association,
            missingRequiredExtensions: association.requiredArtifactExtensions,
            remoteWorkingDirectory: result.remoteWorkingDirectory,
            remoteWorkspaceRefKind: result.remoteWorkspaceRefKind,
          );
          return;
        }
        upsertTaskThreadInternal(
          normalizedSessionKey,
          lifecycleStatus: 'running',
          lastResultCode: 'running',
          lastArtifactSyncAtMs: syncedAtMs,
          lastArtifactSyncStatus: 'syncing',
          openClawTaskAssociation: association.copyWith(
            status: 'syncing-artifacts',
          ),
          updatedAtMs: syncedAtMs,
        );
        return;
      }
      final currentTaskArtifactRelativePaths =
          await _workspaceArtifactPathsModifiedSinceInternal(
            root,
            existingThread.lifecycleState.lastRunAtMs,
            artifactSyncPolicy,
          );
      if (currentTaskArtifactRelativePaths.isNotEmpty) {
        upsertTaskThreadInternal(
          normalizedSessionKey,
          lastArtifactSyncAtMs: syncedAtMs,
          lastArtifactSyncStatus: 'synced',
          lastTaskArtifactRelativePaths: currentTaskArtifactRelativePaths,
          updatedAtMs: syncedAtMs,
        );
        return;
      }
      upsertTaskThreadInternal(
        normalizedSessionKey,
        lastArtifactSyncAtMs: syncedAtMs,
        lastArtifactSyncStatus: 'no-artifacts',
        updatedAtMs: syncedAtMs,
      );
      return;
    }
    await root.create(recursive: true);

    var wroteArtifact = false;
    var failedArtifact = false;
    var skippedArtifact = false;
    final previousSyncStatus =
        existingThread.lastArtifactSyncStatus?.trim().toLowerCase() ?? '';
    final preserveExistingArtifactPaths =
        previousSyncStatus == 'partial' ||
        previousSyncStatus == 'syncing' ||
        previousSyncStatus == 'running' ||
        previousSyncStatus == 'queued';
    final currentTaskArtifactPaths = <String>{};
    if (preserveExistingArtifactPaths) {
      for (final relativePath in existingThread.lastTaskArtifactRelativePaths) {
        final sanitized = _sanitizeArtifactRelativePathInternal(relativePath);
        if (sanitized.isNotEmpty && !artifactSyncPolicy.ignores(sanitized)) {
          currentTaskArtifactPaths.add(sanitized);
        }
      }
    }
    for (final artifact in artifacts) {
      final relativePath = _sanitizeArtifactRelativePathInternal(
        artifact.relativePath,
      );
      if (relativePath.isEmpty || artifactSyncPolicy.ignores(relativePath)) {
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
            await _existingWorkspaceArtifactPathsInternal(
              root,
              relativePath,
              artifactSyncPolicy,
            );
        if (existingArtifactPaths.isEmpty) {
          skippedArtifact = true;
          continue;
        }
        currentTaskArtifactPaths.addAll(existingArtifactPaths);
        wroteArtifact = true;
        continue;
      }
      if (artifactSyncPolicy.rejects(artifact, relativePath, bytes)) {
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
      final resolvedRelativePath =
          DesktopThreadArtifactService.relativePathInternal(
            root.path,
            target.path,
          );
      if (resolvedRelativePath == null || resolvedRelativePath.isEmpty) {
        failedArtifact = true;
        continue;
      }
      currentTaskArtifactPaths.add(resolvedRelativePath);
      wroteArtifact = true;
    }

    final thread = taskThreadForSessionInternal(normalizedSessionKey);
    final association = thread?.openClawTaskAssociation;
    final requiredExts =
        association?.requiredArtifactExtensions ?? const <String>[];
    final missingRequired = requiredExts
        .where((ext) {
          return !currentTaskArtifactPaths.any(
            (p) => openClawArtifactPathHasRequiredExtension(p, ext),
          );
        })
        .toList(growable: false);

    final shouldKeepPollingAfterDownloadFailure =
        !wroteArtifact &&
        failedArtifact &&
        result.success &&
        association != null &&
        (association.requiresArtifactExport ||
            association.requiredArtifactExtensions.isNotEmpty) &&
        (association.artifactScope.trim().isNotEmpty ||
            association.artifactDirectory.trim().isNotEmpty);
    if (shouldKeepPollingAfterDownloadFailure) {
      final firstSyncAtMs =
          artifactSyncStartedAtMs ?? existingThread.lastArtifactSyncAtMs;
      if (openClawArtifactSyncLimitReachedInternal(
        attemptCount: artifactSyncAttempts + 1,
        firstSyncAtMs: firstSyncAtMs,
        nowMs: syncedAtMs,
      )) {
        markOpenClawArtifactSyncTimeoutInternal(
          sessionKey: normalizedSessionKey,
          association: association,
          missingRequiredExtensions: missingRequired.isEmpty
              ? association.requiredArtifactExtensions
              : missingRequired,
          remoteWorkingDirectory: result.remoteWorkingDirectory,
          remoteWorkspaceRefKind: result.remoteWorkspaceRefKind,
        );
        return;
      }
      upsertTaskThreadInternal(
        normalizedSessionKey,
        lifecycleStatus: 'running',
        lastResultCode: 'running',
        lastArtifactSyncAtMs: syncedAtMs,
        lastArtifactSyncStatus: 'syncing',
        lastTaskArtifactRelativePaths: const <String>[],
        openClawTaskAssociation: association.copyWith(
          status: 'syncing-artifacts',
        ),
        updatedAtMs: syncedAtMs,
      );
      return;
    }

    final syncStatus = wroteArtifact
        ? (failedArtifact || skippedArtifact || missingRequired.isNotEmpty
              ? 'partial'
              : 'synced')
        : failedArtifact
        ? 'download-failed'
        : 'no-artifacts';
    final currentTaskArtifactRelativePaths = wroteArtifact
        ? (currentTaskArtifactPaths.toList(growable: false)..sort())
        : const <String>[];
    upsertTaskThreadInternal(
      normalizedSessionKey,
      lastArtifactSyncAtMs: syncedAtMs,
      lastArtifactSyncStatus: syncStatus,
      lastTaskArtifactRelativePaths: currentTaskArtifactRelativePaths,
      updatedAtMs: syncedAtMs,
    );
  }

  // T3: running 轮询是否已越过兜底截止。
  // 预算从 run 开始时间(startedAtMs)起算；startedAtMs 缺失时退化为本轮首次轮询时间(firstPollAtMs)。
  bool openClawRunningPollDeadlineReachedInternal({
    required double? startedAtMs,
    required String taskLoadClass,
    required double? firstPollAtMs,
    double? nowMs,
  }) {
    final anchorMs = (startedAtMs != null && startedAtMs > 0)
        ? startedAtMs
        : firstPollAtMs;
    if (anchorMs == null || anchorMs <= 0) {
      return false;
    }
    final budget =
        kOpenClawRunningPollBudgets[taskLoadClass.trim().toLowerCase()] ??
        kOpenClawRunningPollDefaultBudget;
    final limitMs = (budget + kOpenClawRunningPollGrace).inMilliseconds
        .toDouble();
    final currentMs = nowMs ?? DateTime.now().millisecondsSinceEpoch.toDouble();
    return currentMs - anchorMs >= limitMs;
  }

  // T3: running 轮询越过兜底截止时，落到「可恢复的中断」终态并退出轮询。
  // 注意：服务端可能其实已经跑完，只是结果回传链路断了；因此提示用户可重发以拿回结果。
  void markOpenClawRunningPollTimeoutInternal({
    required String sessionKey,
    required OpenClawTaskAssociation association,
  }) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    aiGatewayPendingSessionKeysInternal.remove(normalizedSessionKey);
    clearAiGatewayStreamingTextInternal(normalizedSessionKey);
    upsertTaskThreadInternal(
      normalizedSessionKey,
      lifecycleStatus: 'interrupted',
      lastResultCode: kOpenClawRunningPollTimeoutCode,
      lastRunAtMs: nowMs,
      lastArtifactSyncAtMs: nowMs,
      lastArtifactSyncStatus: 'interrupted',
      clearOpenClawTaskAssociation: true,
      updatedAtMs: nowMs,
    );
    appendLocalSessionMessageInternal(
      normalizedSessionKey,
      GatewayChatMessage(
        id: nextLocalMessageIdInternal(),
        role: 'assistant',
        text: appText(
          '任务等待已超过预算上限，已结束本轮等待。任务可能已在后台完成但结果回传中断，请重新发送请求以拿回结果。错误码：OPENCLAW_RUN_POLL_TIMEOUT',
          'Waiting for the task exceeded its budget, so this round was ended. The task may have finished in the background but its result could not be delivered. Send the request again to retrieve the result. Error code: OPENCLAW_RUN_POLL_TIMEOUT',
        ),
        timestampMs: nowMs,
        toolCallId: null,
        toolName: null,
        stopReason: null,
        pending: false,
        error: true,
      ),
      persistInThreadContext: true,
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
    unawaited(flushAssistantThreadPersistenceInternal());
  }

  bool openClawArtifactSyncLimitReachedInternal({
    required int attemptCount,
    required double? firstSyncAtMs,
    double? nowMs,
  }) {
    if (attemptCount >= kOpenClawArtifactSyncMaxAttempts) {
      return true;
    }
    final startedAtMs = firstSyncAtMs;
    if (startedAtMs == null || startedAtMs <= 0) {
      return false;
    }
    final currentMs = nowMs ?? DateTime.now().millisecondsSinceEpoch.toDouble();
    return currentMs - startedAtMs >=
        kOpenClawArtifactSyncMaxDuration.inMilliseconds;
  }

  void markOpenClawArtifactSyncTimeoutInternal({
    required String sessionKey,
    required OpenClawTaskAssociation association,
    Iterable<String> missingRequiredExtensions = const <String>[],
    String? remoteWorkingDirectory,
    WorkspaceRefKind? remoteWorkspaceRefKind,
  }) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    final missing =
        missingRequiredExtensions
            .map((ext) => ext.trim())
            .where((ext) => ext.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final missingLabel = missing.isEmpty ? '' : missing.join(', ');
    final messageText = missing.isEmpty
        ? appText(
            'OpenClaw artifact 同步已超时，已按部分结果结束本轮任务。',
            'OpenClaw artifact sync timed out; this task was finished with partial results.',
          )
        : appText(
            'OpenClaw artifact 同步已超时，缺少必需文件类型：$missingLabel。已按部分结果结束本轮任务。',
            'OpenClaw artifact sync timed out before required artifact types arrived: $missingLabel. This task was finished with partial results.',
          );
    aiGatewayPendingSessionKeysInternal.remove(normalizedSessionKey);
    clearAiGatewayStreamingTextInternal(normalizedSessionKey);
    upsertTaskThreadInternal(
      normalizedSessionKey,
      lifecycleStatus: 'ready',
      lastResultCode: kOpenClawArtifactSyncTimeoutCode,
      lastRemoteWorkingDirectory:
          remoteWorkingDirectory?.trim().isNotEmpty == true
          ? remoteWorkingDirectory!.trim()
          : null,
      lastRemoteWorkspaceRefKind: remoteWorkspaceRefKind,
      lastArtifactSyncAtMs: nowMs,
      lastArtifactSyncStatus: 'partial',
      openClawTaskAssociation: association.copyWith(status: 'completed'),
      updatedAtMs: nowMs,
    );
    appendLocalSessionMessageInternal(
      normalizedSessionKey,
      GatewayChatMessage(
        id: nextLocalMessageIdInternal(),
        role: 'assistant',
        text: messageText,
        timestampMs: nowMs,
        toolCallId: null,
        toolName: null,
        stopReason: null,
        pending: false,
        error: false,
      ),
      persistInThreadContext: true,
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
    unawaited(flushAssistantThreadPersistenceInternal());
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
    var uri = Uri.tryParse(rawDownloadUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return const _ArtifactBytesResult.skipped();
    }
    final bridgeEndpoint = resolveBridgeAcpEndpointInternal();
    final bridgeHost = bridgeEndpoint?.host.trim().toLowerCase() ?? '';
    var downloadHost = uri.host.trim().toLowerCase();
    final isLoopback =
        downloadHost == '127.0.0.1' ||
        downloadHost == 'localhost' ||
        downloadHost == '::1';
    var sameBridgeHost =
        bridgeEndpoint != null && (downloadHost == bridgeHost || isLoopback);
    // A local/self-hosted bridge can decorate artifacts with its configured
    // public URL. Keep the signed path/query, but download through the bridge
    // endpoint the user actually selected so credentials never go cross-host.
    if (!sameBridgeHost &&
        bridgeEndpoint != null &&
        uri.path == '/artifacts/openclaw/download' &&
        uri.queryParameters['sig']?.trim().isNotEmpty == true) {
      uri = uri.replace(
        scheme: bridgeEndpoint.scheme,
        host: bridgeEndpoint.host,
        port: bridgeEndpoint.hasPort ? bridgeEndpoint.port : null,
      );
      downloadHost = uri.host.trim().toLowerCase();
      sameBridgeHost = downloadHost == bridgeHost;
    }
    if (!sameBridgeHost) {
      return const _ArtifactBytesResult.skipped();
    }
    final authorization =
        await resolveBridgeArtifactAuthorizationHeaderInternal(uri);
    if (authorization == null || authorization.trim().isEmpty) {
      return const _ArtifactBytesResult.failed();
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
    } catch (error) {
      debugPrint('Artifact write failed for ${target.path}: $error');
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
    final accountSyncState = settingsControllerInternal.accountSyncState;
    final managedBridgeReady =
        settingsControllerInternal.accountSessionTokenInternal
            .trim()
            .isNotEmpty &&
        accountSyncState?.syncState.trim().toLowerCase() == 'ready' &&
        accountSyncState?.tokenConfigured.bridge == true;
    if (managedBridgeReady) {
      return Uri.parse(kManagedBridgeServerUrl);
    }

    final selfHosted = settingsControllerInternal
        .snapshot
        .acpBridgeServerModeConfig
        .selfHosted;
    final selfHostedUrl = selfHosted.serverUrl.trim();
    if (selfHosted.isConfigured && selfHostedUrl.isNotEmpty) {
      final uri = Uri.tryParse(selfHostedUrl);
      if (uri != null && uri.hasScheme && uri.host.trim().isNotEmpty) {
        return uri.replace(query: null, fragment: null);
      }
    }

    return Uri.parse(kManagedBridgeServerUrl);
  }

  Uri? resolveExternalAcpEndpointForTargetInternal(AssistantExecutionTarget _) {
    return resolveBridgeAcpEndpointInternal();
  }

  bool isBridgeAcpRuntimeConfiguredInternal() {
    final bridgeEndpoint = resolveBridgeAcpEndpointInternal();
    if (bridgeEndpoint == null) {
      return false;
    }
    final selfHosted = settingsControllerInternal
        .snapshot
        .acpBridgeServerModeConfig
        .selfHosted;
    if (selfHosted.isConfigured) {
      return true;
    }
    final accountSyncState = settingsControllerInternal.accountSyncState;
    if (settingsControllerInternal.accountSessionTokenInternal
            .trim()
            .isNotEmpty &&
        accountSyncState?.syncState.trim().toLowerCase() == 'ready' &&
        accountSyncState?.tokenConfigured.bridge == true) {
      return true;
    }
    if (settingsControllerInternal.accountSessionTokenInternal
        .trim()
        .isNotEmpty) {
      return false;
    }
    final envToken = _runtimeBridgeAuthEnvTokenInternal();
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
    final accountSyncState = settingsControllerInternal.accountSyncState;
    final managedBridgeReady =
        settingsControllerInternal.accountSessionTokenInternal
            .trim()
            .isNotEmpty &&
        accountSyncState?.syncState.trim().toLowerCase() == 'ready' &&
        accountSyncState?.tokenConfigured.bridge == true;
    final matchesBridgeEndpoint =
        bridgeHost.isNotEmpty &&
        normalizedHost == bridgeHost &&
        (bridgePort <= 0 || endpoint.port == bridgePort);
    if (matchesBridgeEndpoint) {
      if (managedBridgeReady) {
        final bridgeToken = await _resolveManagedBridgeAuthTokenInternal();
        if (bridgeToken != null && bridgeToken.isNotEmpty) {
          return bridgeToken;
        }
      }
      final manualBridgeToken = await _resolveManualBridgeAuthTokenInternal();
      if (manualBridgeToken != null && manualBridgeToken.isNotEmpty) {
        return manualBridgeToken;
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
    final isLoopback =
        normalizedHost == '127.0.0.1' ||
        normalizedHost == 'localhost' ||
        normalizedHost == '::1';
    final accountSyncState = settingsControllerInternal.accountSyncState;
    final managedBridgeReady =
        settingsControllerInternal.accountSessionTokenInternal
            .trim()
            .isNotEmpty &&
        accountSyncState?.syncState.trim().toLowerCase() == 'ready' &&
        accountSyncState?.tokenConfigured.bridge == true;
    if (bridgeHost.isEmpty || (normalizedHost != bridgeHost && !isLoopback)) {
      return null;
    }

    if (managedBridgeReady) {
      final bridgeToken = await _resolveManagedBridgeAuthTokenInternal();
      if (bridgeToken != null && bridgeToken.isNotEmpty) {
        return _normalizeAuthorizationHeaderInternal(bridgeToken);
      }
    }

    final manualBridgeToken = await _resolveManualBridgeAuthTokenInternal();
    if (manualBridgeToken != null && manualBridgeToken.isNotEmpty) {
      return _normalizeAuthorizationHeaderInternal(manualBridgeToken);
    }
    final envBridgeToken = _runtimeBridgeAuthEnvTokenInternal();
    if (envBridgeToken != null && envBridgeToken.isNotEmpty) {
      return _normalizeAuthorizationHeaderInternal(envBridgeToken);
    }
    return null;
  }

  Future<String?> _resolveManualBridgeAuthTokenInternal() async {
    final selfHosted = settingsControllerInternal
        .snapshot
        .acpBridgeServerModeConfig
        .selfHosted;
    if (!selfHosted.isConfigured) {
      return null;
    }
    final passwordRef = selfHosted.passwordRef.trim();
    if (passwordRef.isEmpty) {
      return null;
    }
    final token = (await storeInternal.loadSecretValueByRef(
      passwordRef,
    ))?.trim();
    return token?.isNotEmpty == true ? token : null;
  }

  Future<String?> _resolveManagedBridgeAuthTokenInternal() async {
    if (settingsControllerInternal.accountSessionTokenInternal
        .trim()
        .isNotEmpty) {
      final bridgeToken = (await storeInternal.loadAccountManagedSecret(
        target: kAccountManagedSecretTargetBridgeAuthToken,
      ))?.trim();
      return bridgeToken?.isNotEmpty == true ? bridgeToken : null;
    }

    final envToken = _runtimeBridgeAuthEnvTokenInternal();
    return envToken?.isNotEmpty == true ? envToken : null;
  }

  String? _runtimeBridgeAuthEnvTokenInternal() {
    final aiWorkspaceToken = runtimeEnvironmentValueInternal(
      'AI_WORKSPACE_AUTH_TOKEN',
    );
    if (aiWorkspaceToken != null && aiWorkspaceToken.isNotEmpty) {
      return aiWorkspaceToken;
    }
    return runtimeEnvironmentValueInternal('BRIDGE_AUTH_TOKEN');
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

Future<List<String>> _existingWorkspaceArtifactPathsInternal(
  Directory root,
  String relativePath,
  _ArtifactSyncPolicy policy,
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
    return resolvedRelativePath == null ||
            resolvedRelativePath.isEmpty ||
            policy.ignores(resolvedRelativePath)
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
    if (resolvedRelativePath != null &&
        resolvedRelativePath.isNotEmpty &&
        !_isWorkspaceArtifactNoisePathInternal(resolvedRelativePath) &&
        !policy.ignores(resolvedRelativePath)) {
      paths.add(resolvedRelativePath);
    }
  }
  paths.sort();
  return paths;
}

Future<List<String>> _workspaceArtifactPathsModifiedSinceInternal(
  Directory root,
  double? sinceMs,
  _ArtifactSyncPolicy policy,
) async {
  final thresholdMs = sinceMs ?? 0;
  if (thresholdMs <= 0 || !await root.exists()) {
    return const <String>[];
  }
  final files = await DesktopThreadArtifactService().collectFilesInternal(root);
  final paths = <String>[];
  for (final file in files) {
    try {
      final stat = await file.stat();
      if (stat.modified.millisecondsSinceEpoch.toDouble() <= thresholdMs) {
        continue;
      }
      final resolvedRelativePath =
          DesktopThreadArtifactService.relativePathInternal(
            root.path,
            file.path,
          );
      if (resolvedRelativePath == null || resolvedRelativePath.isEmpty) {
        continue;
      }
      if (_isWorkspaceArtifactNoisePathInternal(resolvedRelativePath)) {
        continue;
      }
      if (policy.ignores(resolvedRelativePath)) {
        continue;
      }
      paths.add(resolvedRelativePath);
    } on FileSystemException {
      continue;
    }
  }
  paths.sort();
  return paths;
}

/// Directory segments that hold intermediate/process files, never final
/// task deliverables.
const Set<String> _workspaceArtifactNoiseDirectorySegmentsInternal = <String>{
  'tmp',
  'temp',
  'cache',
  'caches',
  'logs',
  '__pycache__',
  'node_modules',
  'venv',
};

/// File extensions that mark temporary/in-progress files.
const Set<String> _workspaceArtifactNoiseExtensionsInternal = <String>{
  'tmp',
  'temp',
  'part',
  'partial',
  'crdownload',
  'download',
  'lock',
  'swp',
  'swx',
  'bak',
  'old',
  'log',
  'pyc',
};

/// Whether [relativePath] looks like a temporary/intermediate file rather
/// than a final task result. Applied when the app scans the task workspace
/// to attribute files to the current run (empty-artifact fallback and
/// directory-scope artifact expansion) so the artifact pane only surfaces
/// final deliverables — explicit gateway-exported artifacts are not
/// filtered by this heuristic.
bool _isWorkspaceArtifactNoisePathInternal(String relativePath) {
  final segments = relativePath
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) {
    return true;
  }
  for (final segment in segments) {
    // Hidden files/directories (.DS_Store, .cache/, .git-ish leftovers).
    if (segment.startsWith('.')) {
      return true;
    }
    // Editor backup files ("report.md~").
    if (segment.endsWith('~')) {
      return true;
    }
  }
  for (final segment in segments.sublist(0, segments.length - 1)) {
    if (_workspaceArtifactNoiseDirectorySegmentsInternal.contains(
      segment.toLowerCase(),
    )) {
      return true;
    }
  }
  final baseName = segments.last;
  final dotIndex = baseName.lastIndexOf('.');
  if (dotIndex > 0 && dotIndex < baseName.length - 1) {
    final extension = baseName.substring(dotIndex + 1).toLowerCase();
    if (_workspaceArtifactNoiseExtensionsInternal.contains(extension)) {
      return true;
    }
  }
  return false;
}

Future<_ArtifactSyncPolicy> _loadArtifactSyncPolicyInternal(
  Directory root,
  List<String> selectedSkillKeys,
) async {
  final files = <File>[
    File(
      DesktopThreadArtifactService.resolveAbsolutePathInternal(
        root.path,
        'artifact-ignore.md',
      ),
    ),
  ];
  for (final skillKey in selectedSkillKeys) {
    final normalizedSkillKey = _sanitizeArtifactRelativePathInternal(skillKey);
    if (normalizedSkillKey.isEmpty) {
      continue;
    }
    files.add(
      File(
        DesktopThreadArtifactService.resolveAbsolutePathInternal(
          root.path,
          'skills/$normalizedSkillKey/artifact-ignore.md',
        ),
      ),
    );
  }
  final policyFiles = <String>[];
  for (final file in files) {
    final resolvedRelativePath =
        DesktopThreadArtifactService.relativePathInternal(root.path, file.path);
    if (resolvedRelativePath != null && resolvedRelativePath.isNotEmpty) {
      policyFiles.add(resolvedRelativePath);
    }
  }
  final policies = <_ArtifactSyncPolicy>[
    ..._defaultArtifactSyncPoliciesForSkillsInternal(selectedSkillKeys),
  ];
  try {
    for (final file in files) {
      if (!await file.exists()) {
        continue;
      }
      policies.add(_ArtifactSyncPolicy.parse(await file.readAsString()));
    }
  } on FileSystemException {
    return const _ArtifactSyncPolicy();
  }
  return _ArtifactSyncPolicy.merge(policies, policyFiles: policyFiles);
}

List<_ArtifactSyncPolicy> _defaultArtifactSyncPoliciesForSkillsInternal(
  List<String> selectedSkillKeys,
) {
  final hasVideoSkill = selectedSkillKeys.any((skillKey) {
    final normalized = _sanitizeArtifactRelativePathInternal(
      skillKey,
    ).toLowerCase();
    final segments = normalized.split('/');
    final leaf = segments.isEmpty ? normalized : segments.last;
    return leaf == 'it-infra-evolution-video-v2';
  });
  if (!hasVideoSkill) {
    return const <_ArtifactSyncPolicy>[];
  }
  return <_ArtifactSyncPolicy>[
    _ArtifactSyncPolicy.parse(
      '```artifact-ignore\n'
      'assets/audio/\n'
      'assets/images/\n'
      'build_segments/\n'
      'snapshots/\n'
      'tmp/\n'
      '```\n',
    ),
  ];
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

class _ArtifactSyncPolicy {
  const _ArtifactSyncPolicy({
    this.ignoreRules = const <_ArtifactIgnoreRule>[],
    this.rejectRules = const <_ArtifactRejectRule>[],
    this.policyFiles = const <String>[],
  });

  factory _ArtifactSyncPolicy.merge(
    List<_ArtifactSyncPolicy> policies, {
    required List<String> policyFiles,
  }) {
    return _ArtifactSyncPolicy(
      ignoreRules: policies
          .expand((policy) => policy.ignoreRules)
          .toList(growable: false),
      rejectRules: policies
          .expand((policy) => policy.rejectRules)
          .toList(growable: false),
      policyFiles: policyFiles,
    );
  }

  factory _ArtifactSyncPolicy.parse(String markdown) {
    final ignoreRules = <_ArtifactIgnoreRule>[];
    final rejectRules = <_ArtifactRejectRule>[];
    var inIgnoreBlock = false;
    var inRejectBlock = false;
    var fields = <String, List<String>>{};
    for (final rawLine in markdown.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.startsWith('```')) {
        final fenceName = line
            .replaceFirst(RegExp(r'^`+'), '')
            .trim()
            .toLowerCase();
        if (!inIgnoreBlock &&
            !inRejectBlock &&
            fenceName == 'artifact-ignore') {
          inIgnoreBlock = true;
          continue;
        }
        if (!inRejectBlock && fenceName == 'artifact-reject') {
          inRejectBlock = true;
          fields = <String, List<String>>{};
          continue;
        }
        if (inIgnoreBlock) {
          inIgnoreBlock = false;
        }
        if (inRejectBlock) {
          final rule = _ArtifactRejectRule.tryParse(fields);
          if (rule != null) {
            rejectRules.add(rule);
          }
          inRejectBlock = false;
          fields = <String, List<String>>{};
        }
        continue;
      }
      if (inIgnoreBlock) {
        if (line.isEmpty || line.startsWith('#')) {
          continue;
        }
        final rule = _ArtifactIgnoreRule.tryParse(line);
        if (rule != null) {
          ignoreRules.add(rule);
        }
        continue;
      }
      if (!inRejectBlock || line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final separator = line.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final key = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      fields.putIfAbsent(key, () => <String>[]).add(value);
    }
    return _ArtifactSyncPolicy(
      ignoreRules: ignoreRules,
      rejectRules: rejectRules,
    );
  }

  final List<_ArtifactIgnoreRule> ignoreRules;
  final List<_ArtifactRejectRule> rejectRules;
  final List<String> policyFiles;

  bool ignores(String relativePath) {
    if (_isWorkspaceArtifactNoisePathInternal(relativePath)) {
      return true;
    }
    final normalizedPath = _sanitizeArtifactRelativePathInternal(relativePath);
    if (DesktopThreadArtifactService.baseNameInternal(normalizedPath) ==
            'artifact-ignore.md' ||
        policyFiles.contains(normalizedPath)) {
      return true;
    }
    for (final rule in ignoreRules) {
      if (rule.matches(normalizedPath)) {
        return true;
      }
    }
    return false;
  }

  bool rejects(
    GoTaskServiceArtifact artifact,
    String relativePath,
    List<int> bytes,
  ) {
    for (final rule in rejectRules) {
      if (rule.matches(artifact, relativePath, bytes)) {
        return true;
      }
    }
    return false;
  }
}

class _ArtifactIgnoreRule {
  const _ArtifactIgnoreRule(this.pattern);

  static _ArtifactIgnoreRule? tryParse(String raw) {
    final pattern = _sanitizeArtifactRelativePathInternal(raw);
    if (pattern.isEmpty) {
      return null;
    }
    return _ArtifactIgnoreRule(raw.trim());
  }

  final String pattern;

  bool matches(String relativePath) {
    final normalizedPath = _sanitizeArtifactRelativePathInternal(
      relativePath,
    ).toLowerCase();
    final trimmedPattern = pattern.trim();
    if (trimmedPattern.endsWith('/')) {
      final directoryPattern = _sanitizeArtifactRelativePathInternal(
        trimmedPattern.substring(0, trimmedPattern.length - 1),
      ).toLowerCase();
      return normalizedPath == directoryPattern ||
          normalizedPath.startsWith('$directoryPattern/');
    }
    return _matchesArtifactPathPatternInternal(normalizedPath, trimmedPattern);
  }
}

class _ArtifactRejectRule {
  const _ArtifactRejectRule({
    required this.path,
    required this.contentType,
    required this.contains,
  });

  static _ArtifactRejectRule? tryParse(Map<String, List<String>> fields) {
    final contains = fields['contains'] ?? const <String>[];
    if (contains.isEmpty) {
      return null;
    }
    return _ArtifactRejectRule(
      path: _firstValue(fields['path']),
      contentType: _firstValue(fields['contenttype']),
      contains: contains,
    );
  }

  final String? path;
  final String? contentType;
  final List<String> contains;

  static String? _firstValue(List<String>? values) {
    if (values == null || values.isEmpty) {
      return null;
    }
    return values.first;
  }

  bool matches(
    GoTaskServiceArtifact artifact,
    String relativePath,
    List<int> bytes,
  ) {
    if (path != null &&
        !_matchesArtifactPathPatternInternal(relativePath, path!)) {
      return false;
    }
    if (contentType != null &&
        !artifact.contentType.trim().toLowerCase().contains(
          contentType!.trim().toLowerCase(),
        )) {
      return false;
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    for (final needle in contains) {
      if (!text.contains(needle)) {
        return false;
      }
    }
    return true;
  }
}

bool _matchesArtifactPathPatternInternal(String relativePath, String pattern) {
  final normalizedPath = _sanitizeArtifactRelativePathInternal(
    relativePath,
  ).toLowerCase();
  final normalizedPattern = _sanitizeArtifactRelativePathInternal(
    pattern,
  ).toLowerCase();
  if (normalizedPath.isEmpty || normalizedPattern.isEmpty) {
    return false;
  }
  if (normalizedPattern == normalizedPath) {
    return true;
  }
  if (normalizedPattern.startsWith('*.')) {
    return !normalizedPath.contains('/') &&
        normalizedPath.endsWith(normalizedPattern.substring(1));
  }
  if (normalizedPattern.startsWith('**/*.')) {
    return normalizedPath.endsWith(normalizedPattern.substring(4));
  }
  return false;
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
