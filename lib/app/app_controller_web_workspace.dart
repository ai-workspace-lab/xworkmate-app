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
import 'app_controller_web_session_actions.dart';
import 'app_controller_web_gateway_config.dart';
import 'app_controller_web_gateway_relay.dart';
import 'app_controller_web_gateway_chat.dart';
import 'app_controller_web_helpers.dart';

extension AppControllerWebWorkspace on AppController {
  Future<void> initializeInternal() async {
    try {
      await storeInternal.initialize();
      themeModeInternal = await storeInternal.loadThemeMode();
      settingsInternal = sanitizeSettingsInternal(
        await storeInternal.loadSettingsSnapshot(),
      );
      aiGatewayApiKeyCacheInternal = await storeInternal.loadAiGatewayApiKey();
      for (final profileIndex in <int>[
        kGatewayLocalProfileIndex,
        kGatewayRemoteProfileIndex,
      ]) {
        relayTokenByProfileInternal[profileIndex] = await storeInternal
            .loadRelayToken(profileIndex: profileIndex);
        relayPasswordByProfileInternal[profileIndex] = await storeInternal
            .loadRelayPassword(profileIndex: profileIndex);
      }
      webSessionClientIdInternal = await storeInternal
          .loadOrCreateWebSessionClientId();
      final records = await loadThreadRecordsInternal();
      for (final record in records) {
        final sanitized = sanitizeRecordInternal(record);
        threadRecordsInternal[sanitized.sessionKey] = sanitized;
        await ensureWebTaskThreadBindingInternal(
          sanitized.sessionKey,
          executionTarget: sanitized.executionTarget,
        );
      }
      if (threadRecordsInternal.isEmpty) {
        final record = newRecordInternal(
          target: settingsInternal.assistantExecutionTarget,
          title: appText('新对话', 'New conversation'),
        );
        threadRecordsInternal[record.sessionKey] = record;
        await ensureWebTaskThreadBindingInternal(
          record.sessionKey,
          executionTarget: record.executionTarget,
        );
      }
      final preferredSession = normalizedSessionKeyInternal(
        settingsInternal.assistantLastSessionKey,
      );
      if (preferredSession.isNotEmpty &&
          threadRecordsInternal.containsKey(preferredSession)) {
        currentSessionKeyInternal = preferredSession;
      } else {
        final visible = conversations;
        if (visible.isNotEmpty) {
          currentSessionKeyInternal = visible.first.sessionKey;
        } else {
          currentSessionKeyInternal = threadRecordsInternal.keys.first;
        }
      }
      settingsDraftInternal = settingsInternal;
      settingsDraftInitializedInternal = true;
      recomputeDerivedWorkspaceStateInternal();
    } catch (error) {
      bootstrapErrorInternal = '$error';
    } finally {
      initializingInternal = false;
      notifyChangedInternal();
    }
  }

  void navigateTo(WorkspaceDestination destination) {
    if (!capabilities.supportsDestination(destination)) {
      return;
    }
    destinationInternal = destination;
    notifyChangedInternal();
  }

  Future<void> saveWebSessionPersistenceConfiguration({
    required WebSessionPersistenceMode mode,
    required String remoteBaseUrl,
    required String apiToken,
  }) async {
    final trimmedRemoteBaseUrl = remoteBaseUrl.trim();
    final normalizedRemoteBaseUrl = RemoteWebSessionRepository.normalizeBaseUrl(
      trimmedRemoteBaseUrl,
    );
    if (mode == WebSessionPersistenceMode.remote &&
        trimmedRemoteBaseUrl.isNotEmpty &&
        normalizedRemoteBaseUrl == null) {
      sessionPersistenceStatusMessageInternal = appText(
        'Session API URL 必须使用 HTTPS；仅 localhost / 127.0.0.1 允许 HTTP 作为开发回路。',
        'Session API URLs must use HTTPS. HTTP is allowed only for localhost or 127.0.0.1 during development.',
      );
      notifyChangedInternal();
      return;
    }
    settingsInternal = settingsInternal.copyWith(
      webSessionPersistence: settingsInternal.webSessionPersistence.copyWith(
        mode: mode,
        remoteBaseUrl:
            normalizedRemoteBaseUrl?.toString() ?? trimmedRemoteBaseUrl,
      ),
    );
    webSessionApiTokenCacheInternal = apiToken.trim();
    await persistSettingsInternal();
    await persistThreadsInternal();
    notifyChangedInternal();
  }

