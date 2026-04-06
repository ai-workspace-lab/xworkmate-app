// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/runtime_models.dart';
import '../web/web_acp_client.dart';
import '../web/web_ai_gateway_client.dart';
import '../web/web_artifact_proxy_client.dart';
import '../web/web_relay_gateway_client.dart';
import '../web/web_session_repository.dart';
import '../web/web_store.dart';
import '../web/web_workspace_controllers.dart';
import 'app_capabilities.dart';
import 'ui_feature_manifest.dart';
import 'app_controller_web_core.dart';
import 'app_controller_web_sessions.dart';
import 'app_controller_web_workspace.dart';
import 'app_controller_web_session_actions.dart';
import 'app_controller_web_gateway_config.dart';
import 'app_controller_web_gateway_relay.dart';
import 'app_controller_web_gateway_chat.dart';

WebSessionRepository defaultRemoteSessionRepositoryInternal(
  WebSessionPersistenceConfig config,
  String clientId,
  String accessToken,
) {
  return RemoteWebSessionRepository(
    baseUrl: config.remoteBaseUrl,
    clientId: clientId,
    accessToken: accessToken,
  );
}

extension AppControllerWebHelpers on AppController {
  SettingsTab sanitizeSettingsTabInternal(SettingsTab tab) {
    return switch (tab) {
      SettingsTab.workspace ||
      SettingsTab.agents ||
      SettingsTab.diagnostics ||
      SettingsTab.experimental => SettingsTab.gateway,
      _ => tab,
    };
  }

  SettingsSnapshot sanitizeSettingsInternal(SettingsSnapshot snapshot) {
    final allowedDestinations = featuresFor(
      UiFeaturePlatform.web,
    ).allowedDestinations;
    final target = featuresFor(UiFeaturePlatform.web).sanitizeExecutionTarget(
      sanitizeTargetInternal(snapshot.assistantExecutionTarget),
    );
    final assistantNavigationDestinations =
        normalizeAssistantNavigationDestinations(
              snapshot.assistantNavigationDestinations,
            )
            .where((entry) {
              final destination = entry.destination;
              if (destination != null) {
                return allowedDestinations.contains(destination);
              }
              return allowedDestinations.contains(
                WorkspaceDestination.settings,
              );
            })
            .toList(growable: false);
    final normalizedSessionBaseUrl =
        RemoteWebSessionRepository.normalizeBaseUrl(
          snapshot.webSessionPersistence.remoteBaseUrl,
        )?.toString() ??
        '';
    final localProfile = snapshot.primaryLocalGatewayProfile.copyWith(
      mode: RuntimeConnectionMode.local,
      useSetupCode: false,
      setupCode: '',
      tls: false,
    );
    final remoteProfile = snapshot.primaryRemoteGatewayProfile.copyWith(
      mode: RuntimeConnectionMode.remote,
      useSetupCode: false,
      setupCode: '',
    );
    return snapshot.copyWith(
      assistantExecutionTarget: target,
      gatewayProfiles: replaceGatewayProfileAt(
        replaceGatewayProfileAt(
          snapshot.gatewayProfiles,
          kGatewayLocalProfileIndex,
          localProfile,
        ),
        kGatewayRemoteProfileIndex,
        remoteProfile,
      ),
      webSessionPersistence: snapshot.webSessionPersistence.copyWith(
        remoteBaseUrl: normalizedSessionBaseUrl,
      ),
      assistantNavigationDestinations: assistantNavigationDestinations,
    );
  }

  TaskThread sanitizeRecordInternal(TaskThread record) {
    final target = sanitizeTargetInternal(
      assistantExecutionTargetFromExecutionMode(
        record.executionBinding.executionMode,
      ),
    ) ??
        AssistantExecutionTarget.singleAgent;
    final workspaceBinding = record.workspaceBinding;
    if (!workspaceBinding.isComplete) {
      throw StateError(
        'TaskThread ${record.threadId} is missing a complete workspaceBinding.',
      );
    }
    final workspacePath = workspaceBinding.workspacePath.trim();
    return record.copyWith(
      title: record.title.trim().isEmpty
          ? appText('新对话', 'New conversation')
          : record.title.trim(),
      workspaceBinding: WorkspaceBinding(
        workspaceId: record.threadId,
        workspaceKind: workspaceBinding.workspaceKind,
        workspacePath: workspacePath,
        displayPath: record.displayPath.trim().isEmpty
            ? workspacePath
            : record.displayPath.trim(),
        writable: workspaceBinding.writable,
      ),
      executionBinding: record.executionBinding.copyWith(
        executionMode: threadExecutionModeFromAssistantExecutionTarget(target),
      ),
      lifecycleState: record.lifecycleState.copyWith(status: 'ready'),
    );
  }

