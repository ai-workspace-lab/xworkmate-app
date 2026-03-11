import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/device_identity_store.dart';
import '../runtime/runtime_bootstrap.dart';
import '../runtime/gateway_runtime.dart';
import '../runtime/runtime_controllers.dart';
import '../runtime/runtime_models.dart';
import '../runtime/secure_config_store.dart';

class AppController extends ChangeNotifier {
  AppController() {
    _runtime = GatewayRuntime(
      store: _store,
      identityStore: DeviceIdentityStore(_store),
    );
    _settingsController = SettingsController(_store);
    _agentsController = GatewayAgentsController(_runtime);
    _sessionsController = GatewaySessionsController(_runtime);
    _chatController = GatewayChatController(_runtime);
    _instancesController = InstancesController(_runtime);
    _skillsController = SkillsController(_runtime);
    _connectorsController = ConnectorsController(_runtime);
    _modelsController = ModelsController(_runtime);
    _cronJobsController = CronJobsController(_runtime);
    _devicesController = DevicesController(_runtime);
    _tasksController = DerivedTasksController();
    _attachChildListeners();
    unawaited(_initialize());
  }

  final SecureConfigStore _store = SecureConfigStore();

  late final GatewayRuntime _runtime;
  late final SettingsController _settingsController;
  late final GatewayAgentsController _agentsController;
  late final GatewaySessionsController _sessionsController;
  late final GatewayChatController _chatController;
  late final InstancesController _instancesController;
  late final SkillsController _skillsController;
  late final ConnectorsController _connectorsController;
  late final ModelsController _modelsController;
  late final CronJobsController _cronJobsController;
  late final DevicesController _devicesController;
  late final DerivedTasksController _tasksController;

  WorkspaceDestination _destination = WorkspaceDestination.assistant;
  ThemeMode _themeMode = ThemeMode.light;
  AppSidebarState _sidebarState = AppSidebarState.expanded;
  DetailPanelData? _detailPanel;
  bool _initializing = true;
  String? _bootstrapError;
  StreamSubscription<GatewayPushEvent>? _runtimeEventsSubscription;

  WorkspaceDestination get destination => _destination;
  ThemeMode get themeMode => _themeMode;
  AppSidebarState get sidebarState => _sidebarState;
  DetailPanelData? get detailPanel => _detailPanel;
  bool get initializing => _initializing;
  String? get bootstrapError => _bootstrapError;

  GatewayRuntime get runtime => _runtime;
  SettingsController get settingsController => _settingsController;
  GatewayAgentsController get agentsController => _agentsController;
  GatewaySessionsController get sessionsController => _sessionsController;
  GatewayChatController get chatController => _chatController;
  InstancesController get instancesController => _instancesController;
  SkillsController get skillsController => _skillsController;
  ConnectorsController get connectorsController => _connectorsController;
  ModelsController get modelsController => _modelsController;
  CronJobsController get cronJobsController => _cronJobsController;
  DevicesController get devicesController => _devicesController;
  DerivedTasksController get tasksController => _tasksController;

  GatewayConnectionSnapshot get connection => _runtime.snapshot;
  SettingsSnapshot get settings => _settingsController.snapshot;
  List<GatewayAgentSummary> get agents => _agentsController.agents;
  List<GatewaySessionSummary> get sessions => _sessionsController.sessions;
  List<GatewayInstanceSummary> get instances => _instancesController.items;
  List<GatewaySkillSummary> get skills => _skillsController.items;
  List<GatewayConnectorSummary> get connectors => _connectorsController.items;
  List<GatewayModelSummary> get models => _modelsController.items;
  List<GatewayCronJobSummary> get cronJobs => _cronJobsController.items;
  GatewayDevicePairingList get devices => _devicesController.items;
  String get selectedAgentId => _agentsController.selectedAgentId;
  String get activeAgentName => _agentsController.activeAgentName;
  String get currentSessionKey => _sessionsController.currentSessionKey;
  String? get activeRunId => _chatController.activeRunId;
  AppLanguage get appLanguage => settings.appLanguage;
  AssistantExecutionTarget get assistantExecutionTarget =>
      settings.assistantExecutionTarget;
  AssistantPermissionLevel get assistantPermissionLevel =>
      settings.assistantPermissionLevel;
  bool get hasStoredGatewayCredential =>
      _settingsController.secureRefs.containsKey('gateway_token') ||
      _settingsController.secureRefs.containsKey('gateway_password') ||
      _settingsController.secureRefs.containsKey(
        'gateway_device_token_operator',
      );
  bool get canQuickConnectGateway {
    final profile = settings.gateway;
    if (profile.useSetupCode && profile.setupCode.trim().isNotEmpty) {
      return true;
    }
    final host = profile.host.trim();
    if (host.isEmpty || profile.port <= 0) {
      return false;
    }
    if (profile.mode == RuntimeConnectionMode.local) {
      return true;
    }
    final defaults = GatewayConnectionProfile.defaults();
    return hasStoredGatewayCredential ||
        host != defaults.host ||
        profile.port != defaults.port ||
        profile.tls != defaults.tls ||
        profile.mode != defaults.mode;
  }

