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
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/platform_environment.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_thread_binding.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_runtime_helpers.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopSkillPermissions on AppController {
  void upsertTaskThreadInternal(
    String sessionKey, {
    ThreadOwnerScope? ownerScope,
    WorkspaceBinding? workspaceBinding,
    ExecutionBinding? executionBinding,
    ThreadContextState? contextState,
    ThreadLifecycleState? lifecycleState,
    List<GatewayChatMessage>? messages,
    double? updatedAtMs,
    String? title,
    bool? archived,
    AssistantExecutionTarget? executionTarget,
    AssistantMessageViewMode? messageViewMode,
    List<String>? selectedSkillKeys,
    String? assistantModelId,
    SingleAgentProvider? selectedProvider,
    ThreadSelectionSource? executionTargetSource,
    ThreadSelectionSource? selectedProviderSource,
    ThreadSelectionSource? assistantModelSource,
    ThreadSelectionSource? selectedSkillsSource,
    String? gatewayEntryState,
    String? latestResolvedRuntimeModel,
    String? latestResolvedProviderId,
    String? lifecycleStatus,
    double? lastRunAtMs,
    String? lastResultCode,
    String? lastRemoteWorkingDirectory,
    WorkspaceRefKind? lastRemoteWorkspaceRefKind,
    double? lastArtifactSyncAtMs,
    String? lastArtifactSyncStatus,
    List<String>? lastTaskArtifactRelativePaths,
    OpenClawTaskAssociation? openClawTaskAssociation,
    bool clearOpenClawTaskAssociation = false,
    List<TaskInputAttachmentRecord>? taskInputAttachments,
  }) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (!isAppOwnedAssistantSessionKeyInternal(normalizedSessionKey)) {
      throw StateError(
        'Runtime session key "$normalizedSessionKey" cannot be used as an app task.',
      );
    }
    final existing = taskThreadForSessionInternal(normalizedSessionKey);
    final nextExecutionTarget =
        executionTarget ??
        switch (existing?.executionBinding.executionMode) {
          ThreadExecutionMode.agent => AssistantExecutionTarget.agent,
          ThreadExecutionMode.gateway => AssistantExecutionTarget.gateway,
          null => AssistantExecutionTarget.agent,
        };
    final bridgeSkillKeys = skills
        .map((item) => item.skillKey.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    final selectedSkillCandidates =
        selectedSkillKeys ?? existing?.selectedSkillKeys ?? const <String>[];
    final nextSelectedSkillKeys = selectedSkillCandidates
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .where(
          (item) => bridgeSkillKeys.isEmpty || bridgeSkillKeys.contains(item),
        )
        .toList(growable: false);
    final nextMessages =
        messages ??
        existing?.messages ??
        assistantThreadMessagesInternal[normalizedSessionKey] ??
        const <GatewayChatMessage>[];
    final nextOwnerScope =
        ownerScope ??
        existing?.ownerScope ??
        const ThreadOwnerScope(
          realm: ThreadRealm.local,
          subjectType: ThreadSubjectType.user,
          subjectId: '',
          displayName: '',
        );
    final nextWorkspaceBinding =
        workspaceBinding ??
        existing?.workspaceBinding ??
        buildDesktopWorkspaceBindingInternal(
          normalizedSessionKey,
          executionTarget: nextExecutionTarget,
          ownerScope: nextOwnerScope,
          existingBinding: null,
        );
    if (!nextWorkspaceBinding.isComplete) {
      throw StateError(
        'TaskThread $normalizedSessionKey is missing a complete workspaceBinding.',
      );
    }
    final requestedProvider = selectedProvider?.isUnspecified == false
        ? selectedProvider
        : null;
    final nextProviderId = normalizeSingleAgentProviderId(
      requestedProvider?.providerId ??
          existing?.executionBinding.providerId ??
          existing?.contextState.latestResolvedProviderId ??
          '',
    );
    final shouldDefaultProvider = existing == null && nextProviderId.isEmpty;
    final nextProvider = resolveProviderForExecutionTarget(
      nextProviderId,
      executionTarget: nextExecutionTarget,
      defaultToCatalog: shouldDefaultProvider,
    );
    final nextProviderSource =
        selectedProviderSource ??
        existing?.executionBinding.providerSource ??
        ThreadSelectionSource.inherited;
    final normalizedProviderSource = nextProvider.isUnspecified
        ? ThreadSelectionSource.inherited
        : nextProviderSource;
    final nextExecutionBinding =
        (executionBinding ??
                existing?.executionBinding ??
                ExecutionBinding(
                  executionMode:
                      threadExecutionModeFromAssistantExecutionTarget(
                        nextExecutionTarget,
                      ),
                  executorId: nextProvider.providerId,
                  providerId: nextProvider.providerId,
                  endpointId: '',
                ))
            .copyWith(
              executionMode: threadExecutionModeFromAssistantExecutionTarget(
                nextExecutionTarget,
              ),
              executorId: nextProvider.providerId,
              providerId: nextProvider.providerId,
              executionModeSource:
                  executionTargetSource ??
                  existing?.executionBinding.executionModeSource,
              providerSource: normalizedProviderSource,
            );
    final nextContextState =
        (contextState ??
                existing?.contextState ??
                ThreadContextState(
                  messages: nextMessages,
                  selectedModelId:
                      assistantModelId ??
                      resolvedAssistantModelForTargetInternal(
                        nextExecutionTarget,
                      ),
                  selectedSkillKeys: const <String>[],
                  permissionLevel: AssistantPermissionLevel.defaultAccess,
                  messageViewMode: AssistantMessageViewMode.rendered,
                  latestResolvedRuntimeModel: '',
                  latestResolvedProviderId: '',
                  gatewayEntryState: gatewayEntryStateForTargetInternal(
                    nextExecutionTarget,
                  ),
                  lastRemoteWorkingDirectory: null,
                  lastRemoteWorkspaceRefKind: null,
                  lastArtifactSyncAtMs: null,
                  lastArtifactSyncStatus: null,
                  lastTaskArtifactRelativePaths: const <String>[],
                  taskInputAttachments: const <TaskInputAttachmentRecord>[],
                ))
            .copyWith(
              messages: nextMessages,
              messageViewMode: messageViewMode,
              selectedSkillKeys: nextSelectedSkillKeys,
              selectedModelId:
                  assistantModelId ??
                  existing?.assistantModelId ??
                  resolvedAssistantModelForTargetInternal(nextExecutionTarget),
              selectedModelSource:
                  assistantModelSource ??
                  existing?.contextState.selectedModelSource,
              selectedSkillsSource:
                  selectedSkillsSource ??
                  existing?.contextState.selectedSkillsSource,
              latestResolvedRuntimeModel: latestResolvedRuntimeModel,
              latestResolvedProviderId: latestResolvedProviderId,
              gatewayEntryState: gatewayEntryState,
              lastRemoteWorkingDirectory: lastRemoteWorkingDirectory,
              lastRemoteWorkspaceRefKind: lastRemoteWorkspaceRefKind,
              lastArtifactSyncAtMs: lastArtifactSyncAtMs,
              lastArtifactSyncStatus: lastArtifactSyncStatus,
              lastTaskArtifactRelativePaths: lastTaskArtifactRelativePaths,
              openClawTaskAssociation: openClawTaskAssociation,
              clearOpenClawTaskAssociation: clearOpenClawTaskAssociation,
              taskInputAttachments: taskInputAttachments,
            );
    final nextStatus =
        lifecycleStatus ??
        lifecycleState?.status ??
        existing?.lifecycleState.status ??
        'ready';
    final nextLifecycleState =
        (lifecycleState ??
                existing?.lifecycleState ??
                ThreadLifecycleState(
                  archived:
                      archived ??
                      existing?.archived ??
                      isAssistantTaskArchived(normalizedSessionKey),
                  status: nextStatus,
                  lastRunAtMs: null,
                  lastResultCode: null,
                ))
            .copyWith(
              archived:
                  archived ??
                  existing?.archived ??
                  isAssistantTaskArchived(normalizedSessionKey),
              status: nextStatus,
              lastRunAtMs: lastRunAtMs,
              lastResultCode: lastResultCode,
            );
    final nextRecord = TaskThread(
      threadId: normalizedSessionKey,
      createdAtMs:
          existing?.createdAtMs ??
          DateTime.now().millisecondsSinceEpoch.toDouble(),
      title: title ?? existing?.title ?? '',
      ownerScope: nextOwnerScope,
      workspaceBinding: nextWorkspaceBinding,
      executionBinding: nextExecutionBinding,
      contextState: nextContextState,
      lifecycleState: nextLifecycleState,
      openClawTaskAssociation: nextContextState.openClawTaskAssociation,
      updatedAtMs:
          updatedAtMs ??
          existing?.updatedAtMs ??
          (nextMessages.isNotEmpty ? nextMessages.last.timestampMs : null),
    );
    taskThreadRepositoryInternal.replace(nextRecord);
    if (messages != null) {
      assistantThreadMessagesInternal[normalizedSessionKey] =
          List<GatewayChatMessage>.from(messages);
    }
  }

  Future<void> setCurrentAssistantSessionKeyInternal(
    String sessionKey, {
    bool persistSelection = true,
  }) async {
    var normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (!isAppOwnedAssistantSessionKeyInternal(normalizedSessionKey)) {
      normalizedSessionKey = createAssistantDraftSessionKeyInternal();
      initializeAssistantThreadContext(
        normalizedSessionKey,
        title: appText('新对话', 'New conversation'),
        executionTarget: currentAssistantExecutionTarget,
        messageViewMode: currentAssistantMessageViewMode,
      );
    }
    await sessionsControllerInternal.switchSession(normalizedSessionKey);
    if (persistSelection) {
      await persistAssistantLastSessionKeyInternal(normalizedSessionKey);
    }
  }
}
