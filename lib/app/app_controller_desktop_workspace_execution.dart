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
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/multi_agent_orchestrator.dart';
import '../runtime/platform_environment.dart';
import '../runtime/skill_directory_access.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
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
    final resolvedTarget = sanitizePersistedExecutionTargetInternal(target);
    final currentTarget = assistantExecutionTargetForSession(
      sessionsControllerInternal.currentSessionKey,
    );
    if (currentTarget == resolvedTarget &&
        settings.assistantExecutionTarget == resolvedTarget) {
      return;
    }
    if (!assistantThreadRecordsInternal.containsKey(
      sessionsControllerInternal.currentSessionKey,
    )) {
      initializeAssistantThreadContext(
        sessionsControllerInternal.currentSessionKey,
        executionTarget: resolvedTarget,
        messageViewMode: currentAssistantMessageViewMode,
      );
    }
    StateError? bindingError;
    try {
      await ensureDesktopTaskThreadBindingInternal(
        sessionsControllerInternal.currentSessionKey,
        executionTarget: resolvedTarget,
      );
    } on StateError catch (error) {
      // Keep the user-selected mode even if this thread cannot allocate a
      // writable local workspace yet. Execution-time checks still block runs
      // and surface a clear error when workspace setup is required.
      bindingError = error;
    }
    upsertTaskThreadInternal(
      sessionsControllerInternal.currentSessionKey,
      executionTarget: resolvedTarget,
      executionTargetSource: ThreadSelectionSource.explicit,
      gatewayEntryState: gatewayEntryStateForTargetInternal(resolvedTarget),
      latestResolvedRuntimeModel: '',
      latestResolvedProviderId: '',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
    await applyAssistantExecutionTargetInternal(
      resolvedTarget,
      sessionKey: sessionsControllerInternal.currentSessionKey,
      persistDefaultSelection: true,
    );
    if (bindingError != null) {
      debugPrint('setAssistantExecutionTarget binding fallback: $bindingError');
    }
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }

  Future<void> setAssistantSingleAgentProvider(
    SingleAgentProvider provider,
  ) async {
    final resolvedProvider = resolveAssistantProvider(provider.providerId);
    final sessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    if (sessionKey.isEmpty) {
      return;
    }
    final existing = taskThreadForSessionInternal(sessionKey);
    if (existing != null &&
        normalizeSingleAgentProviderId(existing.executionBinding.providerId) ==
            resolvedProvider.providerId &&
        existing.executionBinding.providerSource ==
            ThreadSelectionSource.explicit) {
      return;
    }
    if (!assistantThreadRecordsInternal.containsKey(sessionKey)) {
      initializeAssistantThreadContext(
        sessionKey,
        executionTarget: AssistantExecutionTarget.agent,
        messageViewMode: assistantMessageViewModeForSession(sessionKey),
      );
    }
    upsertTaskThreadInternal(
      sessionKey,
      executionTarget: AssistantExecutionTarget.agent,
      executionTargetSource: ThreadSelectionSource.explicit,
      singleAgentProvider: resolvedProvider,
      singleAgentProviderSource: ThreadSelectionSource.explicit,
      gatewayEntryState: gatewayEntryStateForTargetInternal(
        AssistantExecutionTarget.agent,
      ),
      latestResolvedProviderId: '',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await applyAssistantExecutionTargetInternal(
      AssistantExecutionTarget.agent,
      sessionKey: sessionKey,
      persistDefaultSelection: true,
    );
    await flushAssistantThreadPersistenceInternal();
    recomputeTasksInternal();
    notifyIfActiveInternal();
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
    if (!assistantThreadRecordsInternal.containsKey(sessionKey)) {
      initializeAssistantThreadContext(
        sessionKey,
        executionTarget: assistantExecutionTargetForSession(sessionKey),
        messageViewMode: assistantMessageViewModeForSession(sessionKey),
      );
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
    bool preserveGatewayHistoryForSelectedThread = true,
  }) async {
    final resolvedTarget = sanitizePersistedExecutionTargetInternal(target);
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    upsertTaskThreadInternal(
      normalizedSessionKey,
      latestResolvedRuntimeModel: '',
      latestResolvedProviderId: '',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
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
    if (!assistantThreadRecordsInternal.containsKey(normalizedSessionKey)) {
      initializeAssistantThreadContext(
        normalizedSessionKey,
        executionTarget: assistantExecutionTargetForSession(
          normalizedSessionKey,
        ),
        messageViewMode: assistantMessageViewModeForSession(
          normalizedSessionKey,
        ),
      );
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
    return assistantThreadRecordsInternal[normalizedSessionKey]?.title.trim() ??
        '';
  }

  void initializeAssistantThreadContext(
    String sessionKey, {
    String title = '',
    AssistantExecutionTarget? executionTarget,
    AssistantMessageViewMode? messageViewMode,
  }) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final resolvedTarget =
        executionTarget ??
        assistantExecutionTargetForSession(currentSessionKey);
    final initialOwnerScope =
        assistantThreadRecordsInternal[normalizedSessionKey]?.ownerScope ??
        const ThreadOwnerScope(
          realm: ThreadRealm.local,
          subjectType: ThreadSubjectType.user,
          subjectId: '',
          displayName: '',
        );
    final initialWorkspaceBinding = buildDesktopWorkspaceBindingInternal(
      normalizedSessionKey,
      executionTarget: resolvedTarget,
      ownerScope: initialOwnerScope,
      existingBinding: assistantThreadRecordsInternal[normalizedSessionKey]
          ?.workspaceBinding,
    );
    upsertTaskThreadInternal(
      normalizedSessionKey,
      title: title.trim(),
      ownerScope: initialOwnerScope,
      executionTarget: resolvedTarget,
      executionTargetSource: ThreadSelectionSource.explicit,
      workspaceBinding: initialWorkspaceBinding,
      messageViewMode:
          messageViewMode ??
          assistantMessageViewModeForSession(currentSessionKey),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    // Re-read the current thread target when the async binding sync runs so a
    // just-created thread cannot be rebound back to a stale target if the user
    // switches execution mode immediately afterwards.
    unawaited(ensureDesktopTaskThreadBindingInternal(normalizedSessionKey));
    unawaited(persistAssistantLastSessionKeyInternal(normalizedSessionKey));
    notifyIfActiveInternal();
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
    final current =
        assistantThreadRecordsInternal[normalizedSessionKey]?.title.trim() ??
        '';
    if (current == normalizedTitle) {
      return;
    }
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
    return assistantThreadRecordsInternal[normalizedSessionKey]?.archived ??
        false;
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
