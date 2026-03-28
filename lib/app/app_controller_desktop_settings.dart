// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

part of 'app_controller_desktop.dart';

extension AppControllerDesktopSettings on AppController {
  Future<void> saveSettingsDraft(SettingsSnapshot snapshot) async {
    if (_disposed) {
      return;
    }
    _settingsDraft = _sanitizeFeatureFlagSettings(
      _sanitizeMultiAgentSettings(
        _sanitizeOllamaCloudSettings(_sanitizeCodeAgentSettings(snapshot)),
      ),
    );
    _settingsDraftInitialized = true;
    _settingsDraftStatusMessage = appText(
      '草稿已更新，点击顶部保存持久化。',
      'Draft updated. Use the top Save button to persist it.',
    );
    notifyListeners();
  }

  void saveGatewayTokenDraft(String value, {required int profileIndex}) {
    _saveSecretDraft(_draftGatewayTokenKey(profileIndex), value);
  }

  void saveGatewayPasswordDraft(String value, {required int profileIndex}) {
    _saveSecretDraft(_draftGatewayPasswordKey(profileIndex), value);
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

  Future<void> persistSettingsDraft() async {
    if (_disposed) {
      return;
    }
    if (!hasSettingsDraftChanges) {
      _settingsDraftStatusMessage = appText(
        '没有需要保存的更改。',
        'There are no changes to save.',
      );
      notifyListeners();
      return;
    }
    final nextSettings = settingsDraft;
    _markPendingApplyDomains(settings, nextSettings);
    await _persistDraftSecrets();
    if (nextSettings.toJsonString() != settings.toJsonString()) {
      await _persistSettingsSnapshot(nextSettings);
    }
    _settingsDraft = settings;
    _settingsDraftInitialized = true;
    _pendingSettingsApply = true;
    _settingsDraftStatusMessage = appText(
      '已保存配置，不立即生效。',
      'Settings saved. They do not take effect until Apply.',
    );
    notifyListeners();
  }

  Future<void> applySettingsDraft() async {
    if (_disposed) {
      return;
    }
    if (hasSettingsDraftChanges) {
      await persistSettingsDraft();
    }
    if (!_pendingSettingsApply) {
      _settingsDraftStatusMessage = appText(
        '没有需要应用的更改。',
        'There are no saved changes to apply.',
      );
      notifyListeners();
      return;
    }
    final currentSettings = settings;
    await _applyPersistedSettingsSideEffects(
      previous: _lastAppliedSettings,
      current: currentSettings,
      refreshAfterSave: true,
    );
    if (_pendingGatewayApply) {
      await _applyPersistedGatewaySettings(currentSettings);
    }
    if (_pendingAiGatewayApply) {
      await _applyPersistedAiGatewaySettings(currentSettings);
    }
    _lastAppliedSettings = settings;
    _pendingSettingsApply = false;
    _pendingGatewayApply = false;
    _pendingAiGatewayApply = false;
    _settingsDraft = settings;
    _settingsDraftInitialized = true;
    _settingsDraftStatusMessage = appText(
      '已按当前配置生效。',
      'The current configuration is now in effect.',
    );
    notifyListeners();
  }

  Future<void> saveSettings(
    SettingsSnapshot snapshot, {
    bool refreshAfterSave = true,
  }) async {
    if (_disposed) {
      return;
    }
    final previous = settings;
    await _persistSettingsSnapshot(snapshot);
    if (_disposed) {
      return;
    }
    await _applyPersistedSettingsSideEffects(
      previous: previous,
      current: settings,
      refreshAfterSave: refreshAfterSave,
    );
    _lastAppliedSettings = settings;
    _settingsDraft = settings;
    _settingsDraftInitialized = true;
    _pendingSettingsApply = false;
    _pendingGatewayApply = false;
    _pendingAiGatewayApply = false;
    _draftSecretValues.clear();
    _settingsDraftStatusMessage = '';
  }

  Future<void> clearAssistantLocalState() async {
    await _flushAssistantThreadPersistence();
    await _store.clearAssistantLocalState();
    await _store.saveAssistantThreadRecords(const <AssistantThreadRecord>[]);
    _assistantThreadPersistQueue = Future<void>.value();
    final defaults = SettingsSnapshot.defaults();
    _assistantThreadRecords.clear();
    _assistantThreadMessages.clear();
    _localSessionMessages.clear();
    _gatewayHistoryCache.clear();
    _aiGatewayStreamingTextBySession.clear();
    _aiGatewayStreamingClients.clear();
    _aiGatewayPendingSessionKeys.clear();
    _aiGatewayAbortedSessionKeys.clear();
    _singleAgentExternalCliPendingSessionKeys.clear();
    _assistantThreadTurnQueues.clear();
    _multiAgentRunPending = false;
    setActiveAppLanguage(defaults.appLanguage);
    await _settingsController.resetSnapshot(defaults);
    _multiAgentOrchestrator.updateConfig(defaults.multiAgent);
    _agentsController.restoreSelection(
      defaults.primaryRemoteGatewayProfile.selectedAgentId,
    );
    _modelsController.restoreFromSettings(defaults.aiGateway);
    await _setCurrentAssistantSessionKey('main', persistSelection: false);
    _chatController.clear();
    _recomputeTasks();
    notifyListeners();
  }

  void _saveSecretDraft(String key, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _draftSecretValues.remove(key);
    } else {
      _draftSecretValues[key] = trimmed;
    }
    _settingsDraftStatusMessage = appText(
      '草稿已更新，点击顶部保存持久化。',
      'Draft updated. Use the top Save button to persist it.',
    );
    notifyListeners();
  }
}
