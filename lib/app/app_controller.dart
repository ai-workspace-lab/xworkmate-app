import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_metadata.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/device_identity_store.dart';
import '../runtime/runtime_bootstrap.dart';
import '../runtime/desktop_platform_service.dart';
import '../runtime/gateway_runtime.dart';
import '../runtime/runtime_controllers.dart';
import '../runtime/runtime_models.dart';
import '../runtime/secure_config_store.dart';
import '../runtime/runtime_coordinator.dart';
import '../runtime/codex_runtime.dart';
import '../runtime/codex_config_bridge.dart';
import '../runtime/code_agent_node_orchestrator.dart';
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/multi_agent_broker.dart';
import '../runtime/multi_agent_mounts.dart';
import '../runtime/multi_agent_orchestrator.dart';

enum CodexCooperationState { notStarted, bridgeOnly, registered }

class AppController extends ChangeNotifier {
  AppController({
    SecureConfigStore? store,
    RuntimeCoordinator? runtimeCoordinator,
    DesktopPlatformService? desktopPlatformService,
  }) {
    _store = store ?? SecureConfigStore();

    final resolvedRuntimeCoordinator =
        runtimeCoordinator ??
        RuntimeCoordinator(
          gateway: GatewayRuntime(
            store: _store,
            identityStore: DeviceIdentityStore(_store),
          ),
          codex: CodexRuntime(),
          configBridge: CodexConfigBridge(),
        );

    _runtimeCoordinator = resolvedRuntimeCoordinator;
    _codeAgentNodeOrchestrator = CodeAgentNodeOrchestrator(_runtimeCoordinator);
    _codeAgentBridgeRegistry = AgentRegistry(_runtimeCoordinator.gateway);
    _settingsController = SettingsController(_store);
    _agentsController = GatewayAgentsController(_runtimeCoordinator.gateway);
    _sessionsController = GatewaySessionsController(
      _runtimeCoordinator.gateway,
    );
    _chatController = GatewayChatController(_runtimeCoordinator.gateway);
    _instancesController = InstancesController(_runtimeCoordinator.gateway);
    _skillsController = SkillsController(_runtimeCoordinator.gateway);
    _connectorsController = ConnectorsController(_runtimeCoordinator.gateway);
    _modelsController = ModelsController(
      _runtimeCoordinator.gateway,
      _settingsController,
    );
    _cronJobsController = CronJobsController(_runtimeCoordinator.gateway);
    _devicesController = DevicesController(_runtimeCoordinator.gateway);
    _tasksController = DerivedTasksController();
    _desktopPlatformService =
        desktopPlatformService ?? createDesktopPlatformService();
    _multiAgentMountManager = MultiAgentMountManager();
    _multiAgentOrchestrator = MultiAgentOrchestrator(
      config: _resolveMultiAgentConfig(_settingsController.snapshot),
    );

    _attachChildListeners();
    unawaited(_initialize());
  }

  late final SecureConfigStore _store;

  late final RuntimeCoordinator _runtimeCoordinator;
  late final CodeAgentNodeOrchestrator _codeAgentNodeOrchestrator;
  late final AgentRegistry _codeAgentBridgeRegistry;
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
  late final DesktopPlatformService _desktopPlatformService;
  late final MultiAgentMountManager _multiAgentMountManager;
  late final MultiAgentOrchestrator _multiAgentOrchestrator;
  MultiAgentBrokerServer? _multiAgentBrokerServer;
  MultiAgentBrokerClient? _multiAgentBrokerClient;
  final Map<String, List<GatewayChatMessage>> _localSessionMessages =
      <String, List<GatewayChatMessage>>{};
  final Map<String, List<GatewayChatMessage>> _gatewayHistoryCache =
      <String, List<GatewayChatMessage>>{};
  final Set<String> _aiGatewayPendingSessionKeys = <String>{};
  bool _multiAgentRunPending = false;
  int _localMessageCounter = 0;

  WorkspaceDestination _destination = WorkspaceDestination.assistant;
  ThemeMode _themeMode = ThemeMode.light;
  AppSidebarState _sidebarState = AppSidebarState.expanded;
  DetailPanelData? _detailPanel;
  bool _initializing = true;
  String? _bootstrapError;
  StreamSubscription<GatewayPushEvent>? _runtimeEventsSubscription;
  bool _disposed = false;

  WorkspaceDestination get destination => _destination;
  ThemeMode get themeMode => _themeMode;
  AppSidebarState get sidebarState => _sidebarState;
  DetailPanelData? get detailPanel => _detailPanel;
  bool get initializing => _initializing;
  String? get bootstrapError => _bootstrapError;

  RuntimeCoordinator get runtimeCoordinator => _runtimeCoordinator;
  GatewayRuntime get _runtime => _runtimeCoordinator.gateway;
  GatewayRuntime get runtime => _runtime;

