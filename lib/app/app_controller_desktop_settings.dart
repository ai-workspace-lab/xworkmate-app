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
import 'app_controller_desktop_single_agent.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopSettings on AppController {
  SettingsSnapshot _markSavedGatewayTargetsForChangedProfiles(
    SettingsSnapshot previous,
    SettingsSnapshot snapshot,
  ) {
    var nextSnapshot = snapshot;
    if (jsonEncode(previous.primaryLocalGatewayProfile.toJson()) !=
        jsonEncode(snapshot.primaryLocalGatewayProfile.toJson())) {
      nextSnapshot = nextSnapshot.markGatewayTargetSaved(
        AssistantExecutionTarget.local,
      );
    }
    if (jsonEncode(previous.primaryRemoteGatewayProfile.toJson()) !=
        jsonEncode(snapshot.primaryRemoteGatewayProfile.toJson())) {
      nextSnapshot = nextSnapshot.markGatewayTargetSaved(
        AssistantExecutionTarget.remote,
      );
    }
    return nextSnapshot;
  }

  Future<void> saveSettingsDraft(SettingsSnapshot snapshot) async {
    if (disposedInternal) {
      return;
    }
    settingsDraftInternal = sanitizeFeatureFlagSettingsInternal(
      sanitizeMultiAgentSettingsInternal(
        sanitizeOllamaCloudSettingsInternal(
          sanitizeCodeAgentSettingsInternal(snapshot),
        ),
      ),
    );
    settingsDraftInitializedInternal = true;
    settingsDraftStatusMessageInternal = appText(
      '草稿已更新，点击顶部保存并生效。',
      'Draft updated. Use the top button to save and apply it.',
    );
    notifyListeners();
  }

  String draftSecretRefKeyInternal(String refName) =>
      'secret_ref::${refName.trim()}';

  void saveGatewayTokenDraft(String value, {required int profileIndex}) {
    saveSecretDraftInternal(
      draftSecretRefKeyInternal(
        settingsDraft.gatewayProfiles[profileIndex].tokenRef.trim().isEmpty
            ? SecretStore.gatewayTokenRefKey(profileIndex)
            : settingsDraft.gatewayProfiles[profileIndex].tokenRef,
      ),
      value,
    );
  }

  void saveGatewayPasswordDraft(String value, {required int profileIndex}) {
    saveSecretDraftInternal(
      draftSecretRefKeyInternal(
        settingsDraft.gatewayProfiles[profileIndex].passwordRef.trim().isEmpty
            ? SecretStore.gatewayPasswordRefKey(profileIndex)
            : settingsDraft.gatewayProfiles[profileIndex].passwordRef,
      ),
      value,
    );
  }

  void saveAiGatewayApiKeyDraft(String value) {
    saveSecretDraftInternal(
      draftSecretRefKeyInternal(
        settingsDraft.aiGateway.apiKeyRef.trim().isEmpty
            ? AppController.draftAiGatewayApiKeyKeyInternal
            : settingsDraft.aiGateway.apiKeyRef,
      ),
      value,
    );
  }

  void saveVaultTokenDraft(String value) {
    saveSecretDraftInternal(
      draftSecretRefKeyInternal(
        settingsDraft.vault.tokenRef.trim().isEmpty
            ? AppController.draftVaultTokenKeyInternal
            : settingsDraft.vault.tokenRef,
      ),
      value,
    );
  }

  void saveOllamaCloudApiKeyDraft(String value) {
    saveSecretDraftInternal(
      draftSecretRefKeyInternal(
        settingsDraft.ollamaCloud.apiKeyRef.trim().isEmpty
            ? AppController.draftOllamaApiKeyKeyInternal
            : settingsDraft.ollamaCloud.apiKeyRef,
      ),
      value,
    );
  }

  Future<void> saveWorkspacePath(String value) async {
    if (disposedInternal) {
      return;
    }
    final trimmed = value.trim();
    if (settings.workspacePath.trim() == trimmed) {
      if (settingsDraftInitializedInternal) {
        settingsDraftInternal = settingsDraft.copyWith(workspacePath: trimmed);
      }
      notifyListeners();
      return;
    }
    final previous = settings;
    await persistSettingsSnapshotInternal(
      settings.copyWith(workspacePath: trimmed),
    );
    if (disposedInternal) {
      return;
    }
    await applyPersistedSettingsSideEffectsInternal(
      previous: previous,
      current: settings,
      refreshAfterSave: true,
    );
    lastAppliedSettingsInternal = settings;
    settingsDraftInternal = settingsDraftInitializedInternal
        ? settingsDraftInternal.copyWith(workspacePath: settings.workspacePath)
        : settings;
    settingsDraftInitializedInternal = true;
    settingsDraftStatusMessageInternal = appText(
      '工作区路径已保存并立即生效。',
      'Workspace path saved and applied immediately.',
    );
    notifyListeners();
  }

  Future<void> persistSettingsDraft() async {
    if (disposedInternal) {
      return;
    }
    if (!hasSettingsDraftChanges) {
      settingsDraftStatusMessageInternal = appText(
        '没有需要保存的更改。',
        'There are no changes to save.',
      );
      notifyListeners();
      return;
    }
    final nextSettings = _markSavedGatewayTargetsForChangedProfiles(
      settings,
      settingsDraft,
    );
    markPendingApplyDomainsInternal(settings, nextSettings);
    await persistDraftSecretsInternal();
    if (nextSettings.toJsonString() != settings.toJsonString()) {
      await persistSettingsSnapshotInternal(nextSettings);
    }
    settingsDraftInternal = settings;
    settingsDraftInitializedInternal = true;
    pendingSettingsApplyInternal = true;
    settingsDraftStatusMessageInternal = appText(
      '已保存配置，等待立即生效。',
      'Settings saved and waiting to be applied.',
    );
    notifyListeners();
  }

  Future<void> applySettingsDraft() async {
    if (disposedInternal) {
      return;
    }
    if (hasSettingsDraftChanges) {
      await persistSettingsDraft();
    }
    if (!pendingSettingsApplyInternal) {
      settingsDraftStatusMessageInternal = appText(
        '没有需要应用的更改。',
        'There are no saved changes to apply.',
      );
      notifyListeners();
      return;
    }
    final currentSettings = settings;
    await applyPersistedSettingsSideEffectsInternal(
      previous: lastAppliedSettingsInternal,
      current: currentSettings,
      refreshAfterSave: true,
    );
    if (pendingGatewayApplyInternal) {
      await applyPersistedGatewaySettingsInternal(currentSettings);
    }
    if (pendingAiGatewayApplyInternal) {
      await applyPersistedAiGatewaySettingsInternal(currentSettings);
    }
    lastAppliedSettingsInternal = settings;
    pendingSettingsApplyInternal = false;
    pendingGatewayApplyInternal = false;
    pendingAiGatewayApplyInternal = false;
    settingsDraftInternal = settings;
    settingsDraftInitializedInternal = true;
    settingsDraftStatusMessageInternal = appText(
      '已按当前配置生效。',
      'The current configuration is now in effect.',
    );
    notifyListeners();
  }

  Future<void> saveSettings(
    SettingsSnapshot snapshot, {
    bool refreshAfterSave = true,
  }) async {
    if (disposedInternal) {
      return;
    }
    final previous = settings;
    final nextSnapshot = _markSavedGatewayTargetsForChangedProfiles(
      previous,
      snapshot,
    );
    await persistSettingsSnapshotInternal(nextSnapshot);
    if (disposedInternal) {
      return;
    }
    await applyPersistedSettingsSideEffectsInternal(
      previous: previous,
      current: settings,
      refreshAfterSave: refreshAfterSave,
    );
    lastAppliedSettingsInternal = settings;
    settingsDraftInternal = settings;
    settingsDraftInitializedInternal = true;
    pendingSettingsApplyInternal = false;
    pendingGatewayApplyInternal = false;
    pendingAiGatewayApplyInternal = false;
    draftSecretValuesInternal.clear();
    settingsDraftStatusMessageInternal = '';
  }

  Future<void> clearAssistantLocalState() async {
    await flushAssistantThreadPersistenceInternal();
    await storeInternal.clearAssistantLocalState();
    await storeInternal.saveTaskThreads(const <TaskThread>[]);
    final defaults = SettingsSnapshot.defaults();
    taskThreadRepositoryInternal.clear();
    assistantThreadMessagesInternal.clear();
    localSessionMessagesInternal.clear();
    gatewayHistoryCacheInternal.clear();
    aiGatewayStreamingTextBySessionInternal.clear();
    aiGatewayStreamingClientsInternal.clear();
    aiGatewayPendingSessionKeysInternal.clear();
    aiGatewayAbortedSessionKeysInternal.clear();
    singleAgentExternalCliPendingSessionKeysInternal.clear();
    assistantThreadTurnQueuesInternal.clear();
    multiAgentRunPendingInternal = false;
    setActiveAppLanguage(defaults.appLanguage);
    await settingsControllerInternal.saveSnapshot(defaults);
    multiAgentOrchestratorInternal.updateConfig(defaults.multiAgent);
    agentsControllerInternal.restoreSelection(
      defaults.primaryRemoteGatewayProfile.selectedAgentId,
    );
    modelsControllerInternal.restoreFromSettings(defaults.aiGateway);
    initializeAssistantThreadContext(
      'main',
      executionTarget: sanitizePersistedExecutionTargetInternal(
        defaults.assistantExecutionTarget,
      ),
      messageViewMode: AssistantMessageViewMode.rendered,
      singleAgentProvider: SingleAgentProvider.auto,
    );
    await setCurrentAssistantSessionKeyInternal(
      'main',
      persistSelection: false,
    );
    taskThreadRepositoryInternal.removeWhere(
      (key, _) => key != 'main',
      persist: false,
    );
    assistantThreadMessagesInternal.removeWhere((key, _) => key != 'main');
    await flushAssistantThreadPersistenceInternal();
    await storeInternal.saveTaskThreads(
      taskThreadRepositoryInternal.snapshot(),
    );
    chatControllerInternal.clear();
    recomputeTasksInternal();
    notifyListeners();
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
      'Draft updated. Use the top button to save and apply it.',
    );
    notifyListeners();
  }
}