  AssistantExecutionTarget? sanitizeTargetInternal(
    AssistantExecutionTarget? target,
  ) {
    return switch (target) {
      AssistantExecutionTarget.auto => AssistantExecutionTarget.auto,
      AssistantExecutionTarget.local => AssistantExecutionTarget.local,
      AssistantExecutionTarget.remote => AssistantExecutionTarget.remote,
      AssistantExecutionTarget.singleAgent =>
        AssistantExecutionTarget.singleAgent,
      _ => AssistantExecutionTarget.auto,
    };
  }

  TaskThread newRecordInternal({
    required AssistantExecutionTarget target,
    String? title,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final prefix = switch (target) {
      AssistantExecutionTarget.auto => 'auto',
      AssistantExecutionTarget.singleAgent => 'single',
      AssistantExecutionTarget.local => 'local',
      AssistantExecutionTarget.remote => 'remote',
    };
    final threadId = '$prefix:$timestamp';
    final workspacePath =
        '/owners/${ThreadRealm.remote.name}/${ThreadSubjectType.user.name}/threads/$threadId';
    return TaskThread(
      threadId: threadId,
      createdAtMs: timestamp.toDouble(),
      updatedAtMs: timestamp.toDouble(),
      title: title ?? appText('新对话', 'New conversation'),
      ownerScope: const ThreadOwnerScope(
        realm: ThreadRealm.remote,
        subjectType: ThreadSubjectType.user,
        subjectId: '',
        displayName: '',
      ),
      workspaceBinding: WorkspaceBinding(
        workspaceId: threadId,
        workspaceKind: WorkspaceKind.remoteFs,
        workspacePath: workspacePath,
        displayPath: workspacePath,
        writable: true,
      ),
      executionBinding: ExecutionBinding(
        executionMode: switch (target) {
          AssistantExecutionTarget.auto => ThreadExecutionMode.auto,
          AssistantExecutionTarget.singleAgent =>
            ThreadExecutionMode.localAgent,
          AssistantExecutionTarget.local => ThreadExecutionMode.gatewayLocal,
          AssistantExecutionTarget.remote => ThreadExecutionMode.gatewayRemote,
        },
        executorId: SingleAgentProvider.auto.providerId,
        providerId: SingleAgentProvider.auto.providerId,
        endpointId: '',
      ),
      contextState: const ThreadContextState(
        messages: <GatewayChatMessage>[],
        selectedModelId: '',
        selectedSkillKeys: <String>[],
        importedSkills: <AssistantThreadSkillEntry>[],
        permissionLevel: AssistantPermissionLevel.defaultAccess,
        messageViewMode: AssistantMessageViewMode.rendered,
        latestResolvedRuntimeModel: '',
        gatewayEntryState: null,
      ),
      lifecycleState: const ThreadLifecycleState(
        archived: false,
        status: 'ready',
        lastRunAtMs: null,
        lastResultCode: null,
      ),
    );
  }

  Future<ThreadOwnerScope> ensureWebThreadOwnerScopeInternal(
    String sessionKey,
  ) async {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    final existing = threadRecordsInternal[normalizedSessionKey]?.ownerScope;
    if (existing != null && existing.subjectId.trim().isNotEmpty) {
      return existing;
    }
    final identity = await relayClientInternal.identityManagerInternal
        .loadOrCreate(storeInternal);
    return ThreadOwnerScope(
      realm: ThreadRealm.remote,
      subjectType: ThreadSubjectType.user,
      subjectId: identity.deviceId,
      displayName: identity.deviceId,
    );
  }

  WorkspaceBinding buildWebWorkspaceBindingInternal(
    String sessionKey, {
    required ThreadOwnerScope ownerScope,
    WorkspaceBinding? existingBinding,
  }) {
    final existingPath = existingBinding?.workspacePath.trim() ?? '';
    final nextPath = existingPath.isNotEmpty
        ? existingPath
        : '/owners/${ownerScope.realm.name}/${ownerScope.subjectType.name}/${ownerScope.subjectId.trim()}/threads/${normalizedSessionKeyInternal(sessionKey)}';
    return (existingBinding ??
            WorkspaceBinding(
              workspaceId: normalizedSessionKeyInternal(sessionKey),
              workspaceKind: WorkspaceKind.remoteFs,
              workspacePath: nextPath,
              displayPath: nextPath,
              writable: true,
            ))
        .copyWith(
          workspaceKind: WorkspaceKind.remoteFs,
          workspacePath: nextPath,
          displayPath: nextPath,
          writable: true,
        );
  }

  ExecutionBinding buildWebExecutionBindingInternal({
    required AssistantExecutionTarget executionTarget,
    required SingleAgentProvider singleAgentProvider,
    ExecutionBinding? existingBinding,
  }) {
    return (existingBinding ??
            ExecutionBinding(
              executionMode: ThreadExecutionMode.localAgent,
              executorId: singleAgentProvider.providerId,
              providerId: singleAgentProvider.providerId,
              endpointId: '',
            ))
        .copyWith(
          executionMode: switch (executionTarget) {
            AssistantExecutionTarget.auto => ThreadExecutionMode.auto,
            AssistantExecutionTarget.singleAgent =>
              ThreadExecutionMode.localAgent,
            AssistantExecutionTarget.local => ThreadExecutionMode.gatewayLocal,
            AssistantExecutionTarget.remote =>
              ThreadExecutionMode.gatewayRemote,
          },
          executorId: singleAgentProvider.providerId,
          providerId: singleAgentProvider.providerId,
        );
  }

  Future<void> ensureWebTaskThreadBindingInternal(
    String sessionKey, {
    AssistantExecutionTarget? executionTarget,
  }) async {
    final key = normalizedSessionKeyInternal(sessionKey);
    final existing = taskThreadForSessionInternal(key);
    final resolvedTarget =
        sanitizeTargetInternal(executionTarget) ??
        assistantExecutionTargetForSession(key);
    final ownerScope = await ensureWebThreadOwnerScopeInternal(key);
    final workspaceBinding = buildWebWorkspaceBindingInternal(
      key,
      ownerScope: ownerScope,
      existingBinding: existing?.workspaceBinding,
    );
    threadRepositoryInternal.replace(
        (existing ?? newRecordInternal(target: resolvedTarget)).copyWith(
          threadId: key,
          ownerScope: ownerScope,
          workspaceBinding: workspaceBinding,
          executionBinding: buildWebExecutionBindingInternal(
            executionTarget: resolvedTarget,
            singleAgentProvider:
                SingleAgentProviderCopy.fromJsonValue(
                  existing?.executionBinding.providerId ?? '',
                ),
            existingBinding: existing?.executionBinding,
          ),
          lifecycleState:
              (existing?.lifecycleState ??
                      const ThreadLifecycleState(
                        archived: false,
                        status: 'ready',
                        lastRunAtMs: null,
                        lastResultCode: null,
                      ))
                  .copyWith(status: 'ready'),
          updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        ),
    );
  }

  void appendAssistantMessageInternal({
    required String sessionKey,
    required String text,
    required bool error,
  }) {
    final existing =
        threadRecordsInternal[sessionKey] ??
        newRecordInternal(target: assistantExecutionTarget);
    final messages = <GatewayChatMessage>[
      ...existing.messages,
      GatewayChatMessage(
        id: messageIdInternal(),
        role: 'assistant',
        text: text,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        toolCallId: null,
        toolName: null,
        stopReason: error ? 'error' : null,
        pending: false,
        error: error,
      ),
    ];
    threadRecordsInternal[sessionKey] = existing.copyWith(
      messages: messages,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      title: deriveThreadTitleInternal(
        existing.title,
        messages,
        fallback: sessionKey,
      ),
    );
    pendingSessionKeysInternal.remove(sessionKey);
    streamingTextBySessionInternal.remove(sessionKey);
    recomputeDerivedWorkspaceStateInternal();
  }

  void handleRelayEventInternal(GatewayPushEvent event) {
    if (event.event != 'chat') {
      return;
    }
    final payload = castMapInternal(event.payload);
    final sessionKey = normalizedSessionKeyInternal(
      payload['sessionKey']?.toString() ?? '',
    );
    if (sessionKey.isEmpty) {
      return;
    }
    if (goTaskServiceManagedRelaySessionsInternal.contains(sessionKey)) {
      return;
    }
    final state = payload['state']?.toString().trim() ?? '';
    final message = castMapInternal(payload['message']);
    final text = extractMessageTextInternal(message);
    if (text.isNotEmpty && state == 'delta') {
      appendStreamingTextInternal(sessionKey, text);
    } else if (text.isNotEmpty && state == 'final') {
      clearStreamingTextInternal(sessionKey);
      appendAssistantMessageInternal(
        sessionKey: sessionKey,
        text: text,
        error: false,
      );
    }
    if (state == 'final' || state == 'aborted' || state == 'error') {
      pendingSessionKeysInternal.remove(sessionKey);
      if (state == 'error' && text.isNotEmpty) {
        appendAssistantMessageInternal(
          sessionKey: sessionKey,
          text: text,
          error: true,
        );
      }
      clearStreamingTextInternal(sessionKey);
      unawaited(refreshRelaySessions());
      unawaited(refreshRelayHistory(sessionKey: sessionKey));
    }
    notifyChangedInternal();
  }

  String normalizedSessionKeyInternal(String sessionKey) {
    final trimmed = sessionKey.trim();
    return trimmed.isEmpty ? 'main' : trimmed;
  }

  AssistantExecutionTarget assistantExecutionTargetForModeInternal(
    RuntimeConnectionMode mode,
  ) {
    return switch (mode) {
      RuntimeConnectionMode.local => AssistantExecutionTarget.local,
      RuntimeConnectionMode.remote => AssistantExecutionTarget.remote,
      RuntimeConnectionMode.unconfigured => AssistantExecutionTarget.auto,
    };
  }

  int profileIndexForTargetInternal(AssistantExecutionTarget target) {
    return switch (target) {
      AssistantExecutionTarget.auto => kGatewayLocalProfileIndex,
      AssistantExecutionTarget.local => kGatewayLocalProfileIndex,
      AssistantExecutionTarget.remote => kGatewayRemoteProfileIndex,
      AssistantExecutionTarget.singleAgent => kGatewayRemoteProfileIndex,
    };
  }

  GatewayConnectionProfile profileForTargetInternal(
    AssistantExecutionTarget target,
  ) {
    return switch (target) {
      AssistantExecutionTarget.auto =>
        settingsInternal.primaryLocalGatewayProfile,
      AssistantExecutionTarget.local =>
        settingsInternal.primaryLocalGatewayProfile,
      AssistantExecutionTarget.remote =>
        settingsInternal.primaryRemoteGatewayProfile,
      AssistantExecutionTarget.singleAgent =>
        settingsInternal.primaryRemoteGatewayProfile,
    };
  }

  String gatewayAddressLabelInternal(GatewayConnectionProfile profile) {
    final host = profile.host.trim();
    if (host.isEmpty || profile.port <= 0) {
      return appText('未连接目标', 'No target');
    }
    return '$host:${profile.port}';
  }

  String gatewayEntryStateForTargetInternal(AssistantExecutionTarget target) {
    return target.promptValue;
  }

  void upsertThreadRecordInternal(
    String sessionKey, {
    List<GatewayChatMessage>? messages,
    double? updatedAtMs,
    String? title,
    bool? archived,
    AssistantExecutionTarget? executionTarget,
    AssistantMessageViewMode? messageViewMode,
    List<AssistantThreadSkillEntry>? importedSkills,
    List<String>? selectedSkillKeys,
    String? assistantModelId,
    SingleAgentProvider? singleAgentProvider,
    ThreadSelectionSource? executionTargetSource,
    ThreadSelectionSource? singleAgentProviderSource,
    ThreadSelectionSource? assistantModelSource,
    ThreadSelectionSource? selectedSkillsSource,
    String? gatewayEntryState,
    bool clearGatewayEntryState = false,
    String? workspacePath,
    WorkspaceKind? workspaceKind,
  }) {
    final key = normalizedSessionKeyInternal(sessionKey);
    final resolvedTarget =
        sanitizeTargetInternal(executionTarget) ??
        assistantExecutionTargetForSession(key);
    final existing =
        taskThreadForSessionInternal(key) ?? newRecordInternal(target: resolvedTarget);
    final nextWorkspaceBinding = existing.workspaceBinding;
    if (!nextWorkspaceBinding.isComplete) {
      throw StateError(
        'TaskThread $key is missing a complete workspaceBinding.',
      );
    }
    threadRepositoryInternal.replace(
      existing.copyWith(
        threadId: key,
        messages: messages ?? existing.messages,
        updatedAtMs: updatedAtMs ?? existing.updatedAtMs,
        title: title ?? existing.title,
        archived: archived ?? existing.archived,
        messageViewMode: messageViewMode ?? existing.messageViewMode,
        importedSkills: importedSkills ?? existing.importedSkills,
        selectedSkillKeys: selectedSkillKeys ?? existing.selectedSkillKeys,
        assistantModelId: assistantModelId ?? existing.assistantModelId,
        assistantModelSource:
            assistantModelSource ?? existing.contextState.selectedModelSource,
        selectedSkillsSource:
            selectedSkillsSource ?? existing.contextState.selectedSkillsSource,
        gatewayEntryState: gatewayEntryState ?? existing.gatewayEntryState,
        clearGatewayEntryState: clearGatewayEntryState,
        workspaceBinding:
            (workspacePath != null || workspaceKind != null)
                ? nextWorkspaceBinding.copyWith(
                    workspacePath: workspacePath,
                    displayPath:
                        workspacePath ?? nextWorkspaceBinding.displayPath,
                    workspaceKind: workspaceKind,
                  )
                : nextWorkspaceBinding,
        executionBinding: existing.executionBinding.copyWith(
          executionMode: threadExecutionModeFromAssistantExecutionTarget(
            resolvedTarget,
          ),
          executorId:
              (singleAgentProvider ?? SingleAgentProviderCopy.fromJsonValue(
                    existing.executionBinding.providerId,
                  ))
                  .providerId,
          providerId:
              (singleAgentProvider ?? SingleAgentProviderCopy.fromJsonValue(
                    existing.executionBinding.providerId,
                  ))
                  .providerId,
          executionModeSource:
              executionTargetSource ??
              existing.executionBinding.executionModeSource,
          providerSource:
              singleAgentProviderSource ?? existing.executionBinding.providerSource,
        ),
        lifecycleState: existing.lifecycleState.copyWith(status: 'ready'),
      ),
    );
    recomputeDerivedWorkspaceStateInternal();
  }

  Future<void> applyAssistantExecutionTargetInternal(
    AssistantExecutionTarget target, {
    required String sessionKey,
    required bool persistDefaultSelection,
  }) async {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    final resolvedTarget =
        sanitizeTargetInternal(target) ??
        assistantExecutionTargetForSession(normalizedSessionKey);
    upsertThreadRecordInternal(
      normalizedSessionKey,
      executionTarget: resolvedTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      gatewayEntryState: gatewayEntryStateForTargetInternal(resolvedTarget),
    );
    if (persistDefaultSelection) {
      settingsInternal = settingsInternal.copyWith(
        assistantExecutionTarget: resolvedTarget,
        assistantLastSessionKey: normalizedSessionKey,
      );
      await persistSettingsInternal();
      await persistThreadsInternal();
    } else {
      await persistThreadsInternal();
    }
    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      return;
    }
    final targetProfile = profileForTargetInternal(resolvedTarget);
    if (targetProfile.host.trim().isEmpty || targetProfile.port <= 0) {
      return;
    }
    final expectedMode = resolvedTarget == AssistantExecutionTarget.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    if (connection.status == RuntimeConnectionStatus.connected &&
        connection.mode == expectedMode) {
      return;
    }
    try {
      await connectRelay(target: resolvedTarget);
    } catch (error) {
      lastAssistantErrorInternal = error.toString();
    }
  }