  List<SecretReferenceEntry> get secretReferences =>
      _settingsController.buildSecretReferences();
  List<SecretAuditEntry> get secretAuditTrail => _settingsController.auditTrail;

  List<GatewayChatMessage> get chatMessages {
    final items = List<GatewayChatMessage>.from(_chatController.messages);
    final streaming = _chatController.streamingAssistantText?.trim() ?? '';
    if (streaming.isNotEmpty) {
      items.add(
        GatewayChatMessage(
          id: 'streaming',
          role: 'assistant',
          text: streaming,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: true,
          error: false,
        ),
      );
    }
    return items;
  }

  void navigateTo(WorkspaceDestination destination) {
    if (_destination == destination) {
      return;
    }
    _destination = destination;
    _detailPanel = null;
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

  Future<void> connectWithSetupCode({
    required String setupCode,
    String token = '',
    String password = '',
  }) async {
    final decoded = decodeGatewaySetupCode(setupCode);
    final resolvedToken = token.trim().isNotEmpty
        ? token.trim()
        : (decoded?.token.trim() ?? '');
    final resolvedPassword = password.trim().isNotEmpty
        ? password.trim()
        : (decoded?.password.trim() ?? '');
    await _settingsController.saveGatewaySecrets(
      token: resolvedToken,
      password: resolvedPassword,
    );
    final nextProfile = settings.gateway.copyWith(
      useSetupCode: true,
      setupCode: setupCode.trim(),
      host: decoded?.host ?? settings.gateway.host,
      port: decoded?.port ?? settings.gateway.port,
      tls: decoded?.tls ?? settings.gateway.tls,
      mode: _modeFromHost(decoded?.host ?? settings.gateway.host),
    );
    await saveSettings(
      settings.copyWith(gateway: nextProfile),
      refreshAfterSave: false,
    );
    await _connectProfile(
      nextProfile,
      authTokenOverride: resolvedToken,
      authPasswordOverride: resolvedPassword,
    );
  }

  Future<void> connectManual({
    required String host,
    required int port,
    required bool tls,
    required RuntimeConnectionMode mode,
    String token = '',
    String password = '',
  }) async {
    await _settingsController.saveGatewaySecrets(
      token: token.trim(),
      password: password.trim(),
    );
    final resolvedHost =
        host.trim().isEmpty && mode == RuntimeConnectionMode.local
        ? '127.0.0.1'
        : host.trim();
    final resolvedPort = mode == RuntimeConnectionMode.local && port <= 0
        ? 18789
        : port;
    final nextProfile = settings.gateway.copyWith(
      mode: mode,
      useSetupCode: false,
      setupCode: '',
      host: resolvedHost,
      port: resolvedPort <= 0 ? 443 : resolvedPort,
      tls: mode == RuntimeConnectionMode.local ? false : tls,
    );
    await saveSettings(
      settings.copyWith(gateway: nextProfile),
      refreshAfterSave: false,
    );
    await _connectProfile(
      nextProfile,
      authTokenOverride: token.trim(),
      authPasswordOverride: password.trim(),
    );
  }

  Future<void> disconnectGateway() async {
    await _runtime.disconnect(clearDesiredProfile: false);
    await _settingsController.refreshDerivedState();
    await _agentsController.refresh();
    await _sessionsController.refresh();
    _chatController.clear();
    await _instancesController.refresh();
    await _skillsController.refresh();
    await _connectorsController.refresh();
    await _modelsController.refresh();
    await _cronJobsController.refresh();
    _devicesController.clear();
    _recomputeTasks();
  }

  Future<void> connectSavedGateway() async {
    await _connectProfile(settings.gateway);
  }

  Future<void> refreshGatewayHealth() async {
    if (!_runtime.isConnected) {
      return;
    }
    try {
      await _runtime.health();
    } catch (_) {}
    try {
      await _runtime.status();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refreshDevices({bool quiet = false}) async {
    await _devicesController.refresh(quiet: quiet);
  }

  Future<void> approveDevicePairing(String requestId) async {
    await _devicesController.approve(requestId);
    await _settingsController.refreshDerivedState();
  }

  Future<void> rejectDevicePairing(String requestId) async {
    await _devicesController.reject(requestId);
  }

  Future<void> removePairedDevice(String deviceId) async {
    await _devicesController.remove(deviceId);
    await _settingsController.refreshDerivedState();
  }

  Future<String?> rotateDeviceRoleToken({
    required String deviceId,
    required String role,
    List<String> scopes = const <String>[],
  }) async {
    final token = await _devicesController.rotateToken(
      deviceId: deviceId,
      role: role,
      scopes: scopes,
    );
    await _settingsController.refreshDerivedState();
    return token;
  }

  Future<void> revokeDeviceRoleToken({
    required String deviceId,
    required String role,
  }) async {
    await _devicesController.revokeToken(deviceId: deviceId, role: role);
    await _settingsController.refreshDerivedState();
  }

  Future<void> refreshAgents() async {
    await _agentsController.refresh();
    _sessionsController.configure(
      mainSessionKey: _runtime.snapshot.mainSessionKey ?? 'main',
      selectedAgentId: _agentsController.selectedAgentId,
      defaultAgentId: '',
    );
    _recomputeTasks();
  }

  Future<void> selectAgent(String? agentId) async {
    _agentsController.selectAgent(agentId);
    final nextProfile = settings.gateway.copyWith(
      selectedAgentId: _agentsController.selectedAgentId,
    );
    await saveSettings(
      settings.copyWith(gateway: nextProfile),
      refreshAfterSave: false,
    );
    _sessionsController.configure(
      mainSessionKey: _runtime.snapshot.mainSessionKey ?? 'main',
      selectedAgentId: _agentsController.selectedAgentId,
      defaultAgentId: '',
    );
    await _chatController.loadSession(_sessionsController.currentSessionKey);
    await _skillsController.refresh(
      agentId: _agentsController.selectedAgentId.isEmpty
          ? null
          : _agentsController.selectedAgentId,
    );
    _recomputeTasks();
  }

  Future<void> refreshSessions() async {
    _sessionsController.configure(
      mainSessionKey: _runtime.snapshot.mainSessionKey ?? 'main',
      selectedAgentId: _agentsController.selectedAgentId,
      defaultAgentId: '',
    );
    await _sessionsController.refresh();
    await _chatController.loadSession(_sessionsController.currentSessionKey);
    _recomputeTasks();
  }

  Future<void> switchSession(String sessionKey) async {
    await _sessionsController.switchSession(sessionKey);
    await _chatController.loadSession(_sessionsController.currentSessionKey);
    _recomputeTasks();
  }

  Future<void> sendChatMessage(
    String message, {
    String thinking = 'off',
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
  }) async {
    await _chatController.sendMessage(
      sessionKey: _sessionsController.currentSessionKey,
      message: message,
      thinking: thinking,
      attachments: attachments,
    );
    _recomputeTasks();
  }

  Future<void> abortRun() async {
    await _chatController.abortRun();
  }

  Future<void> setAssistantExecutionTarget(
    AssistantExecutionTarget target,
  ) async {
    if (settings.assistantExecutionTarget == target) {
      return;
    }
    await saveSettings(
      settings.copyWith(assistantExecutionTarget: target),
      refreshAfterSave: false,
    );
  }

  Future<void> setAssistantPermissionLevel(
    AssistantPermissionLevel level,
  ) async {
    if (settings.assistantPermissionLevel == level) {
      return;
    }
    await saveSettings(
      settings.copyWith(assistantPermissionLevel: level),
      refreshAfterSave: false,
    );
  }

  Future<void> saveSettings(
    SettingsSnapshot snapshot, {
    bool refreshAfterSave = true,
  }) async {
    setActiveAppLanguage(snapshot.appLanguage);
    await _settingsController.saveSnapshot(snapshot);
    _agentsController.restoreSelection(snapshot.gateway.selectedAgentId);
    if (refreshAfterSave) {
      _recomputeTasks();
    }
  }

  Future<String> testOllamaConnection({required bool cloud}) {
    return _settingsController.testOllamaConnection(cloud: cloud);
  }

  Future<String> testVaultConnection() {
    return _settingsController.testVaultConnection();
  }

  Future<ApisixYamlProfile> validateApisixYaml(ApisixYamlProfile profile) {
    return _settingsController.validateApisixYaml(profile);
  }

  List<DerivedTaskItem> taskItemsForTab(String tab) => switch (tab) {
    'Queue' => _tasksController.queue,
    'Running' => _tasksController.running,
    'History' => _tasksController.history,
    'Failed' => _tasksController.failed,
    'Scheduled' => _tasksController.scheduled,
    _ => _tasksController.queue,
  };

  @override
  void dispose() {
    _runtimeEventsSubscription?.cancel();
    _detachChildListeners();
    _runtime.dispose();
    _settingsController.dispose();
    _agentsController.dispose();
    _sessionsController.dispose();
    _chatController.dispose();
    _instancesController.dispose();
    _skillsController.dispose();
    _connectorsController.dispose();
    _modelsController.dispose();
    _cronJobsController.dispose();
    _devicesController.dispose();
    _tasksController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _settingsController.initialize();
      final bootstrap = await RuntimeBootstrapConfig.load();
      final seeded = bootstrap.mergeIntoSettings(settings);
      if (seeded.toJsonString() != settings.toJsonString()) {
        await _settingsController.saveSnapshot(seeded);
      }
      setActiveAppLanguage(settings.appLanguage);
      await _runtime.initialize();
      _agentsController.restoreSelection(settings.gateway.selectedAgentId);
      _sessionsController.configure(
        mainSessionKey: _runtime.snapshot.mainSessionKey ?? 'main',
        selectedAgentId: _agentsController.selectedAgentId,
        defaultAgentId: '',
      );
      _runtimeEventsSubscription = _runtime.events.listen(_handleRuntimeEvent);
      final shouldAutoConnect =
          settings.gateway.useSetupCode &&
          settings.gateway.setupCode.trim().isNotEmpty;
      if (shouldAutoConnect) {
        try {
          await _connectProfile(settings.gateway);
        } catch (_) {
          // Keep the shell usable when auto-connect fails.
        }
      }
    } catch (error) {
      _bootstrapError = error.toString();
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> _connectProfile(
    GatewayConnectionProfile profile, {
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    await _runtime.connectProfile(
      profile,
      authTokenOverride: authTokenOverride,
      authPasswordOverride: authPasswordOverride,
    );
    await refreshGatewayHealth();
    await refreshAgents();
    await refreshSessions();
    await _instancesController.refresh();
    await _skillsController.refresh(
      agentId: _agentsController.selectedAgentId.isEmpty
          ? null
          : _agentsController.selectedAgentId,
    );
    await _connectorsController.refresh();
    await _modelsController.refresh();
    await _cronJobsController.refresh();
    await _devicesController.refresh(quiet: true);
    await _settingsController.refreshDerivedState();
    _recomputeTasks();
  }

  void _handleRuntimeEvent(GatewayPushEvent event) {
    _chatController.handleEvent(event);
    if (event.event == 'chat') {
      final payload = asMap(event.payload);
      final state = stringValue(payload['state']);
      if (state == 'final' || state == 'aborted' || state == 'error') {
        unawaited(refreshSessions());
      }
    }
    if (event.event == 'seqGap') {
      unawaited(refreshSessions());
    }
    if (event.event == 'device.pair.requested' ||
        event.event == 'device.pair.resolved') {
      unawaited(refreshDevices(quiet: true));
    }
  }

  void _recomputeTasks() {
    _tasksController.recompute(
      sessions: _sessionsController.sessions,
      cronJobs: _cronJobsController.items,
      currentSessionKey: _sessionsController.currentSessionKey,
      hasPendingRun: _chatController.hasPendingRun,
      activeAgentName: _agentsController.activeAgentName,
    );
  }

  void _attachChildListeners() {
    _runtime.addListener(_relayChildChange);
    _settingsController.addListener(_relayChildChange);
    _agentsController.addListener(_relayChildChange);
    _sessionsController.addListener(_relayChildChange);
    _chatController.addListener(_relayChildChange);
    _instancesController.addListener(_relayChildChange);
    _skillsController.addListener(_relayChildChange);
    _connectorsController.addListener(_relayChildChange);
    _modelsController.addListener(_relayChildChange);
    _cronJobsController.addListener(_relayChildChange);
    _devicesController.addListener(_relayChildChange);
    _tasksController.addListener(_relayChildChange);
  }

  void _detachChildListeners() {
    _runtime.removeListener(_relayChildChange);
    _settingsController.removeListener(_relayChildChange);
    _agentsController.removeListener(_relayChildChange);
    _sessionsController.removeListener(_relayChildChange);
    _chatController.removeListener(_relayChildChange);
    _instancesController.removeListener(_relayChildChange);
    _skillsController.removeListener(_relayChildChange);
    _connectorsController.removeListener(_relayChildChange);
    _modelsController.removeListener(_relayChildChange);
    _cronJobsController.removeListener(_relayChildChange);
    _devicesController.removeListener(_relayChildChange);
    _tasksController.removeListener(_relayChildChange);
  }

  void _relayChildChange() {
    notifyListeners();
  }

  RuntimeConnectionMode _modeFromHost(String host) {
    final trimmed = host.trim().toLowerCase();
    if (trimmed == '127.0.0.1' || trimmed == 'localhost') {
      return RuntimeConnectionMode.local;
    }
    return RuntimeConnectionMode.remote;
  }
}