  /// Whether Codex bridge is enabled and configured
  bool get isCodexBridgeEnabled => _isCodexBridgeEnabled;
  bool _isCodexBridgeEnabled = false;
  bool _isCodexBridgeBusy = false;
  String? _codexBridgeError;
  String? _codexRuntimeWarning;
  String? _resolvedCodexCliPath;
  CodexCooperationState _codexCooperationState =
      CodexCooperationState.notStarted;
  SettingsController get settingsController => _settingsController;
  GatewayAgentsController get agentsController => _agentsController;
  GatewaySessionsController get sessionsController => _sessionsController;
  MultiAgentOrchestrator get multiAgentOrchestrator => _multiAgentOrchestrator;
  GatewayChatController get chatController => _chatController;
  InstancesController get instancesController => _instancesController;
  SkillsController get skillsController => _skillsController;
  ConnectorsController get connectorsController => _connectorsController;
  ModelsController get modelsController => _modelsController;
  CronJobsController get cronJobsController => _cronJobsController;
  DevicesController get devicesController => _devicesController;
  DerivedTasksController get tasksController => _tasksController;
  DesktopIntegrationState get desktopIntegration =>
      _desktopPlatformService.state;
  bool get supportsDesktopIntegration => desktopIntegration.isSupported;
  bool get desktopPlatformBusy => _desktopPlatformBusy;

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
  bool get hasStoredGatewayToken =>
      _settingsController.secureRefs.containsKey('gateway_token');
  String? get storedGatewayTokenMask =>
      _settingsController.secureRefs['gateway_token'];
  String get aiGatewayUrl => settings.aiGateway.baseUrl.trim();
  bool get hasStoredAiGatewayApiKey =>
      _settingsController.secureRefs.containsKey('ai_gateway_api_key');
  bool get isAiGatewayOnlyMode =>
      settings.assistantExecutionTarget ==
      AssistantExecutionTarget.aiGatewayOnly;
  bool get isCodexBridgeBusy => _isCodexBridgeBusy;
  String? get codexBridgeError => _codexBridgeError;
  String? get codexRuntimeWarning => _codexRuntimeWarning;
  String? get resolvedCodexCliPath => _resolvedCodexCliPath;
  bool get hasDetectedCodexCli => _resolvedCodexCliPath != null;
  String get configuredCodexCliPath => settings.codexCliPath.trim();
  CodeAgentRuntimeMode get configuredCodeAgentRuntimeMode =>
      settings.codeAgentRuntimeMode;
  CodeAgentRuntimeMode get effectiveCodeAgentRuntimeMode =>
      configuredCodeAgentRuntimeMode;
  CodexCooperationState get codexCooperationState => _codexCooperationState;
  bool get isMultiAgentRunPending => _multiAgentRunPending;
  bool _desktopPlatformBusy = false;

  bool get hasAssistantPendingRun =>
      _chatController.hasPendingRun ||
      _multiAgentRunPending ||
      _aiGatewayPendingSessionKeys.contains(currentSessionKey);

  bool get canUseAiGatewayConversation =>
      aiGatewayUrl.isNotEmpty &&
      hasStoredAiGatewayApiKey &&
      resolvedAiGatewayModel.isNotEmpty;

  List<String> get aiGatewayConversationModelChoices {
    final selected = settings.aiGateway.selectedModels
        .map((item) => item.trim())
        .where(
          (item) =>
              item.isNotEmpty &&
              settings.aiGateway.availableModels.contains(item),
        )
        .toList(growable: false);
    if (selected.isNotEmpty) {
      return selected;
    }
    final available = settings.aiGateway.availableModels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (available.isNotEmpty) {
      return available;
    }
    return const <String>[];
  }

  String get resolvedAiGatewayModel {
    final current = settings.defaultModel.trim();
    final choices = aiGatewayConversationModelChoices;
    if (choices.contains(current)) {
      return current;
    }
    if (choices.isNotEmpty) {
      return choices.first;
    }
    return '';
  }

  String get resolvedAssistantModel {
    if (isAiGatewayOnlyMode) {
      return resolvedAiGatewayModel;
    }
    final resolved = resolvedDefaultModel.trim();
    if (resolved.isNotEmpty) {
      return resolved;
    }
    return '';
  }

  String get assistantConversationOwnerLabel {
    if (!isAiGatewayOnlyMode) {
      return activeAgentName;
    }
    final model = resolvedAssistantModel;
    return model.isEmpty ? appText('AI Gateway', 'AI Gateway') : model;
  }

  String get assistantConnectionStatusLabel => isAiGatewayOnlyMode
      ? appText('仅 AI Gateway', 'AI Gateway Only')
      : connection.status.label;

  String get assistantConnectionTargetLabel {
    if (!isAiGatewayOnlyMode) {
      return connection.remoteAddress ?? appText('未连接目标', 'No target');
    }
    final model = resolvedAssistantModel;
    final host = _aiGatewayHostLabel(settings.aiGateway.baseUrl);
    if (model.isNotEmpty && host.isNotEmpty) {
      return '$model · $host';
    }
    if (model.isNotEmpty) {
      return model;
    }
    if (host.isNotEmpty) {
      return host;
    }
    return appText('AI Gateway 未配置', 'AI Gateway not configured');
  }

  Future<String> loadAiGatewayApiKey() async {
    return (await _store.loadAiGatewayApiKey())?.trim() ?? '';
  }

  Future<void> saveMultiAgentConfig(MultiAgentConfig config) async {
    final resolved = _resolveMultiAgentConfig(
      settings.copyWith(multiAgent: config),
    );
    await saveSettings(
      settings.copyWith(multiAgent: resolved),
      refreshAfterSave: false,
    );
    await refreshMultiAgentMounts(sync: resolved.autoSync);
  }

  Future<void> refreshMultiAgentMounts({bool sync = false}) async {
    final resolved = _resolveMultiAgentConfig(settings);
    final reconciled = await _multiAgentMountManager.reconcile(
      config: sync ? resolved : resolved.copyWith(autoSync: false),
      aiGatewayUrl: aiGatewayUrl,
    );
    if (jsonEncode(reconciled.toJson()) !=
        jsonEncode(settings.multiAgent.toJson())) {
      await _settingsController.saveSnapshot(
        settings.copyWith(multiAgent: reconciled),
      );
    }
    _multiAgentOrchestrator.updateConfig(reconciled);
    _notifyIfActive();
  }

