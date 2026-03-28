part of 'app_controller_web.dart';

typedef RemoteWebSessionRepositoryBuilder =
    WebSessionRepository Function(
      WebSessionPersistenceConfig config,
      String clientId,
      String accessToken,
    );

class AppController extends ChangeNotifier {
  AppController({
    WebStore? store,
    WebAiGatewayClient? aiGatewayClient,
    WebAcpClient? acpClient,
    WebRelayGatewayClient? relayClient,
    RemoteWebSessionRepositoryBuilder? remoteSessionRepositoryBuilder,
    UiFeatureManifest? uiFeatureManifest,
  }) : _store = store ?? WebStore(),
       _uiFeatureManifest = uiFeatureManifest ?? UiFeatureManifest.fallback(),
       _aiGatewayClient = aiGatewayClient ?? const WebAiGatewayClient(),
       _acpClient = acpClient ?? const WebAcpClient(),
       _remoteSessionRepositoryBuilder =
           remoteSessionRepositoryBuilder ?? _defaultRemoteSessionRepository {
    _relayClient = relayClient ?? WebRelayGatewayClient(_store);
    _artifactProxyClient = WebArtifactProxyClient(_relayClient);
    _relayEventsSubscription = _relayClient.events.listen(_handleRelayEvent);
    unawaited(_initialize());
  }

  final WebStore _store;
  final UiFeatureManifest _uiFeatureManifest;
  final WebAiGatewayClient _aiGatewayClient;
  final WebAcpClient _acpClient;
  final RemoteWebSessionRepositoryBuilder _remoteSessionRepositoryBuilder;
  late final WebRelayGatewayClient _relayClient;
  late final WebArtifactProxyClient _artifactProxyClient;
  late final BrowserWebSessionRepository _browserSessionRepository =
      BrowserWebSessionRepository(_store);

  late final StreamSubscription<GatewayPushEvent> _relayEventsSubscription;

  SettingsSnapshot _settings = SettingsSnapshot.defaults();
  SettingsSnapshot _settingsDraft = SettingsSnapshot.defaults();
  ThemeMode _themeMode = ThemeMode.light;
  WorkspaceDestination _destination = WorkspaceDestination.assistant;
  SettingsTab _settingsTab = SettingsTab.general;
  bool _settingsDraftInitialized = false;
  bool _pendingSettingsApply = false;
  String _settingsDraftStatusMessage = '';
  final Map<String, String> _draftSecretValues = <String, String>{};
  bool _initializing = true;
  String? _bootstrapError;
  bool _relayBusy = false;
  bool _aiGatewayBusy = false;
  bool _acpBusy = false;
  bool _multiAgentRunPending = false;
  final Map<String, AssistantThreadRecord> _threadRecords =
      <String, AssistantThreadRecord>{};
  final Set<String> _pendingSessionKeys = <String>{};
  final Map<String, String> _streamingTextBySession = <String, String>{};
  final Map<String, Future<void>> _threadTurnQueues = <String, Future<void>>{};
  final Map<String, String> _singleAgentRuntimeModelBySession =
      <String, String>{};
  final WebTasksController _tasksController = WebTasksController();
  String _currentSessionKey = '';
  String? _lastAssistantError;
  String _webSessionApiTokenCache = '';
  String _webSessionClientId = '';
  String _sessionPersistenceStatusMessage = '';
  WebAcpCapabilities _acpCapabilities = const WebAcpCapabilities.empty();
  List<GatewayAgentSummary> _relayAgents = const <GatewayAgentSummary>[];
  List<GatewayInstanceSummary> _relayInstances =
      const <GatewayInstanceSummary>[];
  List<GatewayConnectorSummary> _relayConnectors =
      const <GatewayConnectorSummary>[];
  List<GatewayModelSummary> _relayModels = const <GatewayModelSummary>[];
  List<GatewayCronJobSummary> _relayCronJobs = const <GatewayCronJobSummary>[];
  late final WebSkillsController _skillsController = WebSkillsController(
    refreshVisibleSkills,
  );

