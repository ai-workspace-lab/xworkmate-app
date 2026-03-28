part of 'app_controller_desktop.dart';

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
    final synced = await _settingsController.syncAiGatewayCatalog(
      profile,
      apiKeyOverride: apiKeyOverride,
    );
    _modelsController.restoreFromSettings(
      _settingsController.snapshot.aiGateway,
    );
    _recomputeTasks();
    return synced;
  }

  Future<void> refreshDesktopIntegration() async {
    _desktopPlatformBusy = true;
    notifyListeners();
    try {
      await _desktopPlatformService.refresh();
    } finally {
      _desktopPlatformBusy = false;
      notifyListeners();
    }
  }

  Future<void> saveLinuxDesktopConfig(LinuxDesktopConfig config) async {
    await AppControllerDesktopSettings(
      this,
    ).saveSettings(settings.copyWith(linuxDesktop: config));
  }

  Future<void> setDesktopVpnMode(VpnMode mode) async {
    _desktopPlatformBusy = true;
    notifyListeners();
    try {
      await AppControllerDesktopSettings(this).saveSettings(
        settings.copyWith(
          linuxDesktop: settings.linuxDesktop.copyWith(preferredMode: mode),
        ),
        refreshAfterSave: false,
      );
      await _desktopPlatformService.setMode(mode);
    } finally {
      _desktopPlatformBusy = false;
      notifyListeners();
    }
  }

  Future<void> connectDesktopTunnel() async {
    _desktopPlatformBusy = true;
    notifyListeners();
    try {
      await _desktopPlatformService.connectTunnel();
    } finally {
      _desktopPlatformBusy = false;
      notifyListeners();
    }
  }

  Future<void> disconnectDesktopTunnel() async {
    _desktopPlatformBusy = true;
    notifyListeners();
    try {
      await _desktopPlatformService.disconnectTunnel();
    } finally {
      _desktopPlatformBusy = false;
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
    return _skillDirectoryAccessService.authorizeDirectory(
      suggestedPath: suggestedPath,
    );
  }

  Future<List<AuthorizedSkillDirectory>> authorizeSkillDirectories({
    List<String> suggestedPaths = const <String>[],
  }) {
    return _skillDirectoryAccessService.authorizeDirectories(
      suggestedPaths: suggestedPaths,
    );
  }

  Future<void> saveAuthorizedSkillDirectories(
    List<AuthorizedSkillDirectory> directories,
  ) async {
    if (_disposed) {
      return;
    }
    final previous = settings;
    final previousDraft = _settingsDraft;
    final hadDraftChanges = hasSettingsDraftChanges;
    final draftInitialized = _settingsDraftInitialized;
    final pendingSettingsApply = _pendingSettingsApply;
    final pendingGatewayApply = _pendingGatewayApply;
    final pendingAiGatewayApply = _pendingAiGatewayApply;
    await _persistSettingsSnapshot(
      previous.copyWith(
        authorizedSkillDirectories: normalizeAuthorizedSkillDirectories(
          directories: directories,
        ),
      ),
    );
    if (_disposed) {
      return;
    }
    await _applyPersistedSettingsSideEffects(
      previous: previous,
      current: settings,
      refreshAfterSave: false,
    );
    _lastAppliedSettings = settings;
    if (draftInitialized && hadDraftChanges) {
      _settingsDraft = previousDraft.copyWith(
        authorizedSkillDirectories: settings.authorizedSkillDirectories,
      );
      _settingsDraftInitialized = true;
      _pendingSettingsApply = pendingSettingsApply;
      _pendingGatewayApply = pendingGatewayApply;
      _pendingAiGatewayApply = pendingAiGatewayApply;
    } else {
      _settingsDraft = settings;
      _settingsDraftInitialized = true;
      _pendingSettingsApply = false;
      _pendingGatewayApply = false;
      _pendingAiGatewayApply = false;
      _settingsDraftStatusMessage = '';
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

  Future<String> testOllamaConnection({required bool cloud}) {
    return _settingsController.testOllamaConnection(cloud: cloud);
  }

  Future<String> testOllamaConnectionDraft({
    required bool cloud,
    required SettingsSnapshot snapshot,
    String apiKeyOverride = '',
  }) {
    return _settingsController.testOllamaConnectionDraft(
      cloud: cloud,
      localConfig: snapshot.ollamaLocal,
      cloudConfig: snapshot.ollamaCloud,
      apiKeyOverride: apiKeyOverride,
    );
  }

  Future<String> testVaultConnection() {
    return _settingsController.testVaultConnection();
  }

  Future<String> testVaultConnectionDraft({
    required SettingsSnapshot snapshot,
    String tokenOverride = '',
  }) {
    return _settingsController.testVaultConnectionDraft(
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
    _runtimeCoordinator.gateway.clearLogs();
    _notifyIfActive();
  }

  List<DerivedTaskItem> taskItemsForTab(String tab) => switch (tab) {
    'Queue' => _tasksController.queue,
    'Running' => _tasksController.running,
    'History' => _tasksController.history,
    'Failed' => _tasksController.failed,
    'Scheduled' => _tasksController.scheduled,
    _ => _tasksController.queue,
  };

  /// Enable Codex ↔ Gateway bridge
  Future<void> enableCodexBridge() async {
    if (_isCodexBridgeEnabled || _isCodexBridgeBusy) return;
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

    _isCodexBridgeBusy = true;
    _codexBridgeError = null;

    try {
      final gatewayUrl = aiGatewayUrl;
      final apiKey = await loadAiGatewayApiKey();

      if (gatewayUrl.isEmpty) {
        throw StateError(
          appText('LLM API Endpoint 未配置', 'LLM API Endpoint not configured'),
        );
      }

      await _refreshAcpCapabilities(forceRefresh: true);
      await _refreshSingleAgentCapabilities(forceRefresh: true);

      await _runtimeCoordinator.configureCodexForGateway(
        gatewayUrl: gatewayUrl,
        apiKey: apiKey,
      );

      _registerCodexExternalProvider();
      _isCodexBridgeEnabled = true;
      _codexCooperationState = CodexCooperationState.bridgeOnly;
      await _ensureCodexGatewayRegistration();
      notifyListeners();
    } catch (e) {
      _codexBridgeError = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _isCodexBridgeBusy = false;
      notifyListeners();
    }
  }

  /// Disable Codex ↔ Gateway bridge
  Future<void> disableCodexBridge() async {
    if (!_isCodexBridgeEnabled || _isCodexBridgeBusy) return;

    _isCodexBridgeBusy = true;

    try {
      if (_runtime.isConnected && _codeAgentBridgeRegistry.isRegistered) {
        await _codeAgentBridgeRegistry.unregister();
      } else {
        _codeAgentBridgeRegistry.clearRegistration();
      }
      _isCodexBridgeEnabled = false;
      _codexCooperationState = CodexCooperationState.notStarted;
      _codexBridgeError = null;
      notifyListeners();
    } catch (e) {
      _codexBridgeError = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _isCodexBridgeBusy = false;
      notifyListeners();
    }
  }

  Future<void> _initialize() async {
    try {
      _resolvedUserHomeDirectory = await _skillDirectoryAccessService
          .resolveUserHomeDirectory();
      await _settingsController.initialize();
      final storedAssistantThreads = await _store.loadAssistantThreadRecords();
      if (_disposed) {
        return;
      }
      final bootstrap = await RuntimeBootstrapConfig.load(
        workspacePathHint: settings.workspacePath,
        cliPathHint: settings.cliPath,
      );
      if (_disposed) {
        return;
      }
      final seeded = bootstrap.mergeIntoSettings(settings);
      if (seeded.toJsonString() != settings.toJsonString()) {
        await _settingsController.saveSnapshot(seeded);
        if (_disposed) {
          return;
        }
      }
      final normalized = _sanitizeFeatureFlagSettings(
        _sanitizeMultiAgentSettings(
          _sanitizeOllamaCloudSettings(
            _sanitizeCodeAgentSettings(_settingsController.snapshot),
          ),
        ),
      );
      if (normalized.toJsonString() !=
          _settingsController.snapshot.toJsonString()) {
        await _settingsController.saveSnapshot(normalized);
        if (_disposed) {
          return;
        }
      }
      _restoreAssistantThreads(storedAssistantThreads);
      await _restoreSharedSingleAgentLocalSkillsCache();
      if (_disposed) {
        return;
      }
      _lastObservedSettingsSnapshot = settings;
      _modelsController.restoreFromSettings(settings.aiGateway);
      _multiAgentOrchestrator.updateConfig(settings.multiAgent);
      setActiveAppLanguage(settings.appLanguage);
      await _desktopPlatformService.initialize(settings.linuxDesktop);
      await _desktopPlatformService.setLaunchAtLogin(settings.launchAtLogin);
      await _refreshResolvedCodexCliPath();
      _registerCodexExternalProvider();
      await _refreshSingleAgentCapabilities();
      await _refreshAcpCapabilities(persistMountTargets: true);
      if (_disposed) {
        return;
      }
      final startupTarget = _sanitizeExecutionTarget(
        settings.assistantExecutionTarget,
      );
      _agentsController.restoreSelection(
        settings
                .gatewayProfileForExecutionTarget(startupTarget)
                ?.selectedAgentId ??
            '',
      );
      _sessionsController.configure(
        mainSessionKey: _runtime.snapshot.mainSessionKey ?? 'main',
        selectedAgentId: _agentsController.selectedAgentId,
        defaultAgentId: '',
      );
      await _restoreInitialAssistantSessionSelection();
      await _ensureActiveAssistantThread();
      unawaited(_startupRefreshSharedSingleAgentLocalSkillsCache());
      if (isSingleAgentMode) {
        await refreshSingleAgentSkillsForSession(currentSessionKey);
      }
      _runtimeEventsSubscription = _runtimeCoordinator.gateway.events.listen(
        _handleRuntimeEvent,
      );
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
          await AppControllerDesktopGateway(this)._connectProfile(
            startupProfile,
            profileIndex: _gatewayProfileIndexForExecutionTarget(startupTarget),
          );
        } catch (_) {
          // Keep the shell usable when auto-connect fails.
        }
      }
      _settingsDraft = settings;
      _lastAppliedSettings = settings;
      _lastObservedSettingsSnapshot = settings;
      _settingsDraftInitialized = true;
      _settingsDraftStatusMessage = '';
    } catch (error) {
      if (_disposed) {
        return;
      }
      _bootstrapError = error.toString();
    } finally {
      if (!_disposed) {
        _initializing = false;
        _notifyIfActive();
      }
    }
  }

  void _markPendingApplyDomains(
    SettingsSnapshot previous,
    SettingsSnapshot next,
  ) {
    final hasGatewaySecretDraft = _draftSecretValues.keys.any(
      (key) => _isGatewayDraftKey(key),
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
        _draftSecretValues.containsKey(AppController._draftAiGatewayApiKeyKey);
    _pendingGatewayApply = _pendingGatewayApply || gatewayChanged;
    _pendingAiGatewayApply = _pendingAiGatewayApply || aiGatewayChanged;
  }

  Future<void> _persistDraftSecrets() async {
    for (var index = 0; index < kGatewayProfileListLength; index += 1) {
      final gatewayToken = _draftSecretValues[_draftGatewayTokenKey(index)];
      final gatewayPassword =
          _draftSecretValues[_draftGatewayPasswordKey(index)];
      if ((gatewayToken ?? '').isNotEmpty ||
          (gatewayPassword ?? '').isNotEmpty) {
        await _settingsController.saveGatewaySecrets(
          profileIndex: index,
          token: gatewayToken ?? '',
          password: gatewayPassword ?? '',
        );
      }
    }
    final aiGatewayApiKey =
        _draftSecretValues[AppController._draftAiGatewayApiKeyKey];
    if ((aiGatewayApiKey ?? '').isNotEmpty) {
      await _settingsController.saveAiGatewayApiKey(aiGatewayApiKey!);
    }
    final vaultToken = _draftSecretValues[AppController._draftVaultTokenKey];
    if ((vaultToken ?? '').isNotEmpty) {
      await _settingsController.saveVaultToken(vaultToken!);
    }
    final ollamaApiKey =
        _draftSecretValues[AppController._draftOllamaApiKeyKey];
    if ((ollamaApiKey ?? '').isNotEmpty) {
      await _settingsController.saveOllamaCloudApiKey(ollamaApiKey!);
    }
    _draftSecretValues.clear();
  }

  String _draftGatewayTokenKey(int profileIndex) =>
      'gateway_token_$profileIndex';

  String _draftGatewayPasswordKey(int profileIndex) =>
      'gateway_password_$profileIndex';

  bool _isGatewayDraftKey(String key) =>
      key.startsWith('gateway_token_') || key.startsWith('gateway_password_');

  bool _authorizedSkillDirectoriesChanged(
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

  Future<void> _persistSettingsSnapshot(SettingsSnapshot snapshot) async {
    final sanitized = _sanitizeFeatureFlagSettings(
      _sanitizeMultiAgentSettings(
        _sanitizeOllamaCloudSettings(_sanitizeCodeAgentSettings(snapshot)),
      ),
    );
    _lastObservedSettingsSnapshot = sanitized;
    await _settingsController.saveSnapshot(sanitized);
    _settingsDraft = sanitized;
    _settingsDraftInitialized = true;
  }

  Future<void> _applyPersistedSettingsSideEffects({
    required SettingsSnapshot previous,
    required SettingsSnapshot current,
    required bool refreshAfterSave,
  }) async {
    setActiveAppLanguage(current.appLanguage);
    _multiAgentOrchestrator.updateConfig(current.multiAgent);
    _agentsController.restoreSelection(
      current
              .gatewayProfileForExecutionTarget(
                _sanitizeExecutionTarget(current.assistantExecutionTarget),
              )
              ?.selectedAgentId ??
          '',
    );
    _modelsController.restoreFromSettings(current.aiGateway);
    if (_disposed) {
      return;
    }
    if (previous.codexCliPath != current.codexCliPath ||
        previous.codeAgentRuntimeMode != current.codeAgentRuntimeMode) {
      await _refreshResolvedCodexCliPath();
      _registerCodexExternalProvider();
    }
    unawaited(_refreshSingleAgentCapabilities());
    if (previous.linuxDesktop.toJson().toString() !=
            current.linuxDesktop.toJson().toString() ||
        previous.launchAtLogin != current.launchAtLogin) {
      await _desktopPlatformService.syncConfig(current.linuxDesktop);
      await _desktopPlatformService.setLaunchAtLogin(current.launchAtLogin);
      if (_disposed) {
        return;
      }
    }
    if (_authorizedSkillDirectoriesChanged(previous, current)) {
      await _refreshSharedSingleAgentLocalSkillsCache(forceRescan: true);
      if (_disposed) {
        return;
      }
      if (assistantExecutionTargetForSession(currentSessionKey) ==
          AssistantExecutionTarget.singleAgent) {
        await refreshSingleAgentSkillsForSession(currentSessionKey);
      }
    }
    if (refreshAfterSave) {
      _recomputeTasks();
    }
    unawaited(_refreshAcpCapabilities(persistMountTargets: true));
    notifyListeners();
  }

  Future<void> _applyPersistedGatewaySettings(SettingsSnapshot snapshot) async {
    final target = _sanitizeExecutionTarget(snapshot.assistantExecutionTarget);
    final sessionKey = _normalizedAssistantSessionKey(
      _sessionsController.currentSessionKey,
    );
    _upsertAssistantThreadRecord(
      sessionKey,
      executionTarget: target,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _recomputeTasks();
    _notifyIfActive();
    await _applyAssistantExecutionTarget(
      target,
      sessionKey: sessionKey,
      persistDefaultSelection: false,
    );
    if (target == AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(sessionKey);
    }
    _recomputeTasks();
    _notifyIfActive();
  }
}
