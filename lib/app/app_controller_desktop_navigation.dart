// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

part of 'app_controller_desktop.dart';

extension AppControllerDesktopNavigation on AppController {
  void navigateTo(WorkspaceDestination destination) {
    if (!capabilities.supportsDestination(destination)) {
      return;
    }
    if (destination == WorkspaceDestination.aiGateway ||
        destination == WorkspaceDestination.secrets) {
      openSettings(tab: SettingsTab.gateway);
      return;
    }
    final nextModulesTab = switch (destination) {
      WorkspaceDestination.nodes => ModulesTab.nodes,
      WorkspaceDestination.agents => ModulesTab.agents,
      _ => _modulesTab,
    };
    final shouldClearSettingsDrillIn =
        _settingsDetail != null || _settingsNavigationContext != null;
    final changed =
        _destination != destination ||
        _detailPanel != null ||
        shouldClearSettingsDrillIn ||
        nextModulesTab != _modulesTab;
    if (!changed) {
      return;
    }
    _destination = destination;
    _modulesTab = nextModulesTab;
    _settingsDetail = null;
    _settingsNavigationContext = null;
    _detailPanel = null;
    notifyListeners();
  }

  void navigateHome() {
    final mainSessionKey =
        _runtime.snapshot.mainSessionKey?.trim().isNotEmpty == true
        ? _runtime.snapshot.mainSessionKey!.trim()
        : 'main';
    final homeDestination =
        capabilities.supportsDestination(WorkspaceDestination.assistant)
        ? WorkspaceDestination.assistant
        : (capabilities.allowedDestinations.isEmpty
              ? WorkspaceDestination.assistant
              : capabilities.allowedDestinations.first);
    final destinationChanged = _destination != homeDestination;
    final detailChanged = _detailPanel != null;
    final settingsDrillInChanged =
        _settingsDetail != null || _settingsNavigationContext != null;
    _destination = homeDestination;
    _settingsDetail = null;
    _settingsNavigationContext = null;
    _detailPanel = null;
    if (destinationChanged || detailChanged || settingsDrillInChanged) {
      notifyListeners();
    }
    if (_sessionsController.currentSessionKey != mainSessionKey) {
      unawaited(switchSession(mainSessionKey));
    }
  }

  void openModules({ModulesTab tab = ModulesTab.nodes}) {
    if (tab == ModulesTab.gateway) {
      openSettings(tab: SettingsTab.gateway);
      return;
    }
    final destination = tab == ModulesTab.agents
        ? WorkspaceDestination.agents
        : WorkspaceDestination.nodes;
    if (!capabilities.supportsDestination(destination)) {
      return;
    }
    final changed =
        _destination != destination ||
        _modulesTab != tab ||
        _detailPanel != null ||
        _settingsDetail != null ||
        _settingsNavigationContext != null;
    if (!changed) {
      return;
    }
    _destination = destination;
    _modulesTab = tab;
    _detailPanel = null;
    _settingsDetail = null;
    _settingsNavigationContext = null;
    notifyListeners();
  }

  void setModulesTab(ModulesTab tab) {
    if (_modulesTab == tab) {
      return;
    }
    _modulesTab = tab;
    notifyListeners();
  }

  void openSecrets({SecretsTab tab = SecretsTab.vault}) {
    if (!capabilities.supportsDestination(WorkspaceDestination.settings)) {
      return;
    }
    _secretsTab = tab;
    openSettings(tab: SettingsTab.gateway);
  }

  void setSecretsTab(SecretsTab tab) {
    if (_secretsTab == tab) {
      return;
    }
    _secretsTab = tab;
    notifyListeners();
  }

  void openAiGateway({AiGatewayTab tab = AiGatewayTab.models}) {
    if (!capabilities.supportsDestination(WorkspaceDestination.settings)) {
      return;
    }
    _aiGatewayTab = tab;
    openSettings(tab: SettingsTab.gateway);
  }

  void setAiGatewayTab(AiGatewayTab tab) {
    if (_aiGatewayTab == tab) {
      return;
    }
    _aiGatewayTab = tab;
    notifyListeners();
  }

  void openSettings({
    SettingsTab tab = SettingsTab.general,
    SettingsDetailPage? detail,
    SettingsNavigationContext? navigationContext,
  }) {
    if (!capabilities.supportsDestination(WorkspaceDestination.settings)) {
      return;
    }
    final requestedTab = detail?.tab ?? tab;
    final resolvedTab = _sanitizeSettingsTab(requestedTab);
    final resolvedDetail = detail != null && resolvedTab == detail.tab
        ? detail
        : null;
    final changed =
        _destination != WorkspaceDestination.settings ||
        _settingsTab != resolvedTab ||
        _settingsDetail != resolvedDetail ||
        _settingsNavigationContext != navigationContext ||
        _detailPanel != null;
    if (!changed) {
      return;
    }
    _destination = WorkspaceDestination.settings;
    _settingsTab = resolvedTab;
    _settingsDetail = resolvedDetail;
    _settingsNavigationContext = resolvedDetail == null
        ? null
        : navigationContext;
    _detailPanel = null;
    notifyListeners();
  }

  void setSettingsTab(SettingsTab tab, {bool clearDetail = true}) {
    final resolvedTab = _sanitizeSettingsTab(tab);
    final changed =
        _settingsTab != resolvedTab ||
        (clearDetail &&
            (_settingsDetail != null || _settingsNavigationContext != null));
    if (!changed) {
      return;
    }
    _settingsTab = resolvedTab;
    if (clearDetail) {
      _settingsDetail = null;
      _settingsNavigationContext = null;
    }
    notifyListeners();
  }

  void closeSettingsDetail() {
    if (_settingsDetail == null && _settingsNavigationContext == null) {
      return;
    }
    _settingsDetail = null;
    _settingsNavigationContext = null;
    notifyListeners();
  }

  void cycleSidebarState() {
    _sidebarState = switch (_sidebarState) {
      AppSidebarState.expanded => AppSidebarState.collapsed,
      AppSidebarState.collapsed => AppSidebarState.hidden,
      AppSidebarState.hidden => AppSidebarState.expanded,
    };
    notifyListeners();
  }

  void setSidebarState(AppSidebarState state) {
    if (_sidebarState == state) {
      return;
    }
    _sidebarState = state;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) {
      return;
    }
    _themeMode = mode;
    notifyListeners();
  }

  Future<void> toggleAppLanguage() async {
    await setAppLanguage(
      settings.appLanguage == AppLanguage.zh ? AppLanguage.en : AppLanguage.zh,
    );
  }

  Future<void> setAppLanguage(AppLanguage language) async {
    if (settings.appLanguage == language) {
      return;
    }
    setActiveAppLanguage(language);
    await saveSettings(
      settings.copyWith(appLanguage: language),
      refreshAfterSave: false,
    );
  }

  void openDetail(DetailPanelData detailPanel) {
    _detailPanel = detailPanel;
    notifyListeners();
  }

  void closeDetail() {
    if (_detailPanel == null) {
      return;
    }
    _detailPanel = null;
    notifyListeners();
  }
}