  void navigateHome() {
    navigateTo(WorkspaceDestination.assistant);
  }

  void openSettings({SettingsTab tab = SettingsTab.general}) {
    destinationInternal = WorkspaceDestination.settings;
    settingsTabInternal = sanitizeSettingsTabInternal(tab);
    notifyChangedInternal();
  }

  void setSettingsTab(SettingsTab tab) {
    settingsTabInternal = sanitizeSettingsTabInternal(tab);
    notifyChangedInternal();
  }

  List<DerivedTaskItem> taskItemsForTab(String tab) => switch (tab) {
    'Queue' => tasksControllerInternal.queue,
    'Running' => tasksControllerInternal.running,
    'History' => tasksControllerInternal.history,
    'Failed' => tasksControllerInternal.failed,
    'Scheduled' => tasksControllerInternal.scheduled,
    _ => tasksControllerInternal.queue,
  };

  Future<void> refreshSessions() async {
    if (connection.status == RuntimeConnectionStatus.connected) {
      await refreshRelaySessions();
      await refreshRelayWorkspaceResources();
      await refreshRelayHistory(sessionKey: currentSessionKeyInternal);
      await refreshRelaySkillsForSession(currentSessionKeyInternal);
    } else {
      recomputeDerivedWorkspaceStateInternal();
      notifyChangedInternal();
    }
  }

  Future<void> refreshAgents() async {
    await refreshRelayWorkspaceResources();
  }

  Future<void> refreshGatewayHealth() async {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    await refreshRelayWorkspaceResources();
  }

  Future<void> refreshVisibleSkills(String? agentId) async {
    final target = assistantExecutionTargetForSession(
      currentSessionKeyInternal,
    );
    if (target == AssistantExecutionTarget.local ||
        target == AssistantExecutionTarget.remote) {
      await refreshRelaySkillsForSession(currentSessionKeyInternal);
      return;
    }
    await refreshSingleAgentSkillsForSessionInternal(currentSessionKeyInternal);
  }

  Future<void> toggleAssistantNavigationDestination(
    AssistantFocusEntry destination,
  ) async {
    if (!kAssistantNavigationDestinationCandidates.contains(destination) ||
        !supportsAssistantFocusEntry(destination)) {
      return;
    }
    final current = assistantNavigationDestinations;
    final next = current.contains(destination)
        ? current.where((item) => item != destination).toList(growable: false)
        : <AssistantFocusEntry>[...current, destination];
    settingsInternal = settingsInternal.copyWith(
      assistantNavigationDestinations: next,
    );
    if (settingsDraftInitializedInternal) {
      settingsDraftInternal = settingsDraft.copyWith(
        assistantNavigationDestinations: next,
      );
    }
    notifyChangedInternal();
    await persistSettingsInternal();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (themeModeInternal == mode) {
      return;
    }
    themeModeInternal = mode;
    await storeInternal.saveThemeMode(mode);
    notifyChangedInternal();
  }

  Future<void> saveSettingsDraft(SettingsSnapshot snapshot) async {
    settingsDraftInternal = snapshot;
    settingsDraftInitializedInternal = true;
    settingsDraftStatusMessageInternal = appText(
      '草稿已更新，点击顶部保存持久化。',
      'Draft updated. Use the top Save button to persist it.',
    );
    notifyChangedInternal();
  }

  Future<AuthorizedSkillDirectory?> authorizeSkillDirectory({
    String suggestedPath = '',
  }) async {
    return null;
  }

  Future<List<AuthorizedSkillDirectory>> authorizeSkillDirectories({
    List<String> suggestedPaths = const <String>[],
  }) async {
    return const <AuthorizedSkillDirectory>[];
  }

  Future<void> saveAuthorizedSkillDirectories(
    List<AuthorizedSkillDirectory> directories,
  ) async {
    settingsInternal = settingsInternal.copyWith(
      authorizedSkillDirectories: normalizeAuthorizedSkillDirectories(
        directories: directories,
      ),
    );
    if (settingsDraftInitializedInternal) {
      settingsDraftInternal = settingsDraftInternal.copyWith(
        authorizedSkillDirectories: settingsInternal.authorizedSkillDirectories,
      );
    }
    await persistSettingsInternal();
    notifyChangedInternal();
  }