  UiFeatureManifest get uiFeatureManifest => _uiFeatureManifest;
  AppCapabilities get capabilities =>
      AppCapabilities.fromFeatureAccess(featuresFor(UiFeaturePlatform.web));
  WorkspaceDestination get destination => _destination;
  SettingsTab get settingsTab => _settingsTab;
  ThemeMode get themeMode => _themeMode;
  bool get initializing => _initializing;
  String? get bootstrapError => _bootstrapError;
  SettingsSnapshot get settings => _settings;
  SettingsSnapshot get settingsDraft =>
      _settingsDraftInitialized ? _settingsDraft : _settings;
  bool get supportsSkillDirectoryAuthorization => false;
  List<AuthorizedSkillDirectory> get authorizedSkillDirectories =>
      _settings.authorizedSkillDirectories;
  List<String> get recommendedAuthorizedSkillDirectoryPaths => const <String>[
    '~/.agents/skills',
    '~/.codex/skills',
    '~/.workbuddy/skills',
  ];
  String get userHomeDirectory => '';
  String get settingsYamlPath => '';
  bool get hasSettingsDraftChanges =>
      settingsDraft.toJsonString() != _settings.toJsonString() ||
      _draftSecretValues.isNotEmpty;
  bool get hasPendingSettingsApply => _pendingSettingsApply;
  String get settingsDraftStatusMessage => _settingsDraftStatusMessage;
  AppLanguage get appLanguage => _settings.appLanguage;
  AssistantPermissionLevel get assistantPermissionLevel =>
      _settings.assistantPermissionLevel;
  List<AssistantFocusEntry> get assistantNavigationDestinations => _settings
      .assistantNavigationDestinations
      .where(supportsAssistantFocusEntry)
      .toList(growable: false);
  bool supportsAssistantFocusEntry(AssistantFocusEntry entry) {
    final destination = entry.destination;
    if (destination != null) {
      return capabilities.supportsDestination(destination);
    }
    return capabilities.supportsDestination(WorkspaceDestination.settings);
  }

  GatewayConnectionSnapshot get connection => _relayClient.snapshot;
  bool get relayBusy => _relayBusy;
  bool get aiGatewayBusy => _aiGatewayBusy;
  bool get acpBusy => _acpBusy;
  bool get isMultiAgentRunPending => _multiAgentRunPending;
  String? get lastAssistantError => _lastAssistantError;
  String get currentSessionKey => _currentSessionKey;
  WebSessionPersistenceConfig get webSessionPersistence =>
      _settings.webSessionPersistence;
  String get sessionPersistenceStatusMessage =>
      _sessionPersistenceStatusMessage;
  bool get supportsDesktopIntegration => false;
  WebTasksController get tasksController => _tasksController;
  WebSkillsController get skillsController => _skillsController;
  List<GatewayAgentSummary> get agents => _relayAgents;
  List<GatewayInstanceSummary> get instances => _relayInstances;
  List<GatewayConnectorSummary> get connectors => _relayConnectors;
  List<GatewayCronJobSummary> get cronJobs => _relayCronJobs;
  String get selectedAgentId => '';
  String get activeAgentName {
    final current = _relayAgents.where((item) => item.name.trim().isNotEmpty);
    if (current.isNotEmpty) {
      return current.first.name;
    }
    return appText('助手', 'Assistant');
  }