  Future<void> runMultiAgentCollaboration({
    required String rawPrompt,
    required String composedPrompt,
    required List<CollaborationAttachment> attachments,
    required List<String> selectedSkillLabels,
  }) async {
    final sessionKey = currentSessionKey.trim().isEmpty
        ? 'main'
        : currentSessionKey;
    final client = await _ensureMultiAgentBrokerClient();
    final aiGatewayApiKey = await loadAiGatewayApiKey();
    _multiAgentRunPending = true;
    _appendLocalSessionMessage(
      sessionKey,
      GatewayChatMessage(
        id: _nextLocalMessageId(),
        role: 'user',
        text: rawPrompt,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        toolCallId: null,
        toolName: null,
        stopReason: null,
        pending: false,
        error: false,
      ),
    );
    _recomputeTasks();
    try {
      await for (final event in client.runTask(
        taskPrompt: composedPrompt,
        workingDirectory:
            _resolveCodexWorkingDirectory() ?? Directory.current.path,
        attachments: attachments,
        selectedSkills: selectedSkillLabels,
        aiGatewayBaseUrl: aiGatewayUrl,
        aiGatewayApiKey: aiGatewayApiKey,
      )) {
        if (event.type == 'result') {
          final success = event.data['success'] == true;
          final finalScore = event.data['finalScore'];
          final iterations = event.data['iterations'];
          _appendLocalSessionMessage(
            sessionKey,
            GatewayChatMessage(
              id: _nextLocalMessageId(),
              role: 'assistant',
              text: success
                  ? appText(
                      '多 Agent 协作完成，评分 ${finalScore ?? '-'}，迭代 ${iterations ?? 0} 次。',
                      'Multi-agent collaboration completed with score ${finalScore ?? '-'} after ${iterations ?? 0} iteration(s).',
                    )
                  : appText(
                      '多 Agent 协作失败：${event.data['error'] ?? event.message}',
                      'Multi-agent collaboration failed: ${event.data['error'] ?? event.message}',
                    ),
              timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
              toolCallId: null,
              toolName: null,
              stopReason: null,
              pending: false,
              error: !success,
            ),
          );
          continue;
        }
        _appendLocalSessionMessage(
          sessionKey,
          GatewayChatMessage(
            id: _nextLocalMessageId(),
            role: 'assistant',
            text: event.message,
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: event.title,
            stopReason: null,
            pending: event.pending,
            error: event.error,
          ),
        );
      }
    } catch (error) {
      _appendLocalSessionMessage(
        sessionKey,
        GatewayChatMessage(
          id: _nextLocalMessageId(),
          role: 'assistant',
          text: error.toString(),
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: 'Multi-Agent',
          stopReason: null,
          pending: false,
          error: true,
        ),
      );
    } finally {
      _multiAgentRunPending = false;
      _recomputeTasks();
      _notifyIfActive();
    }
  }

