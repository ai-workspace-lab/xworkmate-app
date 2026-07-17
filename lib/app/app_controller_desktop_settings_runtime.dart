// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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
import '../runtime/secret_store.dart';
import '../runtime/settings_store.dart';
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
import 'app_controller_desktop_thread_binding.dart';
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
    await saveAppUiStateInternal(
      appUiState.copyWith(assistantNavigationDestinations: next),
      notify: true,
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
    if (profile.mode == RuntimeConnectionMode.unconfigured) {
      return (
        state: 'inactive',
        message: appText(
          '当前未配置可用 Gateway 连接。',
          'No active gateway connection is configured.',
        ),
        endpoint: '',
      );
    }

    final temporaryRoot = await Directory.systemTemp.createTemp(
      'xworkmate-gateway-test-',
    );
    final temporaryStore = SecureConfigStore(
      enableSecureStorage: false,
      appDataRootPathResolver: () async =>
          '${temporaryRoot.path}/settings.sqlite3',
      secretRootPathResolver: () async => temporaryRoot.path,
    );
    final runtime = GatewayRuntime(
      store: temporaryStore,
      identityStore: DeviceIdentityStore(temporaryStore),
    );
    await runtime.initialize();
    try {
      final existingIdentity = await storeInternal.loadDeviceIdentity();
      if (existingIdentity != null) {
        await temporaryStore.saveDeviceIdentity(existingIdentity);
        final existingOperatorDeviceToken = await storeInternal.loadDeviceToken(
          deviceId: existingIdentity.deviceId,
          role: 'operator',
        );
        final trimmedExistingOperatorDeviceToken =
            existingOperatorDeviceToken?.trim() ?? '';
        if (trimmedExistingOperatorDeviceToken.isNotEmpty) {
          await temporaryStore.saveDeviceToken(
            deviceId: existingIdentity.deviceId,
            role: 'operator',
            token: trimmedExistingOperatorDeviceToken,
          );
        }
      }
      await runtime.connectProfile(
        profile,
        authTokenOverride: tokenOverride,
        authPasswordOverride: passwordOverride,
      );
      try {
        await runtime.health();
      } catch (e, stackTrace) { debugPrint('Error: $e\n$stackTrace');
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
      } catch (e, stackTrace) { debugPrint('Error: $e\n$stackTrace');
        // Ignore teardown noise from temporary connectivity checks.
      }
      runtime.dispose();
      temporaryStore.dispose();
      try {
        await temporaryRoot.delete(recursive: true);
      } catch (e, stackTrace) { debugPrint('Error: $e\n$stackTrace');
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
      resolvedUserHomeDirectoryInternal = environmentOverrideInternal == null
          ? resolveUserHomeDirectory()
          : resolveUserHomeDirectoryFromControllerEnvironmentInternal(
              environmentOverrideInternal,
            );
      if ((Platform.isIOS || Platform.isAndroid) &&
          environmentOverrideInternal == null) {
        // iOS 进程没有 HOME 环境变量；线程工作区必须落在应用 Documents 下。
        // 必须在 restoreAssistantThreadsInternal 之前完成，绑定迁移才有基准。
        try {
          mobileWorkspaceBaseDirectoryInternal =
              (await getApplicationDocumentsDirectory()).path;
        } catch (error) {
          debugPrint('Resolve mobile documents directory failed: $error');
        }
      }
      await settingsControllerInternal.initialize();
      final loadedAppUiState = await storeInternal.loadAppUiState();
      final sanitizedAppUiState = sanitizeAppUiStateInternal(loadedAppUiState);
      appUiStateInternal = sanitizedAppUiState;
      if (sanitizedAppUiState.toJsonString() !=
          loadedAppUiState.toJsonString()) {
        await storeInternal.saveAppUiState(sanitizedAppUiState);
      }
      final storedAssistantThreads = await storeInternal.loadTaskThreads();
      final sanitizedAssistantThreads =
          discardKnownPollutedTestTaskThreadsInternal(storedAssistantThreads);
      if (sanitizedAssistantThreads.length != storedAssistantThreads.length) {
        await storeInternal.saveTaskThreads(sanitizedAssistantThreads);
      }
      final skippedInvalidThreadRecords =
          storeInternal.lastSkippedInvalidTaskThreadRecords;
      startupTaskThreadWarningInternal = skippedInvalidThreadRecords.isEmpty
          ? null
          : formatStartupTaskThreadWarningInternal(skippedInvalidThreadRecords);
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
        sanitizeOllamaCloudSettingsInternal(
          sanitizeCodeAgentSettingsInternal(
            settingsControllerInternal.snapshot,
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
      } catch (e, stackTrace) { debugPrint('Error: $e\n$stackTrace');
        // Keep initialization resilient when remote account restore fails.
      }
      restoreAssistantThreadsInternal(sanitizedAssistantThreads);
      if (disposedInternal) {
        return;
      }
      lastObservedSettingsSnapshotInternal = settings;
      modelsControllerInternal.restoreFromSettings(settings.aiGateway);
      setActiveAppLanguage(settings.appLanguage);
      await desktopPlatformServiceInternal.initialize(settings.linuxDesktop);
      await desktopPlatformServiceInternal.setLaunchAtLogin(
        settings.launchAtLogin,
      );
      registerCodexExternalProviderInternal();
      await refreshAcpCapabilitiesInternal(persistMountTargets: true);
      if (disposedInternal) {
        return;
      }
      final startupTarget = sanitizePersistedExecutionTargetInternal(
        settings.assistantExecutionTarget,
      );
      agentsControllerInternal.restoreSelection(
        settings
                .gatewayProfileForExecutionTarget(startupTarget)
                ?.selectedAgentId ??
            '',
      );
      sessionsControllerInternal.configure(
        selectedAgentId: agentsControllerInternal.selectedAgentId,
        defaultAgentId: '',
      );
      await restoreInitialAssistantSessionSelectionInternal();
      await ensureActiveAssistantThreadInternal();
      await ensureDesktopTaskThreadBindingInternal(currentSessionKey);
      runtimeEventsSubscriptionInternal = runtimeCoordinatorInternal
          .gateway
          .events
          .listen(handleRuntimeEventInternal);
      final startupProfile = settings.gatewayProfileForExecutionTarget(
        startupTarget,
      );
      final shouldAutoConnect =
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
        } catch (e, stackTrace) { debugPrint('Error: $e\n$stackTrace');
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

  String formatStartupTaskThreadWarningInternal(
    List<SkippedTaskThreadRecord> records,
  ) {
    final grouped = <SkippedTaskThreadReason, List<String>>{};
    for (final item in records) {
      grouped.putIfAbsent(item.reason, () => <String>[]).add(item.threadId);
    }

    String zhSegment(SkippedTaskThreadReason reason, List<String> threadIds) {
      final joined = threadIds.join(', ');
      return switch (reason) {
        SkippedTaskThreadReason.removedAutoExecutionMode =>
          '仍使用已移除 Auto 执行模式: $joined',
        SkippedTaskThreadReason.incompleteWorkspaceBinding =>
          '缺少完整 workspaceBinding: $joined',
        SkippedTaskThreadReason.invalidPersistedThreadData => '数据无效: $joined',
      };
    }

    String enSegment(SkippedTaskThreadReason reason, List<String> threadIds) {
      final joined = threadIds.join(', ');
      return switch (reason) {
        SkippedTaskThreadReason.removedAutoExecutionMode =>
          'removed Auto execution mode: $joined',
        SkippedTaskThreadReason.incompleteWorkspaceBinding =>
          'missing a complete workspaceBinding: $joined',
        SkippedTaskThreadReason.invalidPersistedThreadData =>
          'invalid persisted data: $joined',
      };
    }

    final reasons = grouped.keys.toList()
      ..sort((left, right) => left.index.compareTo(right.index));
    final zhSummary = reasons
        .map((reason) => zhSegment(reason, grouped[reason]!))
        .join('；');
    final enSummary = reasons
        .map((reason) => enSegment(reason, grouped[reason]!))
        .join('; ');
    return appText(
      '已跳过 ${records.length} 个旧任务线程：$zhSummary',
      'Skipped ${records.length} persisted task threads: $enSummary',
    );
  }

  void markPendingApplyDomainsInternal(
    SettingsSnapshot previous,
    SettingsSnapshot next,
  ) {
    final gatewayDraftKeys = <String>{
      for (final profile in previous.gatewayProfiles) ...[
        'secret_ref::${profile.tokenRef.trim().isEmpty ? '' : profile.tokenRef.trim()}',
        'secret_ref::${profile.passwordRef.trim().isEmpty ? '' : profile.passwordRef.trim()}',
      ],
      for (final profile in next.gatewayProfiles) ...[
        'secret_ref::${profile.tokenRef.trim().isEmpty ? '' : profile.tokenRef.trim()}',
        'secret_ref::${profile.passwordRef.trim().isEmpty ? '' : profile.passwordRef.trim()}',
      ],
    }..remove('secret_ref::');
    final aiGatewayDraftKeys = <String>{
      'secret_ref::${next.aiGateway.apiKeyRef.trim().isEmpty ? AppController.draftAiGatewayApiKeyKeyInternal : next.aiGateway.apiKeyRef.trim()}',
      'secret_ref::${previous.aiGateway.apiKeyRef.trim().isEmpty ? AppController.draftAiGatewayApiKeyKeyInternal : previous.aiGateway.apiKeyRef.trim()}',
      AppController.draftAiGatewayApiKeyKeyInternal,
    };
    final hasGatewaySecretDraft = draftSecretValuesInternal.keys.any(
      (key) => gatewayDraftKeys.contains(key) || isGatewayDraftKeyInternal(key),
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
    final hasAiGatewaySecretDraft = draftSecretValuesInternal.keys.any(
      aiGatewayDraftKeys.contains,
    );
    final aiGatewayChanged =
        previous.aiGateway.toJson().toString() !=
            next.aiGateway.toJson().toString() ||
        previous.defaultModel != next.defaultModel ||
        hasAiGatewaySecretDraft;
    pendingGatewayApplyInternal = pendingGatewayApplyInternal || gatewayChanged;
    pendingAiGatewayApplyInternal =
        pendingAiGatewayApplyInternal || aiGatewayChanged;
  }

  Future<void> persistDraftSecretsInternal() async {
    for (final entry in draftSecretValuesInternal.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (value.isEmpty) {
        continue;
      }
      if (key.startsWith('secret_ref::')) {
        final refName = key.substring('secret_ref::'.length).trim();
        if (refName.isEmpty) {
          continue;
        }
        await settingsControllerInternal.saveSecretValueByRef(
          refName,
          value,
          provider: settingsControllerInternal.providerNameForSecretInternal(
            refName,
          ),
          module: settingsControllerInternal.moduleForSecretInternal(refName),
        );
        continue;
      }
      if (key == AppController.draftAiGatewayApiKeyKeyInternal) {
        await settingsControllerInternal.saveAiGatewayApiKey(value);
        continue;
      }
      if (key == AppController.draftVaultTokenKeyInternal) {
        await settingsControllerInternal.saveVaultToken(value);
        continue;
      }
      if (key == AppController.draftOllamaApiKeyKeyInternal) {
        await settingsControllerInternal.saveOllamaCloudApiKey(value);
      }
    }
    draftSecretValuesInternal.clear();
  }

  String draftGatewayTokenKeyInternal(int profileIndex) =>
      'gateway_token_$profileIndex';

  String draftGatewayPasswordKeyInternal(int profileIndex) =>
      'gateway_password_$profileIndex';

  bool isGatewayDraftKeyInternal(String key) =>
      key.startsWith('secret_ref::gateway_token_') ||
      key.startsWith('secret_ref::gateway_password_') ||
      key.startsWith('gateway_token_') ||
      key.startsWith('gateway_password_');

  Future<void> persistSettingsSnapshotInternal(
    SettingsSnapshot snapshot,
  ) async {
    final sanitized = sanitizeFeatureFlagSettingsInternal(
      sanitizeOllamaCloudSettingsInternal(
        sanitizeCodeAgentSettingsInternal(snapshot),
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
    themeModeInternal = current.themeMode;

    final bridgeChanged =
        previous.acpBridgeServerModeConfig.toJsonString() !=
        current.acpBridgeServerModeConfig.toJsonString();

    if (refreshAfterSave || bridgeChanged) {
      // Re-trigger Bridge capability discovery if the mode or endpoint changed.
      unawaited(refreshAcpCapabilitiesInternal());
    }

    if (disposedInternal) {
      return;
    }
    if (previous.codeAgentRuntimeMode != current.codeAgentRuntimeMode) {
      registerCodexExternalProviderInternal();
    }
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
    if (previous.workspacePath != current.workspacePath) {
      await ensureDesktopTaskThreadBindingInternal(currentSessionKey);
      if (disposedInternal) {
        return;
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
    final sessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    final target = assistantExecutionTargetForSession(sessionKey);
    upsertTaskThreadInternal(
      sessionKey,
      executionTarget: target,
      executionTargetSource: ThreadSelectionSource.explicit,
      gatewayEntryState: gatewayEntryStateForTargetInternal(target),
      latestResolvedRuntimeModel: '',
      latestResolvedProviderId: '',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
    await applyAssistantExecutionTargetInternal(
      target,
      sessionKey: sessionKey,
      persistDefaultSelection: false,
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }
}
