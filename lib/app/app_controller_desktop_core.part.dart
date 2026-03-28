part of 'app_controller_desktop.dart';

enum CodexCooperationState { notStarted, bridgeOnly, registered }

class _SingleAgentSkillScanRoot {
  const _SingleAgentSkillScanRoot({
    required this.path,
    required this.source,
    required this.scope,
    this.bookmark = '',
  });

  final String path;
  final String source;
  final String scope;
  final String bookmark;

  _SingleAgentSkillScanRoot copyWith({
    String? path,
    String? source,
    String? scope,
    String? bookmark,
  }) {
    return _SingleAgentSkillScanRoot(
      path: path ?? this.path,
      source: source ?? this.source,
      scope: scope ?? this.scope,
      bookmark: bookmark ?? this.bookmark,
    );
  }
}

const String _singleAgentLocalSkillsCacheRelativePath =
    'cache/single-agent-local-skills.json';
const int _singleAgentLocalSkillsCacheSchemaVersion = 4;

class AppController extends ChangeNotifier {
  static const List<_SingleAgentSkillScanRoot>
  _defaultSingleAgentGlobalSkillScanRoots = <_SingleAgentSkillScanRoot>[
    _SingleAgentSkillScanRoot(
      path: '~/.agents/skills',
      source: 'agents',
      scope: 'user',
    ),
    _SingleAgentSkillScanRoot(
      path: '~/.codex/skills',
      source: 'codex',
      scope: 'user',
    ),
    _SingleAgentSkillScanRoot(
      path: '~/.workbuddy/skills',
      source: 'workbuddy',
      scope: 'user',
    ),
  ];
  static const List<_SingleAgentSkillScanRoot>
  _defaultSingleAgentWorkspaceSkillScanRoots = <_SingleAgentSkillScanRoot>[
    _SingleAgentSkillScanRoot(
      path: 'skills',
      source: 'workspace',
      scope: 'workspace',
    ),
  ];
  AppController({
    SecureConfigStore? store,
    RuntimeCoordinator? runtimeCoordinator,
    DesktopPlatformService? desktopPlatformService,
    UiFeatureManifest? uiFeatureManifest,
    SkillDirectoryAccessService? skillDirectoryAccessService,
    List<String>? singleAgentSharedSkillScanRootOverrides,
    List<SingleAgentProvider>? availableSingleAgentProvidersOverride,
    ArisBundleRepository? arisBundleRepository,
    SingleAgentRunner? singleAgentRunner,
  }) {
    _store = store ?? SecureConfigStore();
    _uiFeatureManifest = uiFeatureManifest ?? UiFeatureManifest.fallback();
    _hostUiFeaturePlatform = Platform.isIOS || Platform.isAndroid
        ? UiFeaturePlatform.mobile
        : UiFeaturePlatform.desktop;

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
    _skillDirectoryAccessService =
        skillDirectoryAccessService ?? createSkillDirectoryAccessService();
    _singleAgentSharedSkillScanRootOverrides =
        singleAgentSharedSkillScanRootOverrides?.toList(growable: false);
    _gatewayAcpClient = GatewayAcpClient(
      endpointResolver: _resolveGatewayAcpEndpoint,
    );
    _singleAgentAppServerClient = DirectSingleAgentAppServerClient(
      endpointResolver: _resolveSingleAgentEndpoint,
    );
    _availableSingleAgentProvidersOverride =
        availableSingleAgentProvidersOverride;
    _arisBundleRepository = arisBundleRepository ?? ArisBundleRepository();
    _goCoreLocator = GoCoreLocator();
    _singleAgentRunner =
        singleAgentRunner ??
        DefaultSingleAgentRunner(appServerClient: _singleAgentAppServerClient);
    _multiAgentOrchestrator = MultiAgentOrchestrator(
      config: _resolveMultiAgentConfig(_settingsController.snapshot),
      arisBundleRepository: _arisBundleRepository,
      goCoreLocator: _goCoreLocator,
    );

    _attachChildListeners();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_persistSharedSingleAgentLocalSkillsCache());
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
    unawaited(_gatewayAcpClient.dispose());
    unawaited(_singleAgentAppServerClient.dispose());
    super.dispose();
  }

  late final SecureConfigStore _store;
  late final UiFeatureManifest _uiFeatureManifest;
  late final UiFeaturePlatform _hostUiFeaturePlatform;

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
  late final SkillDirectoryAccessService _skillDirectoryAccessService;
  late final List<String>? _singleAgentSharedSkillScanRootOverrides;
  late final GatewayAcpClient _gatewayAcpClient;
  late final DirectSingleAgentAppServerClient _singleAgentAppServerClient;
  late final List<SingleAgentProvider>? _availableSingleAgentProvidersOverride;
  late final ArisBundleRepository _arisBundleRepository;
  late final GoCoreLocator _goCoreLocator;
  late final SingleAgentRunner _singleAgentRunner;
  late final MultiAgentOrchestrator _multiAgentOrchestrator;
  Map<SingleAgentProvider, DirectSingleAgentCapabilities>
  _singleAgentCapabilitiesByProvider =
      const <SingleAgentProvider, DirectSingleAgentCapabilities>{};
  final Map<String, List<GatewayChatMessage>> _assistantThreadMessages =
      <String, List<GatewayChatMessage>>{};
  final Map<String, AssistantThreadRecord> _assistantThreadRecords =
      <String, AssistantThreadRecord>{};
  final Map<String, List<GatewayChatMessage>> _localSessionMessages =
      <String, List<GatewayChatMessage>>{};
  final Map<String, List<GatewayChatMessage>> _gatewayHistoryCache =
      <String, List<GatewayChatMessage>>{};
  final Map<String, String> _aiGatewayStreamingTextBySession =
      <String, String>{};
  final Map<String, String> _singleAgentRuntimeModelBySession =
      <String, String>{};
  final DesktopThreadArtifactService _threadArtifactService =
      DesktopThreadArtifactService();
  List<AssistantThreadSkillEntry> _singleAgentSharedImportedSkills =
      const <AssistantThreadSkillEntry>[];
  bool _singleAgentLocalSkillsHydrated = false;
  Future<void>? _singleAgentSharedSkillsRefreshInFlight;
  final Map<String, HttpClient> _aiGatewayStreamingClients =
      <String, HttpClient>{};
  final Set<String> _aiGatewayPendingSessionKeys = <String>{};
  final Set<String> _aiGatewayAbortedSessionKeys = <String>{};
  final Set<String> _singleAgentExternalCliPendingSessionKeys = <String>{};
  final Map<String, Future<void>> _assistantThreadTurnQueues =
      <String, Future<void>>{};
  bool _multiAgentRunPending = false;
  int _localMessageCounter = 0;

  WorkspaceDestination _destination = WorkspaceDestination.assistant;
  ThemeMode _themeMode = ThemeMode.light;
  AppSidebarState _sidebarState = AppSidebarState.expanded;
  ModulesTab _modulesTab = ModulesTab.nodes;
  SecretsTab _secretsTab = SecretsTab.vault;
  AiGatewayTab _aiGatewayTab = AiGatewayTab.models;
  SettingsTab _settingsTab = SettingsTab.general;
  SettingsDetailPage? _settingsDetail;
  SettingsNavigationContext? _settingsNavigationContext;
  DetailPanelData? _detailPanel;
  SettingsSnapshot _settingsDraft = SettingsSnapshot.defaults();
  SettingsSnapshot _lastAppliedSettings = SettingsSnapshot.defaults();
  final Map<String, String> _draftSecretValues = <String, String>{};
  bool _settingsDraftInitialized = false;
  bool _pendingSettingsApply = false;
  bool _pendingGatewayApply = false;
  bool _pendingAiGatewayApply = false;
  String _settingsDraftStatusMessage = '';
  bool _initializing = true;
  String? _bootstrapError;
  StreamSubscription<GatewayPushEvent>? _runtimeEventsSubscription;
  bool _disposed = false;
  String _resolvedUserHomeDirectory = resolveUserHomeDirectory();
  SettingsSnapshot _lastObservedSettingsSnapshot = SettingsSnapshot.defaults();
  Future<void> _assistantThreadPersistQueue = Future<void>.value();
  Future<void> _settingsObservationQueue = Future<void>.value();

  List<_SingleAgentSkillScanRoot> get _singleAgentSharedSkillScanRoots {
    final configuredRoots =
        (_singleAgentSharedSkillScanRootOverrides?.map(
          _singleAgentSharedSkillScanRootFromOverride,
        ))?.toList(growable: false) ??
        _defaultSingleAgentGlobalSkillScanRoots;
    final authorizedByPath = <String, AuthorizedSkillDirectory>{
      for (final directory in settings.authorizedSkillDirectories)
        normalizeAuthorizedSkillDirectoryPath(directory.path): directory,
    };
    final resolvedRoots = <_SingleAgentSkillScanRoot>[];
    final seenPaths = <String>{};
    for (final root in configuredRoots) {
      final resolvedPath = _resolveSingleAgentSkillRootPath(root.path);
      if (resolvedPath.isEmpty || !seenPaths.add(resolvedPath)) {
        continue;
      }
      final authorizedDirectory = authorizedByPath.remove(resolvedPath);
      final bookmark = authorizedDirectory?.bookmark.trim() ?? '';
      resolvedRoots.add(root.copyWith(bookmark: bookmark));
    }
    for (final directory in authorizedByPath.values) {
      resolvedRoots.add(
        _singleAgentSharedSkillScanRootFromAuthorizedDirectory(directory),
      );
    }
    return resolvedRoots;
  }

  WorkspaceDestination get destination => _destination;
  UiFeatureManifest get uiFeatureManifest => _uiFeatureManifest;
  AppCapabilities get capabilities =>
      AppCapabilities.fromFeatureAccess(featuresFor(_hostUiFeaturePlatform));
  ThemeMode get themeMode => _themeMode;
  AppSidebarState get sidebarState => _sidebarState;
  ModulesTab get modulesTab => _modulesTab;
  SecretsTab get secretsTab => _secretsTab;
  AiGatewayTab get aiGatewayTab => _aiGatewayTab;
  SettingsTab get settingsTab => _settingsTab;
  SettingsDetailPage? get settingsDetail => _settingsDetail;
  SettingsNavigationContext? get settingsNavigationContext =>
      _settingsNavigationContext;
  DetailPanelData? get detailPanel => _detailPanel;
  bool get initializing => _initializing;
  String? get bootstrapError => _bootstrapError;

  UiFeatureAccess featuresFor(UiFeaturePlatform platform) {
    final manifest = applyAppleAppStorePolicy(
      _uiFeatureManifest,
      hostPlatform: platform,
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    );
    return manifest.forPlatform(platform);
  }

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
  SettingsSnapshot get settingsDraft =>
      _settingsDraftInitialized ? _settingsDraft : settings;
  bool get supportsSkillDirectoryAuthorization =>
      _skillDirectoryAccessService.isSupported;
  List<AuthorizedSkillDirectory> get authorizedSkillDirectories =>
      settings.authorizedSkillDirectories;
  List<String> get recommendedAuthorizedSkillDirectoryPaths =>
      _defaultSingleAgentGlobalSkillScanRoots
          .map((item) => item.path)
          .toList(growable: false);
  String get userHomeDirectory => _resolvedUserHomeDirectory;
  String get settingsYamlPath => defaultUserSettingsFilePath() ?? '';
  bool get hasSettingsDraftChanges =>
      settingsDraft.toJsonString() != settings.toJsonString() ||
      _draftSecretValues.isNotEmpty;
  bool get hasPendingSettingsApply => _pendingSettingsApply;
  String get settingsDraftStatusMessage => _settingsDraftStatusMessage;
  List<GatewayAgentSummary> get agents => _agentsController.agents;
  List<GatewaySessionSummary> get sessions => isSingleAgentMode
      ? _assistantSessionSummaries()
      : _sessionsController.sessions;
  List<GatewaySessionSummary> get assistantSessions => _assistantSessions();
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
      currentAssistantExecutionTarget;
  AssistantExecutionTarget get currentAssistantExecutionTarget =>
      assistantExecutionTargetForSession(currentSessionKey);
  AssistantMessageViewMode get currentAssistantMessageViewMode =>
      assistantMessageViewModeForSession(currentSessionKey);
  AssistantPermissionLevel get assistantPermissionLevel =>
      settings.assistantPermissionLevel;
  bool get hasStoredGatewayCredential =>
      hasStoredGatewayTokenForProfile(_activeGatewayProfileIndex) ||
      hasStoredGatewayPasswordForProfile(_activeGatewayProfileIndex) ||
      _settingsController.secureRefs.containsKey(
        'gateway_device_token_operator',
      );
  bool get hasStoredGatewayToken =>
      hasStoredGatewayTokenForProfile(_activeGatewayProfileIndex);
  String? get storedGatewayTokenMask =>
      storedGatewayTokenMaskForProfile(_activeGatewayProfileIndex);
  String get aiGatewayUrl => settings.aiGateway.baseUrl.trim();
  bool get hasStoredAiGatewayApiKey =>
      _settingsController.secureRefs.containsKey('ai_gateway_api_key');
  bool get isSingleAgentMode =>
      currentAssistantExecutionTarget == AssistantExecutionTarget.singleAgent;
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
  bool get _showsSingleAgentRuntimeDebugMessages => settings.experimentalDebug;
  bool _desktopPlatformBusy = false;

  static const String _draftAiGatewayApiKeyKey = 'ai_gateway_api_key';
  static const String _draftVaultTokenKey = 'vault_token';
  static const String _draftOllamaApiKeyKey = 'ollama_cloud_api_key';

  bool get hasAssistantPendingRun =>
      assistantSessionHasPendingRun(currentSessionKey);

  bool get canUseAiGatewayConversation =>
      aiGatewayUrl.isNotEmpty &&
      hasStoredAiGatewayApiKey &&
      resolvedAiGatewayModel.isNotEmpty;

  int get _activeGatewayProfileIndex {
    final target = currentAssistantExecutionTarget;
    if (target == AssistantExecutionTarget.singleAgent) {
      return kGatewayRemoteProfileIndex;
    }
    return _gatewayProfileIndexForExecutionTarget(target);
  }

  bool hasStoredGatewayTokenForProfile(int profileIndex) =>
      _settingsController.hasStoredGatewayTokenForProfile(profileIndex);

  bool hasStoredGatewayPasswordForProfile(int profileIndex) =>
      _settingsController.hasStoredGatewayPasswordForProfile(profileIndex);

  String? storedGatewayTokenMaskForProfile(int profileIndex) =>
      _settingsController.storedGatewayTokenMaskForProfile(profileIndex);

  String? storedGatewayPasswordMaskForProfile(int profileIndex) =>
      _settingsController.storedGatewayPasswordMaskForProfile(profileIndex);

  List<SingleAgentProvider> get configuredSingleAgentProviders =>
      normalizeSingleAgentProviderList(
        (_availableSingleAgentProvidersOverride ??
                settings.availableSingleAgentProviders)
            .where((item) => item != SingleAgentProvider.auto)
            .map(settings.resolveSingleAgentProvider),
      );

  List<SingleAgentProvider> get availableSingleAgentProviders =>
      configuredSingleAgentProviders
          .where(_canUseSingleAgentProvider)
          .toList(growable: false);

  bool get hasAnyAvailableSingleAgentProvider =>
      availableSingleAgentProviders.isNotEmpty;

  bool _canUseSingleAgentProvider(SingleAgentProvider provider) {
    final override = _availableSingleAgentProvidersOverride;
    if (override != null) {
      return provider != SingleAgentProvider.auto &&
          override.contains(provider);
    }
    if (provider == SingleAgentProvider.auto) {
      return hasAnyAvailableSingleAgentProvider;
    }
    final capabilities = _singleAgentCapabilitiesByProvider[provider];
    return capabilities?.available == true &&
        capabilities!.supportsProvider(provider);
  }

  SingleAgentProvider? _resolvedSingleAgentProvider(
    SingleAgentProvider selection,
  ) {
    if (selection != SingleAgentProvider.auto) {
      final resolvedSelection = settings.resolveSingleAgentProvider(selection);
      return _canUseSingleAgentProvider(resolvedSelection)
          ? resolvedSelection
          : null;
    }
    for (final provider in configuredSingleAgentProviders) {
      if (_canUseSingleAgentProvider(provider)) {
        return provider;
      }
    }
    return null;
  }

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
    return assistantModelForSession(currentSessionKey);
  }

  String _resolvedAssistantModelForTarget(AssistantExecutionTarget target) {
    if (target == AssistantExecutionTarget.singleAgent) {
      return '';
    }
    final resolved = resolvedDefaultModel.trim();
    if (resolved.isNotEmpty) {
      return resolved;
    }
    return '';
  }

  List<AssistantThreadSkillEntry> assistantImportedSkillsForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    return _assistantThreadRecords[normalizedSessionKey]?.importedSkills ??
        const <AssistantThreadSkillEntry>[];
  }

  // Keep legacy public APIs as class members for cross-library callers.
  void navigateTo(WorkspaceDestination destination) =>
      AppControllerDesktopNavigation(this).navigateTo(destination);

  void navigateHome() => AppControllerDesktopNavigation(this).navigateHome();

  void openModules({ModulesTab tab = ModulesTab.nodes}) =>
      AppControllerDesktopNavigation(this).openModules(tab: tab);

  void openSettings({
    SettingsTab tab = SettingsTab.general,
    SettingsDetailPage? detail,
    SettingsNavigationContext? navigationContext,
  }) => AppControllerDesktopNavigation(this).openSettings(
    tab: tab,
    detail: detail,
    navigationContext: navigationContext,
  );

  void openDetail(DetailPanelData detailPanel) =>
      AppControllerDesktopNavigation(this).openDetail(detailPanel);

  Future<void> sendChatMessage(
    String message, {
    String thinking = 'off',
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    List<CollaborationAttachment> localAttachments =
        const <CollaborationAttachment>[],
    List<String> selectedSkillLabels = const <String>[],
  }) => AppControllerDesktopThreadActions(this).sendChatMessage(
    message,
    thinking: thinking,
    attachments: attachments,
    localAttachments: localAttachments,
    selectedSkillLabels: selectedSkillLabels,
  );

  Future<void> refreshMultiAgentMounts({bool sync = false}) =>
      AppControllerDesktopThreadSessions(
        this,
      ).refreshMultiAgentMounts(sync: sync);
}