  Future<void> openOnlineWorkspace() async {
    const url = 'https://www.svc.plus/Xworkmate';
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
        return;
      }
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
        return;
      }
      if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {
      // Best effort only. Do not surface a blocking error from a convenience link.
    }
  }

  List<String> get aiGatewayModelChoices {
    return aiGatewayConversationModelChoices;
  }

  List<String> get connectedGatewayModelChoices {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return const <String>[];
    }
    return _modelsController.items
        .map((item) => item.id.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<String> get assistantModelChoices {
    if (isAiGatewayOnlyMode) {
      return aiGatewayConversationModelChoices;
    }
    final runtimeModels = connectedGatewayModelChoices;
    if (runtimeModels.isNotEmpty) {
      return runtimeModels;
    }
    final resolved = resolvedDefaultModel.trim();
    if (resolved.isNotEmpty) {
      return <String>[resolved];
    }
    final localDefault = settings.ollamaLocal.defaultModel.trim();
    if (localDefault.isNotEmpty) {
      return <String>[localDefault];
    }
    return const <String>[];
  }

  String get resolvedDefaultModel {
    final current = settings.defaultModel.trim();
    if (current.isNotEmpty) {
      return current;
    }
    final localDefault = settings.ollamaLocal.defaultModel.trim();
    if (localDefault.isNotEmpty) {
      return localDefault;
    }
    final runtimeModels = connectedGatewayModelChoices;
    if (runtimeModels.isNotEmpty) {
      return runtimeModels.first;
    }
    final aiGatewayChoices = aiGatewayConversationModelChoices;
    if (aiGatewayChoices.isNotEmpty) {
      return aiGatewayChoices.first;
    }
    return '';
  }

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
  List<RuntimeLogEntry> get runtimeLogs => _runtime.logs;
  List<WorkspaceDestination> get assistantNavigationDestinations =>
      normalizeAssistantNavigationDestinations(
        settings.assistantNavigationDestinations,
      );

  List<GatewayChatMessage> get chatMessages {
    final sessionKey = _normalizedAssistantSessionKey(
      _sessionsController.currentSessionKey,
    );
    final items = List<GatewayChatMessage>.from(
      isAiGatewayOnlyMode
          ? (_gatewayHistoryCache[sessionKey] ?? const <GatewayChatMessage>[])
          : _chatController.messages,
    );
    final localItems = _localSessionMessages[sessionKey];
    if (localItems != null && localItems.isNotEmpty) {
      items.addAll(localItems);
    }
    final streaming = isAiGatewayOnlyMode
        ? ''
        : (_chatController.streamingAssistantText?.trim() ?? '');
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

  String _normalizedAssistantSessionKey(String sessionKey) {
    final trimmed = sessionKey.trim();
    return trimmed.isEmpty ? 'main' : trimmed;
  }

  void navigateTo(WorkspaceDestination destination) {
    if (_destination == destination) {
      return;
    }
    _destination = destination;
    _detailPanel = null;
    notifyListeners();
  }

  void navigateHome() {
    final mainSessionKey =
        _runtime.snapshot.mainSessionKey?.trim().isNotEmpty == true
        ? _runtime.snapshot.mainSessionKey!.trim()
        : 'main';
    final destinationChanged = _destination != WorkspaceDestination.assistant;
    final detailChanged = _detailPanel != null;
    _destination = WorkspaceDestination.assistant;
    _detailPanel = null;
    if (destinationChanged || detailChanged) {
      notifyListeners();
    }
    if (_sessionsController.currentSessionKey != mainSessionKey) {
      unawaited(switchSession(mainSessionKey));
    }
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
      settings.copyWith(
        gateway: nextProfile,
        assistantExecutionTarget: _assistantExecutionTargetForMode(
          nextProfile.mode,
        ),
      ),
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
      settings.copyWith(
        gateway: nextProfile,
        assistantExecutionTarget: _assistantExecutionTargetForMode(
          nextProfile.mode,
        ),
      ),
      refreshAfterSave: false,
    );
    await _connectProfile(
      nextProfile,
      authTokenOverride: token.trim(),
      authPasswordOverride: password.trim(),
    );
  }

  Future<void> disconnectGateway() async {
    _clearCodexGatewayRegistration();
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

  Future<void> clearStoredGatewayToken() async {
    await _settingsController.clearGatewaySecrets(token: true);
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
    if (isAiGatewayOnlyMode) {
      await _sendAiGatewayMessage(
        message,
        thinking: thinking,
        attachments: attachments,
      );
      _recomputeTasks();
      return;
    }
    final dispatch = _codeAgentNodeOrchestrator.buildGatewayDispatch(
      _buildCodeAgentNodeState(),
    );
    await _chatController.sendMessage(
      sessionKey: _sessionsController.currentSessionKey,
      message: message,
      thinking: thinking,
      attachments: attachments,
      agentId: dispatch.agentId,
      metadata: dispatch.metadata,
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
    if (target == AssistantExecutionTarget.aiGatewayOnly) {
      _preserveGatewayHistoryForSession(_sessionsController.currentSessionKey);
      final nextGatewayProfile = settings.gateway.copyWith(
        mode: RuntimeConnectionMode.unconfigured,
        useSetupCode: false,
        setupCode: '',
      );
      await saveSettings(
        settings.copyWith(
          assistantExecutionTarget: target,
          gateway: nextGatewayProfile,
        ),
        refreshAfterSave: false,
      );
      if (_runtime.isConnected) {
        try {
          await disconnectGateway();
        } catch (_) {
          // Preserve the selected AI Gateway-only mode even if the active
          // gateway session does not close cleanly on the first attempt.
        }
      }
      return;
    }

    await saveSettings(
      settings.copyWith(assistantExecutionTarget: target),
      refreshAfterSave: false,
    );
    final targetProfile = _gatewayProfileForAssistantExecutionTarget(target);
    try {
      await _connectProfile(targetProfile);
    } catch (_) {
      // Keep the selected execution target even when the immediate reconnect
      // fails so the user can retry or adjust gateway settings manually.
    }
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

  Future<void> selectDefaultModel(String modelId) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty || settings.defaultModel == trimmed) {
      return;
    }
    await saveSettings(
      settings.copyWith(defaultModel: trimmed),
      refreshAfterSave: false,
    );
  }

  Future<void> selectAssistantModel(String modelId) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final choices = assistantModelChoices;
    if (choices.isNotEmpty && !choices.contains(trimmed)) {
      return;
    }
    await selectDefaultModel(trimmed);
  }

  String assistantCustomTaskTitle(String sessionKey) {
    return settings.assistantCustomTaskTitles[sessionKey]?.trim() ?? '';
  }

  Future<void> saveAssistantTaskTitle(String sessionKey, String title) async {
    final normalizedSessionKey = sessionKey.trim();
    if (normalizedSessionKey.isEmpty) {
      return;
    }
    final normalizedTitle = title.trim();
    final next = Map<String, String>.from(settings.assistantCustomTaskTitles);
    final current = next[normalizedSessionKey]?.trim() ?? '';
    if (normalizedTitle.isEmpty) {
      if (current.isEmpty) {
        return;
      }
      next.remove(normalizedSessionKey);
    } else {
      if (current == normalizedTitle) {
        return;
      }
      next[normalizedSessionKey] = normalizedTitle;
    }
    await saveSettings(
      settings.copyWith(assistantCustomTaskTitles: next),
      refreshAfterSave: false,
    );
  }

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
    await saveSettings(
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

  Future<void> saveSettings(
    SettingsSnapshot snapshot, {
    bool refreshAfterSave = true,
  }) async {
    final current = settings;
    final sanitized = _sanitizeMultiAgentSettings(
      _sanitizeCodeAgentSettings(snapshot),
    );
    setActiveAppLanguage(sanitized.appLanguage);
    await _settingsController.saveSnapshot(sanitized);
    _multiAgentOrchestrator.updateConfig(sanitized.multiAgent);
    _agentsController.restoreSelection(sanitized.gateway.selectedAgentId);
    _modelsController.restoreFromSettings(sanitized.aiGateway);
    if (current.codexCliPath != sanitized.codexCliPath ||
        current.codeAgentRuntimeMode != sanitized.codeAgentRuntimeMode) {
      _registerCodexExternalProvider(codexPath: sanitized.codexCliPath);
      await _refreshCodexCliAvailability();
    }
    if (current.linuxDesktop.toJson().toString() !=
            sanitized.linuxDesktop.toJson().toString() ||
        current.launchAtLogin != sanitized.launchAtLogin) {
      await _desktopPlatformService.syncConfig(sanitized.linuxDesktop);
      await _desktopPlatformService.setLaunchAtLogin(sanitized.launchAtLogin);
    }
    if (refreshAfterSave) {
      _recomputeTasks();
    }
    unawaited(refreshMultiAgentMounts(sync: sanitized.multiAgent.autoSync));
    notifyListeners();
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
    await saveSettings(settings.copyWith(linuxDesktop: config));
  }

  Future<void> setDesktopVpnMode(VpnMode mode) async {
    _desktopPlatformBusy = true;
    notifyListeners();
    try {
      await saveSettings(
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
    await saveSettings(
      settings.copyWith(launchAtLogin: enabled),
      refreshAfterSave: false,
    );
  }

  Future<void> toggleAssistantNavigationDestination(
    WorkspaceDestination destination,
  ) async {
    if (!kAssistantNavigationDestinationCandidates.contains(destination)) {
      return;
    }
    final current = assistantNavigationDestinations;
    final next = current.contains(destination)
        ? current.where((item) => item != destination).toList(growable: false)
        : <WorkspaceDestination>[...current, destination];
    await saveSettings(
      settings.copyWith(assistantNavigationDestinations: next),
      refreshAfterSave: false,
    );
  }

  Future<String> testOllamaConnection({required bool cloud}) {
    return _settingsController.testOllamaConnection(cloud: cloud);
  }

  Future<String> testVaultConnection() {
    return _settingsController.testVaultConnection();
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

    _isCodexBridgeBusy = true;
    _codexBridgeError = null;

    try {
      final gatewayUrl = aiGatewayUrl;
      final apiKey = await loadAiGatewayApiKey();

      if (gatewayUrl.isEmpty) {
        throw StateError(
          appText('AI Gateway URL 未配置', 'AI Gateway URL not configured'),
        );
      }

      final runtimeMode = effectiveCodeAgentRuntimeMode;
      String? codexPath;
      if (runtimeMode == CodeAgentRuntimeMode.externalCli) {
        codexPath = await _resolveCodexCliPath();
        if (codexPath == null) {
          throw StateError(
            appText(
              '未找到 Codex CLI。请先安装或填写可执行文件路径。',
              'Codex CLI not found. Install it or set a manual binary path.',
            ),
          );
        }
      }

      await _runtimeCoordinator.configureCodexForGateway(
        gatewayUrl: gatewayUrl,
        apiKey: apiKey,
      );

      await _runtimeCoordinator.startCodeAgentRuntime(
        runtimeMode: runtimeMode,
        codexPath: codexPath,
        workingDirectory: _resolveCodexWorkingDirectory(),
      );

      _registerCodexExternalProvider(codexPath: codexPath);
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
      await _runtimeCoordinator.stopCodeAgentRuntime();
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

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _runtimeEventsSubscription?.cancel();
    _detachChildListeners();
    _runtimeCoordinator.dispose();
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
    _store.dispose();
    _desktopPlatformService.dispose();
    unawaited(_multiAgentBrokerServer?.stop() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _settingsController.initialize();
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
      final normalized = _sanitizeMultiAgentSettings(
        _sanitizeCodeAgentSettings(_settingsController.snapshot),
      );
      if (normalized.toJsonString() !=
          _settingsController.snapshot.toJsonString()) {
        await _settingsController.saveSnapshot(normalized);
        if (_disposed) {
          return;
        }
      }
      _modelsController.restoreFromSettings(settings.aiGateway);
      _multiAgentOrchestrator.updateConfig(settings.multiAgent);
      setActiveAppLanguage(settings.appLanguage);
      await _desktopPlatformService.initialize(settings.linuxDesktop);
      await _desktopPlatformService.setLaunchAtLogin(settings.launchAtLogin);
      _registerCodexExternalProvider();
      await _refreshCodexCliAvailability();
      if (_disposed) {
        return;
      }
      _agentsController.restoreSelection(settings.gateway.selectedAgentId);
      _sessionsController.configure(
        mainSessionKey: _runtime.snapshot.mainSessionKey ?? 'main',
        selectedAgentId: _agentsController.selectedAgentId,
        defaultAgentId: '',
      );
      _runtimeEventsSubscription = _runtimeCoordinator.gateway.events.listen(
        _handleRuntimeEvent,
      );
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
      await refreshMultiAgentMounts(sync: settings.multiAgent.autoSync);
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
    await _ensureCodexGatewayRegistration();
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

  SettingsSnapshot _sanitizeMultiAgentSettings(SettingsSnapshot snapshot) {
    final resolved = _resolveMultiAgentConfig(snapshot);
    if (jsonEncode(snapshot.multiAgent.toJson()) ==
        jsonEncode(resolved.toJson())) {
      return snapshot;
    }
    return snapshot.copyWith(multiAgent: resolved);
  }

  MultiAgentConfig _resolveMultiAgentConfig(SettingsSnapshot snapshot) {
    final defaults = MultiAgentConfig.defaults();
    final current = snapshot.multiAgent;
    final ollamaEndpoint = snapshot.ollamaLocal.endpoint.trim().isEmpty
        ? current.ollamaEndpoint
        : snapshot.ollamaLocal.endpoint.trim();
    final engineerModel = current.engineer.model.trim().isNotEmpty
        ? current.engineer.model.trim()
        : snapshot.ollamaLocal.defaultModel.trim().isNotEmpty
        ? snapshot.ollamaLocal.defaultModel.trim()
        : defaults.engineer.model;
    final architectModel = current.architect.model.trim().isNotEmpty
        ? current.architect.model.trim()
        : defaults.architect.model;
    final testerModel = current.tester.model.trim().isNotEmpty
        ? current.tester.model.trim()
        : defaults.tester.model;
    return current.copyWith(
      ollamaEndpoint: ollamaEndpoint,
      architect: current.architect.copyWith(model: architectModel),
      engineer: current.engineer.copyWith(model: engineerModel),
      tester: current.tester.copyWith(model: testerModel),
      mountTargets: current.mountTargets.isEmpty
          ? MultiAgentConfig.defaults().mountTargets
          : current.mountTargets,
    );
  }

  Future<MultiAgentBrokerClient> _ensureMultiAgentBrokerClient() async {
    _multiAgentBrokerServer ??= MultiAgentBrokerServer(_multiAgentOrchestrator);
    await _multiAgentBrokerServer!.start();
    final uri = _multiAgentBrokerServer!.wsUri;
    if (uri == null) {
      throw StateError('Multi-agent broker is unavailable');
    }
    _multiAgentBrokerClient = MultiAgentBrokerClient(uri);
    return _multiAgentBrokerClient!;
  }

  Future<void> _sendAiGatewayMessage(
    String message, {
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
  }) async {
    final sessionKey = _sessionsController.currentSessionKey.trim().isEmpty
        ? 'main'
        : _sessionsController.currentSessionKey.trim();
    final trimmed = message.trim();
    if (trimmed.isEmpty && attachments.isEmpty) {
      return;
    }

    final baseUrl = _normalizeAiGatewayBaseUrl(settings.aiGateway.baseUrl);
    if (baseUrl == null) {
      _appendLocalSessionMessage(
        sessionKey,
        _assistantErrorMessage(
          appText(
            'AI Gateway URL 未配置，无法发送对话。',
            'AI Gateway URL is not configured, so the conversation could not be sent.',
          ),
        ),
      );
      return;
    }

    final apiKey = await loadAiGatewayApiKey();
    if (apiKey.isEmpty) {
      _appendLocalSessionMessage(
        sessionKey,
        _assistantErrorMessage(
          appText(
            'AI Gateway API Key 未配置，无法发送对话。',
            'AI Gateway API key is not configured, so the conversation could not be sent.',
          ),
        ),
      );
      return;
    }

    final model = resolvedAiGatewayModel;
    if (model.isEmpty) {
      _appendLocalSessionMessage(
        sessionKey,
        _assistantErrorMessage(
          appText(
            '当前没有可用的 AI Gateway 对话模型。请先在 AI Gateway 页面同步并选择可用模型。',
            'No AI Gateway chat model is available yet. Sync and select a supported model in AI Gateway first.',
          ),
        ),
      );
      return;
    }

    final userText = trimmed.isEmpty ? 'See attached.' : trimmed;
    _appendLocalSessionMessage(
      sessionKey,
      GatewayChatMessage(
        id: _nextLocalMessageId(),
        role: 'user',
        text: userText,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        toolCallId: null,
        toolName: null,
        stopReason: null,
        pending: false,
        error: false,
      ),
    );
    _aiGatewayPendingSessionKeys.add(sessionKey);
    _recomputeTasks();
    _notifyIfActive();

    try {
      final assistantText = await _requestAiGatewayCompletion(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        thinking: thinking,
        sessionKey: sessionKey,
      );
      _appendLocalSessionMessage(
        sessionKey,
        GatewayChatMessage(
          id: _nextLocalMessageId(),
          role: 'assistant',
          text: assistantText,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      );
    } catch (error) {
      _appendLocalSessionMessage(
        sessionKey,
        _assistantErrorMessage(_aiGatewayErrorLabel(error)),
      );
    } finally {
      _aiGatewayPendingSessionKeys.remove(sessionKey);
      _recomputeTasks();
      _notifyIfActive();
    }
  }

  Future<String> _requestAiGatewayCompletion({
    required Uri baseUrl,
    required String apiKey,
    required String model,
    required String thinking,
    required String sessionKey,
  }) async {
    final uri = _aiGatewayChatUri(baseUrl);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set('x-api-key', apiKey);
      final payload = <String, dynamic>{
        'model': model,
        'stream': false,
        'messages': _buildAiGatewayRequestMessages(sessionKey),
      };
      final normalizedThinking = thinking.trim().toLowerCase();
      if (normalizedThinking.isNotEmpty && normalizedThinking != 'off') {
        payload['reasoning_effort'] = normalizedThinking;
      }
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _AiGatewayChatException(
          _formatAiGatewayHttpError(
            response.statusCode,
            _extractAiGatewayErrorDetail(body),
          ),
        );
      }
      final decoded = jsonDecode(_extractFirstJsonDocument(body));
      final assistantText = _extractAiGatewayAssistantText(decoded);
      if (assistantText.trim().isEmpty) {
        throw const FormatException('Missing assistant content');
      }
      return assistantText.trim();
    } finally {
      client.close(force: true);
    }
  }

  List<Map<String, String>> _buildAiGatewayRequestMessages(String sessionKey) {
    final history = <GatewayChatMessage>[
      ...(_gatewayHistoryCache[sessionKey] ?? const <GatewayChatMessage>[]),
      ...(_localSessionMessages[sessionKey] ?? const <GatewayChatMessage>[]),
    ];
    return history
        .where((message) {
          final role = message.role.trim().toLowerCase();
          return (role == 'user' || role == 'assistant') &&
              (message.toolName ?? '').trim().isEmpty &&
              message.text.trim().isNotEmpty;
        })
        .map(
          (message) => <String, String>{
            'role': message.role.trim().toLowerCase() == 'assistant'
                ? 'assistant'
                : 'user',
            'content': message.text.trim(),
          },
        )
        .toList(growable: false);
  }

  GatewayChatMessage _assistantErrorMessage(String text) {
    return GatewayChatMessage(
      id: _nextLocalMessageId(),
      role: 'assistant',
      text: text,
      timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      toolCallId: null,
      toolName: null,
      stopReason: null,
      pending: false,
      error: true,
    );
  }

  void _appendLocalSessionMessage(
    String sessionKey,
    GatewayChatMessage message,
  ) {
    final key = sessionKey.trim().isEmpty ? 'main' : sessionKey.trim();
    final next = List<GatewayChatMessage>.from(
      _localSessionMessages[key] ?? const <GatewayChatMessage>[],
    )..add(message);
    _localSessionMessages[key] = next;
    _notifyIfActive();
  }

  void _preserveGatewayHistoryForSession(String sessionKey) {
    final key = sessionKey.trim().isEmpty ? 'main' : sessionKey.trim();
    if (_chatController.messages.isEmpty) {
      return;
    }
    _gatewayHistoryCache[key] = List<GatewayChatMessage>.from(
      _chatController.messages,
    );
  }

  String _nextLocalMessageId() {
    _localMessageCounter += 1;
    return 'local-${DateTime.now().microsecondsSinceEpoch}-$_localMessageCounter';
  }

  Uri? _normalizeAiGatewayBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    final pathSegments = uri.pathSegments.where((item) => item.isNotEmpty);
    return uri.replace(
      pathSegments: pathSegments.isEmpty ? const <String>['v1'] : pathSegments,
      query: null,
      fragment: null,
    );
  }

  Uri _aiGatewayChatUri(Uri baseUrl) {
    final pathSegments = baseUrl.pathSegments
        .where((item) => item.isNotEmpty)
        .toList(growable: true);
    if (pathSegments.isEmpty) {
      pathSegments.add('v1');
    }
    if (pathSegments.length >= 2 &&
        pathSegments[pathSegments.length - 2] == 'chat' &&
        pathSegments.last == 'completions') {
      return baseUrl.replace(query: null, fragment: null);
    }
    if (pathSegments.last == 'models') {
      pathSegments.removeLast();
    }
    if (pathSegments.last != 'chat') {
      pathSegments.add('chat');
    }
    pathSegments.add('completions');
    return baseUrl.replace(
      pathSegments: pathSegments,
      query: null,
      fragment: null,
    );
  }

  String _aiGatewayHostLabel(String raw) {
    final uri = _normalizeAiGatewayBaseUrl(raw);
    if (uri == null) {
      return '';
    }
    if (uri.hasPort) {
      return '${uri.host}:${uri.port}';
    }
    return uri.host;
  }

  String _aiGatewayErrorLabel(Object error) {
    if (error is _AiGatewayChatException) {
      return error.message;
    }
    if (error is SocketException) {
      return appText('无法连接到 AI Gateway。', 'Unable to reach the AI Gateway.');
    }
    if (error is HandshakeException) {
      return appText(
        'AI Gateway TLS 握手失败。',
        'AI Gateway TLS handshake failed.',
      );
    }
    if (error is TimeoutException) {
      return appText('AI Gateway 请求超时。', 'AI Gateway request timed out.');
    }
    if (error is FormatException) {
      return appText(
        'AI Gateway 返回了无法解析的响应。',
        'AI Gateway returned an invalid response.',
      );
    }
    return error.toString();
  }

  String _formatAiGatewayHttpError(int statusCode, String detail) {
    final base = switch (statusCode) {
      400 => appText(
        'AI Gateway 请求无效 (400)',
        'AI Gateway rejected the request (400)',
      ),
      401 => appText(
        'AI Gateway 鉴权失败 (401)',
        'AI Gateway authentication failed (401)',
      ),
      403 => appText('AI Gateway 拒绝访问 (403)', 'AI Gateway denied access (403)'),
      404 => appText(
        'AI Gateway chat 接口不存在 (404)',
        'AI Gateway chat endpoint was not found (404)',
      ),
      429 => appText(
        'AI Gateway 限流 (429)',
        'AI Gateway rate limited the request (429)',
      ),
      >= 500 => appText(
        'AI Gateway 当前不可用 ($statusCode)',
        'AI Gateway is unavailable right now ($statusCode)',
      ),
      _ => appText(
        'AI Gateway 返回状态码 $statusCode',
        'AI Gateway responded with status $statusCode',
      ),
    };
    final trimmed = detail.trim();
    return trimmed.isEmpty ? base : '$base · $trimmed';
  }

  String _extractAiGatewayErrorDetail(String body) {
    if (body.trim().isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(_extractFirstJsonDocument(body));
      final map = asMap(decoded);
      final error = asMap(map['error']);
      return (stringValue(error['message']) ??
              stringValue(map['message']) ??
              stringValue(map['detail']) ??
              '')
          .trim();
    } on FormatException {
      return '';
    }
  }

  String _extractAiGatewayAssistantText(Object? decoded) {
    final map = asMap(decoded);
    final choices = asList(map['choices']);
    if (choices.isNotEmpty) {
      final firstChoice = asMap(choices.first);
      final message = asMap(firstChoice['message']);
      final content = _extractAiGatewayContent(message['content']);
      if (content.isNotEmpty) {
        return content;
      }
    }

    final output = asList(map['output']);
    for (final item in output) {
      final entry = asMap(item);
      final content = _extractAiGatewayContent(entry['content']);
      if (content.isNotEmpty) {
        return content;
      }
    }

    final direct = _extractAiGatewayContent(map['content']);
    if (direct.isNotEmpty) {
      return direct;
    }
    return stringValue(map['output_text'])?.trim() ?? '';
  }

  String _extractAiGatewayContent(Object? content) {
    if (content is String) {
      return content.trim();
    }
    final parts = <String>[];
    for (final item in asList(content)) {
      final map = asMap(item);
      final nestedText = stringValue(map['text']);
      if (nestedText != null && nestedText.trim().isNotEmpty) {
        parts.add(nestedText.trim());
        continue;
      }
      final type = stringValue(map['type']) ?? '';
      if (type == 'output_text') {
        final text = stringValue(map['text']) ?? stringValue(map['value']);
        if (text != null && text.trim().isNotEmpty) {
          parts.add(text.trim());
        }
      }
    }
    return parts.join('\n').trim();
  }

  String _extractFirstJsonDocument(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty response body');
    }
    final start = trimmed.indexOf(RegExp(r'[\{\[]'));
    if (start < 0) {
      throw const FormatException('Missing JSON document');
    }
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < trimmed.length; index++) {
      final char = trimmed[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (char == '{' || char == '[') {
        depth += 1;
      } else if (char == '}' || char == ']') {
        depth -= 1;
        if (depth == 0) {
          return trimmed.substring(start, index + 1);
        }
      }
    }
    throw const FormatException('Unterminated JSON document');
  }

  SettingsSnapshot _sanitizeCodeAgentSettings(SettingsSnapshot snapshot) {
    _codexRuntimeWarning =
        snapshot.codeAgentRuntimeMode == CodeAgentRuntimeMode.builtIn
        ? appText(
            '内置 Codex 仍处于实验阶段；建议优先使用 External Codex CLI。',
            'Built-in Codex is still experimental; External Codex CLI is recommended.',
          )
        : null;
    final normalizedPath = snapshot.codexCliPath.trim();
    if (normalizedPath == snapshot.codexCliPath) {
      return snapshot;
    }
    return snapshot.copyWith(codexCliPath: normalizedPath);
  }

  Future<void> _refreshCodexCliAvailability() async {
    _resolvedCodexCliPath = await _runtimeCoordinator.resolveCodexPath(
      codexPath: settings.codexCliPath,
    );
    _notifyIfActive();
  }

  Future<String?> _resolveCodexCliPath() async {
    if (_resolvedCodexCliPath != null) {
      return _resolvedCodexCliPath;
    }
    await _refreshCodexCliAvailability();
    return _resolvedCodexCliPath;
  }

  String? _resolveCodexWorkingDirectory() {
    final candidate = settings.workspacePath.trim();
    if (candidate.isEmpty) {
      return null;
    }
    final directory = Directory(candidate);
    return directory.existsSync() ? directory.path : null;
  }

  void _registerCodexExternalProvider({String? codexPath}) {
    _runtimeCoordinator.registerExternalCodeAgent(
      ExternalCodeAgentProvider(
        id: 'codex',
        name: 'Codex CLI',
        command: (codexPath?.trim().isNotEmpty ?? false)
            ? codexPath!.trim()
            : 'codex',
        defaultArgs: const <String>['app-server', '--listen', 'stdio://'],
        capabilities: const <String>[
          'chat',
          'code-edit',
          'gateway-bridge',
          'memory-sync',
        ],
      ),
    );
  }

  CodeAgentNodeState _buildCodeAgentNodeState() {
    return CodeAgentNodeState(
      selectedAgentId: _agentsController.selectedAgentId,
      gatewayConnected: _runtime.isConnected,
      executionTarget: settings.assistantExecutionTarget,
      runtimeMode: effectiveCodeAgentRuntimeMode,
      bridgeEnabled: _isCodexBridgeEnabled,
      bridgeState: _codexCooperationState.name,
      preferredProviderId: 'codex',
      resolvedCodexCliPath: _resolvedCodexCliPath,
      configuredCodexCliPath: configuredCodexCliPath,
    );
  }

  GatewayMode _bridgeGatewayMode() {
    return switch (settings.gateway.mode) {
      RuntimeConnectionMode.local => GatewayMode.local,
      RuntimeConnectionMode.remote => GatewayMode.remote,
      RuntimeConnectionMode.unconfigured => GatewayMode.offline,
    };
  }

  Future<void> _ensureCodexGatewayRegistration() async {
    if (!_isCodexBridgeEnabled) {
      return;
    }

    if (!_runtime.isConnected) {
      _codexCooperationState = CodexCooperationState.bridgeOnly;
      _codeAgentBridgeRegistry.clearRegistration();
      notifyListeners();
      return;
    }

    if (_codeAgentBridgeRegistry.isRegistered) {
      _codexCooperationState = CodexCooperationState.registered;
      notifyListeners();
      return;
    }

    try {
      final dispatch = _codeAgentNodeOrchestrator.buildGatewayDispatch(
        _buildCodeAgentNodeState(),
      );
      await _codeAgentBridgeRegistry.register(
        agentType: 'code-agent-bridge',
        name: 'XWorkmate Codex Bridge',
        version: kAppVersion,
        transport: 'stdio-bridge',
        capabilities: const <AgentCapability>[
          AgentCapability(
            name: 'chat',
            description: 'Bridge external Codex CLI chat turns.',
          ),
          AgentCapability(
            name: 'code-edit',
            description: 'Bridge code editing tasks through Codex CLI.',
          ),
          AgentCapability(
            name: 'memory-sync',
            description: 'Coordinate memory sync through OpenClaw Gateway.',
          ),
        ],
        metadata: <String, dynamic>{
          ...dispatch.metadata,
          'providerId': 'codex',
          'runtimeMode': effectiveCodeAgentRuntimeMode.name,
          'gatewayMode': _bridgeGatewayMode().name,
          'binaryConfigured': (resolvedCodexCliPath ?? configuredCodexCliPath)
              .trim()
              .isNotEmpty,
          'capabilities': const <String>[
            'chat',
            'code-edit',
            'gateway-bridge',
            'memory-sync',
          ],
        },
      );
      _codexCooperationState = CodexCooperationState.registered;
      _codexBridgeError = null;
    } catch (error) {
      _codexCooperationState = CodexCooperationState.bridgeOnly;
      _codexBridgeError = error.toString();
    }

    notifyListeners();
  }

  void _clearCodexGatewayRegistration() {
    _codeAgentBridgeRegistry.clearRegistration();
    if (_isCodexBridgeEnabled) {
      _codexCooperationState = CodexCooperationState.bridgeOnly;
    } else {
      _codexCooperationState = CodexCooperationState.notStarted;
    }
    notifyListeners();
  }

  void _recomputeTasks() {
    _tasksController.recompute(
      sessions: _sessionsController.sessions,
      cronJobs: _cronJobsController.items,
      currentSessionKey: _sessionsController.currentSessionKey,
      hasPendingRun: hasAssistantPendingRun,
      activeAgentName: _agentsController.activeAgentName,
    );
  }

  void _attachChildListeners() {
    _runtimeCoordinator.addListener(_relayChildChange);
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
    _multiAgentOrchestrator.addListener(_relayChildChange);
  }

  void _detachChildListeners() {
    _runtimeCoordinator.removeListener(_relayChildChange);
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
    _multiAgentOrchestrator.removeListener(_relayChildChange);
  }

  void _relayChildChange() {
    _notifyIfActive();
  }

  void _notifyIfActive() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  RuntimeConnectionMode _modeFromHost(String host) {
    final trimmed = host.trim().toLowerCase();
    if (trimmed == '127.0.0.1' || trimmed == 'localhost') {
      return RuntimeConnectionMode.local;
    }
    return RuntimeConnectionMode.remote;
  }

  AssistantExecutionTarget _assistantExecutionTargetForMode(
    RuntimeConnectionMode mode,
  ) {
    return switch (mode) {
      RuntimeConnectionMode.unconfigured =>
        AssistantExecutionTarget.aiGatewayOnly,
      RuntimeConnectionMode.local => AssistantExecutionTarget.local,
      RuntimeConnectionMode.remote => AssistantExecutionTarget.remote,
    };
  }

  GatewayConnectionProfile _gatewayProfileForAssistantExecutionTarget(
    AssistantExecutionTarget target,
  ) {
    if (target == AssistantExecutionTarget.aiGatewayOnly) {
      return settings.gateway.copyWith(
        mode: RuntimeConnectionMode.unconfigured,
        useSetupCode: false,
        setupCode: '',
      );
    }

    final desiredMode = switch (target) {
      AssistantExecutionTarget.aiGatewayOnly =>
        RuntimeConnectionMode.unconfigured,
      AssistantExecutionTarget.local => RuntimeConnectionMode.local,
      AssistantExecutionTarget.remote => RuntimeConnectionMode.remote,
    };
    final savedProfile = settings.gateway;
    if (savedProfile.mode == desiredMode) {
      return savedProfile;
    }

    if (desiredMode == RuntimeConnectionMode.local) {
      return savedProfile.copyWith(
        mode: RuntimeConnectionMode.local,
        useSetupCode: false,
        setupCode: '',
        host: '127.0.0.1',
        port: 18789,
        tls: false,
      );
    }

    final defaults = GatewayConnectionProfile.defaults();
    final savedHost = savedProfile.host.trim().isEmpty
        ? defaults.host
        : savedProfile.host.trim();
    final savedPort = savedProfile.port <= 0
        ? defaults.port
        : savedProfile.port;
    return savedProfile.copyWith(
      mode: RuntimeConnectionMode.remote,
      useSetupCode: false,
      setupCode: '',
      host: savedHost,
      port: savedPort,
      tls: savedProfile.tls,
    );
  }
}

class _AiGatewayChatException implements Exception {
  const _AiGatewayChatException(this.message);

  final String message;

  @override
  String toString() => message;
}
