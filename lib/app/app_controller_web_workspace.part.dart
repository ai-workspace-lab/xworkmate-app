part of 'app_controller_web.dart';

extension AppControllerWebWorkspace on AppController {
  Future<void> _initialize() async {
    try {
      await _store.initialize();
      _themeMode = await _store.loadThemeMode();
      _settings = _sanitizeSettings(await _store.loadSettingsSnapshot());
      _aiGatewayApiKeyCache = await _store.loadAiGatewayApiKey();
      for (final profileIndex in <int>[
        kGatewayLocalProfileIndex,
        kGatewayRemoteProfileIndex,
      ]) {
        _relayTokenByProfile[profileIndex] = await _store.loadRelayToken(
          profileIndex: profileIndex,
        );
        _relayPasswordByProfile[profileIndex] = await _store.loadRelayPassword(
          profileIndex: profileIndex,
        );
      }
      _webSessionClientId = await _store.loadOrCreateWebSessionClientId();
      final records = await _loadThreadRecords();
      for (final record in records) {
        final sanitized = _sanitizeRecord(record);
        _threadRecords[sanitized.sessionKey] = sanitized;
      }
      if (_threadRecords.isEmpty) {
        final record = _newRecord(
          target: _settings.assistantExecutionTarget,
          title: appText('新对话', 'New conversation'),
        );
        _threadRecords[record.sessionKey] = record;
      }
      final preferredSession = _normalizedSessionKey(
        _settings.assistantLastSessionKey,
      );
      if (preferredSession.isNotEmpty &&
          _threadRecords.containsKey(preferredSession)) {
        _currentSessionKey = preferredSession;
      } else {
        final visible = conversations;
        if (visible.isNotEmpty) {
          _currentSessionKey = visible.first.sessionKey;
        } else {
          _currentSessionKey = _threadRecords.keys.first;
        }
      }
      _settingsDraft = _settings;
      _settingsDraftInitialized = true;
      _recomputeDerivedWorkspaceState();
    } catch (error) {
      _bootstrapError = '$error';
    } finally {
      _initializing = false;
      _notifyChanged();
    }
  }

