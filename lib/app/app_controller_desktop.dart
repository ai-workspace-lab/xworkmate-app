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
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/multi_agent_orchestrator.dart';
import '../runtime/platform_environment.dart';
import '../runtime/single_agent_runner.dart';
import '../runtime/skill_directory_access.dart';

part 'app_controller_desktop_navigation.dart';
part 'app_controller_desktop_gateway.dart';
part 'app_controller_desktop_settings.dart';
part 'app_controller_desktop_single_agent.dart';

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

  int assistantSkillCountForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) ==
        AssistantExecutionTarget.singleAgent) {
      return assistantImportedSkillsForSession(normalizedSessionKey).length;
    }
    return skills.length;
  }

  int get currentAssistantSkillCount =>
      assistantSkillCountForSession(currentSessionKey);

  List<String> assistantSelectedSkillKeysForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final importedKeys = assistantImportedSkillsForSession(
      normalizedSessionKey,
    ).map((item) => item.key).toSet();
    final selected =
        _assistantThreadRecords[normalizedSessionKey]?.selectedSkillKeys ??
        const <String>[];
    return selected
        .where((item) => importedKeys.contains(item))
        .toList(growable: false);
  }

  List<AssistantThreadSkillEntry> assistantSelectedSkillsForSession(
    String sessionKey,
  ) {
    final selectedKeys = assistantSelectedSkillKeysForSession(
      sessionKey,
    ).toSet();
    return assistantImportedSkillsForSession(
      sessionKey,
    ).where((item) => selectedKeys.contains(item.key)).toList(growable: false);
  }

  String assistantModelForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      if (singleAgentUsesAiChatFallbackForSession(normalizedSessionKey)) {
        final recordModel =
            _assistantThreadRecords[normalizedSessionKey]?.assistantModelId
                .trim() ??
            '';
        if (recordModel.isNotEmpty) {
          return recordModel;
        }
        return resolvedAiGatewayModel;
      }
      return singleAgentRuntimeModelForSession(normalizedSessionKey);
    }
    final recordModel =
        _assistantThreadRecords[normalizedSessionKey]?.assistantModelId
            .trim() ??
        '';
    if (recordModel.isNotEmpty) {
      return recordModel;
    }
    return _resolvedAssistantModelForTarget(target);
  }

  String assistantWorkspaceRefForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final recordRef =
        _assistantThreadRecords[normalizedSessionKey]?.workspaceRef.trim() ??
        '';
    if (recordRef.isNotEmpty) {
      return recordRef;
    }
    return _defaultWorkspaceRefForSession(normalizedSessionKey);
  }

  WorkspaceRefKind assistantWorkspaceRefKindForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final record = _assistantThreadRecords[normalizedSessionKey];
    if (record != null && record.workspaceRef.trim().isNotEmpty) {
      return record.workspaceRefKind;
    }
    return _defaultWorkspaceRefKindForTarget(
      assistantExecutionTargetForSession(normalizedSessionKey),
    );
  }

  Future<AssistantArtifactSnapshot> loadAssistantArtifactSnapshot({
    String? sessionKey,
  }) {
    final resolvedSessionKey = _normalizedAssistantSessionKey(
      sessionKey ?? currentSessionKey,
    );
    return _threadArtifactService.loadSnapshot(
      workspaceRef: assistantWorkspaceRefForSession(resolvedSessionKey),
      workspaceRefKind: assistantWorkspaceRefKindForSession(resolvedSessionKey),
    );
  }

  Future<AssistantArtifactPreview> loadAssistantArtifactPreview(
    AssistantArtifactEntry entry, {
    String? sessionKey,
  }) {
    final resolvedSessionKey = _normalizedAssistantSessionKey(
      sessionKey ?? currentSessionKey,
    );
    return _threadArtifactService.loadPreview(
      entry: entry,
      workspaceRef: assistantWorkspaceRefForSession(resolvedSessionKey),
      workspaceRefKind: assistantWorkspaceRefKindForSession(resolvedSessionKey),
    );
  }

  SingleAgentProvider singleAgentProviderForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final stored =
        _assistantThreadRecords[normalizedSessionKey]?.singleAgentProvider ??
        SingleAgentProvider.auto;
    return settings.resolveSingleAgentProvider(stored);
  }

  SingleAgentProvider get currentSingleAgentProvider =>
      singleAgentProviderForSession(currentSessionKey);

  SingleAgentProvider? singleAgentResolvedProviderForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    return _resolvedSingleAgentProvider(
      singleAgentProviderForSession(normalizedSessionKey),
    );
  }

  SingleAgentProvider? get currentSingleAgentResolvedProvider =>
      singleAgentResolvedProviderForSession(currentSessionKey);

  bool singleAgentUsesAiChatFallbackForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return false;
    }
    return !hasAnyAvailableSingleAgentProvider && canUseAiGatewayConversation;
  }

  bool get currentSingleAgentUsesAiChatFallback =>
      singleAgentUsesAiChatFallbackForSession(currentSessionKey);

  bool singleAgentNeedsAiGatewayConfigurationForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return false;
    }
    return !hasAnyAvailableSingleAgentProvider && !canUseAiGatewayConversation;
  }

  bool get currentSingleAgentNeedsAiGatewayConfiguration =>
      singleAgentNeedsAiGatewayConfigurationForSession(currentSessionKey);

  bool singleAgentHasResolvedProviderForSession(String sessionKey) {
    return singleAgentResolvedProviderForSession(sessionKey) != null;
  }

  bool get currentSingleAgentHasResolvedProvider =>
      singleAgentHasResolvedProviderForSession(currentSessionKey);

  bool singleAgentShouldSuggestAutoSwitchForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return false;
    }
    final selection = singleAgentProviderForSession(normalizedSessionKey);
    if (selection == SingleAgentProvider.auto) {
      return false;
    }
    return !_canUseSingleAgentProvider(selection) &&
        hasAnyAvailableSingleAgentProvider;
  }

  bool get currentSingleAgentShouldSuggestAutoSwitch =>
      singleAgentShouldSuggestAutoSwitchForSession(currentSessionKey);

  String singleAgentRuntimeModelForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    return _singleAgentRuntimeModelBySession[normalizedSessionKey]?.trim() ??
        '';
  }

  String get currentSingleAgentRuntimeModel =>
      singleAgentRuntimeModelForSession(currentSessionKey);

  String singleAgentModelDisplayLabelForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final runtimeModel = singleAgentRuntimeModelForSession(
      normalizedSessionKey,
    );
    if (runtimeModel.isNotEmpty) {
      return runtimeModel;
    }
    final model = assistantModelForSession(normalizedSessionKey);
    if (model.isNotEmpty) {
      return model;
    }
    if (singleAgentUsesAiChatFallbackForSession(normalizedSessionKey)) {
      return appText('AI Chat fallback', 'AI Chat fallback');
    }
    final provider =
        singleAgentResolvedProviderForSession(normalizedSessionKey) ??
        singleAgentProviderForSession(normalizedSessionKey);
    return appText(
      '请先配置 ${provider.label} 模型',
      'Configure ${provider.label} model',
    );
  }

  String get currentSingleAgentModelDisplayLabel =>
      singleAgentModelDisplayLabelForSession(currentSessionKey);

  bool singleAgentShouldShowModelControlForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return true;
    }
    if (singleAgentUsesAiChatFallbackForSession(normalizedSessionKey)) {
      return true;
    }
    return singleAgentRuntimeModelForSession(normalizedSessionKey).isNotEmpty;
  }

  bool get currentSingleAgentShouldShowModelControl =>
      singleAgentShouldShowModelControlForSession(currentSessionKey);

  List<SingleAgentProvider> get singleAgentProviderOptions =>
      <SingleAgentProvider>[
        SingleAgentProvider.auto,
        ...configuredSingleAgentProviders,
      ];

  String singleAgentProviderLabelForSession(String sessionKey) {
    return singleAgentProviderForSession(sessionKey).label;
  }

  String get assistantConversationOwnerLabel {
    if (!isSingleAgentMode) {
      return activeAgentName;
    }
    final resolvedProvider = currentSingleAgentResolvedProvider;
    if (resolvedProvider != null) {
      return resolvedProvider.label;
    }
    final provider = currentSingleAgentProvider;
    if (provider != SingleAgentProvider.auto) {
      return provider.label;
    }
    if (currentSingleAgentUsesAiChatFallback) {
      return appText('AI Chat fallback', 'AI Chat fallback');
    }
    return appText('单机智能体', 'Single Agent');
  }

  AssistantThreadConnectionState get currentAssistantConnectionState =>
      assistantConnectionStateForSession(currentSessionKey);

  AssistantThreadConnectionState assistantConnectionStateForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      final provider = singleAgentProviderForSession(normalizedSessionKey);
      final resolvedProvider = singleAgentResolvedProviderForSession(
        normalizedSessionKey,
      );
      final model = assistantModelForSession(normalizedSessionKey);
      final fallbackReady = singleAgentUsesAiChatFallbackForSession(
        normalizedSessionKey,
      );
      final host = _aiGatewayHostLabel(settings.aiGateway.baseUrl);
      final providerReady = resolvedProvider != null;
      final detail = providerReady
          ? _joinConnectionParts(<String>[resolvedProvider.label, model])
          : fallbackReady
          ? _joinConnectionParts(<String>[
              appText('AI Chat fallback', 'AI Chat fallback'),
              model,
              host,
            ])
          : singleAgentShouldSuggestAutoSwitchForSession(normalizedSessionKey)
          ? appText(
              '${provider.label} 不可用，可切到 Auto',
              '${provider.label} is unavailable. Switch to Auto.',
            )
          : singleAgentNeedsAiGatewayConfigurationForSession(
              normalizedSessionKey,
            )
          ? appText(
              '没有可用的外部 Agent ACP 端点，请配置 LLM API fallback。',
              'No external Agent ACP endpoint is available. Configure LLM API fallback.',
            )
          : appText(
              '当前线程的外部 Agent ACP 连接尚未就绪。',
              'The external Agent ACP connection for this thread is not ready yet.',
            );
      return AssistantThreadConnectionState(
        executionTarget: target,
        status: providerReady || fallbackReady
            ? RuntimeConnectionStatus.connected
            : RuntimeConnectionStatus.offline,
        primaryLabel: target.label,
        detailLabel: detail.isEmpty
            ? appText('未配置单机智能体', 'Single Agent is not configured')
            : detail,
        ready: providerReady || fallbackReady,
        pairingRequired: false,
        gatewayTokenMissing: false,
        lastError: null,
      );
    }

    final expectedMode = target == AssistantExecutionTarget.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    final matchesTarget = connection.mode == expectedMode;
    final fallbackProfile = _gatewayProfileForAssistantExecutionTarget(target);
    final fallbackAddress = _gatewayAddressLabel(fallbackProfile);
    final detail = matchesTarget
        ? (connection.remoteAddress?.trim().isNotEmpty == true
              ? connection.remoteAddress!.trim()
              : fallbackAddress)
        : fallbackAddress;
    final status = matchesTarget
        ? connection.status
        : RuntimeConnectionStatus.offline;
    return AssistantThreadConnectionState(
      executionTarget: target,
      status: status,
      primaryLabel: status.label,
      detailLabel: detail,
      ready: status == RuntimeConnectionStatus.connected,
      pairingRequired: matchesTarget && connection.pairingRequired,
      gatewayTokenMissing: matchesTarget && connection.gatewayTokenMissing,
      lastError: matchesTarget ? connection.lastError?.trim() : null,
    );
  }

  String get assistantConnectionStatusLabel =>
      currentAssistantConnectionState.primaryLabel;

  String get assistantConnectionTargetLabel {
    return currentAssistantConnectionState.detailLabel;
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
    await _refreshAcpCapabilities(persistMountTargets: true);
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
    await _enqueueThreadTurn<void>(sessionKey, () async {
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
        final taskStream = _gatewayAcpClient.runMultiAgent(
          GatewayAcpMultiAgentRequest(
            sessionId: sessionKey,
            threadId: sessionKey,
            prompt: composedPrompt,
            workingDirectory:
                _assistantWorkingDirectoryForSession(sessionKey) ??
                Directory.current.path,
            attachments: attachments,
            selectedSkills: selectedSkillLabels,
            aiGatewayBaseUrl: aiGatewayUrl,
            aiGatewayApiKey: aiGatewayApiKey,
            resumeSession: true,
          ),
        );
        await for (final event in taskStream) {
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
      } on GatewayAcpException catch (error) {
        _appendLocalSessionMessage(
          sessionKey,
          GatewayChatMessage(
            id: _nextLocalMessageId(),
            role: 'assistant',
            text: appText(
              '多 Agent 协作不可用（Gateway ACP）：${error.message}',
              'Multi-agent collaboration is unavailable (Gateway ACP): ${error.message}',
            ),
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: 'Multi-Agent',
            stopReason: null,
            pending: false,
            error: true,
          ),
        );
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
    });
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
    return _assistantModelChoicesForSession(currentSessionKey);
  }

  List<String> _assistantModelChoicesForSession(String sessionKey) {
    final target = assistantExecutionTargetForSession(sessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      if (singleAgentUsesAiChatFallbackForSession(sessionKey)) {
        return aiGatewayConversationModelChoices;
      }
      final selectedModel =
          _assistantThreadRecords[_normalizedAssistantSessionKey(sessionKey)]
              ?.assistantModelId
              .trim();
      if (selectedModel?.isNotEmpty == true) {
        return <String>[selectedModel!];
      }
      return const <String>[];
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
    final target = currentAssistantExecutionTarget;
    if (target == AssistantExecutionTarget.singleAgent) {
      return false;
    }
    final profile = _gatewayProfileForAssistantExecutionTarget(target);
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
    final defaults = switch (target) {
      AssistantExecutionTarget.singleAgent =>
        GatewayConnectionProfile.emptySlot(index: kGatewayRemoteProfileIndex),
      AssistantExecutionTarget.local =>
        GatewayConnectionProfile.defaultsLocal(),
      AssistantExecutionTarget.remote =>
        GatewayConnectionProfile.defaultsRemote(),
    };
    return hasStoredGatewayCredential ||
        host != defaults.host ||
        profile.port != defaults.port ||
        profile.tls != defaults.tls ||
        profile.mode != defaults.mode;
  }

  String _joinConnectionParts(List<String> parts) {
    final normalized = parts
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return normalized.join(' · ');
  }

  String _gatewayAddressLabel(GatewayConnectionProfile profile) {
    final host = profile.host.trim();
    if (host.isEmpty || profile.port <= 0) {
      return appText('未连接目标', 'No target');
    }
    return '$host:${profile.port}';
  }

  List<SecretReferenceEntry> get secretReferences =>
      _settingsController.buildSecretReferences();
  List<SecretAuditEntry> get secretAuditTrail => _settingsController.auditTrail;
  List<RuntimeLogEntry> get runtimeLogs => _runtime.logs;
  List<AssistantFocusEntry> get assistantNavigationDestinations =>
      normalizeAssistantNavigationDestinations(
        settings.assistantNavigationDestinations,
      ).where(supportsAssistantFocusEntry).toList(growable: false);

  bool supportsAssistantFocusEntry(AssistantFocusEntry entry) {
    final destination = entry.destination;
    if (destination != null) {
      return capabilities.supportsDestination(destination);
    }
    return capabilities.supportsDestination(WorkspaceDestination.settings);
  }

  List<GatewayChatMessage> get chatMessages {
    final sessionKey = _normalizedAssistantSessionKey(
      _sessionsController.currentSessionKey,
    );
    final items = List<GatewayChatMessage>.from(
      isSingleAgentMode
          ? const <GatewayChatMessage>[]
          : _chatController.messages,
    );
    final threadItems = isSingleAgentMode
        ? _assistantThreadMessages[sessionKey]
        : null;
    if (threadItems != null && threadItems.isNotEmpty) {
      items.addAll(threadItems);
    }
    final localItems = _localSessionMessages[sessionKey];
    if (localItems != null && localItems.isNotEmpty) {
      items.addAll(localItems);
    }
    final streaming = isSingleAgentMode
        ? (_aiGatewayStreamingTextBySession[sessionKey]?.trim() ?? '')
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

  AssistantExecutionTarget assistantExecutionTargetForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    return _sanitizeExecutionTarget(
      _assistantThreadRecords[normalizedSessionKey]?.executionTarget ??
          settings.assistantExecutionTarget,
    );
  }

  AssistantMessageViewMode assistantMessageViewModeForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    return _assistantThreadRecords[normalizedSessionKey]?.messageViewMode ??
        AssistantMessageViewMode.rendered;
  }

  String _defaultWorkspaceRefForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    return switch (target) {
      AssistantExecutionTarget.remote => settings.remoteProjectRoot.trim(),
      AssistantExecutionTarget.local || AssistantExecutionTarget.singleAgent =>
        _defaultLocalWorkspaceRefForSession(normalizedSessionKey),
    };
  }

  String _defaultLocalWorkspaceRefForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final baseWorkspace = settings.workspacePath.trim();
    if (baseWorkspace.isEmpty || normalizedSessionKey == 'main') {
      return baseWorkspace;
    }
    final threadWorkspace =
        '${_trimTrailingPathSeparator(baseWorkspace)}/.xworkmate/threads/${_threadWorkspaceDirectoryName(normalizedSessionKey)}';
    _ensureLocalWorkspaceDirectory(threadWorkspace);
    return threadWorkspace;
  }

  String _threadWorkspaceDirectoryName(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final sanitized = normalizedSessionKey
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return sanitized.isEmpty ? 'thread' : sanitized;
  }

  String _trimTrailingPathSeparator(String path) {
    if (path.endsWith('/') && path.length > 1) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  void _ensureLocalWorkspaceDirectory(String path) {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return;
    }
    try {
      Directory(normalizedPath).createSync(recursive: true);
    } catch (_) {
      // Best effort only. The caller can still decide whether to use fallback behavior.
    }
  }

  bool _usesLegacySharedWorkspaceRef(
    String sessionKey, {
    AssistantExecutionTarget? executionTarget,
    String? workspaceRef,
    WorkspaceRefKind? workspaceRefKind,
  }) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (normalizedSessionKey == 'main') {
      return false;
    }
    final resolvedTarget =
        executionTarget ??
        assistantExecutionTargetForSession(normalizedSessionKey);
    if (resolvedTarget == AssistantExecutionTarget.remote) {
      return false;
    }
    final normalizedRef = workspaceRef?.trim() ?? '';
    if (normalizedRef.isEmpty) {
      return false;
    }
    return workspaceRefKind == WorkspaceRefKind.localPath &&
        normalizedRef == settings.workspacePath.trim();
  }

  WorkspaceRefKind _defaultWorkspaceRefKindForTarget(
    AssistantExecutionTarget target,
  ) {
    return switch (target) {
      AssistantExecutionTarget.remote => WorkspaceRefKind.remotePath,
      AssistantExecutionTarget.local ||
      AssistantExecutionTarget.singleAgent => WorkspaceRefKind.localPath,
    };
  }

  void _syncAssistantWorkspaceRefForSession(
    String sessionKey, {
    AssistantExecutionTarget? executionTarget,
  }) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final resolvedTarget =
        executionTarget ??
        assistantExecutionTargetForSession(normalizedSessionKey);
    final nextWorkspaceRef = _defaultWorkspaceRefForSession(
      normalizedSessionKey,
    );
    final nextWorkspaceRefKind = _defaultWorkspaceRefKindForTarget(
      resolvedTarget,
    );
    final existing = _assistantThreadRecords[normalizedSessionKey];
    final existingWorkspaceRef = existing?.workspaceRef.trim() ?? '';
    if (existing != null &&
        existingWorkspaceRef.isNotEmpty &&
        existing.workspaceRefKind == nextWorkspaceRefKind &&
        !_usesLegacySharedWorkspaceRef(
          normalizedSessionKey,
          executionTarget: resolvedTarget,
          workspaceRef: existingWorkspaceRef,
          workspaceRefKind: existing.workspaceRefKind,
        )) {
      return;
    }
    if (existing != null &&
        existingWorkspaceRef == nextWorkspaceRef &&
        existing.workspaceRefKind == nextWorkspaceRefKind) {
      return;
    }
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      executionTarget: resolvedTarget,
      workspaceRef: nextWorkspaceRef,
      workspaceRefKind: nextWorkspaceRefKind,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
  }

  List<GatewaySessionSummary> _assistantSessions() {
    final archivedKeys = settings.assistantArchivedTaskKeys
        .map(_normalizedAssistantSessionKey)
        .toSet();
    final byKey = <String, GatewaySessionSummary>{};

    for (final session in _sessionsController.sessions) {
      final normalizedSessionKey = _normalizedAssistantSessionKey(session.key);
      if (archivedKeys.contains(normalizedSessionKey)) {
        continue;
      }
      byKey[normalizedSessionKey] = session;
    }

    for (final record in _assistantThreadRecords.values) {
      final normalizedSessionKey = _normalizedAssistantSessionKey(
        record.sessionKey,
      );
      if (normalizedSessionKey.isEmpty ||
          archivedKeys.contains(normalizedSessionKey) ||
          record.archived) {
        continue;
      }
      byKey.putIfAbsent(
        normalizedSessionKey,
        () => _assistantSessionSummaryFor(normalizedSessionKey, record: record),
      );
    }

    final currentKey = _normalizedAssistantSessionKey(currentSessionKey);
    if (!archivedKeys.contains(currentKey) && !byKey.containsKey(currentKey)) {
      byKey[currentKey] = _assistantSessionSummaryFor(currentKey);
    }

    final items = byKey.values.toList(growable: true)
      ..sort(
        (left, right) =>
            (right.updatedAtMs ?? 0).compareTo(left.updatedAtMs ?? 0),
      );
    return items;
  }

  bool assistantSessionHasPendingRun(String sessionKey) {
    final normalized = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalized) ==
        AssistantExecutionTarget.singleAgent) {
      return _aiGatewayPendingSessionKeys.contains(normalized);
    }
    return (_chatController.hasPendingRun || _multiAgentRunPending) &&
        matchesSessionKey(normalized, _sessionsController.currentSessionKey);
  }

  void navigateTo(WorkspaceDestination destination) =>
      AppControllerDesktopNavigation(this).navigateTo(destination);

  void navigateHome() => AppControllerDesktopNavigation(this).navigateHome();

  void openModules({ModulesTab tab = ModulesTab.nodes}) =>
      AppControllerDesktopNavigation(this).openModules(tab: tab);

  void setModulesTab(ModulesTab tab) =>
      AppControllerDesktopNavigation(this).setModulesTab(tab);

  void openSecrets({SecretsTab tab = SecretsTab.vault}) =>
      AppControllerDesktopNavigation(this).openSecrets(tab: tab);

  void setSecretsTab(SecretsTab tab) =>
      AppControllerDesktopNavigation(this).setSecretsTab(tab);

  void openAiGateway({AiGatewayTab tab = AiGatewayTab.models}) =>
      AppControllerDesktopNavigation(this).openAiGateway(tab: tab);

  void setAiGatewayTab(AiGatewayTab tab) =>
      AppControllerDesktopNavigation(this).setAiGatewayTab(tab);

  void openSettings({
    SettingsTab tab = SettingsTab.general,
    SettingsDetailPage? detail,
    SettingsNavigationContext? navigationContext,
  }) => AppControllerDesktopNavigation(this).openSettings(
    tab: tab,
    detail: detail,
    navigationContext: navigationContext,
  );

  void setSettingsTab(SettingsTab tab, {bool clearDetail = true}) =>
      AppControllerDesktopNavigation(
        this,
      ).setSettingsTab(tab, clearDetail: clearDetail);

  void closeSettingsDetail() =>
      AppControllerDesktopNavigation(this).closeSettingsDetail();

  void cycleSidebarState() =>
      AppControllerDesktopNavigation(this).cycleSidebarState();

  void setSidebarState(AppSidebarState state) =>
      AppControllerDesktopNavigation(this).setSidebarState(state);

  void setThemeMode(ThemeMode mode) =>
      AppControllerDesktopNavigation(this).setThemeMode(mode);

  Future<void> toggleAppLanguage() =>
      AppControllerDesktopNavigation(this).toggleAppLanguage();

  Future<void> setAppLanguage(AppLanguage language) =>
      AppControllerDesktopNavigation(this).setAppLanguage(language);

  void openDetail(DetailPanelData detailPanel) =>
      AppControllerDesktopNavigation(this).openDetail(detailPanel);

  void closeDetail() => AppControllerDesktopNavigation(this).closeDetail();

  Future<void> connectWithSetupCode({
    required String setupCode,
    String token = '',
    String password = '',
  }) => AppControllerDesktopGateway(this).connectWithSetupCode(
    setupCode: setupCode,
    token: token,
    password: password,
  );

  Future<void> connectManual({
    required String host,
    required int port,
    required bool tls,
    required RuntimeConnectionMode mode,
    String token = '',
    String password = '',
  }) => AppControllerDesktopGateway(this).connectManual(
    host: host,
    port: port,
    tls: tls,
    mode: mode,
    token: token,
    password: password,
  );

  Future<void> disconnectGateway() =>
      AppControllerDesktopGateway(this).disconnectGateway();

  Future<void> saveSettingsDraft(SettingsSnapshot snapshot) =>
      AppControllerDesktopSettings(this).saveSettingsDraft(snapshot);

  void saveGatewayTokenDraft(String value, {required int profileIndex}) =>
      AppControllerDesktopSettings(
        this,
      ).saveGatewayTokenDraft(value, profileIndex: profileIndex);

  void saveGatewayPasswordDraft(String value, {required int profileIndex}) =>
      AppControllerDesktopSettings(
        this,
      ).saveGatewayPasswordDraft(value, profileIndex: profileIndex);

  void saveAiGatewayApiKeyDraft(String value) =>
      AppControllerDesktopSettings(this).saveAiGatewayApiKeyDraft(value);

  void saveVaultTokenDraft(String value) =>
      AppControllerDesktopSettings(this).saveVaultTokenDraft(value);

  void saveOllamaCloudApiKeyDraft(String value) =>
      AppControllerDesktopSettings(this).saveOllamaCloudApiKeyDraft(value);

  Future<void> persistSettingsDraft() =>
      AppControllerDesktopSettings(this).persistSettingsDraft();

  Future<void> applySettingsDraft() =>
      AppControllerDesktopSettings(this).applySettingsDraft();

  Future<void> saveSettings(
    SettingsSnapshot snapshot, {
    bool refreshAfterSave = true,
  }) => AppControllerDesktopSettings(
    this,
  ).saveSettings(snapshot, refreshAfterSave: refreshAfterSave);

  Future<void> clearAssistantLocalState() =>
      AppControllerDesktopSettings(this).clearAssistantLocalState();

  Future<void> _connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) => AppControllerDesktopGateway(this)._connectProfile(
    profile,
    profileIndex: profileIndex,
    authTokenOverride: authTokenOverride,
    authPasswordOverride: authPasswordOverride,
  );

  Future<void> _sendSingleAgentMessage(
    String message, {
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<CollaborationAttachment> localAttachments,
  }) => AppControllerDesktopSingleAgent(this)._sendSingleAgentMessage(
    message,
    thinking: thinking,
    attachments: attachments,
    localAttachments: localAttachments,
  );

  Future<void> _abortAiGatewayRun(String sessionKey) =>
      AppControllerDesktopSingleAgent(this)._abortAiGatewayRun(sessionKey);

  Future<void> connectSavedGateway() async {
    final target = currentAssistantExecutionTarget;
    if (target == AssistantExecutionTarget.singleAgent) {
      return;
    }
    await _connectProfile(
      _gatewayProfileForAssistantExecutionTarget(target),
      profileIndex: _gatewayProfileIndexForExecutionTarget(target),
    );
  }

  Future<void> clearStoredGatewayToken({int? profileIndex}) async {
    await _settingsController.clearGatewaySecrets(
      profileIndex: profileIndex,
      token: true,
    );
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
    if (currentAssistantExecutionTarget !=
        AssistantExecutionTarget.singleAgent) {
      final target = currentAssistantExecutionTarget;
      final nextProfile = _gatewayProfileForAssistantExecutionTarget(
        target,
      ).copyWith(selectedAgentId: _agentsController.selectedAgentId);
      await saveSettings(
        settings.copyWithGatewayProfileAt(
          _gatewayProfileIndexForExecutionTarget(target),
          nextProfile,
        ),
        refreshAfterSave: false,
      );
    }
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
    final previousSessionKey = _normalizedAssistantSessionKey(
      _sessionsController.currentSessionKey,
    );
    final nextSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final nextTarget = assistantExecutionTargetForSession(nextSessionKey);
    final nextViewMode = assistantMessageViewModeForSession(nextSessionKey);

    if (!isSingleAgentMode) {
      _preserveGatewayHistoryForSession(previousSessionKey);
    }

    await _setCurrentAssistantSessionKey(nextSessionKey);
    _upsertAssistantThreadRecord(
      nextSessionKey,
      executionTarget: nextTarget,
      messageViewMode: nextViewMode,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _syncAssistantWorkspaceRefForSession(
      nextSessionKey,
      executionTarget: nextTarget,
    );
    await _applyAssistantExecutionTarget(
      nextTarget,
      sessionKey: nextSessionKey,
      persistDefaultSelection: false,
    );
    if (nextTarget == AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(nextSessionKey);
    }
    _recomputeTasks();
  }

  Future<void> sendChatMessage(
    String message, {
    String thinking = 'off',
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    List<CollaborationAttachment> localAttachments =
        const <CollaborationAttachment>[],
    List<String> selectedSkillLabels = const <String>[],
  }) async {
    _syncAssistantWorkspaceRefForSession(_sessionsController.currentSessionKey);
    if (isSingleAgentMode) {
      await _sendSingleAgentMessage(
        message,
        thinking: thinking,
        attachments: attachments,
        localAttachments: localAttachments,
      );
      await _flushAssistantThreadPersistence();
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
    if (_multiAgentRunPending) {
      final sessionKey = _normalizedAssistantSessionKey(
        _sessionsController.currentSessionKey,
      );
      try {
        await _gatewayAcpClient.cancelSession(
          sessionId: sessionKey,
          threadId: sessionKey,
        );
      } catch (_) {
        // Best effort cancellation only.
      }
      _multiAgentRunPending = false;
      _recomputeTasks();
      _notifyIfActive();
      return;
    }
    if (isSingleAgentMode) {
      final sessionKey = _normalizedAssistantSessionKey(
        _sessionsController.currentSessionKey,
      );
      if (_singleAgentExternalCliPendingSessionKeys.contains(sessionKey)) {
        await _singleAgentRunner.abort(sessionKey);
        _aiGatewayPendingSessionKeys.remove(sessionKey);
        _singleAgentExternalCliPendingSessionKeys.remove(sessionKey);
        _clearAiGatewayStreamingText(sessionKey);
        _recomputeTasks();
        _notifyIfActive();
        return;
      }
      await _abortAiGatewayRun(_sessionsController.currentSessionKey);
      return;
    }
    await _chatController.abortRun();
  }

  Future<void> prepareForExit() async {
    try {
      await abortRun();
    } catch (_) {
      // Best effort only. Native termination still proceeds.
    }
    await _flushAssistantThreadPersistence();
  }

  Map<String, dynamic> desktopStatusSnapshot() {
    final pausedTasks = _tasksController.scheduled
        .where((item) => item.status == 'Disabled')
        .length;
    final timedOutTasks = _tasksController.failed
        .where(_looksLikeTimedOutTask)
        .length;
    final failedTasks = _tasksController.failed.length;
    final queuedTasks = _tasksController.queue.length;
    final runningTasks = _tasksController.running.length;
    final scheduledTasks = _tasksController.scheduled.length;
    final badgeCount = runningTasks + pausedTasks + timedOutTasks;
    return <String, dynamic>{
      'connectionStatus': _desktopConnectionStatusValue(connection.status),
      'connectionLabel': connection.status.label,
      'runningTasks': runningTasks,
      'pausedTasks': pausedTasks,
      'timedOutTasks': timedOutTasks,
      'queuedTasks': queuedTasks,
      'scheduledTasks': scheduledTasks,
      'failedTasks': failedTasks,
      'totalTasks': _tasksController.totalCount,
      'badgeCount': badgeCount > 0 ? badgeCount : runningTasks + queuedTasks,
    };
  }

  bool _looksLikeTimedOutTask(DerivedTaskItem item) {
    final haystack = '${item.status} ${item.title} ${item.summary}'
        .toLowerCase();
    return haystack.contains('timed out') ||
        haystack.contains('timeout') ||
        haystack.contains('超时');
  }

  String _desktopConnectionStatusValue(RuntimeConnectionStatus status) {
    switch (status) {
      case RuntimeConnectionStatus.connected:
        return 'connected';
      case RuntimeConnectionStatus.connecting:
        return 'connecting';
      case RuntimeConnectionStatus.error:
        return 'error';
      case RuntimeConnectionStatus.offline:
        return 'disconnected';
    }
  }

  Future<void> setAssistantExecutionTarget(
    AssistantExecutionTarget target,
  ) async {
    final resolvedTarget = _sanitizeExecutionTarget(target);
    final currentTarget = assistantExecutionTargetForSession(
      _sessionsController.currentSessionKey,
    );
    if (currentTarget == resolvedTarget &&
        settings.assistantExecutionTarget == resolvedTarget) {
      return;
    }
    _upsertAssistantThreadRecord(
      _sessionsController.currentSessionKey,
      executionTarget: resolvedTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _syncAssistantWorkspaceRefForSession(
      _sessionsController.currentSessionKey,
      executionTarget: resolvedTarget,
    );
    _recomputeTasks();
    _notifyIfActive();
    await _applyAssistantExecutionTarget(
      resolvedTarget,
      sessionKey: _sessionsController.currentSessionKey,
      persistDefaultSelection: true,
    );
    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(
        _sessionsController.currentSessionKey,
      );
    }
    _recomputeTasks();
    _notifyIfActive();
  }

  Future<void> setSingleAgentProvider(SingleAgentProvider provider) async {
    final sessionKey = _normalizedAssistantSessionKey(currentSessionKey);
    final sanitizedProvider = settings.resolveSingleAgentProvider(provider);
    if (singleAgentProviderForSession(sessionKey) == sanitizedProvider) {
      return;
    }
    _singleAgentRuntimeModelBySession.remove(sessionKey);
    _upsertAssistantThreadRecord(
      sessionKey,
      singleAgentProvider: sanitizedProvider,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _recomputeTasks();
    _notifyIfActive();
    if (assistantExecutionTargetForSession(sessionKey) ==
        AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(sessionKey);
    }
    unawaited(refreshMultiAgentMounts(sync: settings.multiAgent.autoSync));
  }

  Future<void> setAssistantMessageViewMode(
    AssistantMessageViewMode mode,
  ) async {
    final sessionKey = _normalizedAssistantSessionKey(
      _sessionsController.currentSessionKey,
    );
    if (assistantMessageViewModeForSession(sessionKey) == mode) {
      return;
    }
    _upsertAssistantThreadRecord(
      sessionKey,
      messageViewMode: mode,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _flushAssistantThreadPersistence();
    _recomputeTasks();
    _notifyIfActive();
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

  Future<void> _applyAssistantExecutionTarget(
    AssistantExecutionTarget target, {
    required String sessionKey,
    required bool persistDefaultSelection,
  }) async {
    final resolvedTarget = _sanitizeExecutionTarget(target);
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (resolvedTarget != AssistantExecutionTarget.singleAgent) {
      _singleAgentRuntimeModelBySession.remove(normalizedSessionKey);
    }
    if (!matchesSessionKey(
      normalizedSessionKey,
      _sessionsController.currentSessionKey,
    )) {
      await _setCurrentAssistantSessionKey(normalizedSessionKey);
    }
    if (persistDefaultSelection &&
        settings.assistantExecutionTarget != resolvedTarget) {
      await saveSettings(
        settings.copyWith(assistantExecutionTarget: resolvedTarget),
        refreshAfterSave: false,
      );
    }

    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      if (_runtime.isConnected) {
        _preserveGatewayHistoryForSession(normalizedSessionKey);
      }
      await _ensureActiveAssistantThread();
      if (_runtime.isConnected) {
        try {
          await disconnectGateway();
        } catch (_) {
          // Preserve the selected thread-bound target even when the active
          // gateway session does not close cleanly on the first attempt.
        }
      } else {
        _chatController.clear();
      }
      await _setCurrentAssistantSessionKey(normalizedSessionKey);
      return;
    }

    final targetProfile = _gatewayProfileForAssistantExecutionTarget(
      resolvedTarget,
    );
    try {
      await _connectProfile(
        targetProfile,
        profileIndex: _gatewayProfileIndexForExecutionTarget(resolvedTarget),
      );
    } catch (_) {
      // Keep the selected execution target even when the immediate reconnect
      // fails so the user can retry or adjust gateway settings manually.
    }
    await _setCurrentAssistantSessionKey(normalizedSessionKey);
    await _chatController.loadSession(normalizedSessionKey);
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
    await selectAssistantModelForSession(currentSessionKey, modelId);
  }

  Future<void> selectAssistantModelForSession(
    String sessionKey,
    String modelId,
  ) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final choices = matchesSessionKey(normalizedSessionKey, currentSessionKey)
        ? assistantModelChoices
        : _assistantModelChoicesForSession(normalizedSessionKey);
    if (choices.isNotEmpty && !choices.contains(trimmed)) {
      return;
    }
    if (_assistantThreadRecords[normalizedSessionKey]?.assistantModelId ==
        trimmed) {
      return;
    }
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      assistantModelId: trimmed,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _recomputeTasks();
    _notifyIfActive();
  }

  String assistantCustomTaskTitle(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final settingsTitle =
        settings.assistantCustomTaskTitles[normalizedSessionKey]?.trim() ?? '';
    if (settingsTitle.isNotEmpty) {
      return settingsTitle;
    }
    return _assistantThreadRecords[normalizedSessionKey]?.title.trim() ?? '';
  }

  void initializeAssistantThreadContext(
    String sessionKey, {
    String title = '',
    AssistantExecutionTarget? executionTarget,
    AssistantMessageViewMode? messageViewMode,
    SingleAgentProvider? singleAgentProvider,
  }) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final resolvedTarget =
        executionTarget ??
        assistantExecutionTargetForSession(currentSessionKey);
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      title: title.trim(),
      executionTarget: resolvedTarget,
      messageViewMode:
          messageViewMode ??
          assistantMessageViewModeForSession(currentSessionKey),
      singleAgentProvider:
          singleAgentProvider ??
          singleAgentProviderForSession(currentSessionKey),
      workspaceRef: _defaultWorkspaceRefForSession(normalizedSessionKey),
      workspaceRefKind: _defaultWorkspaceRefKindForTarget(resolvedTarget),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    unawaited(_persistAssistantLastSessionKey(normalizedSessionKey));
    _notifyIfActive();
  }

  Future<void> refreshSingleAgentSkillsForSession(String sessionKey) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return;
    }
    final localSkills = await _singleAgentLocalSkillsForSession(
      normalizedSessionKey,
    );
    final provider =
        singleAgentResolvedProviderForSession(normalizedSessionKey) ??
        currentSingleAgentResolvedProvider;
    if (provider == null) {
      await _replaceSingleAgentThreadSkills(normalizedSessionKey, localSkills);
      return;
    }
    try {
      await _refreshAcpCapabilities();
      final response = await _gatewayAcpClient.request(
        method: 'skills.status',
        params: <String, dynamic>{
          'sessionId': normalizedSessionKey,
          'threadId': normalizedSessionKey,
          'mode': 'single-agent',
          'provider': provider.providerId,
        },
      );
      final result = asMap(response['result']);
      final payload = result.isNotEmpty ? result : response;
      final skills = asList(payload['skills'])
          .map(asMap)
          .map((item) => _singleAgentSkillEntryFromAcp(item, provider))
          .where((item) => item.key.isNotEmpty && item.label.isNotEmpty)
          .toList(growable: false);
      await _replaceSingleAgentThreadSkills(
        normalizedSessionKey,
        _mergeSingleAgentSkillEntries(
          groups: <List<AssistantThreadSkillEntry>>[localSkills, skills],
        ),
      );
    } on GatewayAcpException catch (error) {
      if (_unsupportedAcpSkillsStatus(error)) {
        await _replaceSingleAgentThreadSkills(
          normalizedSessionKey,
          localSkills,
        );
        return;
      }
      await _replaceSingleAgentThreadSkills(normalizedSessionKey, localSkills);
    } catch (_) {
      await _replaceSingleAgentThreadSkills(normalizedSessionKey, localSkills);
    }
  }

  Future<void> refreshSingleAgentLocalSkillsForSession(
    String sessionKey,
  ) async {
    await _refreshSharedSingleAgentLocalSkillsCache(forceRescan: true);
    await refreshSingleAgentSkillsForSession(sessionKey);
  }

  Future<void> toggleAssistantSkillForSession(
    String sessionKey,
    String skillKey,
  ) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final normalizedSkillKey = skillKey.trim();
    if (normalizedSkillKey.isEmpty) {
      return;
    }
    final importedKeys = assistantImportedSkillsForSession(
      normalizedSessionKey,
    ).map((item) => item.key).toSet();
    if (!importedKeys.contains(normalizedSkillKey)) {
      return;
    }
    final nextSelected = List<String>.from(
      assistantSelectedSkillKeysForSession(normalizedSessionKey),
    );
    if (nextSelected.contains(normalizedSkillKey)) {
      nextSelected.remove(normalizedSkillKey);
    } else {
      nextSelected.add(normalizedSkillKey);
    }
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      selectedSkillKeys: nextSelected,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _notifyIfActive();
    await _flushAssistantThreadPersistence();
  }

  Future<void> saveAssistantTaskTitle(String sessionKey, String title) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
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
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      title: normalizedTitle,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _recomputeTasks();
    _notifyIfActive();
  }

  bool isAssistantTaskArchived(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    return settings.assistantArchivedTaskKeys.any(
      (item) => _normalizedAssistantSessionKey(item) == normalizedSessionKey,
    );
  }

  Future<void> saveAssistantTaskArchived(
    String sessionKey,
    bool archived,
  ) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (normalizedSessionKey.isEmpty) {
      return;
    }
    final next = <String>[
      ...settings.assistantArchivedTaskKeys.where(
        (item) => _normalizedAssistantSessionKey(item) != normalizedSessionKey,
      ),
    ];
    if (archived) {
      next.add(normalizedSessionKey);
    }
    await saveSettings(
      settings.copyWith(assistantArchivedTaskKeys: next),
      refreshAfterSave: false,
    );
    if (archived) {
      unawaited(
        _enqueueThreadTurn<void>(normalizedSessionKey, () async {
          try {
            await _gatewayAcpClient.closeSession(
              sessionId: normalizedSessionKey,
              threadId: normalizedSessionKey,
            );
          } catch (_) {
            // Best effort only.
          }
        }).catchError((_) {}),
      );
    }
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      archived: archived,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _recomputeTasks();
    _notifyIfActive();
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
    await saveSettings(
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

  Future<void> _initialize() async {
    try {
      _resolvedUserHomeDirectory = await _skillDirectoryAccessService
          .resolveUserHomeDirectory();
      await _settingsController.initialize();
      _restoreAssistantThreads(await _store.loadAssistantThreadRecords());
      await _restoreSharedSingleAgentLocalSkillsCache();
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
          await _connectProfile(
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
        _draftSecretValues.containsKey(_draftAiGatewayApiKeyKey);
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
    final aiGatewayApiKey = _draftSecretValues[_draftAiGatewayApiKeyKey];
    if ((aiGatewayApiKey ?? '').isNotEmpty) {
      await _settingsController.saveAiGatewayApiKey(aiGatewayApiKey!);
    }
    final vaultToken = _draftSecretValues[_draftVaultTokenKey];
    if ((vaultToken ?? '').isNotEmpty) {
      await _settingsController.saveVaultToken(vaultToken!);
    }
    final ollamaApiKey = _draftSecretValues[_draftOllamaApiKeyKey];
    if ((ollamaApiKey ?? '').isNotEmpty) {
      await _settingsController.saveOllamaCloudApiKey(ollamaApiKey!);
    }
    _draftSecretValues.clear();
  }

  static String _draftGatewayTokenKey(int profileIndex) =>
      'gateway_token_$profileIndex';

  static String _draftGatewayPasswordKey(int profileIndex) =>
      'gateway_password_$profileIndex';

  static bool _isGatewayDraftKey(String key) =>
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

  Future<void> _applyPersistedAiGatewaySettings(
    SettingsSnapshot snapshot,
  ) async {
    final apiKey = await _settingsController.loadAiGatewayApiKey();
    if (snapshot.aiGateway.baseUrl.trim().isEmpty || apiKey.trim().isEmpty) {
      return;
    }
    try {
      await syncAiGatewayCatalog(snapshot.aiGateway, apiKeyOverride: apiKey);
    } catch (_) {
      // Keep the saved draft applied even if model sync fails immediately.
    }
  }

  Future<void> _ensureActiveAssistantThread() async {
    if (!isSingleAgentMode ||
        !isAssistantTaskArchived(_sessionsController.currentSessionKey)) {
      return;
    }
    final fallback = _assistantSessionSummaries().firstWhere(
      (item) => !isAssistantTaskArchived(item.key),
      orElse: () => GatewaySessionSummary(
        key: 'draft:${DateTime.now().millisecondsSinceEpoch}',
        kind: 'assistant',
        displayName: appText('新对话', 'New conversation'),
        surface: 'Assistant',
        subject: null,
        room: null,
        space: null,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        sessionId: null,
        systemSent: false,
        abortedLastRun: false,
        thinkingLevel: null,
        verboseLevel: null,
        inputTokens: null,
        outputTokens: null,
        totalTokens: null,
        model: null,
        contextTokens: null,
        derivedTitle: appText('新对话', 'New conversation'),
        lastMessagePreview: null,
      ),
    );
    await _setCurrentAssistantSessionKey(fallback.key);
  }

  Future<void> _restoreInitialAssistantSessionSelection() async {
    final normalized = _normalizedAssistantSessionKey(
      settings.assistantLastSessionKey,
    );
    final known =
        normalized == 'main' ||
        _assistantThreadRecords.containsKey(normalized) ||
        _assistantThreadMessages.containsKey(normalized);
    if (normalized.isEmpty || !known || isAssistantTaskArchived(normalized)) {
      return;
    }
    await _setCurrentAssistantSessionKey(normalized, persistSelection: false);
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

  SettingsSnapshot _sanitizeFeatureFlagSettings(SettingsSnapshot snapshot) {
    final features = featuresFor(_hostUiFeaturePlatform);
    final allowedNavigation =
        normalizeAssistantNavigationDestinations(
              snapshot.assistantNavigationDestinations,
            )
            .where((entry) {
              final destination = entry.destination;
              if (destination != null) {
                return features.allowedDestinations.contains(destination);
              }
              return features.allowedDestinations.contains(
                WorkspaceDestination.settings,
              );
            })
            .toList(growable: false);
    final sanitizedExecutionTarget = features.sanitizeExecutionTarget(
      snapshot.assistantExecutionTarget,
    );
    final multiAgentConfig = features.supportsMultiAgent
        ? snapshot.multiAgent
        : snapshot.multiAgent.copyWith(enabled: false);
    final experimentalCanvas =
        features.allowsExperimentalSetting(
          UiFeatureKeys.settingsExperimentalCanvas,
        )
        ? snapshot.experimentalCanvas
        : false;
    final experimentalBridge =
        features.allowsExperimentalSetting(
          UiFeatureKeys.settingsExperimentalBridge,
        )
        ? snapshot.experimentalBridge
        : false;
    final experimentalDebug =
        features.allowsExperimentalSetting(
          UiFeatureKeys.settingsExperimentalDebug,
        )
        ? snapshot.experimentalDebug
        : false;
    return snapshot.copyWith(
      assistantExecutionTarget: sanitizedExecutionTarget,
      assistantNavigationDestinations: allowedNavigation,
      multiAgent: multiAgentConfig,
      experimentalCanvas: experimentalCanvas,
      experimentalBridge: experimentalBridge,
      experimentalDebug: experimentalDebug,
    );
  }

  SettingsSnapshot _sanitizeOllamaCloudSettings(SettingsSnapshot snapshot) {
    final rawBaseUrl = snapshot.ollamaCloud.baseUrl.trim();
    final normalized = rawBaseUrl.endsWith('/')
        ? rawBaseUrl.substring(0, rawBaseUrl.length - 1)
        : rawBaseUrl;
    if (normalized != 'https://ollama.svc.plus') {
      return snapshot;
    }
    return snapshot.copyWith(
      ollamaCloud: snapshot.ollamaCloud.copyWith(baseUrl: 'https://ollama.com'),
    );
  }

  SettingsTab _sanitizeSettingsTab(SettingsTab tab) {
    return featuresFor(_hostUiFeaturePlatform).sanitizeSettingsTab(tab);
  }

  AssistantExecutionTarget _sanitizeExecutionTarget(
    AssistantExecutionTarget? target,
  ) {
    return featuresFor(_hostUiFeaturePlatform).sanitizeExecutionTarget(target);
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
      framework: current.arisEnabled
          ? MultiAgentFramework.aris
          : current.framework,
      arisEnabled:
          current.framework == MultiAgentFramework.aris || current.arisEnabled,
      ollamaEndpoint: ollamaEndpoint,
      architect: current.architect.copyWith(model: architectModel),
      engineer: current.engineer.copyWith(model: engineerModel),
      tester: current.tester.copyWith(model: testerModel),
      mountTargets: current.mountTargets.isEmpty
          ? MultiAgentConfig.defaults().mountTargets
          : current.mountTargets,
    );
  }

  void _appendAssistantThreadMessage(
    String sessionKey,
    GatewayChatMessage message,
  ) {
    final key = _normalizedAssistantSessionKey(sessionKey);
    final next = List<GatewayChatMessage>.from(
      _assistantThreadMessages[key] ?? const <GatewayChatMessage>[],
    )..add(message);
    _assistantThreadMessages[key] = next;
    _upsertAssistantThreadRecord(
      key,
      messages: next,
      updatedAtMs:
          message.timestampMs ??
          DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _notifyIfActive();
  }

  Future<void> _flushAssistantThreadPersistence() async {
    await _assistantThreadPersistQueue.catchError((_) {});
  }

  void _appendLocalSessionMessage(
    String sessionKey,
    GatewayChatMessage message,
  ) {
    final key = _normalizedAssistantSessionKey(sessionKey);
    final next = List<GatewayChatMessage>.from(
      _localSessionMessages[key] ?? const <GatewayChatMessage>[],
    )..add(message);
    _localSessionMessages[key] = next;
    _notifyIfActive();
  }

  void _preserveGatewayHistoryForSession(String sessionKey) {
    final key = _normalizedAssistantSessionKey(sessionKey);
    if (_chatController.messages.isEmpty) {
      return;
    }
    _gatewayHistoryCache[key] = List<GatewayChatMessage>.from(
      _chatController.messages,
    );
  }

  List<GatewaySessionSummary> _assistantSessionSummaries() {
    final archivedKeys = settings.assistantArchivedTaskKeys
        .map(_normalizedAssistantSessionKey)
        .toSet();
    final items = <GatewaySessionSummary>[];

    for (final record in _assistantThreadRecords.values) {
      final sessionKey = _normalizedAssistantSessionKey(record.sessionKey);
      if (archivedKeys.contains(sessionKey) || record.archived) {
        continue;
      }
      items.add(_assistantSessionSummaryFor(sessionKey, record: record));
    }

    final currentSessionKey = _normalizedAssistantSessionKey(
      _sessionsController.currentSessionKey,
    );
    final hasCurrent = items.any(
      (item) => matchesSessionKey(item.key, currentSessionKey),
    );
    if (!hasCurrent && !archivedKeys.contains(currentSessionKey)) {
      items.add(_assistantSessionSummaryFor(currentSessionKey));
    }

    items.sort((left, right) {
      return (right.updatedAtMs ?? 0).compareTo(left.updatedAtMs ?? 0);
    });
    return items;
  }

  GatewaySessionSummary _assistantSessionSummaryFor(
    String sessionKey, {
    AssistantThreadRecord? record,
  }) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final resolvedRecord =
        record ?? _assistantThreadRecords[normalizedSessionKey];
    final messages =
        resolvedRecord?.messages ??
        _assistantThreadMessages[normalizedSessionKey] ??
        const <GatewayChatMessage>[];
    final preview = _assistantThreadPreview(messages);
    final title = assistantCustomTaskTitle(normalizedSessionKey);
    final lastMessage = messages.isNotEmpty ? messages.last : null;
    final updatedAtMs =
        resolvedRecord?.updatedAtMs ??
        lastMessage?.timestampMs ??
        DateTime.now().millisecondsSinceEpoch.toDouble();
    return GatewaySessionSummary(
      key: normalizedSessionKey,
      kind: 'assistant',
      displayName: title.isEmpty ? null : title,
      surface: 'Assistant',
      subject: preview,
      room: null,
      space: null,
      updatedAtMs: updatedAtMs,
      sessionId: normalizedSessionKey,
      systemSent: false,
      abortedLastRun: lastMessage?.error == true,
      thinkingLevel: null,
      verboseLevel: null,
      inputTokens: null,
      outputTokens: null,
      totalTokens: null,
      model: assistantModelForSession(normalizedSessionKey),
      contextTokens: null,
      derivedTitle: title.isEmpty ? null : title,
      lastMessagePreview: preview,
    );
  }

  String? _assistantThreadPreview(List<GatewayChatMessage> messages) {
    for (final message in messages.reversed) {
      final role = message.role.trim().toLowerCase();
      if (role != 'user' && role != 'assistant') {
        continue;
      }
      final text = message.text.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  String _gatewayEntryStateForTarget(AssistantExecutionTarget target) {
    return target.promptValue;
  }

  Future<List<AssistantThreadSkillEntry>> _scanSingleAgentSkillEntries(
    List<_SingleAgentSkillScanRoot> roots, {
    String workspaceRef = '',
  }) async {
    final dedupedByName = <String, AssistantThreadSkillEntry>{};
    for (final rootSpec in roots) {
      var resolvedRootPath = _resolveSingleAgentSkillRootPath(
        rootSpec.path,
        workspaceRef: workspaceRef,
      );
      if (resolvedRootPath.isEmpty) {
        continue;
      }
      SkillDirectoryAccessHandle? accessHandle;
      try {
        if (rootSpec.bookmark.trim().isNotEmpty) {
          accessHandle = await _skillDirectoryAccessService.openDirectory(
            AuthorizedSkillDirectory(
              path: resolvedRootPath,
              bookmark: rootSpec.bookmark,
            ),
          );
          if (accessHandle == null) {
            continue;
          }
          resolvedRootPath = normalizeAuthorizedSkillDirectoryPath(
            accessHandle.path,
          );
        }
        final root = Directory(resolvedRootPath);
        if (!await root.exists()) {
          continue;
        }
        final skillFiles = await _collectSkillFilesFromDirectory(root);
        for (final entity in skillFiles) {
          final entry = await _skillEntryFromFile(
            entity,
            rootSpec,
            resolvedRootPath,
          );
          final normalizedName = entry.label.trim().toLowerCase();
          if (normalizedName.isEmpty) {
            continue;
          }
          dedupedByName[normalizedName] = entry;
        }
      } catch (_) {
        continue;
      } finally {
        await accessHandle?.close();
      }
    }
    final entries = dedupedByName.values.toList(growable: false);
    entries.sort((left, right) => left.label.compareTo(right.label));
    return entries;
  }

  Future<List<File>> _collectSkillFilesFromDirectory(Directory root) async {
    final skillFiles = <File>[];
    final visitedDirectories = <String>{};

    Future<void> visitDirectory(Directory directory) async {
      final directoryKey = await _directoryScanKey(directory);
      if (!visitedDirectories.add(directoryKey)) {
        return;
      }
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File) {
          if (entity.uri.pathSegments.last == 'SKILL.md') {
            skillFiles.add(entity);
          }
          continue;
        }
        if (entity is Directory) {
          await visitDirectory(entity);
          continue;
        }
        if (entity is! Link) {
          continue;
        }
        final resolvedType = await FileSystemEntity.type(
          entity.path,
          followLinks: true,
        );
        if (resolvedType == FileSystemEntityType.file) {
          if (entity.uri.pathSegments.last == 'SKILL.md') {
            skillFiles.add(File(entity.path));
          }
          continue;
        }
        if (resolvedType == FileSystemEntityType.directory) {
          await visitDirectory(Directory(entity.path));
        }
      }
    }

    await visitDirectory(root);
    return skillFiles;
  }

  Future<String> _directoryScanKey(Directory directory) async {
    try {
      return await directory.resolveSymbolicLinks();
    } catch (_) {
      return directory.absolute.path;
    }
  }

  Future<List<AssistantThreadSkillEntry>> _scanSingleAgentSharedSkillEntries() {
    return _scanSingleAgentSkillEntries(_singleAgentSharedSkillScanRoots);
  }

  Future<List<AssistantThreadSkillEntry>> _scanSingleAgentWorkspaceSkillEntries(
    String sessionKey,
  ) {
    if (assistantWorkspaceRefKindForSession(sessionKey) !=
        WorkspaceRefKind.localPath) {
      return Future<List<AssistantThreadSkillEntry>>.value(
        const <AssistantThreadSkillEntry>[],
      );
    }
    return _scanSingleAgentSkillEntries(
      _defaultSingleAgentWorkspaceSkillScanRoots,
      workspaceRef: assistantWorkspaceRefForSession(sessionKey),
    );
  }

  _SingleAgentSkillScanRoot _singleAgentSharedSkillScanRootFromOverride(
    String rawPath,
  ) {
    final normalizedPath = rawPath.trim();
    final lowered = normalizedPath.toLowerCase();
    return _SingleAgentSkillScanRoot(
      path: normalizedPath,
      source: _sourceForSkillRootPath(lowered),
      scope: normalizedPath.startsWith('/etc/') ? 'system' : 'user',
    );
  }

  _SingleAgentSkillScanRoot
  _singleAgentSharedSkillScanRootFromAuthorizedDirectory(
    AuthorizedSkillDirectory directory,
  ) {
    final normalizedPath = normalizeAuthorizedSkillDirectoryPath(
      directory.path,
    );
    final lowered = normalizedPath.toLowerCase();
    return _SingleAgentSkillScanRoot(
      path: normalizedPath,
      source: _sourceForSkillRootPath(lowered),
      scope: normalizedPath.startsWith('/etc/') ? 'system' : 'user',
      bookmark: directory.bookmark,
    );
  }

  String _resolveSingleAgentSkillRootPath(
    String rawPath, {
    String workspaceRef = '',
  }) {
    final trimmed = rawPath.trim().replaceFirst(RegExp(r'^\./'), '');
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('/')) {
      return trimmed;
    }
    if (trimmed.startsWith('~/')) {
      final home = _resolvedUserHomeDirectory.trim();
      return home.isEmpty ? trimmed : '$home/${trimmed.substring(2)}';
    }
    final normalizedWorkspace = workspaceRef.trim();
    if (normalizedWorkspace.isEmpty) {
      return '';
    }
    final base = normalizedWorkspace.endsWith('/')
        ? normalizedWorkspace.substring(0, normalizedWorkspace.length - 1)
        : normalizedWorkspace;
    return '$base/$trimmed';
  }

  String _sourceForSkillRootPath(String path) {
    if (path == '/etc/skills' || path.startsWith('/etc/skills/')) {
      return 'system';
    }
    if (path == '~/.agents/skills' || path.endsWith('/.agents/skills')) {
      return 'agents';
    }
    if (path == '~/.codex/skills' || path.endsWith('/.codex/skills')) {
      return 'codex';
    }
    if (path == '~/.workbuddy/skills' || path.endsWith('/.workbuddy/skills')) {
      return 'workbuddy';
    }
    return 'custom';
  }

  Future<AssistantThreadSkillEntry> _skillEntryFromFile(
    File file,
    _SingleAgentSkillScanRoot root,
    String rootPath,
  ) async {
    final content = await file.readAsString();
    final nameMatch = RegExp(
      "^name:\\s*[\"']?(.+?)[\"']?\\s*\$",
      multiLine: true,
    ).firstMatch(content);
    final descriptionMatch = RegExp(
      "^description:\\s*[\"']?(.+?)[\"']?\\s*\$",
      multiLine: true,
    ).firstMatch(content);
    final directory = file.parent;
    final label =
        (nameMatch?.group(1) ??
                directory.uri.pathSegments
                    .where((item) => item.isNotEmpty)
                    .last)
            .trim();
    final relativeSource = directory.path.startsWith(rootPath)
        ? directory.path
              .substring(rootPath.length)
              .replaceFirst(RegExp(r'^/'), '')
        : directory.path;
    final sourceSegments = <String>[
      root.source,
      if (root.scope != root.source) root.scope,
    ].where((item) => item.trim().isNotEmpty).toList(growable: false);
    final sourceLabel = sourceSegments.join(' · ');
    return AssistantThreadSkillEntry(
      key: directory.path,
      label: label,
      description: (descriptionMatch?.group(1) ?? '').trim(),
      source: root.source,
      sourcePath: file.path,
      scope: root.scope,
      sourceLabel: relativeSource.isEmpty
          ? sourceLabel
          : '$sourceLabel · $relativeSource',
    );
  }

  void _restoreAssistantThreads(List<AssistantThreadRecord> records) {
    _assistantThreadRecords.clear();
    _assistantThreadMessages.clear();
    _singleAgentSharedImportedSkills = const <AssistantThreadSkillEntry>[];
    _singleAgentLocalSkillsHydrated = false;
    final archivedKeys = settings.assistantArchivedTaskKeys
        .map(_normalizedAssistantSessionKey)
        .toSet();
    for (final record in records) {
      final sessionKey = _normalizedAssistantSessionKey(record.sessionKey);
      if (sessionKey.isEmpty) {
        continue;
      }
      final titleFromSettings = assistantCustomTaskTitle(sessionKey);
      final shouldMigrateWorkspaceRef =
          record.workspaceRef.trim().isEmpty ||
          _usesLegacySharedWorkspaceRef(
            sessionKey,
            executionTarget:
                record.executionTarget ?? settings.assistantExecutionTarget,
            workspaceRef: record.workspaceRef,
            workspaceRefKind: record.workspaceRefKind,
          );
      final normalizedRecord = record.copyWith(
        sessionKey: sessionKey,
        title: titleFromSettings.isEmpty
            ? record.title.trim()
            : titleFromSettings,
        archived: record.archived || archivedKeys.contains(sessionKey),
        executionTarget:
            record.executionTarget ?? settings.assistantExecutionTarget,
        messageViewMode: record.messageViewMode,
        selectedSkillKeys: record.selectedSkillKeys
            .where(
              (item) => record.importedSkills.any((skill) => skill.key == item),
            )
            .toList(growable: false),
        assistantModelId: record.assistantModelId.trim().isEmpty
            ? _resolvedAssistantModelForTarget(
                record.executionTarget ?? settings.assistantExecutionTarget,
              )
            : record.assistantModelId.trim(),
        singleAgentProvider: record.singleAgentProvider,
        gatewayEntryState: (record.gatewayEntryState ?? '').trim().isEmpty
            ? _gatewayEntryStateForTarget(
                record.executionTarget ?? settings.assistantExecutionTarget,
              )
            : record.gatewayEntryState,
        workspaceRef: shouldMigrateWorkspaceRef
            ? _defaultWorkspaceRefForSession(sessionKey)
            : record.workspaceRef.trim(),
        workspaceRefKind: shouldMigrateWorkspaceRef
            ? _defaultWorkspaceRefKindForTarget(
                record.executionTarget ?? settings.assistantExecutionTarget,
              )
            : record.workspaceRefKind,
      );
      _assistantThreadRecords[sessionKey] = normalizedRecord;
      if (normalizedRecord.messages.isNotEmpty) {
        _assistantThreadMessages[sessionKey] = List<GatewayChatMessage>.from(
          normalizedRecord.messages,
        );
      }
    }
  }

  Future<void> _refreshSharedSingleAgentLocalSkillsCache({
    required bool forceRescan,
  }) async {
    if (!forceRescan && _singleAgentLocalSkillsHydrated) {
      return;
    }
    if (!forceRescan && await _restoreSharedSingleAgentLocalSkillsCache()) {
      return;
    }
    final existingRefresh = _singleAgentSharedSkillsRefreshInFlight;
    if (existingRefresh != null) {
      await existingRefresh;
      if (!forceRescan) {
        return;
      }
    }
    late final Future<void> refreshFuture;
    refreshFuture = () async {
      final sharedSkills = await _scanSingleAgentSharedSkillEntries();
      _singleAgentSharedImportedSkills = sharedSkills;
      _singleAgentLocalSkillsHydrated = true;
      await _persistSharedSingleAgentLocalSkillsCache();
    }();
    _singleAgentSharedSkillsRefreshInFlight = refreshFuture;
    try {
      await refreshFuture;
    } finally {
      if (identical(_singleAgentSharedSkillsRefreshInFlight, refreshFuture)) {
        _singleAgentSharedSkillsRefreshInFlight = null;
      }
    }
  }

  Future<void> ensureSharedSingleAgentLocalSkillsLoaded() async {
    if (_singleAgentLocalSkillsHydrated) {
      return;
    }
    await _refreshSharedSingleAgentLocalSkillsCache(forceRescan: false);
  }

  Future<void> _startupRefreshSharedSingleAgentLocalSkillsCache() async {
    await _refreshSharedSingleAgentLocalSkillsCache(forceRescan: true);
    if (_disposed) {
      return;
    }
    if (assistantExecutionTargetForSession(currentSessionKey) ==
        AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(currentSessionKey);
      return;
    }
    _notifyIfActive();
  }

  Future<List<AssistantThreadSkillEntry>> _singleAgentLocalSkillsForSession(
    String sessionKey,
  ) async {
    final workspaceSkills = await _scanSingleAgentWorkspaceSkillEntries(
      sessionKey,
    );
    return _mergeSingleAgentSkillEntries(
      groups: <List<AssistantThreadSkillEntry>>[
        _singleAgentSharedImportedSkills,
        workspaceSkills,
      ],
    );
  }

  List<AssistantThreadSkillEntry> _mergeSingleAgentSkillEntries({
    required List<List<AssistantThreadSkillEntry>> groups,
  }) {
    final merged = <String, AssistantThreadSkillEntry>{};
    for (final group in groups) {
      for (final skill in group) {
        final normalizedName = skill.label.trim().toLowerCase();
        if (normalizedName.isEmpty || merged.containsKey(normalizedName)) {
          continue;
        }
        merged[normalizedName] = skill;
      }
    }
    final entries = merged.values.toList(growable: false);
    entries.sort((left, right) => left.label.compareTo(right.label));
    return entries;
  }

  Future<bool> _restoreSharedSingleAgentLocalSkillsCache() async {
    try {
      final payload = await _store.loadSupportJson(
        _singleAgentLocalSkillsCacheRelativePath,
      );
      if (payload == null) {
        return false;
      }
      final schemaVersion = int.tryParse(
        payload['schemaVersion']?.toString() ?? '',
      );
      if (schemaVersion != _singleAgentLocalSkillsCacheSchemaVersion) {
        return false;
      }
      final skills = asList(payload['skills'])
          .map(asMap)
          .map(
            (item) => AssistantThreadSkillEntry.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .where((item) => item.key.trim().isNotEmpty && item.label.isNotEmpty)
          .toList(growable: false);
      if (skills.isEmpty) {
        _singleAgentSharedImportedSkills = const <AssistantThreadSkillEntry>[];
        _singleAgentLocalSkillsHydrated = false;
        return false;
      }
      _singleAgentSharedImportedSkills = skills;
      _singleAgentLocalSkillsHydrated = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistSharedSingleAgentLocalSkillsCache() async {
    try {
      await _store.saveSupportJson(
        _singleAgentLocalSkillsCacheRelativePath,
        <String, dynamic>{
          'schemaVersion': _singleAgentLocalSkillsCacheSchemaVersion,
          'savedAtMs': DateTime.now().millisecondsSinceEpoch.toDouble(),
          'skills': _singleAgentSharedImportedSkills
              .map((item) => item.toJson())
              .toList(growable: false),
        },
      );
    } catch (_) {
      // Best effort only for local cache persistence.
    }
  }

  Future<void> _replaceSingleAgentThreadSkills(
    String sessionKey,
    List<AssistantThreadSkillEntry> importedSkills,
  ) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final importedKeys = importedSkills.map((item) => item.key).toSet();
    final nextSelected =
        (_assistantThreadRecords[normalizedSessionKey]?.selectedSkillKeys ??
                const <String>[])
            .where(importedKeys.contains)
            .toList(growable: false);
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      importedSkills: importedSkills,
      selectedSkillKeys: nextSelected,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _notifyIfActive();
  }

  AssistantThreadSkillEntry _singleAgentSkillEntryFromAcp(
    Map<String, dynamic> item,
    SingleAgentProvider provider,
  ) {
    return AssistantThreadSkillEntry(
      key: item['skillKey']?.toString().trim().isNotEmpty == true
          ? item['skillKey'].toString().trim()
          : (item['name']?.toString().trim() ?? ''),
      label: item['name']?.toString().trim() ?? '',
      description: item['description']?.toString().trim() ?? '',
      source: item['source']?.toString().trim() ?? provider.providerId,
      sourcePath: item['path']?.toString().trim() ?? '',
      scope: item['scope']?.toString().trim().isNotEmpty == true
          ? item['scope'].toString().trim()
          : 'session',
      sourceLabel: item['sourceLabel']?.toString().trim().isNotEmpty == true
          ? item['sourceLabel'].toString().trim()
          : (item['source']?.toString().trim().isNotEmpty == true
                ? item['source'].toString().trim()
                : provider.label),
    );
  }

  bool _unsupportedAcpSkillsStatus(GatewayAcpException error) {
    final code = (error.code ?? '').trim();
    if (code == '-32601' || code == 'METHOD_NOT_FOUND') {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('unknown method') ||
        message.contains('method not found') ||
        message.contains('skills.status');
  }

  void _upsertAssistantThreadRecord(
    String sessionKey, {
    List<GatewayChatMessage>? messages,
    double? updatedAtMs,
    String? title,
    bool? archived,
    AssistantExecutionTarget? executionTarget,
    AssistantMessageViewMode? messageViewMode,
    List<AssistantThreadSkillEntry>? importedSkills,
    List<String>? selectedSkillKeys,
    String? assistantModelId,
    SingleAgentProvider? singleAgentProvider,
    String? gatewayEntryState,
    String? workspaceRef,
    WorkspaceRefKind? workspaceRefKind,
  }) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final existing = _assistantThreadRecords[normalizedSessionKey];
    final nextExecutionTarget =
        executionTarget ??
        existing?.executionTarget ??
        settings.assistantExecutionTarget;
    final nextImportedSkills =
        importedSkills ??
        existing?.importedSkills ??
        const <AssistantThreadSkillEntry>[];
    final importedKeys = nextImportedSkills.map((item) => item.key).toSet();
    final nextSelectedSkillKeys =
        (selectedSkillKeys ?? existing?.selectedSkillKeys ?? const <String>[])
            .where(importedKeys.contains)
            .toList(growable: false);
    final nextMessages =
        messages ??
        existing?.messages ??
        _assistantThreadMessages[normalizedSessionKey] ??
        const <GatewayChatMessage>[];
    final nextRecord = AssistantThreadRecord(
      sessionKey: normalizedSessionKey,
      messages: nextMessages,
      updatedAtMs:
          updatedAtMs ??
          existing?.updatedAtMs ??
          (nextMessages.isNotEmpty ? nextMessages.last.timestampMs : null),
      title: title ?? existing?.title ?? '',
      archived:
          archived ??
          existing?.archived ??
          isAssistantTaskArchived(normalizedSessionKey),
      executionTarget: nextExecutionTarget,
      messageViewMode:
          messageViewMode ??
          existing?.messageViewMode ??
          AssistantMessageViewMode.rendered,
      importedSkills: nextImportedSkills,
      selectedSkillKeys: nextSelectedSkillKeys,
      assistantModelId:
          assistantModelId ??
          existing?.assistantModelId ??
          _resolvedAssistantModelForTarget(nextExecutionTarget),
      singleAgentProvider:
          singleAgentProvider ??
          existing?.singleAgentProvider ??
          SingleAgentProvider.auto,
      gatewayEntryState:
          gatewayEntryState ??
          existing?.gatewayEntryState ??
          _gatewayEntryStateForTarget(nextExecutionTarget),
      workspaceRef:
          workspaceRef ??
          existing?.workspaceRef ??
          _defaultWorkspaceRefForSession(normalizedSessionKey),
      workspaceRefKind:
          workspaceRefKind ??
          existing?.workspaceRefKind ??
          _defaultWorkspaceRefKindForTarget(nextExecutionTarget),
    );
    _assistantThreadRecords[normalizedSessionKey] = nextRecord;
    if (messages != null) {
      _assistantThreadMessages[normalizedSessionKey] =
          List<GatewayChatMessage>.from(messages);
    }
    final snapshot = _assistantThreadRecords.values.toList(growable: false);
    final nextPersist = _assistantThreadPersistQueue.catchError((_) {}).then((
      _,
    ) async {
      if (_disposed) {
        return;
      }
      try {
        await _store.saveAssistantThreadRecords(snapshot);
      } catch (_) {
        // Assistant thread persistence is background best-effort. Keep the
        // in-memory session usable even when teardown or temp-directory
        // cleanup races with the durable write.
      }
    });
    _assistantThreadPersistQueue = nextPersist;
    unawaited(nextPersist);
  }

  Future<void> _setCurrentAssistantSessionKey(
    String sessionKey, {
    bool persistSelection = true,
  }) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (normalizedSessionKey.isEmpty) {
      return;
    }
    await _sessionsController.switchSession(normalizedSessionKey);
    if (persistSelection) {
      await _persistAssistantLastSessionKey(normalizedSessionKey);
    }
  }

  Future<void> _persistAssistantLastSessionKey(String sessionKey) async {
    if (_disposed) {
      return;
    }
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (normalizedSessionKey.isEmpty ||
        settings.assistantLastSessionKey == normalizedSessionKey) {
      return;
    }
    try {
      await saveSettings(
        settings.copyWith(assistantLastSessionKey: normalizedSessionKey),
        refreshAfterSave: false,
      );
    } catch (_) {
      // Best effort only during teardown-sensitive transitions.
    }
  }

  void _setAiGatewayStreamingText(String sessionKey, String text) {
    final key = _normalizedAssistantSessionKey(sessionKey);
    if (text.trim().isEmpty) {
      _aiGatewayStreamingTextBySession.remove(key);
    } else {
      _aiGatewayStreamingTextBySession[key] = text;
    }
    _notifyIfActive();
  }

  void _appendAiGatewayStreamingText(String sessionKey, String delta) {
    if (delta.isEmpty) {
      return;
    }
    final key = _normalizedAssistantSessionKey(sessionKey);
    final current = _aiGatewayStreamingTextBySession[key] ?? '';
    _aiGatewayStreamingTextBySession[key] = '$current$delta';
    _notifyIfActive();
  }

  void _clearAiGatewayStreamingText(String sessionKey) {
    final key = _normalizedAssistantSessionKey(sessionKey);
    if (_aiGatewayStreamingTextBySession.remove(key) != null) {
      _notifyIfActive();
    }
  }

  String _nextLocalMessageId() {
    _localMessageCounter += 1;
    return 'local-${DateTime.now().microsecondsSinceEpoch}-$_localMessageCounter';
  }

  Future<T> _enqueueThreadTurn<T>(String threadId, Future<T> Function() task) {
    final normalizedThreadId = _normalizedAssistantSessionKey(threadId);
    final previous =
        _assistantThreadTurnQueues[normalizedThreadId] ?? Future<void>.value();
    final completer = Completer<T>();
    late final Future<void> next;
    next = previous
        .catchError((_) {})
        .then((_) async {
          try {
            completer.complete(await task());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .whenComplete(() {
          if (identical(_assistantThreadTurnQueues[normalizedThreadId], next)) {
            _assistantThreadTurnQueues.remove(normalizedThreadId);
          }
        });
    _assistantThreadTurnQueues[normalizedThreadId] = next;
    return completer.future;
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
      return appText('无法连接到 LLM API。', 'Unable to reach the LLM API.');
    }
    if (error is HandshakeException) {
      return appText('LLM API TLS 握手失败。', 'LLM API TLS handshake failed.');
    }
    if (error is TimeoutException) {
      return appText('LLM API 请求超时。', 'LLM API request timed out.');
    }
    if (error is FormatException) {
      return appText(
        'LLM API 返回了无法解析的响应。',
        'LLM API returned an invalid response.',
      );
    }
    return error.toString();
  }

  String _formatAiGatewayHttpError(int statusCode, String detail) {
    final base = switch (statusCode) {
      400 => appText(
        'LLM API 请求无效 (400)',
        'LLM API rejected the request (400)',
      ),
      401 => appText(
        'LLM API 鉴权失败 (401)',
        'LLM API authentication failed (401)',
      ),
      403 => appText('LLM API 拒绝访问 (403)', 'LLM API denied access (403)'),
      404 => appText(
        'LLM API chat 接口不存在 (404)',
        'LLM API chat endpoint was not found (404)',
      ),
      429 => appText(
        'LLM API 限流 (429)',
        'LLM API rate limited the request (429)',
      ),
      >= 500 => appText(
        'LLM API 当前不可用 ($statusCode)',
        'LLM API is unavailable right now ($statusCode)',
      ),
      _ => appText(
        'LLM API 返回状态码 $statusCode',
        'LLM API responded with status $statusCode',
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
    final normalizedRuntimeMode =
        snapshot.codeAgentRuntimeMode == CodeAgentRuntimeMode.builtIn
        ? CodeAgentRuntimeMode.externalCli
        : snapshot.codeAgentRuntimeMode;
    _codexRuntimeWarning =
        snapshot.codeAgentRuntimeMode == CodeAgentRuntimeMode.builtIn
        ? appText(
            '内置 Codex 运行时当前仅保留为未来扩展位；已自动切换为 External Codex CLI。',
            'Built-in Codex runtime is reserved for a future release; XWorkmate switched back to External Codex CLI automatically.',
          )
        : null;
    final normalizedPath = snapshot.codexCliPath.trim();
    if (normalizedPath == snapshot.codexCliPath &&
        normalizedRuntimeMode == snapshot.codeAgentRuntimeMode) {
      return snapshot;
    }
    return snapshot.copyWith(
      codeAgentRuntimeMode: normalizedRuntimeMode,
      codexCliPath: normalizedPath,
    );
  }

  Future<void> _refreshAcpCapabilities({
    bool forceRefresh = false,
    bool persistMountTargets = false,
  }) async {
    GatewayAcpCapabilities capabilities;
    try {
      capabilities = await _gatewayAcpClient.loadCapabilities(
        forceRefresh: forceRefresh,
      );
    } catch (_) {
      capabilities = const GatewayAcpCapabilities.empty();
    }
    if (persistMountTargets && !_disposed) {
      final currentConfig = settings.multiAgent;
      final nextTargets = _mergeAcpCapabilitiesIntoMountTargets(
        currentConfig.mountTargets,
        capabilities,
      );
      final nextConfig = currentConfig.copyWith(mountTargets: nextTargets);
      if (jsonEncode(nextConfig.toJson()) !=
          jsonEncode(currentConfig.toJson())) {
        await _settingsController.saveSnapshot(
          settings.copyWith(multiAgent: nextConfig),
        );
        _multiAgentOrchestrator.updateConfig(nextConfig);
      }
    }
    _notifyIfActive();
  }

  Future<void> _refreshSingleAgentCapabilities({
    bool forceRefresh = false,
  }) async {
    final gatewayToken = await settingsController.loadGatewayToken();
    final next = <SingleAgentProvider, DirectSingleAgentCapabilities>{};
    for (final provider in configuredSingleAgentProviders) {
      final profile = settings.externalAcpEndpointForProvider(provider);
      if (!profile.enabled || profile.endpoint.trim().isEmpty) {
        next[provider] = const DirectSingleAgentCapabilities.unavailable(
          endpoint: '',
        );
        continue;
      }
      try {
        next[provider] = await _singleAgentAppServerClient.loadCapabilities(
          provider: provider,
          forceRefresh: forceRefresh,
          gatewayToken: gatewayToken,
        );
      } catch (_) {
        next[provider] = const DirectSingleAgentCapabilities.unavailable(
          endpoint: '',
        );
      }
    }
    _singleAgentCapabilitiesByProvider = next;
    if (!_disposed) {
      _notifyIfActive();
    }
  }

  Future<void> _refreshResolvedCodexCliPath() async {
    if (effectiveCodeAgentRuntimeMode != CodeAgentRuntimeMode.externalCli) {
      _resolvedCodexCliPath = null;
      return;
    }
    if (shouldBlockEmbeddedAgentLaunch(
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    )) {
      _resolvedCodexCliPath = null;
      return;
    }

    final configuredPath = configuredCodexCliPath;
    String? detectedPath;
    if (configuredPath.isNotEmpty) {
      try {
        if (await File(configuredPath).exists()) {
          detectedPath = configuredPath;
        }
      } catch (_) {
        detectedPath = null;
      }
    }
    detectedPath ??= await _runtimeCoordinator.codex.findCodexBinary();
    if (_disposed) {
      return;
    }
    _resolvedCodexCliPath = detectedPath;
  }

  List<ManagedMountTargetState> _mergeAcpCapabilitiesIntoMountTargets(
    List<ManagedMountTargetState> current,
    GatewayAcpCapabilities capabilities,
  ) {
    final source = current.isEmpty
        ? ManagedMountTargetState.defaults()
        : current;
    final providers = capabilities.providers
        .map((item) => item.providerId)
        .toSet();
    return source
        .map((item) {
          final available = switch (item.targetId) {
            'codex' => providers.contains('codex'),
            'opencode' => providers.contains('opencode'),
            'claude' => providers.contains('claude'),
            'gemini' => providers.contains('gemini'),
            'aris' => capabilities.multiAgent,
            'openclaw' => capabilities.multiAgent || capabilities.singleAgent,
            _ => false,
          };
          return item.copyWith(
            available: available,
            discoveryState: available ? 'ready' : 'unavailable',
            syncState: available ? item.syncState : 'idle',
            detail: available
                ? appText(
                    '来源：Gateway ACP capabilities',
                    'Source: Gateway ACP capabilities',
                  )
                : appText(
                    'Gateway ACP 未报告该能力。',
                    'Gateway ACP did not report this capability.',
                  ),
          );
        })
        .toList(growable: false);
  }

  String? _assistantWorkingDirectoryForSession(String sessionKey) {
    final candidate = assistantWorkspaceRefForSession(sessionKey).trim();
    if (candidate.isEmpty) {
      return null;
    }
    return candidate;
  }

  String? _resolveLocalAssistantWorkingDirectoryForSession(String sessionKey) {
    if (assistantWorkspaceRefKindForSession(sessionKey) !=
        WorkspaceRefKind.localPath) {
      return null;
    }
    final candidate = _assistantWorkingDirectoryForSession(sessionKey);
    if (candidate == null) {
      return null;
    }
    final directory = Directory(candidate);
    return directory.existsSync() ? directory.path : null;
  }

  void _registerCodexExternalProvider() {
    _runtimeCoordinator.registerExternalCodeAgent(
      ExternalCodeAgentProvider(
        id: 'codex',
        name: 'Codex ACP',
        command: 'xworkmate-agent-gateway',
        transport: ExternalAgentTransport.websocketJsonRpc,
        endpoint: '',
        defaultArgs: const <String>[],
        capabilities: const <String>[
          'chat',
          'code-edit',
          'gateway-bridge',
          'memory-sync',
          'single-agent',
          'multi-agent',
        ],
      ),
    );
  }

  CodeAgentNodeState _buildCodeAgentNodeState() {
    return CodeAgentNodeState(
      selectedAgentId: _agentsController.selectedAgentId,
      gatewayConnected: _runtime.isConnected,
      executionTarget: currentAssistantExecutionTarget,
      runtimeMode: effectiveCodeAgentRuntimeMode,
      bridgeEnabled: _isCodexBridgeEnabled,
      bridgeState: _codexCooperationState.name,
      preferredProviderId: 'codex',
      resolvedCodexCliPath: _resolvedCodexCliPath,
      configuredCodexCliPath: configuredCodexCliPath,
    );
  }

  GatewayMode _bridgeGatewayMode() {
    if (!_runtime.isConnected) {
      return GatewayMode.offline;
    }
    return switch (currentAssistantExecutionTarget) {
      AssistantExecutionTarget.singleAgent => GatewayMode.offline,
      AssistantExecutionTarget.local => GatewayMode.local,
      AssistantExecutionTarget.remote => GatewayMode.remote,
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
      sessions: sessions,
      cronJobs: _cronJobsController.items,
      currentSessionKey: _sessionsController.currentSessionKey,
      hasPendingRun: hasAssistantPendingRun,
      activeAgentName: _agentsController.activeAgentName,
    );
  }

  void _attachChildListeners() {
    _runtimeCoordinator.addListener(_relayChildChange);
    _settingsController.addListener(_handleSettingsControllerChange);
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
    _settingsController.removeListener(_handleSettingsControllerChange);
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

  void _handleSettingsControllerChange() {
    final previous = _lastObservedSettingsSnapshot;
    final current = settings;
    final previousJson = previous.toJsonString();
    final currentJson = current.toJsonString();
    if (currentJson == previousJson) {
      _notifyIfActive();
      return;
    }
    final hadDraftChanges =
        _settingsDraftInitialized &&
        (_settingsDraft.toJsonString() != previousJson ||
            _draftSecretValues.isNotEmpty);
    if (!_settingsDraftInitialized || !hadDraftChanges) {
      _settingsDraft = current;
      _settingsDraftInitialized = true;
      _settingsDraftStatusMessage = '';
    }
    _lastObservedSettingsSnapshot = current;
    _settingsObservationQueue = _settingsObservationQueue
        .then((_) async {
          await _handleObservedSettingsChange(
            previous: previous,
            current: current,
          );
        })
        .catchError((_) {});
    _notifyIfActive();
  }

  Future<void> _handleObservedSettingsChange({
    required SettingsSnapshot previous,
    required SettingsSnapshot current,
  }) async {
    if (_disposed) {
      return;
    }
    setActiveAppLanguage(current.appLanguage);
    _multiAgentOrchestrator.updateConfig(current.multiAgent);
    if (previous.codexCliPath != current.codexCliPath ||
        previous.codeAgentRuntimeMode != current.codeAgentRuntimeMode) {
      await _refreshResolvedCodexCliPath();
      _registerCodexExternalProvider();
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
    _notifyIfActive();
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

  Uri? _resolveSingleAgentEndpoint(SingleAgentProvider provider) {
    final endpoint = settings
        .externalAcpEndpointForProvider(provider)
        .endpoint
        .trim();
    if (endpoint.isEmpty) {
      return null;
    }
    final normalizedInput = endpoint.contains('://')
        ? endpoint
        : 'ws://$endpoint';
    final uri = Uri.tryParse(normalizedInput);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    final scheme = uri.scheme.trim().toLowerCase();
    if (scheme != 'ws' &&
        scheme != 'wss' &&
        scheme != 'http' &&
        scheme != 'https') {
      return null;
    }
    return uri;
  }

  Uri? _resolveGatewayAcpEndpoint() {
    final target = assistantExecutionTargetForSession(
      _sessionsController.currentSessionKey,
    );
    if (target == AssistantExecutionTarget.singleAgent) {
      final remote = _gatewayProfileBaseUri(
        settings.primaryRemoteGatewayProfile,
      );
      if (remote != null) {
        return remote;
      }
      return _gatewayProfileBaseUri(settings.primaryLocalGatewayProfile);
    }
    return _gatewayProfileBaseUri(
      _gatewayProfileForAssistantExecutionTarget(target),
    );
  }

  Uri? _gatewayProfileBaseUri(GatewayConnectionProfile profile) {
    final host = profile.host.trim();
    if (host.isEmpty || profile.port <= 0) {
      return null;
    }
    return Uri(
      scheme: profile.tls ? 'https' : 'http',
      host: host,
      port: profile.port,
    );
  }

  RuntimeConnectionMode _modeFromHost(String host) {
    final trimmed = host.trim().toLowerCase();
    if (_isLoopbackHost(trimmed)) {
      return RuntimeConnectionMode.local;
    }
    return RuntimeConnectionMode.remote;
  }

  bool _isLoopbackHost(String host) {
    final trimmed = host.trim().toLowerCase();
    return trimmed == '127.0.0.1' || trimmed == 'localhost';
  }

  AssistantExecutionTarget _assistantExecutionTargetForMode(
    RuntimeConnectionMode mode,
  ) {
    return switch (mode) {
      RuntimeConnectionMode.unconfigured =>
        AssistantExecutionTarget.singleAgent,
      RuntimeConnectionMode.local => AssistantExecutionTarget.local,
      RuntimeConnectionMode.remote => AssistantExecutionTarget.remote,
    };
  }

  GatewayConnectionProfile _gatewayProfileForAssistantExecutionTarget(
    AssistantExecutionTarget target,
  ) {
    return switch (target) {
      AssistantExecutionTarget.local => settings.primaryLocalGatewayProfile,
      AssistantExecutionTarget.remote => settings.primaryRemoteGatewayProfile,
      AssistantExecutionTarget.singleAgent => throw StateError(
        'Single Agent target has no OpenClaw gateway profile.',
      ),
    };
  }

  int _gatewayProfileIndexForExecutionTarget(AssistantExecutionTarget target) {
    return switch (target) {
      AssistantExecutionTarget.local => kGatewayLocalProfileIndex,
      AssistantExecutionTarget.remote => kGatewayRemoteProfileIndex,
      AssistantExecutionTarget.singleAgent => throw StateError(
        'Single Agent target has no OpenClaw gateway profile index.',
      ),
    };
  }
}

class _AiGatewayChatException implements Exception {
  const _AiGatewayChatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _AiGatewayAbortException implements Exception {
  const _AiGatewayAbortException(this.partialText);

  final String partialText;
}