  Future<T> enqueueThreadTurnInternal<T>(
    String threadId,
    Future<T> Function() task,
  ) {
    final normalizedThreadId = normalizedSessionKeyInternal(threadId);
    final previous =
        threadTurnQueuesInternal[normalizedThreadId] ?? Future<void>.value();
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
          if (identical(threadTurnQueuesInternal[normalizedThreadId], next)) {
            threadTurnQueuesInternal.remove(normalizedThreadId);
          }
        });
    threadTurnQueuesInternal[normalizedThreadId] = next;
    return completer.future;
  }

  String augmentPromptWithAttachmentsInternal(
    String prompt,
    List<GatewayChatAttachmentPayload> attachments,
  ) {
    if (attachments.isEmpty) {
      return prompt;
    }
    final buffer = StringBuffer(prompt.trim());
    buffer.write('\n\n');
    buffer.writeln(appText('附件（仅供本轮参考）：', 'Attachments (for this turn only):'));
    for (final item in attachments) {
      final name = item.fileName.trim().isEmpty ? 'attachment' : item.fileName;
      final mime = item.mimeType.trim().isEmpty
          ? 'application/octet-stream'
          : item.mimeType;
      buffer.writeln('- $name ($mime)');
    }
    return buffer.toString().trim();
  }

  Uri? acpEndpointForTargetInternal(AssistantExecutionTarget target) {
    final resolvedTarget = target == AssistantExecutionTarget.singleAgent
        ? AssistantExecutionTarget.remote
        : target;
    final profile = profileForTargetInternal(resolvedTarget);
    final host = profile.host.trim();
    if (host.isEmpty) {
      return null;
    }
    final candidate = host.contains('://')
        ? host
        : '${profile.tls ? 'https' : 'http'}://$host:${profile.port}';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    final scheme = uri.scheme.trim().isEmpty
        ? (profile.tls ? 'https' : 'http')
        : uri.scheme.trim().toLowerCase();
    final resolvedPort = uri.hasPort
        ? uri.port
        : (scheme == 'https' ? 443 : 80);
    return uri.replace(
      scheme: scheme,
      port: resolvedPort,
      path: '',
      query: null,
      fragment: null,
    );
  }

  Future<Map<String, dynamic>> requestAcpSessionMessageInternal({
    required Uri endpoint,
    required Map<String, dynamic> params,
    required bool hasInlineAttachments,
    void Function(Map<String, dynamic> notification)? onNotification,
  }) async {
    try {
      return await acpClientInternal.request(
        endpoint: endpoint,
        method: 'session.message',
        params: params,
        onNotification: onNotification,
      );
    } on WebAcpException catch (error) {
      if (!hasInlineAttachments ||
          !canFallbackInlineAttachmentsInternal(error)) {
        rethrow;
      }
      final fallbackParams = Map<String, dynamic>.from(params)
        ..remove('inlineAttachments');
      try {
        return await acpClientInternal.request(
          endpoint: endpoint,
          method: 'session.message',
          params: fallbackParams,
          onNotification: onNotification,
        );
      } on Object catch (fallbackError) {
        throw Exception(
          appText(
            'ACP 暂不支持 inline 附件，回退旧协议也失败：$fallbackError',
            'ACP does not support inline attachments, and fallback to legacy attachment payload failed: $fallbackError',
          ),
        );
      }
    }
  }

  Future<void> refreshAcpCapabilitiesInternal(Uri endpoint) async {
    try {
      acpCapabilitiesInternal = await acpClientInternal.loadCapabilities(
        endpoint: endpoint,
      );
    } catch (_) {
      acpCapabilitiesInternal = const WebAcpCapabilities.empty();
    }
  }

  bool canFallbackInlineAttachmentsInternal(WebAcpException error) {
    final code = (error.code ?? '').trim();
    if (code == '-32602' || code == 'INVALID_PARAMS') {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('inlineattachment') ||
        message.contains('unexpected field') ||
        message.contains('unknown field') ||
        message.contains('invalid params');
  }

  bool unsupportedAcpSkillsStatusInternal(WebAcpException error) {
    final code = (error.code ?? '').trim();
    if (code == '-32601' || code == 'METHOD_NOT_FOUND') {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('unknown method') ||
        message.contains('method not found') ||
        message.contains('skills.status');
  }

  int base64SizeInternal(String base64) {
    final normalized = base64.trim().split(',').last.trim();
    if (normalized.isEmpty) {
      return 0;
    }
    final padding = normalized.endsWith('==')
        ? 2
        : (normalized.endsWith('=') ? 1 : 0);
    return (normalized.length * 3 ~/ 4) - padding;
  }

  AcpSessionUpdateInternal? acpSessionUpdateFromNotificationInternal(
    Map<String, dynamic> notification, {
    required String sessionKey,
  }) {
    final method =
        notification['method']?.toString().trim().toLowerCase() ?? '';
    final params = castMapInternal(notification['params']);
    final payload = params.isNotEmpty
        ? params
        : castMapInternal(notification['payload']);
    final event = payload['event']?.toString().trim().toLowerCase() ?? method;
    final type =
        payload['type']?.toString().trim().toLowerCase() ??
        payload['state']?.toString().trim().toLowerCase() ??
        event;
    final payloadSession = normalizedSessionKeyInternal(
      payload['sessionId']?.toString() ??
          payload['threadId']?.toString() ??
          payload['sessionKey']?.toString() ??
          sessionKey,
    );
    if (payloadSession != normalizedSessionKeyInternal(sessionKey)) {
      return null;
    }
    final messageMap = castMapInternal(payload['message']);
    final messageText = extractMessageTextInternal(messageMap).trim().isNotEmpty
        ? extractMessageTextInternal(messageMap).trim()
        : payload['message']?.toString().trim() ?? '';
    final text =
        payload['delta']?.toString() ??
        payload['text']?.toString() ??
        payload['outputDelta']?.toString() ??
        '';
    final error =
        (payload['error'] is bool && payload['error'] as bool) ||
        type == 'error' ||
        event.contains('error');
    return AcpSessionUpdateInternal(
      type: type,
      text: text,
      message: messageText,
      error: error,
    );
  }

  void appendStreamingTextInternal(String sessionKey, String delta) {
    if (delta.isEmpty) {
      return;
    }
    final key = normalizedSessionKeyInternal(sessionKey);
    final current = streamingTextBySessionInternal[key] ?? '';
    streamingTextBySessionInternal[key] = '$current$delta';
  }

  void clearStreamingTextInternal(String sessionKey) {
    streamingTextBySessionInternal.remove(
      normalizedSessionKeyInternal(sessionKey),
    );
  }

  Future<void> persistSettingsInternal() async {
    await storeInternal.saveSettingsSnapshot(settingsInternal);
  }

  void saveSecretDraftInternal(String key, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      draftSecretValuesInternal.remove(key);
    } else {
      draftSecretValuesInternal[key] = trimmed;
    }
    settingsDraftStatusMessageInternal = appText(
      '草稿已更新，点击顶部保存持久化。',
      'Draft updated. Use the top Save button to persist it.',
    );
    notifyChangedInternal();
  }

  Future<void> persistDraftSecretsInternal() async {
    final aiGatewayApiKey =
        draftSecretValuesInternal[AppController
            .draftAiGatewayApiKeyKeyInternal];
    if ((aiGatewayApiKey ?? '').isNotEmpty) {
      aiGatewayApiKeyCacheInternal = aiGatewayApiKey!;
      await storeInternal.saveAiGatewayApiKey(aiGatewayApiKeyCacheInternal);
    }
    draftSecretValuesInternal.clear();
  }

  Future<void> persistThreadsInternal() async {
    final records = threadRepositoryInternal.snapshot();
    await browserSessionRepositoryInternal.saveThreadRecords(records);
    final invalidRemoteConfigMessage =
        invalidRemoteSessionConfigMessageInternal();
    if (invalidRemoteConfigMessage != null) {
      sessionPersistenceStatusMessageInternal = invalidRemoteConfigMessage;
      return;
    }
    final remoteRepository = resolveRemoteSessionRepositoryInternal();
    if (remoteRepository == null) {
      sessionPersistenceStatusMessageInternal = '';
      return;
    }
    try {
      await remoteRepository.saveThreadRecords(records);
      sessionPersistenceStatusMessageInternal = appText(
        '远端 Session API 已同步，浏览器缓存仍保留一份本地副本。',
        'Remote session API synced successfully; the browser cache remains as a local fallback.',
      );
    } catch (error) {
      sessionPersistenceStatusMessageInternal =
          sessionPersistenceErrorLabelInternal(error);
    }
  }

  Future<List<TaskThread>> loadThreadRecordsInternal() async {
    final browserRecords = await browserSessionRepositoryInternal
        .loadThreadRecords();
    final invalidRemoteConfigMessage =
        invalidRemoteSessionConfigMessageInternal();
    if (invalidRemoteConfigMessage != null) {
      sessionPersistenceStatusMessageInternal = invalidRemoteConfigMessage;
      return browserRecords;
    }
    final remoteRepository = resolveRemoteSessionRepositoryInternal();
    if (remoteRepository == null) {
      sessionPersistenceStatusMessageInternal = '';
      return browserRecords;
    }
    try {
      final remoteRecords = await remoteRepository.loadThreadRecords();
      if (remoteRecords.isNotEmpty) {
        sessionPersistenceStatusMessageInternal = appText(
          '远端 Session API 已启用，并覆盖浏览器中的本地缓存。',
          'Remote session API is active and overrides the browser cache.',
        );
        await browserSessionRepositoryInternal.saveThreadRecords(remoteRecords);
        return remoteRecords;
      }
      sessionPersistenceStatusMessageInternal = appText(
        '远端 Session API 已启用，但当前为空；浏览器缓存不会自动导入远端。',
        'The remote session API is active but empty, and the browser cache will not be imported automatically.',
      );
      return const <TaskThread>[];
    } catch (error) {
      sessionPersistenceStatusMessageInternal =
          sessionPersistenceErrorLabelInternal(error);
      return browserRecords;
    }
  }

  WebSessionRepository? resolveRemoteSessionRepositoryInternal() {
    final config = settingsInternal.webSessionPersistence;
    if (config.mode != WebSessionPersistenceMode.remote) {
      return null;
    }
    final normalizedBaseUrl = RemoteWebSessionRepository.normalizeBaseUrl(
      config.remoteBaseUrl,
    );
    if (normalizedBaseUrl == null) {
      return null;
    }
    return remoteSessionRepositoryBuilderInternal(
      config.copyWith(remoteBaseUrl: normalizedBaseUrl.toString()),
      webSessionClientIdInternal,
      webSessionApiTokenCacheInternal,
    );
  }

  String? invalidRemoteSessionConfigMessageInternal() {
    final config = settingsInternal.webSessionPersistence;
    if (config.mode != WebSessionPersistenceMode.remote ||
        config.remoteBaseUrl.trim().isEmpty) {
      return null;
    }
    if (RemoteWebSessionRepository.normalizeBaseUrl(config.remoteBaseUrl) !=
        null) {
      return null;
    }
    return appText(
      'Session API URL 无效。请使用 HTTPS，或仅在 localhost / 127.0.0.1 开发环境中使用 HTTP。',
      'The Session API URL is invalid. Use HTTPS, or HTTP only for localhost / 127.0.0.1 during development.',
    );
  }

  String sessionPersistenceErrorLabelInternal(Object error) {
    return appText(
      '远端 Session API 当前不可用，已回退到浏览器缓存。${error.toString()}',
      'The remote session API is unavailable, so XWorkmate fell back to the browser cache. ${error.toString()}',
    );
  }

  String titleForRecordInternal(TaskThread record) {
    final customTitle =
        settingsInternal
            .assistantCustomTaskTitles[normalizedSessionKeyInternal(
              record.sessionKey,
            )]
            ?.trim() ??
        '';
    if (customTitle.isNotEmpty) {
      return customTitle;
    }
    final title = record.title.trim();
    if (title.isNotEmpty) {
      return title;
    }
    return deriveThreadTitleInternal(
      '',
      record.messages,
      fallback: record.sessionKey,
    );
  }

  String previewForRecordInternal(TaskThread record) {
    for (final message in record.messages.reversed) {
      final text = message.text.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return appText(
      '等待描述这个任务的第一条消息',
      'Waiting for the first message of this task',
    );
  }

  String deriveThreadTitleInternal(
    String currentTitle,
    List<GatewayChatMessage> messages, {
    String fallback = '',
  }) {
    final trimmedCurrent = currentTitle.trim();
    if (trimmedCurrent.isNotEmpty &&
        trimmedCurrent != appText('新对话', 'New conversation')) {
      return trimmedCurrent;
    }
    for (final message in messages) {
      if (message.role.trim().toLowerCase() != 'user') {
        continue;
      }
      final text = message.text.trim();
      if (text.isEmpty) {
        continue;
      }
      return text.length <= 32 ? text : '${text.substring(0, 32)}...';
    }
    return fallback.isEmpty ? appText('新对话', 'New conversation') : fallback;
  }

  String hostLabelInternal(String rawUrl) {
    final normalized = aiGatewayClientInternal.normalizeBaseUrl(rawUrl);
    return normalized?.host.trim() ?? '';
  }

  String messageIdInternal() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  Map<String, dynamic> castMapInternal(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  String extractMessageTextInternal(Map<String, dynamic> message) {
    final directContent = message['content'];
    if (directContent is String) {
      return directContent;
    }
    final parts = <String>[];
    if (directContent is List) {
      for (final part in directContent) {
        final map = castMapInternal(part);
        final text = map['text']?.toString().trim();
        if (text != null && text.isNotEmpty) {
          parts.add(text);
        }
      }
    }
    return parts.join('\n').trim();
  }
}

class AcpSessionUpdateInternal {
  const AcpSessionUpdateInternal({
    required this.type,
    required this.text,
    required this.message,
    required this.error,
  });

  final String type;
  final String text;
  final String message;
  final bool error;
}

class WebConversationSummary {
  const WebConversationSummary({
    required this.sessionKey,
    required this.title,
    required this.preview,
    required this.updatedAtMs,
    required this.executionTarget,
    required this.pending,
    required this.current,
  });

  final String sessionKey;
  final String title;
  final String preview;
  final double updatedAtMs;
  final AssistantExecutionTarget executionTarget;
  final bool pending;
  final bool current;
}
