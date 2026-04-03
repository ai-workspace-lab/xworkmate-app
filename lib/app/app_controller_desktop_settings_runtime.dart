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
import '../runtime/go_gateway_runtime_desktop_client.dart';
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
import 'app_controller_desktop_thread_binding.dart';
import 'app_controller_desktop_single_agent.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopSettingsRuntime on AppController {
  Future<void> updateAiGatewaySelection(List<String> selectedModels) async {
    final available = settings.aiGateway.availableModels;
    final normalized = selectedModels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && available.contains(item))
        .toList(growable: false);
    final fallbackSelection = normalized.isNotEmpty
        ? normalized
        : available.isNotEmpty
        ? <String>[available.first]
        : const <String>[];
    final currentDefaultModel = settings.defaultModel.trim();
    final resolvedDefaultModel = fallbackSelection.contains(currentDefaultModel)
        ? currentDefaultModel
        : fallbackSelection.isNotEmpty
        ? fallbackSelection.first
        : '';
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(
        aiGateway: settings.aiGateway.copyWith(
          selectedModels: fallbackSelection,
        ),
        defaultModel: resolvedDefaultModel,
      ),
      refreshAfterSave: false,
    );
  }

  Future<AiGatewayProfile> syncAiGatewayCatalog(
    AiGatewayProfile profile, {
    String apiKeyOverride = '',
  }) async {
    final synced = await settingsControllerInternal.syncAiGatewayCatalog(
      profile,
      apiKeyOverride: apiKeyOverride,
    );
    modelsControllerInternal.restoreFromSettings(
      settingsControllerInternal.snapshot.aiGateway,
    );
    recomputeTasksInternal();
    return synced;
  }

  Future<void> refreshDesktopIntegration() async {
    desktopPlatformBusyInternal = true;
    notifyListeners();
    try {
      await desktopPlatformServiceInternal.refresh();
    } finally {
      desktopPlatformBusyInternal = false;
      notifyListeners();
    }
  }

  Future<void> saveLinuxDesktopConfig(LinuxDesktopConfig config) async {
    await AppControllerDesktopSettings(
      this,
    ).saveSettings(settings.copyWith(linuxDesktop: config));
  }

  Future<void> setDesktopVpnMode(VpnMode mode) async {
    desktopPlatformBusyInternal = true;
    notifyListeners();
    try {
      await AppControllerDesktopSettings(this).saveSettings(
        settings.copyWith(
          linuxDesktop: settings.linuxDesktop.copyWith(preferredMode: mode),
        ),
        refreshAfterSave: false,
      );
      await desktopPlatformServiceInternal.setMode(mode);
    } finally {
      desktopPlatformBusyInternal = false;
      notifyListeners();
    }
  }

  Future<void> connectDesktopTunnel() async {
    desktopPlatformBusyInternal = true;
    notifyListeners();
    try {
      await desktopPlatformServiceInternal.connectTunnel();
    } finally {
      desktopPlatformBusyInternal = false;
      notifyListeners();
    }
  }

  Future<void> disconnectDesktopTunnel() async {
    desktopPlatformBusyInternal = true;
    notifyListeners();
    try {
      await desktopPlatformServiceInternal.disconnectTunnel();
    } finally {
      desktopPlatformBusyInternal = false;
      notifyListeners();
    }
  }

  Future<void> setLaunchAtLogin(bool enabled) async {
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(launchAtLogin: enabled),
      refreshAfterSave: false,
    );
  }

  Future<AuthorizedSkillDirectory?> authorizeSkillDirectory({
    String suggestedPath = '',
  }) {
    return skillDirectoryAccessServiceInternal.authorizeDirectory(
      suggestedPath: suggestedPath,
    );
  }

  Future<List<AuthorizedSkillDirectory>> authorizeSkillDirectories({
    List<String> suggestedPaths = const <String>[],
  }) {
    return skillDirectoryAccessServiceInternal.authorizeDirectories(
      suggestedPaths: suggestedPaths,
    );
  }

  Future<void> saveAuthorizedSkillDirectories(
    List<AuthorizedSkillDirectory> directories,
  ) async {
    if (disposedInternal) {
      return;
    }
    final previous = settings;
    final previousDraft = settingsDraftInternal;
    final hadDraftChanges = hasSettingsDraftChanges;
    final draftInitialized = settingsDraftInitializedInternal;
    final pendingSettingsApply = pendingSettingsApplyInternal;
    final pendingGatewayApply = pendingGatewayApplyInternal;
    final pendingAiGatewayApply = pendingAiGatewayApplyInternal;
    await persistSettingsSnapshotInternal(
      previous.copyWith(
        authorizedSkillDirectories: normalizeAuthorizedSkillDirectories(
          directories: directories,
        ),
      ),
    );
    if (disposedInternal) {
      return;
    }
    await applyPersistedSettingsSideEffectsInternal(
      previous: previous,
      current: settings,
      refreshAfterSave: false,
    );
    lastAppliedSettingsInternal = settings;
    if (draftInitialized && hadDraftChanges) {
      settingsDraftInternal = previousDraft.copyWith(
        authorizedSkillDirectories: settings.authorizedSkillDirectories,
      );
      settingsDraftInitializedInternal = true;
      pendingSettingsApplyInternal = pendingSettingsApply;
      pendingGatewayApplyInternal = pendingGatewayApply;
      pendingAiGatewayApplyInternal = pendingAiGatewayApply;
    } else {
      settingsDraftInternal = settings;
      settingsDraftInitializedInternal = true;
      pendingSettingsApplyInternal = false;
      pendingGatewayApplyInternal = false;
      pendingAiGatewayApplyInternal = false;
      settingsDraftStatusMessageInternal = '';
    }
    notifyListeners();
  }

  Future<void> toggleAssistantNavigationDestination(
    AssistantFocusEntry destination,
  ) async {
    if (!kAssistantNavigationDestinationCandidates.contains(destination)) {
      return;
    }
    if (!supportsAssistantFocusEntry(destination)) {
      return;
    }
    final current = assistantNavigationDestinations;
    final next = current.contains(destination)
        ? current.where((item) => item != destination).toList(growable: false)
        : <AssistantFocusEntry>[...current, destination];
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(assistantNavigationDestinations: next),
      refreshAfterSave: false,
    );
  }

  Future<void> toggleAccountWorkspaceFollowed() async {
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(
        accountWorkspaceFollowed: !settings.accountWorkspaceFollowed,
      ),
      refreshAfterSave: false,
    );
  }

  Future<String> testOllamaConnection({required bool cloud}) {
    return settingsControllerInternal.testOllamaConnection(cloud: cloud);
  }

  Future<String> testOllamaConnectionDraft({
    required bool cloud,
    required SettingsSnapshot snapshot,
    String apiKeyOverride = '',
  }) {
    return settingsControllerInternal.testOllamaConnectionDraft(
      cloud: cloud,
      localConfig: snapshot.ollamaLocal,
      cloudConfig: snapshot.ollamaCloud,
      apiKeyOverride: apiKeyOverride,
    );
  }

  Future<String> testVaultConnection() {
    return settingsControllerInternal.testVaultConnection();
  }

  Future<String> testVaultConnectionDraft({
    required SettingsSnapshot snapshot,
    String tokenOverride = '',
  }) {
    return settingsControllerInternal.testVaultConnectionDraft(
      snapshot.vault,
      tokenOverride: tokenOverride,
    );
  }

  Future<({String state, String message, String endpoint})>
  testGatewayConnectionDraft({
    required GatewayConnectionProfile profile,
    required AssistantExecutionTarget executionTarget,
    String tokenOverride = '',
    String passwordOverride = '',
  }) async {
    if (executionTarget == AssistantExecutionTarget.singleAgent ||
        profile.mode == RuntimeConnectionMode.unconfigured) {
      return (
        state: 'inactive',
        message: appText(
          '当前模式使用单机智能体，不建立 OpenClaw Gateway 会话。',
          'The current mode uses Single Agent and does not open an OpenClaw Gateway session.',
        ),
        endpoint: '',
      );
    }

    final temporaryRoot = await Directory.systemTemp.createTemp(
      'xworkmate-gateway-test-',
    );
    final temporaryStore = SecureConfigStore(
      enableSecureStorage: false,
      databasePathResolver: () async =>
          '${temporaryRoot.path}/settings.sqlite3',
      fallbackDirectoryPathResolver: () async => temporaryRoot.path,
    );
    final runtime = GatewayRuntime(
      store: temporaryStore,
      identityStore: DeviceIdentityStore(temporaryStore),
    );
    await runtime.initialize();
    try {
      await runtime.connectProfile(
        profile,
        authTokenOverride: tokenOverride,
        authPasswordOverride: passwordOverride,
      );
      try {
        await runtime.health();
      } catch (_) {
        // Connectivity succeeded; health is best-effort for the test path.
      }
      final endpoint =
          runtime.snapshot.remoteAddress ?? '${profile.host}:${profile.port}';
      return (
        state: 'success',
        message: appText('连接成功。', 'Connection succeeded.'),
        endpoint: endpoint,
      );
    } catch (error) {
      return (
        state: 'error',
        message: error.toString(),
        endpoint: '${profile.host}:${profile.port}',
      );
    } finally {
      try {
        await runtime.disconnect(clearDesiredProfile: false);
      } catch (_) {
        // Ignore teardown noise from temporary connectivity checks.
      }
      runtime.dispose();
      temporaryStore.dispose();
      try {
        await temporaryRoot.delete(recursive: true);
      } catch (_) {
        // Ignore cleanup noise for temporary connectivity checks.
      }
    }
  }

  void clearRuntimeLogs() {
    runtimeCoordinatorInternal.gateway.clearLogs();
    notifyIfActiveInternal();
  }

  List<DerivedTaskItem> taskItemsForTab(String tab) => switch (tab) {
    'Queue' => tasksControllerInternal.queue,
    'Running' => tasksControllerInternal.running,
    'History' => tasksControllerInternal.history,
    'Failed' => tasksControllerInternal.failed,
    'Scheduled' => tasksControllerInternal.scheduled,
    _ => tasksControllerInternal.queue,
  };

  /// Enable Codex ↔ Gateway bridge
  Future<void> enableCodexBridge() async {
    if (isCodexBridgeEnabledInternal || isCodexBridgeBusyInternal) return;
    if (shouldBlockEmbeddedAgentLaunch(
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    )) {
      throw StateError(
        appText(
          'App Store 版本不允许在应用内启动或桥接外部 CLI 进程。',
          'App Store builds do not allow in-app external CLI bridge processes.',
        ),
      );
    }

    isCodexBridgeBusyInternal = true;
    codexBridgeErrorInternal = null;

    try {
      final gatewayUrl = aiGatewayUrl;
      final apiKey = await loadAiGatewayApiKey();

      if (gatewayUrl.isEmpty) {
        throw StateError(
          appText('LLM API Endpoint 未配置', 'LLM API Endpoint not configured'),
        );
      }

      await refreshAcpCapabilitiesInternal(forceRefresh: true);
      await refreshSingleAgentCapabilitiesInternal(forceRefresh: true);

      await runtimeCoordinatorInternal.configureCodexForGateway(
        gatewayUrl: gatewayUrl,
        apiKey: apiKey,
      );

      registerCodexExternalProviderInternal();
      isCodexBridgeEnabledInternal = true;
      codexCooperationStateInternal = CodexCooperationState.bridgeOnly;
      await ensureCodexGatewayRegistrationInternal();
      notifyListeners();
    } catch (e) {
      codexBridgeErrorInternal = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      isCodexBridgeBusyInternal = false;
      notifyListeners();
    }
  }

  /// Disable Codex ↔ Gateway bridge
  Future<void> disableCodexBridge() async {
    if (!isCodexBridgeEnabledInternal || isCodexBridgeBusyInternal) return;

    isCodexBridgeBusyInternal = true;

    try {
      if (runtimeInternal.isConnected &&
          codeAgentBridgeRegistryInternal.isRegistered) {
        await codeAgentBridgeRegistryInternal.unregister();
      } else {
        codeAgentBridgeRegistryInternal.clearRegistration();
      }
      isCodexBridgeEnabledInternal = false;
      codexCooperationStateInternal = CodexCooperationState.notStarted;
      codexBridgeErrorInternal = null;
      notifyListeners();
    } catch (e) {
      codexBridgeErrorInternal = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      isCodexBridgeBusyInternal = false;
      notifyListeners();
    }
  }

  Future<void> initializeInternal() async {
    try {
      resolvedUserHomeDirectoryInternal =
          await skillDirectoryAccessServiceInternal.resolveUserHomeDirectory();
      await settingsControllerInternal.initialize();
      final storedAssistantThreads = await storeInternal.loadTaskThreads();
      if (disposedInternal) {
        return;
      }
      final bootstrap = await RuntimeBootstrapConfig.load(
        workspacePathHint: settings.workspacePath,
        cliPathHint: settings.cliPath,
      );
      if (disposedInternal) {
        return;
      }
      final seeded = bootstrap.mergeIntoSettings(settings);
      if (seeded.toJsonString() != settings.toJsonString()) {
        await settingsControllerInternal.saveSnapshot(seeded);
        if (disposedInternal) {
          return;
        }
      }
      final normalized = sanitizeFeatureFlagSettingsInternal(
        sanitizeMultiAgentSettingsInternal(
          sanitizeOllamaCloudSettingsInternal(
            sanitizeCodeAgentSettingsInternal(
              settingsControllerInternal.snapshot,
            ),
          ),
        ),
      );
      if (normalized.toJsonString() !=
          settingsControllerInternal.snapshot.toJsonString()) {
        await settingsControllerInternal.saveSnapshot(normalized);
        if (disposedInternal) {
          return;
        }
      }
      try {
        await settingsControllerInternal.restoreAccountSession();
      } catch (_) {
        // Keep initialization resilient when remote account restore fails.
      }
      restoreAssistantThreadsInternal(storedAssistantThreads);
      await restoreSharedSingleAgentLocalSkillsCacheInternal();
      if (disposedInternal) {
        return;
      }
      lastObservedSettingsSnapshotInternal = settings;
      modelsControllerInternal.restoreFromSettings(settings.aiGateway);
      multiAgentOrchestratorInternal.updateConfig(settings.multiAgent);
      setActiveAppLanguage(settings.appLanguage);
      await desktopPlatformServiceInternal.initialize(settings.linuxDesktop);
      await desktopPlatformServiceInternal.setLaunchAtLogin(
        settings.launchAtLogin,
      );
      await refreshResolvedCodexCliPathInternal();
      registerCodexExternalProviderInternal();
      await refreshSingleAgentCapabilitiesInternal();
      await refreshAcpCapabilitiesInternal(persistMountTargets: true);
      if (disposedInternal) {
        return;
      }
      final startupTarget = sanitizeExecutionTargetInternal(
        settings.assistantExecutionTarget,
      );
      agentsControllerInternal.restoreSelection(
        settings
                .gatewayProfileForExecutionTarget(startupTarget)
                ?.selectedAgentId ??
            '',
      );
      sessionsControllerInternal.configure(
        mainSessionKey: runtimeInternal.snapshot.mainSessionKey ?? 'main',
        selectedAgentId: agentsControllerInternal.selectedAgentId,
        defaultAgentId: '',
      );
      await restoreInitialAssistantSessionSelectionInternal();
      await ensureActiveAssistantThreadInternal();
      await ensureDesktopTaskThreadBindingInternal(currentSessionKey);
      unawaited(startupRefreshSharedSingleAgentLocalSkillsCacheInternal());
      if (isSingleAgentMode) {
        await refreshSingleAgentSkillsForSession(currentSessionKey);
      }
      runtimeEventsSubscriptionInternal = runtimeCoordinatorInternal
          .gateway
          .events
          .listen(handleRuntimeEventInternal);
      final startupProfile = settings.gatewayProfileForExecutionTarget(
        startupTarget,
      );
      final shouldAutoConnect =
          startupTarget != AssistantExecutionTarget.singleAgent &&
          startupProfile != null &&
          startupProfile.useSetupCode &&
          startupProfile.setupCode.trim().isNotEmpty;
      if (shouldAutoConnect) {
        try {
          await AppControllerDesktopGateway(this).connectProfileInternal(
            startupProfile,
            profileIndex: gatewayProfileIndexForExecutionTargetInternal(
              startupTarget,
            ),
          );
        } catch (_) {
          // Keep the shell usable when auto-connect fails.
        }
      }
      settingsDraftInternal = settings;
      lastAppliedSettingsInternal = settings;
      lastObservedSettingsSnapshotInternal = settings;
      settingsDraftInitializedInternal = true;
      settingsDraftStatusMessageInternal = '';
    } catch (error) {
      if (disposedInternal) {
        return;
      }
      bootstrapErrorInternal = error.toString();
    } finally {
      if (!disposedInternal) {
        initializingInternal = false;
        notifyIfActiveInternal();
      }
    }
  }

  void markPendingApplyDomainsInternal(
    SettingsSnapshot previous,
    SettingsSnapshot next,
  ) {
    final hasGatewaySecretDraft = draftSecretValuesInternal.keys.any(
      (key) => isGatewayDraftKeyInternal(key),
    );
    final gatewayChanged =
        jsonEncode(
              previous.gatewayProfiles.map((item) => item.toJson()).toList(),
            ) !=
            jsonEncode(
              next.gatewayProfiles.map((item) => item.toJson()).toList(),
            ) ||
        previous.assistantExecutionTarget != next.assistantExecutionTarget ||
        hasGatewaySecretDraft;
    final aiGatewayChanged =
        previous.aiGateway.toJson().toString() !=
            next.aiGateway.toJson().toString() ||
        previous.defaultModel != next.defaultModel ||
        draftSecretValuesInternal.containsKey(
          AppController.draftAiGatewayApiKeyKeyInternal,
        );
    pendingGatewayApplyInternal = pendingGatewayApplyInternal || gatewayChanged;
    pendingAiGatewayApplyInternal =
        pendingAiGatewayApplyInternal || aiGatewayChanged;
  }

  Future<void> persistDraftSecretsInternal() async {
    for (var index = 0; index < kGatewayProfileListLength; index += 1) {
      final gatewayToken =
          draftSecretValuesInternal[draftGatewayTokenKeyInternal(index)];
      final gatewayPassword =
          draftSecretValuesInternal[draftGatewayPasswordKeyInternal(index)];
      if ((gatewayToken ?? '').isNotEmpty ||
          (gatewayPassword ?? '').isNotEmpty) {
        await settingsControllerInternal.saveGatewaySecrets(
          profileIndex: index,
          token: gatewayToken ?? '',
          password: gatewayPassword ?? '',
        );
      }
    }
    final aiGatewayApiKey =
        draftSecretValuesInternal[AppController
            .draftAiGatewayApiKeyKeyInternal];
    if ((aiGatewayApiKey ?? '').isNotEmpty) {
      await settingsControllerInternal.saveAiGatewayApiKey(aiGatewayApiKey!);
    }
    final vaultToken =
        draftSecretValuesInternal[AppController.draftVaultTokenKeyInternal];
    if ((vaultToken ?? '').isNotEmpty) {
      await settingsControllerInternal.saveVaultToken(vaultToken!);
    }
    final ollamaApiKey =
        draftSecretValuesInternal[AppController.draftOllamaApiKeyKeyInternal];
    if ((ollamaApiKey ?? '').isNotEmpty) {
      await settingsControllerInternal.saveOllamaCloudApiKey(ollamaApiKey!);
    }
    draftSecretValuesInternal.clear();
  }

  String draftGatewayTokenKeyInternal(int profileIndex) =>
      'gateway_token_$profileIndex';

  String draftGatewayPasswordKeyInternal(int profileIndex) =>
      'gateway_password_$profileIndex';

  bool isGatewayDraftKeyInternal(String key) =>
      key.startsWith('gateway_token_') || key.startsWith('gateway_password_');

  bool authorizedSkillDirectoriesChangedInternal(
    SettingsSnapshot previous,
    SettingsSnapshot current,
  ) {
    return jsonEncode(
          previous.authorizedSkillDirectories
              .map((item) => item.toJson())
              .toList(growable: false),
        ) !=
        jsonEncode(
          current.authorizedSkillDirectories
              .map((item) => item.toJson())
              .toList(growable: false),
        );
  }

  Future<void> persistSettingsSnapshotInternal(
    SettingsSnapshot snapshot,
  ) async {
    final sanitized = sanitizeFeatureFlagSettingsInternal(
      sanitizeMultiAgentSettingsInternal(
        sanitizeOllamaCloudSettingsInternal(
          sanitizeCodeAgentSettingsInternal(snapshot),
        ),
      ),
    );
    lastObservedSettingsSnapshotInternal = sanitized;
    await settingsControllerInternal.saveSnapshot(sanitized);
    settingsDraftInternal = sanitized;
    settingsDraftInitializedInternal = true;
  }

  Future<void> applyPersistedSettingsSideEffectsInternal({
    required SettingsSnapshot previous,
    required SettingsSnapshot current,
    required bool refreshAfterSave,
  }) async {
    setActiveAppLanguage(current.appLanguage);
    multiAgentOrchestratorInternal.updateConfig(current.multiAgent);
    agentsControllerInternal.restoreSelection(
      current
              .gatewayProfileForExecutionTarget(
                sanitizeExecutionTargetInternal(
                  current.assistantExecutionTarget,
                ),
              )
              ?.selectedAgentId ??
          '',
    );
    modelsControllerInternal.restoreFromSettings(current.aiGateway);
    if (disposedInternal) {
      return;
    }
    if (previous.codexCliPath != current.codexCliPath ||
        previous.codeAgentRuntimeMode != current.codeAgentRuntimeMode) {
      await refreshResolvedCodexCliPathInternal();
      registerCodexExternalProviderInternal();
    }
    unawaited(refreshSingleAgentCapabilitiesInternal().catchError((_) {}));
    if (previous.linuxDesktop.toJson().toString() !=
            current.linuxDesktop.toJson().toString() ||
        previous.launchAtLogin != current.launchAtLogin) {
      await desktopPlatformServiceInternal.syncConfig(current.linuxDesktop);
      await desktopPlatformServiceInternal.setLaunchAtLogin(
        current.launchAtLogin,
      );
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
    if (previous.workspacePath != current.workspacePath) {
      await ensureDesktopTaskThreadBindingInternal(currentSessionKey);
      if (disposedInternal) {
        return;
      }
      if (assistantExecutionTargetForSession(currentSessionKey) ==
          AssistantExecutionTarget.singleAgent) {
        await refreshSingleAgentSkillsForSession(currentSessionKey);
      }
    }
    if (refreshAfterSave) {
      recomputeTasksInternal();
    }
    unawaited(
      refreshAcpCapabilitiesInternal(
        persistMountTargets: true,
      ).catchError((_) {}),
    );
    notifyListeners();
  }

  Future<void> applyPersistedGatewaySettingsInternal(
    SettingsSnapshot snapshot,
  ) async {
    final target = sanitizeExecutionTargetInternal(
      snapshot.assistantExecutionTarget,
    );
    final sessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    upsertTaskThreadInternal(
      sessionKey,
      executionTarget: target,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
    await applyAssistantExecutionTargetInternal(
      target,
      sessionKey: sessionKey,
      persistDefaultSelection: false,
    );
    if (target == AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(sessionKey);
    }
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }
}