  bool get hasStoredGatewayToken =>
      hasStoredGatewayTokenForProfile(kGatewayRemoteProfileIndex) ||
      hasStoredGatewayTokenForProfile(kGatewayLocalProfileIndex);
  bool get hasStoredAiGatewayApiKey => storedAiGatewayApiKeyMask != null;
  String? get storedGatewayTokenMask => storedRelayTokenMask;
  String? storedRelayTokenMaskForProfile(int profileIndex) =>
      WebStore.maskValue((_relayTokenByProfile[profileIndex] ?? '').trim());
  String? storedRelayPasswordMaskForProfile(int profileIndex) =>
      WebStore.maskValue((_relayPasswordByProfile[profileIndex] ?? '').trim());
  bool hasStoredGatewayTokenForProfile(int profileIndex) =>
      ((_relayTokenByProfile[profileIndex] ?? '').trim().isNotEmpty);
  bool hasStoredGatewayPasswordForProfile(int profileIndex) =>
      ((_relayPasswordByProfile[profileIndex] ?? '').trim().isNotEmpty);
  String? get storedRelayTokenMask => WebStore.maskValue(
    (_relayTokenByProfile[kGatewayRemoteProfileIndex] ?? '').trim(),
  );
  String? get storedRelayPasswordMask => WebStore.maskValue(
    (_relayPasswordByProfile[kGatewayRemoteProfileIndex] ?? '').trim(),
  );
  String? get storedAiGatewayApiKeyMask => WebStore.maskValue(
    _aiGatewayApiKeyCache.trim().isEmpty ? '' : _aiGatewayApiKeyCache,
  );
  String? get storedWebSessionApiTokenMask => WebStore.maskValue(
    _webSessionApiTokenCache.trim().isEmpty ? '' : _webSessionApiTokenCache,
  );
  bool get usesRemoteSessionPersistence =>
      webSessionPersistence.mode == WebSessionPersistenceMode.remote &&
      RemoteWebSessionRepository.normalizeBaseUrl(
            webSessionPersistence.remoteBaseUrl,
          ) !=
          null;

  final Map<int, String> _relayTokenByProfile = <int, String>{};
  final Map<int, String> _relayPasswordByProfile = <int, String>{};
  String _aiGatewayApiKeyCache = '';

  static const String _draftAiGatewayApiKeyKey = 'ai_gateway_api_key';
  static const String _draftVaultTokenKey = 'vault_token';
  static const String _draftOllamaApiKeyKey = 'ollama_cloud_api_key';

  UiFeatureAccess featuresFor(UiFeaturePlatform platform) {
    return _uiFeatureManifest.forPlatform(platform);
  }

  WebAcpCapabilities get acpCapabilities => _acpCapabilities;

  void _notifyChanged() {
    notifyListeners();
  }

  void _recomputeDerivedWorkspaceState() {
    if (_threadRecords.isEmpty) {
      _currentSessionKey = '';
      _tasksController.recompute(
        threads: const <AssistantThreadRecord>[],
        cronJobs: _relayCronJobs,
        currentSessionKey: _currentSessionKey,
        pendingSessionKeys: _pendingSessionKeys,
      );
      return;
    }

    if (_currentSessionKey.trim().isEmpty ||
        !_threadRecords.containsKey(_currentSessionKey)) {
      final preferredSession = _settings.assistantLastSessionKey.trim();
      if (preferredSession.isNotEmpty &&
          _threadRecords.containsKey(preferredSession)) {
        _currentSessionKey = preferredSession;
      } else {
        _currentSessionKey = _threadRecords.keys.first;
      }
    }

    _tasksController.recompute(
      threads: _threadRecords.values.toList(growable: false),
      cronJobs: _relayCronJobs,
      currentSessionKey: _currentSessionKey,
      pendingSessionKeys: _pendingSessionKeys,
    );
  }

  GatewaySkillSummary _gatewaySkillFromThreadEntry(
    AssistantThreadSkillEntry skill,
  ) {
    return GatewaySkillSummary(
      name: skill.label,
      description: skill.description,
      source: skill.sourcePath.isEmpty ? skill.source : skill.sourcePath,
      skillKey: skill.key,
      primaryEnv: null,
      eligible: true,
      disabled: false,
      missingBins: const <String>[],
      missingEnv: const <String>[],
      missingConfig: const <String>[],
    );
  }

  @override
  void dispose() {
    unawaited(_relayEventsSubscription.cancel());
    unawaited(_relayClient.dispose());
    super.dispose();
  }
}