  void saveAiGatewayApiKeyDraft(String value) {
    saveSecretDraftInternal(
      AppController.draftAiGatewayApiKeyKeyInternal,
      value,
    );
  }

  void saveVaultTokenDraft(String value) {
    saveSecretDraftInternal(AppController.draftVaultTokenKeyInternal, value);
  }

  void saveOllamaCloudApiKeyDraft(String value) {
    saveSecretDraftInternal(AppController.draftOllamaApiKeyKeyInternal, value);
  }

  Future<String> testOllamaConnection({required bool cloud}) async {
    return cloud
        ? 'Cloud test unavailable on web'
        : 'Local test unavailable on web';
  }

  Future<String> testOllamaConnectionDraft({
    required bool cloud,
    required SettingsSnapshot snapshot,
    String apiKeyOverride = '',
  }) async {
    return testOllamaConnection(cloud: cloud);
  }

  Future<String> testVaultConnection() async {
    return 'Vault test unavailable on web';
  }

  Future<String> testVaultConnectionDraft({
    required SettingsSnapshot snapshot,
    String tokenOverride = '',
  }) async {
    return testVaultConnection();
  }

  Future<({String state, String message, String endpoint})>
  testGatewayConnectionDraft({
    required GatewayConnectionProfile profile,
    required AssistantExecutionTarget executionTarget,
    String tokenOverride = '',
    String passwordOverride = '',
  }) async {
    final resolvedTarget =
        sanitizeTargetInternal(executionTarget) ??
        AssistantExecutionTarget.remote;
    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      return (
        state: 'error',
        message: appText(
          'Single Agent 不需要 Gateway 连通性测试。',
          'Single Agent does not require a gateway connectivity test.',
        ),
        endpoint: '',
      );
    }
    final expectedMode = resolvedTarget == AssistantExecutionTarget.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    final candidateProfile = profile.copyWith(
      mode: expectedMode,
      useSetupCode: false,
      setupCode: '',
      tls: expectedMode == RuntimeConnectionMode.local ? false : profile.tls,
    );
    final endpoint = gatewayAddressLabelInternal(candidateProfile);
    final client = WebRelayGatewayClient(storeInternal);
    try {
      await client.connect(
        profile: candidateProfile,
        authToken: tokenOverride.trim(),
        authPassword: passwordOverride.trim(),
      );
      return (
        state: 'connected',
        message: appText('连接测试成功。', 'Connection test succeeded.'),
        endpoint: endpoint,
      );
    } catch (error) {
      return (state: 'error', message: error.toString(), endpoint: endpoint);
    } finally {
      await client.dispose();
    }
  }

  Future<void> persistSettingsDraft() async {
    if (!hasSettingsDraftChanges) {
      settingsDraftStatusMessageInternal = appText(
        '没有需要保存的更改。',
        'There are no changes to save.',
      );
      notifyChangedInternal();
      return;
    }
    settingsInternal = settingsDraft;
    await persistDraftSecretsInternal();
    await persistSettingsInternal();
    settingsDraftInternal = settingsInternal;
    settingsDraftInitializedInternal = true;
    pendingSettingsApplyInternal = true;
    settingsDraftStatusMessageInternal = appText(
      '已保存配置，不立即生效。',
      'Settings saved. They do not take effect until Apply.',
    );
    notifyChangedInternal();
  }

  Future<void> applySettingsDraft() async {
    if (hasSettingsDraftChanges) {
      await persistSettingsDraft();
    }
    if (!pendingSettingsApplyInternal) {
      settingsDraftStatusMessageInternal = appText(
        '没有需要应用的更改。',
        'There are no saved changes to apply.',
      );
      notifyChangedInternal();
      return;
    }
    settingsDraftInternal = settingsInternal;
    settingsDraftInitializedInternal = true;
    pendingSettingsApplyInternal = false;
    settingsDraftStatusMessageInternal = appText(
      '已按当前配置生效。',
      'The current configuration is now in effect.',
    );
    notifyChangedInternal();
  }

  Future<void> toggleAppLanguage() async {
    final next = settingsInternal.appLanguage == AppLanguage.zh
        ? AppLanguage.en
        : AppLanguage.zh;
    settingsInternal = settingsInternal.copyWith(appLanguage: next);
    await persistSettingsInternal();
    notifyChangedInternal();
  }
}
