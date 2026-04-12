// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'app_metadata.dart';
import 'app_capabilities.dart';
import 'app_store_policy.dart';
import 'ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/device_identity_store.dart';
import '../runtime/aris_bundle.dart';
import '../runtime/go_core.dart';
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
import '../runtime/skill_directory_access.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_single_agent.dart';
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
    late final Future<void> next;
    next = previous
        .catchError((_) {})
        .then((_) async {
          try {
            completer.complete(await task());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .whenComplete(() {
          if (identical(
            assistantThreadTurnQueuesInternal[normalizedThreadId],
            next,
          )) {
            assistantThreadTurnQueuesInternal.remove(normalizedThreadId);
          }
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
    if ((lowered.contains('acp_endpoint_missing') ||
            lowered.contains('missing acp endpoint')) &&
        target == AssistantExecutionTarget.singleAgent) {
      return appText(
        '当前线程还没有同步到 Bridge Server。请先登录账号并在设置里完成同步后再重试。',
        'This thread does not have a synced bridge server yet. Sign in and complete Settings sync before trying again.',
      );
    }
    if (lowered.contains('gateway not connected') ||
        lowered.contains('code: offline') ||
        lowered.contains('offlin') && lowered.contains('gateway')) {
      if (target == AssistantExecutionTarget.singleAgent) {
        final selection = singleAgentProviderForSession(
          sessionsControllerInternal.currentSessionKey,
        );
        final provider =
            advertisedSingleAgentProviderInternal(selection) ?? selection;
        final providerLabel = provider.isUnspecified
            ? appText('Bridge Provider', 'Bridge Provider')
            : provider.label;
        final address = _extractGatewayAddressFromErrorInternal(raw);
        return address.isEmpty
            ? appText(
                '当前线程的 Bridge Provider（$providerLabel）未连接。请先在设置里连接并同步后再重试。',
                'The Bridge Provider for this thread ($providerLabel) is not connected. Connect and sync it from Settings, then try again.',
              )
            : appText(
                '当前线程的 Bridge Provider（$providerLabel）未连接：$address。请先在设置里连接并同步后再重试。',
                'The Bridge Provider for this thread ($providerLabel) is not connected: $address. Connect and sync it from Settings, then try again.',
              );
      }
      final profile = gatewayProfileForAssistantExecutionTargetInternal(target);
      final address = gatewayAddressLabelInternal(profile);
      final targetLabel = target.label;
      return address == appText('未连接目标', 'No target')
          ? appText(
              '当前线程目标网关未连接。请先连接 $targetLabel，然后再重试。',
              'The selected gateway target for this thread is not connected. Connect $targetLabel first, then try again.',
            )
          : appText(
              '当前线程目标网关未连接：$address。请先连接后再重试。',
              'The selected gateway target for this thread is not connected: $address. Connect it first, then try again.',
            );
    }
    return raw;
  }

  String _extractGatewayAddressFromErrorInternal(String raw) {
    final match = RegExp(
      r'((?:\d{1,3}\.){3}\d{1,3}:\d+|localhost:\d+|[a-zA-Z0-9.-]+:\d+)',
    ).firstMatch(raw);
    return match?.group(1)?.trim() ?? '';
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
  ) {
    final normalizedRuntimeMode =
        snapshot.codeAgentRuntimeMode == CodeAgentRuntimeMode.builtIn
        ? CodeAgentRuntimeMode.externalCli
        : snapshot.codeAgentRuntimeMode;
    codexRuntimeWarningInternal =
        snapshot.codeAgentRuntimeMode == CodeAgentRuntimeMode.builtIn
        ? appText(
            '内置 Codex 运行时当前仅保留为未来扩展位；已自动切换为 External Codex CLI。',
            'Built-in Codex runtime is reserved for a future release; XWorkmate switched back to External Codex CLI automatically.',
          )
        : null;
    if (normalizedRuntimeMode == snapshot.codeAgentRuntimeMode) {
      return snapshot;
    }
    return snapshot.copyWith(
      codeAgentRuntimeMode: normalizedRuntimeMode,
    );
  }

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

  String? resolveLocalAssistantWorkingDirectoryForSessionInternal(
    String sessionKey, {
    bool requireLocalExistence = true,
  }) => resolveLocalAssistantWorkingDirectoryForSessionRuntimeInternal(
    this,
    sessionKey,
    requireLocalExistence: requireLocalExistence,
  );

  String? resolveSingleAgentWorkingDirectoryForSessionInternal(
    String sessionKey, {
    SingleAgentProvider? provider,
  }) => resolveSingleAgentWorkingDirectoryForSessionRuntimeInternal(
    this,
    sessionKey,
    provider: provider,
  );

  bool singleAgentProviderRequiresLocalPathInternal(
    SingleAgentProvider provider,
  ) => singleAgentProviderRequiresLocalPathRuntimeInternal(this, provider);

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

  CodeAgentNodeState buildCodeAgentNodeStateInternal() =>
      buildCodeAgentNodeStateRuntimeInternal(this);

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
    instancesControllerInternal.addListener(relayChildChangeInternal);
    skillsControllerInternal.addListener(relayChildChangeInternal);
    connectorsControllerInternal.addListener(relayChildChangeInternal);
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
    instancesControllerInternal.removeListener(relayChildChangeInternal);
    skillsControllerInternal.removeListener(relayChildChangeInternal);
    connectorsControllerInternal.removeListener(relayChildChangeInternal);
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
    if (authorizedSkillDirectoriesChangedInternal(previous, current)) {
      await refreshSharedSingleAgentLocalSkillsCacheInternal(forceRescan: true);
      if (disposedInternal) {
        return;
      }
      if (assistantExecutionTargetForSession(currentSessionKey) ==
          AssistantExecutionTarget.singleAgent) {
        await refreshSingleAgentSkillsForSession(currentSessionKey);
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
    final artifacts = result.artifacts;
    final syncedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    if (artifacts.isEmpty) {
      upsertTaskThreadInternal(
        normalizedSessionKey,
        lastArtifactSyncAtMs: syncedAtMs,
        lastArtifactSyncStatus: 'no-artifacts',
        updatedAtMs: syncedAtMs,
      );
      return;
    }
    final existingThread = requireTaskThreadForSessionInternal(
      normalizedSessionKey,
    );
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
    await root.create(recursive: true);

    var wroteArtifact = false;
    for (final artifact in artifacts) {
      if (!artifact.hasInlineContent) {
        continue;
      }
      final relativePath = _sanitizeArtifactRelativePathInternal(
        artifact.relativePath,
      );
      if (relativePath.isEmpty) {
        continue;
      }
      final target = await _nextArtifactTargetFileInternal(root, relativePath);
      await target.parent.create(recursive: true);
      await target.writeAsBytes(
        _decodeArtifactContentInternal(artifact),
        flush: true,
      );
      wroteArtifact = true;
    }

    upsertTaskThreadInternal(
      normalizedSessionKey,
      lastArtifactSyncAtMs: syncedAtMs,
      lastArtifactSyncStatus: wroteArtifact ? 'synced' : 'no-inline-content',
      updatedAtMs: syncedAtMs,
    );
  }

  Uri? resolveGatewayAcpEndpointInternal() {
    return resolveBridgeAcpEndpointInternal();
  }

  Uri? resolveBridgeAcpEndpointInternal() {
    final endpoint =
        settingsControllerInternal
                .accountSyncState
                ?.syncedDefaults
                .bridgeServerUrl
                .trim()
                .isNotEmpty ==
            true
        ? settingsControllerInternal
              .accountSyncState!
              .syncedDefaults
              .bridgeServerUrl
              .trim()
        : settings
              .acpBridgeServerModeConfig
              .cloudSynced
              .remoteServerSummary
              .endpoint
              .trim();
    final uri = Uri.tryParse(endpoint);
    final scheme = uri?.scheme.trim().toLowerCase() ?? '';
    if (uri == null || !kSupportedExternalAcpEndpointSchemes.contains(scheme)) {
      return null;
    }
    return uri.replace(query: null, fragment: null);
  }

  Uri? resolveExternalAcpEndpointForTargetInternal(AssistantExecutionTarget _) {
    return resolveBridgeAcpEndpointInternal();
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
      final bridgeToken =
          (await storeInternal.loadAccountManagedSecret(
            target: kAccountManagedSecretTargetBridgeAuthToken,
          ))?.trim() ??
          '';
      if (bridgeToken.isNotEmpty) {
        return 'Bearer $bridgeToken';
      }
    }
    return null;
  }

  int? gatewayProfileIndexMatchingEndpointInternal(Uri endpoint) {
    final normalizedHost = endpoint.host.trim().toLowerCase();
    final gateway = gatewayProfileBaseUriInternal(
      settings.primaryGatewayProfile,
    );
    if (gateway != null &&
        gateway.host.trim().toLowerCase() == normalizedHost &&
        gateway.port == endpoint.port) {
      return kGatewayRemoteProfileIndex;
    }
    return null;
  }

  RuntimeConnectionMode modeFromHostInternal(String host) {
    final trimmed = host.trim().toLowerCase();
    if (isLoopbackHostInternal(trimmed)) {
      return RuntimeConnectionMode.local;
    }
    return RuntimeConnectionMode.remote;
  }

  bool isLoopbackHostInternal(String host) {
    final trimmed = host.trim().toLowerCase();
    return trimmed == '127.0.0.1' || trimmed == 'localhost';
  }

  AssistantExecutionTarget assistantExecutionTargetForModeInternal(
    RuntimeConnectionMode mode,
  ) {
    return switch (mode) {
      RuntimeConnectionMode.unconfigured =>
        AssistantExecutionTarget.singleAgent,
      RuntimeConnectionMode.local => AssistantExecutionTarget.gateway,
      RuntimeConnectionMode.remote => AssistantExecutionTarget.gateway,
    };
  }

  GatewayConnectionProfile gatewayProfileForAssistantExecutionTargetInternal(
    AssistantExecutionTarget target,
  ) {
    return switch (target) {
      AssistantExecutionTarget.gateway => settings.primaryGatewayProfile,
      AssistantExecutionTarget.singleAgent => throw StateError(
        'Single Agent target has no gateway profile.',
      ),
    };
  }

  int gatewayProfileIndexForExecutionTargetInternal(
    AssistantExecutionTarget target,
  ) {
    return switch (target) {
      AssistantExecutionTarget.gateway => kGatewayRemoteProfileIndex,
      AssistantExecutionTarget.singleAgent => throw StateError(
        'Single Agent target has no gateway profile index.',
      ),
    };
  }
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
