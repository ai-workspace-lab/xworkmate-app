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
import '../runtime/direct_single_agent_app_server_client.dart';
import '../runtime/gateway_acp_client.dart';
import '../runtime/codex_runtime.dart';
import '../runtime/codex_config_bridge.dart';
import '../runtime/code_agent_node_orchestrator.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/desktop_thread_artifact_service.dart';
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/multi_agent_orchestrator.dart';
import '../runtime/platform_environment.dart';
import '../runtime/single_agent_runner.dart';
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
import 'app_controller_desktop_runtime_helpers.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopSkillPermissions on AppController {
  Future<void> refreshSharedSingleAgentLocalSkillsCacheInternal({
    required bool forceRescan,
  }) async {
    if (!forceRescan && singleAgentLocalSkillsHydratedInternal) {
      return;
    }
    if (!forceRescan &&
        await restoreSharedSingleAgentLocalSkillsCacheInternal()) {
      return;
    }
    final existingRefresh = singleAgentSharedSkillsRefreshInFlightInternal;
    if (existingRefresh != null) {
      await existingRefresh;
      if (!forceRescan) {
        return;
      }
    }
    late final Future<void> refreshFuture;
    refreshFuture = () async {
      final sharedSkills = await scanSingleAgentSharedSkillEntriesInternal();
      singleAgentSharedImportedSkillsInternal = sharedSkills;
      singleAgentLocalSkillsHydratedInternal = true;
      await persistSharedSingleAgentLocalSkillsCacheInternal();
    }();
    singleAgentSharedSkillsRefreshInFlightInternal = refreshFuture;
    try {
      await refreshFuture;
    } finally {
      if (identical(
        singleAgentSharedSkillsRefreshInFlightInternal,
        refreshFuture,
      )) {
        singleAgentSharedSkillsRefreshInFlightInternal = null;
      }
    }
  }

  Future<void> ensureSharedSingleAgentLocalSkillsLoaded() async {
    if (singleAgentLocalSkillsHydratedInternal) {
      return;
    }
    await refreshSharedSingleAgentLocalSkillsCacheInternal(forceRescan: false);
  }

  Future<void> startupRefreshSharedSingleAgentLocalSkillsCacheInternal() async {
    await refreshSharedSingleAgentLocalSkillsCacheInternal(forceRescan: true);
    if (disposedInternal) {
      return;
    }
    if (assistantExecutionTargetForSession(currentSessionKey) ==
        AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(currentSessionKey);
      return;
    }
    notifyIfActiveInternal();
  }

  Future<List<AssistantThreadSkillEntry>>
  singleAgentLocalSkillsForSessionInternal(String sessionKey) async {
    await ensureSharedSingleAgentLocalSkillsLoaded();
    final workspaceSkills = await scanSingleAgentWorkspaceSkillEntriesInternal(
      sessionKey,
    );
    return mergeSingleAgentSkillEntriesInternal(
      groups: <List<AssistantThreadSkillEntry>>[
        singleAgentSharedImportedSkillsInternal,
        workspaceSkills,
      ],
    );
  }

  List<AssistantThreadSkillEntry> mergeSingleAgentSkillEntriesInternal({
    required List<List<AssistantThreadSkillEntry>> groups,
  }) {
    final merged = <String, AssistantThreadSkillEntry>{};
    for (final group in groups) {
      for (final skill in group) {
        final normalizedName = skill.label.trim().toLowerCase();
        if (normalizedName.isEmpty || merged.containsKey(normalizedName)) {
          continue;
        }
        merged[normalizedName] = skill;
      }
    }
    final entries = merged.values.toList(growable: false);
    entries.sort((left, right) => left.label.compareTo(right.label));
    return entries;
  }

  Future<bool> restoreSharedSingleAgentLocalSkillsCacheInternal() async {
    try {
      final payload = await storeInternal.loadSupportJson(
        singleAgentLocalSkillsCacheRelativePathInternal,
      );
      if (payload == null) {
        return false;
      }
      final schemaVersion = int.tryParse(
        payload['schemaVersion']?.toString() ?? '',
      );
      if (schemaVersion != singleAgentLocalSkillsCacheSchemaVersionInternal) {
        return false;
      }
      final skills = asList(payload['skills'])
          .map(asMap)
          .map(
            (item) => AssistantThreadSkillEntry.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .where((item) => item.key.trim().isNotEmpty && item.label.isNotEmpty)
          .toList(growable: false);
      if (skills.isEmpty) {
        singleAgentSharedImportedSkillsInternal =
            const <AssistantThreadSkillEntry>[];
        singleAgentLocalSkillsHydratedInternal = false;
        return false;
      }
      singleAgentSharedImportedSkillsInternal = skills;
      singleAgentLocalSkillsHydratedInternal = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> persistSharedSingleAgentLocalSkillsCacheInternal() async {
    try {
      await storeInternal.saveSupportJson(
        singleAgentLocalSkillsCacheRelativePathInternal,
        <String, dynamic>{
          'schemaVersion': singleAgentLocalSkillsCacheSchemaVersionInternal,
          'savedAtMs': DateTime.now().millisecondsSinceEpoch.toDouble(),
          'skills': singleAgentSharedImportedSkillsInternal
              .map((item) => item.toJson())
              .toList(growable: false),
        },
      );
    } catch (_) {
      // Best effort only for local cache persistence.
    }
  }

  Future<void> replaceSingleAgentThreadSkillsInternal(
    String sessionKey,
    List<AssistantThreadSkillEntry> importedSkills,
  ) async {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final importedKeys = importedSkills.map((item) => item.key).toSet();
    final nextSelected =
        (assistantThreadRecordsInternal[normalizedSessionKey]
                    ?.selectedSkillKeys ??
                const <String>[])
            .where(importedKeys.contains)
            .toList(growable: false);
    upsertTaskThreadInternal(
      normalizedSessionKey,
      importedSkills: importedSkills,
      selectedSkillKeys: nextSelected,
      selectedSkillsSource: assistantThreadRecordsInternal[normalizedSessionKey]
          ?.contextState
          .selectedSkillsSource,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    notifyIfActiveInternal();
  }

  AssistantThreadSkillEntry singleAgentSkillEntryFromAcpInternal(
    Map<String, dynamic> item,
    SingleAgentProvider provider,
  ) {
    return AssistantThreadSkillEntry(
      key: item['skillKey']?.toString().trim().isNotEmpty == true
          ? item['skillKey'].toString().trim()
          : (item['name']?.toString().trim() ?? ''),
      label: item['name']?.toString().trim() ?? '',
      description: item['description']?.toString().trim() ?? '',
      source: item['source']?.toString().trim() ?? provider.providerId,
      sourcePath: item['path']?.toString().trim() ?? '',
      scope: item['scope']?.toString().trim().isNotEmpty == true
          ? item['scope'].toString().trim()
          : 'session',
      sourceLabel: item['sourceLabel']?.toString().trim().isNotEmpty == true
          ? item['sourceLabel'].toString().trim()
          : (item['source']?.toString().trim().isNotEmpty == true
                ? item['source'].toString().trim()
                : provider.label),
    );
  }

  bool unsupportedAcpSkillsStatusInternal(GatewayAcpException error) {
    final code = (error.code ?? '').trim();
    if (code == '-32601' || code == 'METHOD_NOT_FOUND') {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('unknown method') ||
        message.contains('method not found') ||
        message.contains('skills.status');
  }

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
    List<AssistantThreadSkillEntry>? importedSkills,
    List<String>? selectedSkillKeys,
    String? assistantModelId,
    SingleAgentProvider? singleAgentProvider,
    ThreadSelectionSource? executionTargetSource,
    ThreadSelectionSource? singleAgentProviderSource,
    ThreadSelectionSource? assistantModelSource,
    ThreadSelectionSource? selectedSkillsSource,
    String? gatewayEntryState,
  }) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final existing = taskThreadForSessionInternal(normalizedSessionKey);
    final nextExecutionTarget =
        executionTarget ??
        switch (existing?.executionBinding.executionMode) {
          ThreadExecutionMode.auto => AssistantExecutionTarget.auto,
          ThreadExecutionMode.localAgent =>
            AssistantExecutionTarget.singleAgent,
          ThreadExecutionMode.gatewayLocal => AssistantExecutionTarget.local,
          ThreadExecutionMode.gatewayRemote => AssistantExecutionTarget.remote,
          null => settings.assistantExecutionTarget,
        };
    final nextImportedSkills =
        importedSkills ??
        existing?.importedSkills ??
        const <AssistantThreadSkillEntry>[];
    final importedKeys = nextImportedSkills.map((item) => item.key).toSet();
    final nextSelectedSkillKeys =
        (selectedSkillKeys ?? existing?.selectedSkillKeys ?? const <String>[])
            .where(importedKeys.contains)
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
        workspaceBinding ?? existing?.workspaceBinding;
    if (nextWorkspaceBinding == null || !nextWorkspaceBinding.isComplete) {
      throw StateError(
        'TaskThread $normalizedSessionKey is missing a complete workspaceBinding.',
      );
    }
    final nextProvider =
        singleAgentProvider ??
        SingleAgentProviderCopy.fromJsonValue(
          executionBinding?.providerId ?? existing?.executionBinding.providerId,
        );
    final nextExecutionBinding =
        (executionBinding ??
                existing?.executionBinding ??
                ExecutionBinding(
                  executionMode: ThreadExecutionMode.localAgent,
                  executorId: nextProvider.providerId,
                  providerId: nextProvider.providerId,
                  endpointId: '',
                ))
            .copyWith(
              executionMode: switch (nextExecutionTarget) {
                AssistantExecutionTarget.auto => ThreadExecutionMode.auto,
                AssistantExecutionTarget.singleAgent =>
                  ThreadExecutionMode.localAgent,
                AssistantExecutionTarget.local =>
                  ThreadExecutionMode.gatewayLocal,
                AssistantExecutionTarget.remote =>
                  ThreadExecutionMode.gatewayRemote,
              },
              executorId: nextProvider.providerId,
              providerId: nextProvider.providerId,
              executionModeSource:
                  executionTargetSource ??
                  existing?.executionBinding.executionModeSource,
              providerSource:
                  singleAgentProviderSource ??
                  existing?.executionBinding.providerSource,
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
                  importedSkills: const <AssistantThreadSkillEntry>[],
                  permissionLevel: AssistantPermissionLevel.defaultAccess,
                  messageViewMode: AssistantMessageViewMode.rendered,
                  latestResolvedRuntimeModel: '',
                  gatewayEntryState: gatewayEntryStateForTargetInternal(
                    nextExecutionTarget,
                  ),
                ))
            .copyWith(
              messages: nextMessages,
              messageViewMode: messageViewMode,
              importedSkills: nextImportedSkills,
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
              gatewayEntryState: gatewayEntryState,
            );
    final nextStatus =
        lifecycleState?.status ?? existing?.lifecycleState.status ?? 'ready';
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
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (normalizedSessionKey.isEmpty) {
      return;
    }
    await sessionsControllerInternal.switchSession(normalizedSessionKey);
    if (persistSelection) {
      await persistAssistantLastSessionKeyInternal(normalizedSessionKey);
    }
  }
}
