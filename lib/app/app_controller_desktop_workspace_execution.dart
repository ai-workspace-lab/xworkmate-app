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
import 'app_controller_desktop_thread_binding.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopWorkspaceExecution on AppController {
  Future<void> setAssistantExecutionTarget(
    AssistantExecutionTarget target,
  ) async {
    final resolvedTarget = sanitizeExecutionTargetInternal(target);
    final currentTarget = assistantExecutionTargetForSession(
      sessionsControllerInternal.currentSessionKey,
    );
    if (currentTarget == resolvedTarget &&
        settings.assistantExecutionTarget == resolvedTarget) {
      return;
    }
    upsertTaskThreadInternal(
      sessionsControllerInternal.currentSessionKey,
      executionTarget: resolvedTarget,
      executionTargetSource: ThreadSelectionSource.explicit,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await ensureDesktopTaskThreadBindingInternal(
      sessionsControllerInternal.currentSessionKey,
      executionTarget: resolvedTarget,
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
    await applyAssistantExecutionTargetInternal(
      resolvedTarget,
      sessionKey: sessionsControllerInternal.currentSessionKey,
      persistDefaultSelection: true,
    );
    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(
        sessionsControllerInternal.currentSessionKey,
      );
    }
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }

  Future<void> setSingleAgentProvider(SingleAgentProvider provider) async {
    final sessionKey = normalizedAssistantSessionKeyInternal(currentSessionKey);
    final sanitizedProvider = settings.resolveSingleAgentProvider(provider);
    if (singleAgentProviderForSession(sessionKey) == sanitizedProvider) {
      return;
    }
    singleAgentRuntimeModelBySessionInternal.remove(sessionKey);
    upsertTaskThreadInternal(
      sessionKey,
      singleAgentProvider: sanitizedProvider,
      singleAgentProviderSource: ThreadSelectionSource.explicit,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
    if (assistantExecutionTargetForSession(sessionKey) ==
        AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(sessionKey);
    }
    unawaited(refreshMultiAgentMounts(sync: settings.multiAgent.autoSync));
  }

  Future<void> setAssistantMessageViewMode(
    AssistantMessageViewMode mode,
  ) async {
    final sessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    if (assistantMessageViewModeForSession(sessionKey) == mode) {
      return;
    }
    upsertTaskThreadInternal(
      sessionKey,
      messageViewMode: mode,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await flushAssistantThreadPersistenceInternal();
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }

  Future<void> setAssistantPermissionLevel(
    AssistantPermissionLevel level,
  ) async {
    if (settings.assistantPermissionLevel == level) {
      return;
    }
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(assistantPermissionLevel: level),
      refreshAfterSave: false,
    );
  }

  Future<void> applyAssistantExecutionTargetInternal(
    AssistantExecutionTarget target, {
    required String sessionKey,
    required bool persistDefaultSelection,
  }) async {
    final resolvedTarget = sanitizeExecutionTargetInternal(target);
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (resolvedTarget != AssistantExecutionTarget.singleAgent) {
      singleAgentRuntimeModelBySessionInternal.remove(normalizedSessionKey);
    }
    if (!matchesSessionKey(
      normalizedSessionKey,
      sessionsControllerInternal.currentSessionKey,
    )) {
      await setCurrentAssistantSessionKeyInternal(normalizedSessionKey);
    }
    if (persistDefaultSelection &&
        settings.assistantExecutionTarget != resolvedTarget) {
      await AppControllerDesktopSettings(this).saveSettings(
        settings.copyWith(assistantExecutionTarget: resolvedTarget),
        refreshAfterSave: false,
      );
    }

    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      if (runtimeInternal.isConnected) {
        preserveGatewayHistoryForSessionInternal(normalizedSessionKey);
      }
      await ensureActiveAssistantThreadInternal();
      if (runtimeInternal.isConnected) {
        try {
          await AppControllerDesktopGateway(this).disconnectGateway();
        } catch (_) {
          // Preserve the selected thread-bound target even when the active
          // gateway session does not close cleanly on the first attempt.
        }
      } else {
        chatControllerInternal.clear();
      }
      await setCurrentAssistantSessionKeyInternal(normalizedSessionKey);
      return;
    }

    final targetProfile = gatewayProfileForAssistantExecutionTargetInternal(
      resolvedTarget,
    );
    try {
      await AppControllerDesktopGateway(this).connectProfileInternal(
        targetProfile,
        profileIndex: gatewayProfileIndexForExecutionTargetInternal(
          resolvedTarget,
        ),
      );
    } catch (_) {
      // Keep the selected execution target even when the immediate reconnect
      // fails so the user can retry or adjust gateway settings manually.
    }
    await setCurrentAssistantSessionKeyInternal(normalizedSessionKey);
    await chatControllerInternal.loadSession(normalizedSessionKey);
  }

  Future<void> selectDefaultModel(String modelId) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty || settings.defaultModel == trimmed) {
      return;
    }
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(defaultModel: trimmed),
      refreshAfterSave: false,
    );
  }

  Future<void> selectAssistantModel(String modelId) async {
    await selectAssistantModelForSession(currentSessionKey, modelId);
  }

  Future<void> selectAssistantModelForSession(
    String sessionKey,
    String modelId,
  ) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final choices = matchesSessionKey(normalizedSessionKey, currentSessionKey)
        ? assistantModelChoices
        : assistantModelChoicesForSessionInternal(normalizedSessionKey);
    if (choices.isNotEmpty && !choices.contains(trimmed)) {
      return;
    }
    if (assistantThreadRecordsInternal[normalizedSessionKey]
            ?.assistantModelId ==
        trimmed) {
      return;
    }
    upsertTaskThreadInternal(
      normalizedSessionKey,
      assistantModelId: trimmed,
      assistantModelSource: ThreadSelectionSource.explicit,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }

  String assistantCustomTaskTitle(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final settingsTitle =
        settings.assistantCustomTaskTitles[normalizedSessionKey]?.trim() ?? '';
    if (settingsTitle.isNotEmpty) {
      return settingsTitle;
    }
    return assistantThreadRecordsInternal[normalizedSessionKey]?.title.trim() ??
        '';
  }

  void initializeAssistantThreadContext(
    String sessionKey, {
    String title = '',
    AssistantExecutionTarget? executionTarget,
    AssistantMessageViewMode? messageViewMode,
    SingleAgentProvider? singleAgentProvider,
  }) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final resolvedTarget =
        executionTarget ??
        assistantExecutionTargetForSession(currentSessionKey);
    final initialWorkspaceBinding =
        resolvedTarget == AssistantExecutionTarget.singleAgent
        ? (() {
            final localPath = localThreadWorkspacePathInternal(
              normalizedSessionKey,
            );
            return WorkspaceBinding(
              workspaceId: normalizedSessionKey,
              workspaceKind: WorkspaceKind.localFs,
              workspacePath: localPath,
              displayPath: localPath,
              writable: true,
            );
          })()
        : null;
    upsertTaskThreadInternal(
      normalizedSessionKey,
      title: title.trim(),
      executionTarget: resolvedTarget,
      workspaceBinding: initialWorkspaceBinding,
      messageViewMode:
          messageViewMode ??
          assistantMessageViewModeForSession(currentSessionKey),
      singleAgentProvider:
          singleAgentProvider ??
          singleAgentProviderForSession(currentSessionKey),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    unawaited(
      ensureDesktopTaskThreadBindingInternal(
        normalizedSessionKey,
        executionTarget: resolvedTarget,
      ),
    );
    unawaited(persistAssistantLastSessionKeyInternal(normalizedSessionKey));
    notifyIfActiveInternal();
  }

  Future<void> refreshSingleAgentSkillsForSession(String sessionKey) async {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return;
    }
    final localSkills = await singleAgentLocalSkillsForSessionInternal(
      normalizedSessionKey,
    );
    final provider =
        singleAgentResolvedProviderForSession(normalizedSessionKey) ??
        currentSingleAgentResolvedProvider;
    if (provider == null) {
      await replaceSingleAgentThreadSkillsInternal(
        normalizedSessionKey,
        localSkills,
      );
      return;
    }
    await replaceSingleAgentThreadSkillsInternal(
      normalizedSessionKey,
      localSkills,
    );
    try {
      await refreshAcpCapabilitiesInternal();
      final response = await gatewayAcpClientInternal.request(
        method: 'skills.status',
        params: <String, dynamic>{
          'sessionId': normalizedSessionKey,
          'threadId': normalizedSessionKey,
          'mode': 'single-agent',
          'provider': provider.providerId,
        },
      );
      final result = asMap(response['result']);
      final payload = result.isNotEmpty ? result : response;
      final skills = asList(payload['skills'])
          .map(asMap)
          .map((item) => singleAgentSkillEntryFromAcpInternal(item, provider))
          .where((item) => item.key.isNotEmpty && item.label.isNotEmpty)
          .toList(growable: false);
      await replaceSingleAgentThreadSkillsInternal(
        normalizedSessionKey,
        mergeSingleAgentSkillEntriesInternal(
          groups: <List<AssistantThreadSkillEntry>>[localSkills, skills],
        ),
      );
    } on GatewayAcpException catch (error) {
      if (unsupportedAcpSkillsStatusInternal(error)) {
        await replaceSingleAgentThreadSkillsInternal(
          normalizedSessionKey,
          localSkills,
        );
        return;
      }
      await replaceSingleAgentThreadSkillsInternal(
        normalizedSessionKey,
        localSkills,
      );
    } catch (_) {
      await replaceSingleAgentThreadSkillsInternal(
        normalizedSessionKey,
        localSkills,
      );
    }
  }

  Future<void> refreshSingleAgentLocalSkillsForSession(
    String sessionKey,
  ) async {
    await refreshSharedSingleAgentLocalSkillsCacheInternal(forceRescan: true);
    await refreshSingleAgentSkillsForSession(sessionKey);
  }

  Future<void> toggleAssistantSkillForSession(
    String sessionKey,
    String skillKey,
  ) async {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final normalizedSkillKey = skillKey.trim();
    if (normalizedSkillKey.isEmpty) {
      return;
    }
    final importedKeys = assistantImportedSkillsForSession(
      normalizedSessionKey,
    ).map((item) => item.key).toSet();
    if (!importedKeys.contains(normalizedSkillKey)) {
      return;
    }
    final nextSelected = List<String>.from(
      assistantSelectedSkillKeysForSession(normalizedSessionKey),
    );
    if (nextSelected.contains(normalizedSkillKey)) {
      nextSelected.remove(normalizedSkillKey);
    } else {
      nextSelected.add(normalizedSkillKey);
    }
    upsertTaskThreadInternal(
      normalizedSessionKey,
      selectedSkillKeys: nextSelected,
      selectedSkillsSource: ThreadSelectionSource.explicit,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    notifyIfActiveInternal();
    await flushAssistantThreadPersistenceInternal();
  }

  Future<void> saveAssistantTaskTitle(String sessionKey, String title) async {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (normalizedSessionKey.isEmpty) {
      return;
    }
    final normalizedTitle = title.trim();
    final next = Map<String, String>.from(settings.assistantCustomTaskTitles);
    final current = next[normalizedSessionKey]?.trim() ?? '';
    if (normalizedTitle.isEmpty) {
      if (current.isEmpty) {
        return;
      }
      next.remove(normalizedSessionKey);
    } else {
      if (current == normalizedTitle) {
        return;
      }
      next[normalizedSessionKey] = normalizedTitle;
    }
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(assistantCustomTaskTitles: next),
      refreshAfterSave: false,
    );
    upsertTaskThreadInternal(
      normalizedSessionKey,
      title: normalizedTitle,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }

  bool isAssistantTaskArchived(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    return settings.assistantArchivedTaskKeys.any(
      (item) =>
          normalizedAssistantSessionKeyInternal(item) == normalizedSessionKey,
    );
  }

  Future<void> saveAssistantTaskArchived(
    String sessionKey,
    bool archived,
  ) async {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (normalizedSessionKey.isEmpty) {
      return;
    }
    final next = <String>[
      ...settings.assistantArchivedTaskKeys.where(
        (item) =>
            normalizedAssistantSessionKeyInternal(item) != normalizedSessionKey,
      ),
    ];
    if (archived) {
      next.add(normalizedSessionKey);
    }
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(assistantArchivedTaskKeys: next),
      refreshAfterSave: false,
    );
    if (archived) {
      unawaited(
        enqueueThreadTurnInternal<void>(normalizedSessionKey, () async {
          try {
            await gatewayAcpClientInternal.closeSession(
              sessionId: normalizedSessionKey,
              threadId: normalizedSessionKey,
            );
          } catch (_) {
            // Best effort only.
          }
        }).catchError((_) {}),
      );
    }
    upsertTaskThreadInternal(
      normalizedSessionKey,
      archived: archived,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }
}