  void navigateTo(WorkspaceDestination destination) {
    if (!capabilities.supportsDestination(destination)) {
      return;
    }
    _destination = destination;
    _notifyChanged();
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
      _sessionPersistenceStatusMessage = appText(
        'Session API URL 必须使用 HTTPS；仅 localhost / 127.0.0.1 允许 HTTP 作为开发回路。',
        'Session API URLs must use HTTPS. HTTP is allowed only for localhost or 127.0.0.1 during development.',
      );
      _notifyChanged();
      return;
    }
    _settings = _settings.copyWith(
      webSessionPersistence: _settings.webSessionPersistence.copyWith(
        mode: mode,
        remoteBaseUrl:
            normalizedRemoteBaseUrl?.toString() ?? trimmedRemoteBaseUrl,
      ),
    );
    _webSessionApiTokenCache = apiToken.trim();
    await _persistSettings();
    await _persistThreads();
    _notifyChanged();
  }

  void navigateHome() {
    navigateTo(WorkspaceDestination.assistant);
  }

  void openSettings({SettingsTab tab = SettingsTab.general}) {
    _destination = WorkspaceDestination.settings;
    _settingsTab = _sanitizeSettingsTab(tab);
    _notifyChanged();
  }

  void setSettingsTab(SettingsTab tab) {
    _settingsTab = _sanitizeSettingsTab(tab);
    _notifyChanged();
  }

  List<DerivedTaskItem> taskItemsForTab(String tab) => switch (tab) {
    'Queue' => _tasksController.queue,
    'Running' => _tasksController.running,
    'History' => _tasksController.history,
    'Failed' => _tasksController.failed,
    'Scheduled' => _tasksController.scheduled,
    _ => _tasksController.queue,
  };

  Future<void> refreshSessions() async {
    if (connection.status == RuntimeConnectionStatus.connected) {
      await refreshRelaySessions();
      await refreshRelayWorkspaceResources();
      await refreshRelayHistory(sessionKey: _currentSessionKey);
      await refreshRelaySkillsForSession(_currentSessionKey);
    } else {
      _recomputeDerivedWorkspaceState();
      _notifyChanged();
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
    final target = assistantExecutionTargetForSession(_currentSessionKey);
    if (target == AssistantExecutionTarget.local ||
        target == AssistantExecutionTarget.remote) {
      await refreshRelaySkillsForSession(_currentSessionKey);
      return;
    }
    await _refreshSingleAgentSkillsForSession(_currentSessionKey);
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
    _settings = _settings.copyWith(assistantNavigationDestinations: next);
    if (_settingsDraftInitialized) {
      _settingsDraft = settingsDraft.copyWith(
        assistantNavigationDestinations: next,
      );
    }
    _notifyChanged();
    await _persistSettings();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }
    _themeMode = mode;
    await _store.saveThemeMode(mode);
    _notifyChanged();
  }

  Future<void> saveSettingsDraft(SettingsSnapshot snapshot) async {
    _settingsDraft = snapshot;
    _settingsDraftInitialized = true;
    _settingsDraftStatusMessage = appText(
      '草稿已更新，点击顶部保存持久化。',
      'Draft updated. Use the top Save button to persist it.',
    );
    _notifyChanged();
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
    _settings = _settings.copyWith(
      authorizedSkillDirectories: normalizeAuthorizedSkillDirectories(
        directories: directories,
      ),
    );
    if (_settingsDraftInitialized) {
      _settingsDraft = _settingsDraft.copyWith(
        authorizedSkillDirectories: _settings.authorizedSkillDirectories,
      );
    }
    await _persistSettings();
    _notifyChanged();
  }

  void saveAiGatewayApiKeyDraft(String value) {
    _saveSecretDraft(AppController._draftAiGatewayApiKeyKey, value);
  }

  void saveVaultTokenDraft(String value) {
    _saveSecretDraft(AppController._draftVaultTokenKey, value);
  }

  void saveOllamaCloudApiKeyDraft(String value) {
    _saveSecretDraft(AppController._draftOllamaApiKeyKey, value);
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
        _sanitizeTarget(executionTarget) ?? AssistantExecutionTarget.remote;
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
    final endpoint = _gatewayAddressLabel(candidateProfile);
    final client = WebRelayGatewayClient(_store);
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
      _settingsDraftStatusMessage = appText(
        '没有需要保存的更改。',
        'There are no changes to save.',
      );
      _notifyChanged();
      return;
    }
    _settings = settingsDraft;
    await _persistDraftSecrets();
    await _persistSettings();
    _settingsDraft = _settings;
    _settingsDraftInitialized = true;
    _pendingSettingsApply = true;
    _settingsDraftStatusMessage = appText(
      '已保存配置，不立即生效。',
      'Settings saved. They do not take effect until Apply.',
    );
    _notifyChanged();
  }

  Future<void> applySettingsDraft() async {
    if (hasSettingsDraftChanges) {
      await persistSettingsDraft();
    }
    if (!_pendingSettingsApply) {
      _settingsDraftStatusMessage = appText(
        '没有需要应用的更改。',
        'There are no saved changes to apply.',
      );
      _notifyChanged();
      return;
    }
    _settingsDraft = _settings;
    _settingsDraftInitialized = true;
    _pendingSettingsApply = false;
    _settingsDraftStatusMessage = appText(
      '已按当前配置生效。',
      'The current configuration is now in effect.',
    );
    _notifyChanged();
  }

  Future<void> toggleAppLanguage() async {
    final next = _settings.appLanguage == AppLanguage.zh
        ? AppLanguage.en
        : AppLanguage.zh;
    _settings = _settings.copyWith(appLanguage: next);
    await _persistSettings();
    _notifyChanged();
  }
}
