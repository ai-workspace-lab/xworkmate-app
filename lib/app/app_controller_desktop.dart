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
import '../runtime/single_agent_runner.dart';

enum CodexCooperationState { notStarted, bridgeOnly, registered }

class _SingleAgentSkillScanRoot {
  const _SingleAgentSkillScanRoot({
    required this.path,
    required this.source,
    required this.scope,
  });

  final String path;
  final String source;
  final String scope;
}

class AppController extends ChangeNotifier {
  static const List<_SingleAgentSkillScanRoot>
  _defaultGatewayOnlySkillScanRoots = <_SingleAgentSkillScanRoot>[
    _SingleAgentSkillScanRoot(
      path: '/etc/skills',
      source: 'system',
      scope: 'system',
    ),
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

  AppController({
    SecureConfigStore? store,
    RuntimeCoordinator? runtimeCoordinator,
    DesktopPlatformService? desktopPlatformService,
    UiFeatureManifest? uiFeatureManifest,
    List<String>? singleAgentLocalSkillScanRoots,
    List<SingleAgentProvider>? availableSingleAgentProvidersOverride,
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
    _singleAgentLocalSkillScanRoots =
        (singleAgentLocalSkillScanRoots ??
                (_isFlutterTestEnvironment ? const <String>[] : null))
            ?.map(_singleAgentSkillScanRootFromOverride)
            .toList(growable: false) ??
        _resolveDefaultSingleAgentSkillScanRoots();
    _gatewayAcpClient = GatewayAcpClient(
      endpointResolver: _resolveGatewayAcpEndpoint,
    );
    _singleAgentAppServerClient = DirectSingleAgentAppServerClient(
      endpointResolver: _resolveSingleAgentEndpoint,
    );
    _availableSingleAgentProvidersOverride =
        availableSingleAgentProvidersOverride;
    _arisBundleRepository = ArisBundleRepository();
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
  late final List<_SingleAgentSkillScanRoot> _singleAgentLocalSkillScanRoots;
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

  static bool get _isFlutterTestEnvironment =>
      Platform.environment.containsKey('FLUTTER_TEST');
  Future<void> _assistantThreadPersistQueue = Future<void>.value();

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

  List<SingleAgentProvider> get availableSingleAgentProviders =>
      (_availableSingleAgentProvidersOverride ?? kBuiltinExternalAcpProviders)
          .where((item) => item != SingleAgentProvider.auto)
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
      return _canUseSingleAgentProvider(selection) ? selection : null;
    }
    for (final provider in SingleAgentProvider.values) {
      if (provider == SingleAgentProvider.auto) {
        continue;
      }
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
    final imported =
        _assistantThreadRecords[normalizedSessionKey]?.importedSkills ??
        const <AssistantThreadSkillEntry>[];
    if (assistantExecutionTargetForSession(normalizedSessionKey) ==
        AssistantExecutionTarget.singleAgent) {
      if (imported.isNotEmpty) {
        return imported;
      }
      return _singleAgentSharedImportedSkills;
    }
    return imported;
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
    return sanitizeAppStoreSingleAgentProvider(
      _assistantThreadRecords[normalizedSessionKey]?.singleAgentProvider ??
          SingleAgentProvider.auto,
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    );
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
      const <SingleAgentProvider>[
        SingleAgentProvider.auto,
        ...kBuiltinExternalAcpProviders,
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
                _resolveCodexWorkingDirectory() ?? Directory.current.path,
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
  List<WorkspaceDestination> get assistantNavigationDestinations =>
      normalizeAssistantNavigationDestinations(
        settings.assistantNavigationDestinations,
      ).where(capabilities.supportsDestination).toList(growable: false);

  List<GatewayChatMessage> get chatMessages {
    final sessionKey = _normalizedAssistantSessionKey(
      _sessionsController.currentSessionKey,
    );
    final items = List<GatewayChatMessage>.from(
      isSingleAgentMode
          ? (_gatewayHistoryCache[sessionKey] ?? const <GatewayChatMessage>[])
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
      AssistantExecutionTarget.local ||
      AssistantExecutionTarget.singleAgent => settings.workspacePath.trim(),
    };
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
    if (existing != null &&
        existing.workspaceRef == nextWorkspaceRef &&
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
    final resolvedProfileIndex = _gatewayProfileIndexForExecutionTarget(
      _assistantExecutionTargetForMode(
        _modeFromHost(
          decoded?.host ?? settings.primaryRemoteGatewayProfile.host,
        ),
      ),
    );
    await _settingsController.saveGatewaySecrets(
      profileIndex: resolvedProfileIndex,
      token: resolvedToken,
      password: resolvedPassword,
    );
    final resolvedTarget = _assistantExecutionTargetForMode(
      _modeFromHost(decoded?.host ?? settings.primaryRemoteGatewayProfile.host),
    );
    final currentProfile = _gatewayProfileForAssistantExecutionTarget(
      resolvedTarget,
    );
    final nextProfile = currentProfile.copyWith(
      useSetupCode: true,
      setupCode: setupCode.trim(),
      host: decoded?.host ?? currentProfile.host,
      port: decoded?.port ?? currentProfile.port,
      tls: decoded?.tls ?? currentProfile.tls,
      mode: resolvedTarget == AssistantExecutionTarget.local
          ? RuntimeConnectionMode.local
          : RuntimeConnectionMode.remote,
    );
    await saveSettings(
      settings
          .copyWithGatewayProfileAt(
            _gatewayProfileIndexForExecutionTarget(resolvedTarget),
            nextProfile,
          )
          .copyWith(assistantExecutionTarget: resolvedTarget),
      refreshAfterSave: false,
    );
    _upsertAssistantThreadRecord(
      _sessionsController.currentSessionKey,
      executionTarget: resolvedTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _connectProfile(
      nextProfile,
      profileIndex: resolvedProfileIndex,
      authTokenOverride: resolvedToken,
      authPasswordOverride: resolvedPassword,
    );
    await _chatController.loadSession(_sessionsController.currentSessionKey);
  }

  Future<void> connectManual({
    required String host,
    required int port,
    required bool tls,
    required RuntimeConnectionMode mode,
    String token = '',
    String password = '',
  }) async {
    final nextTarget = _assistantExecutionTargetForMode(mode);
    final nextProfileIndex = _gatewayProfileIndexForExecutionTarget(nextTarget);
    await _settingsController.saveGatewaySecrets(
      profileIndex: nextProfileIndex,
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
    final nextProfile = _gatewayProfileForAssistantExecutionTarget(nextTarget)
        .copyWith(
          mode: mode,
          useSetupCode: false,
          setupCode: '',
          host: resolvedHost,
          port: resolvedPort <= 0 ? 443 : resolvedPort,
          tls: mode == RuntimeConnectionMode.local ? false : tls,
        );
    await saveSettings(
      settings
          .copyWithGatewayProfileAt(
            _gatewayProfileIndexForExecutionTarget(nextTarget),
            nextProfile,
          )
          .copyWith(assistantExecutionTarget: nextTarget),
      refreshAfterSave: false,
    );
    _upsertAssistantThreadRecord(
      _sessionsController.currentSessionKey,
      executionTarget: nextTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _connectProfile(
      nextProfile,
      profileIndex: nextProfileIndex,
      authTokenOverride: token.trim(),
      authPasswordOverride: password.trim(),
    );
    await _chatController.loadSession(_sessionsController.currentSessionKey);
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
      workspaceRef: _defaultWorkspaceRefForSession(nextSessionKey),
      workspaceRefKind: _defaultWorkspaceRefKindForTarget(nextTarget),
    );
    await _applyAssistantExecutionTarget(
      nextTarget,
      sessionKey: nextSessionKey,
      persistDefaultSelection: false,
    );
    if (nextTarget == AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentLocalSkillsForSession(nextSessionKey);
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
      workspaceRef: switch (resolvedTarget) {
        AssistantExecutionTarget.remote => settings.remoteProjectRoot.trim(),
        AssistantExecutionTarget.local ||
        AssistantExecutionTarget.singleAgent => settings.workspacePath.trim(),
      },
      workspaceRefKind: _defaultWorkspaceRefKindForTarget(resolvedTarget),
    );
    _recomputeTasks();
    _notifyIfActive();
    await _applyAssistantExecutionTarget(
      resolvedTarget,
      sessionKey: _sessionsController.currentSessionKey,
      persistDefaultSelection: true,
    );
    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentLocalSkillsForSession(
        _sessionsController.currentSessionKey,
      );
    }
    _recomputeTasks();
    _notifyIfActive();
  }

  Future<void> setSingleAgentProvider(SingleAgentProvider provider) async {
    final sessionKey = _normalizedAssistantSessionKey(currentSessionKey);
    final sanitizedProvider = sanitizeAppStoreSingleAgentProvider(
      provider,
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    );
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
      await refreshSingleAgentLocalSkillsForSession(sessionKey);
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
      workspaceRef: switch (resolvedTarget) {
        AssistantExecutionTarget.remote => settings.remoteProjectRoot.trim(),
        AssistantExecutionTarget.local ||
        AssistantExecutionTarget.singleAgent => settings.workspacePath.trim(),
      },
      workspaceRefKind: _defaultWorkspaceRefKindForTarget(resolvedTarget),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    unawaited(_persistAssistantLastSessionKey(normalizedSessionKey));
    _notifyIfActive();
  }

  Future<void> refreshSingleAgentLocalSkillsForSession(
    String sessionKey,
  ) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return;
    }

    final availableSkills = await _scanSingleAgentLocalSkillEntries();
    _singleAgentSharedImportedSkills = availableSkills;
    final importedKeys = availableSkills.map((item) => item.key).toSet();
    final refreshTargets = <String>{
      normalizedSessionKey,
      for (final entry in _assistantThreadRecords.entries)
        if (assistantExecutionTargetForSession(entry.key) ==
            AssistantExecutionTarget.singleAgent)
          entry.key,
    };
    final refreshedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    for (final targetSessionKey in refreshTargets) {
      final existingSelected =
          _assistantThreadRecords[targetSessionKey]?.selectedSkillKeys ??
          const <String>[];
      final nextSelected = existingSelected
          .where(importedKeys.contains)
          .toList(growable: false);
      _upsertAssistantThreadRecord(
        targetSessionKey,
        importedSkills: availableSkills,
        selectedSkillKeys: nextSelected,
        updatedAtMs: targetSessionKey == normalizedSessionKey
            ? refreshedAtMs
            : _assistantThreadRecords[targetSessionKey]?.updatedAtMs,
      );
    }
    _notifyIfActive();
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
    _saveSecretDraft(_draftAiGatewayApiKeyKey, value);
  }

  void saveVaultTokenDraft(String value) {
    _saveSecretDraft(_draftVaultTokenKey, value);
  }

  void saveOllamaCloudApiKeyDraft(String value) {
    _saveSecretDraft(_draftOllamaApiKeyKey, value);
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
    if (!capabilities.supportsDestination(destination)) {
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
    if (blocksAppStoreEmbeddedAgentProcesses(
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
      final runtimeMode = effectiveCodeAgentRuntimeMode;
      if (runtimeMode == CodeAgentRuntimeMode.externalCli &&
          !_canUseSingleAgentProvider(SingleAgentProvider.codex)) {
        throw StateError(
          appText(
            '外部 single-agent endpoint 未报告 Codex 可用，请先检查 app-server / Gateway 配置。',
            'The external single-agent endpoint did not report Codex availability. Check the app-server or Gateway endpoint first.',
          ),
        );
      }

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
      await _settingsController.initialize();
      _restoreAssistantThreads(await _store.loadAssistantThreadRecords());
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
      if (isSingleAgentMode) {
        await refreshSingleAgentLocalSkillsForSession(currentSessionKey);
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

  Future<void> _connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    await _runtime.connectProfile(
      profile,
      profileIndex: profileIndex,
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

  Future<void> _persistSettingsSnapshot(SettingsSnapshot snapshot) async {
    final sanitized = _sanitizeFeatureFlagSettings(
      _sanitizeMultiAgentSettings(
        _sanitizeOllamaCloudSettings(_sanitizeCodeAgentSettings(snapshot)),
      ),
    );
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
      await refreshSingleAgentLocalSkillsForSession(sessionKey);
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
    final allowedNavigation = normalizeAssistantNavigationDestinations(
      snapshot.assistantNavigationDestinations,
    ).where(features.allowedDestinations.contains).toList(growable: false);
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

  Future<void> _sendSingleAgentMessage(
    String message, {
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<CollaborationAttachment> localAttachments,
  }) async {
    final sessionKey = _normalizedAssistantSessionKey(
      _sessionsController.currentSessionKey,
    );
    final trimmed = message.trim();
    if (trimmed.isEmpty && attachments.isEmpty) {
      return;
    }
    await _enqueueThreadTurn<void>(sessionKey, () async {
      final userText = trimmed.isEmpty ? 'See attached.' : trimmed;
      _appendAssistantThreadMessage(
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
        final selection = singleAgentProviderForSession(sessionKey);
        final selectedSkills = assistantSelectedSkillsForSession(sessionKey);
        final gatewayToken = await settingsController.loadGatewayToken();
        final resolution = await _singleAgentRunner.resolveProvider(
          selection: selection,
          configuredCodexCliPath: configuredCodexCliPath,
          gatewayToken: gatewayToken,
        );
        final provider = resolution.resolvedProvider;
        if (provider == null) {
          if (singleAgentUsesAiChatFallbackForSession(sessionKey)) {
            _appendAssistantThreadMessage(
              sessionKey,
              GatewayChatMessage(
                id: _nextLocalMessageId(),
                role: 'assistant',
                text: _singleAgentFallbackLabel(resolution.fallbackReason),
                timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
                toolCallId: null,
                toolName: 'AI Chat fallback',
                stopReason: null,
                pending: false,
                error: false,
              ),
            );
            await _sendAiGatewayMessage(
              message,
              thinking: thinking,
              attachments: attachments,
              sessionKeyOverride: sessionKey,
              appendUserMessage: false,
              managePendingState: false,
            );
          } else {
            _appendAssistantThreadMessage(
              sessionKey,
              GatewayChatMessage(
                id: _nextLocalMessageId(),
                role: 'assistant',
                text: _singleAgentUnavailableLabel(
                  sessionKey,
                  resolution.fallbackReason,
                ),
                timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
                toolCallId: null,
                toolName: provider?.label ?? selection.label,
                stopReason: null,
                pending: false,
                error: false,
              ),
            );
          }
          return;
        }

        _appendAssistantThreadMessage(
          sessionKey,
          GatewayChatMessage(
            id: _nextLocalMessageId(),
            role: 'assistant',
            text: appText(
              '单机智能体已切换到 ${provider.label} 执行当前任务。',
              'Single Agent is using ${provider.label} for this task.',
            ),
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: provider.label,
            stopReason: null,
            pending: false,
            error: false,
          ),
        );
        _singleAgentExternalCliPendingSessionKeys.add(sessionKey);

        final result = await _singleAgentRunner.run(
          SingleAgentRunRequest(
            sessionId: sessionKey,
            provider: provider,
            prompt: message,
            model: assistantModelForSession(sessionKey),
            gatewayToken: gatewayToken,
            workingDirectory:
                _resolveCodexWorkingDirectory() ?? Directory.current.path,
            attachments: localAttachments,
            selectedSkills: selectedSkills,
            aiGatewayBaseUrl: aiGatewayUrl,
            aiGatewayApiKey: await loadAiGatewayApiKey(),
            config: settings.multiAgent,
            onOutput: (text) => _appendAiGatewayStreamingText(sessionKey, text),
            configuredCodexCliPath: configuredCodexCliPath,
          ),
        );
        final resolvedRuntimeModel = result.resolvedModel.trim();
        if (resolvedRuntimeModel.isNotEmpty) {
          _singleAgentRuntimeModelBySession[sessionKey] = resolvedRuntimeModel;
        }
        _clearAiGatewayStreamingText(sessionKey);
        if (result.aborted) {
          final partial = result.output.trim();
          if (partial.isNotEmpty) {
            _appendAssistantThreadMessage(
              sessionKey,
              GatewayChatMessage(
                id: _nextLocalMessageId(),
                role: 'assistant',
                text: partial,
                timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
                toolCallId: null,
                toolName: null,
                stopReason: 'aborted',
                pending: false,
                error: false,
              ),
            );
          }
          return;
        }
        if (result.shouldFallbackToAiChat) {
          if (singleAgentUsesAiChatFallbackForSession(sessionKey)) {
            _appendAssistantThreadMessage(
              sessionKey,
              GatewayChatMessage(
                id: _nextLocalMessageId(),
                role: 'assistant',
                text: _singleAgentFallbackLabel(
                  result.fallbackReason ?? result.errorMessage,
                ),
                timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
                toolCallId: null,
                toolName: 'AI Chat fallback',
                stopReason: null,
                pending: false,
                error: false,
              ),
            );
            await _sendAiGatewayMessage(
              message,
              thinking: thinking,
              attachments: attachments,
              sessionKeyOverride: sessionKey,
              appendUserMessage: false,
              managePendingState: false,
            );
          } else {
            _appendAssistantThreadMessage(
              sessionKey,
              GatewayChatMessage(
                id: _nextLocalMessageId(),
                role: 'assistant',
                text: _singleAgentUnavailableLabel(
                  sessionKey,
                  result.fallbackReason ?? result.errorMessage,
                ),
                timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
                toolCallId: null,
                toolName: provider.label,
                stopReason: null,
                pending: false,
                error: false,
              ),
            );
          }
          return;
        }

        if (!result.success) {
          _appendAssistantThreadMessage(
            sessionKey,
            _assistantErrorMessage(
              appText(
                '单机智能体执行失败：${result.errorMessage}',
                'Single Agent execution failed: ${result.errorMessage}',
              ),
            ),
          );
          return;
        }

        _appendAssistantThreadMessage(
          sessionKey,
          GatewayChatMessage(
            id: _nextLocalMessageId(),
            role: 'assistant',
            text: result.output,
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: false,
          ),
        );
      } catch (error) {
        _clearAiGatewayStreamingText(sessionKey);
        _appendAssistantThreadMessage(
          sessionKey,
          _assistantErrorMessage(error.toString()),
        );
      } finally {
        _singleAgentExternalCliPendingSessionKeys.remove(sessionKey);
        _clearAiGatewayStreamingText(sessionKey);
        _aiGatewayPendingSessionKeys.remove(sessionKey);
        _recomputeTasks();
        _notifyIfActive();
      }
    });
  }

  Future<void> _sendAiGatewayMessage(
    String message, {
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    String? sessionKeyOverride,
    bool appendUserMessage = true,
    bool managePendingState = true,
  }) async {
    final sessionKey = _normalizedAssistantSessionKey(
      sessionKeyOverride ?? _sessionsController.currentSessionKey,
    );
    final trimmed = message.trim();
    if (trimmed.isEmpty && attachments.isEmpty) {
      return;
    }

    final baseUrl = _normalizeAiGatewayBaseUrl(settings.aiGateway.baseUrl);
    if (baseUrl == null) {
      _appendAssistantThreadMessage(
        sessionKey,
        _assistantErrorMessage(
          appText(
            'LLM API Endpoint 未配置，无法发送对话。',
            'LLM API Endpoint is not configured, so the conversation could not be sent.',
          ),
        ),
      );
      return;
    }

    final apiKey = await loadAiGatewayApiKey();
    if (apiKey.isEmpty) {
      _appendAssistantThreadMessage(
        sessionKey,
        _assistantErrorMessage(
          appText(
            'LLM API Token 未配置，无法发送对话。',
            'LLM API Token is not configured, so the conversation could not be sent.',
          ),
        ),
      );
      return;
    }

    final model = resolvedAiGatewayModel;
    if (model.isEmpty) {
      _appendAssistantThreadMessage(
        sessionKey,
        _assistantErrorMessage(
          appText(
            '当前没有可用的 LLM API 对话模型。请先在 设置 -> 集成 中同步并选择可用模型。',
            'No LLM API chat model is available yet. Sync and select a supported model in Settings -> Integrations first.',
          ),
        ),
      );
      return;
    }

    if (appendUserMessage) {
      final userText = trimmed.isEmpty ? 'See attached.' : trimmed;
      _appendAssistantThreadMessage(
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
    }
    if (managePendingState) {
      _aiGatewayPendingSessionKeys.add(sessionKey);
      _recomputeTasks();
      _notifyIfActive();
    }

    try {
      final assistantText = await _requestAiGatewayCompletion(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        thinking: thinking,
        sessionKey: sessionKey,
      );
      _appendAssistantThreadMessage(
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
    } on _AiGatewayAbortException catch (error) {
      final partial = error.partialText.trim();
      if (partial.isNotEmpty) {
        _appendAssistantThreadMessage(
          sessionKey,
          GatewayChatMessage(
            id: _nextLocalMessageId(),
            role: 'assistant',
            text: partial,
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: null,
            stopReason: 'aborted',
            pending: false,
            error: false,
          ),
        );
      }
    } catch (error) {
      _appendAssistantThreadMessage(
        sessionKey,
        _assistantErrorMessage(_aiGatewayErrorLabel(error)),
      );
    } finally {
      _aiGatewayStreamingClients.remove(sessionKey);
      _clearAiGatewayStreamingText(sessionKey);
      if (managePendingState) {
        _aiGatewayPendingSessionKeys.remove(sessionKey);
        _recomputeTasks();
        _notifyIfActive();
      }
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
    _aiGatewayStreamingClients[sessionKey] = client;
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/event-stream, application/json',
      );
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set('x-api-key', apiKey);
      final payload = <String, dynamic>{
        'model': model,
        'stream': true,
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
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.transform(utf8.decoder).join();
        throw _AiGatewayChatException(
          _formatAiGatewayHttpError(
            response.statusCode,
            _extractAiGatewayErrorDetail(body),
          ),
        );
      }
      final contentType =
          response.headers.contentType?.mimeType.toLowerCase() ??
          response.headers
              .value(HttpHeaders.contentTypeHeader)
              ?.toLowerCase() ??
          '';
      if (contentType.contains('text/event-stream')) {
        final streamed = await _readAiGatewayStreamingResponse(
          response: response,
          sessionKey: sessionKey,
        );
        if (streamed.trim().isEmpty) {
          throw const FormatException('Missing assistant content');
        }
        return streamed.trim();
      }
      return await _readAiGatewayJsonCompletion(response);
    } catch (error) {
      if (_consumeAiGatewayAbort(sessionKey)) {
        throw _AiGatewayAbortException(
          _aiGatewayStreamingTextBySession[sessionKey] ?? '',
        );
      }
      rethrow;
    } finally {
      _aiGatewayStreamingClients.remove(sessionKey);
      client.close(force: true);
    }
  }

  List<Map<String, String>> _buildAiGatewayRequestMessages(String sessionKey) {
    final history = <GatewayChatMessage>[
      ...(_gatewayHistoryCache[sessionKey] ?? const <GatewayChatMessage>[]),
      ...(_assistantThreadMessages[sessionKey] ?? const <GatewayChatMessage>[]),
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

  Future<String> _readAiGatewayJsonCompletion(
    HttpClientResponse response,
  ) async {
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(_extractFirstJsonDocument(body));
    final assistantText = _extractAiGatewayAssistantText(decoded);
    if (assistantText.trim().isEmpty) {
      throw const FormatException('Missing assistant content');
    }
    return assistantText.trim();
  }

  Future<String> _readAiGatewayStreamingResponse({
    required HttpClientResponse response,
    required String sessionKey,
  }) async {
    final buffer = StringBuffer();
    final eventLines = <String>[];

    void processEvent(String payload) {
      final trimmed = payload.trim();
      if (trimmed.isEmpty) {
        return;
      }
      if (trimmed == '[DONE]') {
        return;
      }
      final deltaText = _extractAiGatewayStreamText(trimmed);
      if (deltaText.isEmpty) {
        return;
      }
      final current = buffer.toString();
      if (current.isEmpty || deltaText == current) {
        buffer
          ..clear()
          ..write(deltaText);
      } else if (deltaText.startsWith(current)) {
        buffer
          ..clear()
          ..write(deltaText);
      } else {
        buffer.write(deltaText);
      }
      _setAiGatewayStreamingText(sessionKey, buffer.toString());
    }

    await for (final line
        in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (_consumeAiGatewayAbort(sessionKey)) {
        throw _AiGatewayAbortException(buffer.toString());
      }
      if (line.isEmpty) {
        if (eventLines.isNotEmpty) {
          processEvent(eventLines.join('\n'));
          eventLines.clear();
        }
        continue;
      }
      if (line.startsWith('data:')) {
        eventLines.add(line.substring(5).trimLeft());
      }
    }

    if (eventLines.isNotEmpty) {
      processEvent(eventLines.join('\n'));
    }

    return buffer.toString();
  }

  String _extractAiGatewayStreamText(String payload) {
    final decoded = jsonDecode(_extractFirstJsonDocument(payload));
    final map = asMap(decoded);
    final choices = asList(map['choices']);
    if (choices.isNotEmpty) {
      final firstChoice = asMap(choices.first);
      final delta = asMap(firstChoice['delta']);
      final deltaContent = _extractAiGatewayContent(delta['content']);
      if (deltaContent.isNotEmpty) {
        return deltaContent;
      }
    }
    return _extractAiGatewayAssistantText(decoded);
  }

  Future<void> _abortAiGatewayRun(String sessionKey) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    _aiGatewayAbortedSessionKeys.add(normalizedSessionKey);
    final client = _aiGatewayStreamingClients.remove(normalizedSessionKey);
    if (client != null) {
      try {
        client.close(force: true);
      } catch (_) {
        // Best effort only.
      }
    }
    _aiGatewayPendingSessionKeys.remove(normalizedSessionKey);
    _clearAiGatewayStreamingText(normalizedSessionKey);
    _recomputeTasks();
    _notifyIfActive();
  }

  bool _consumeAiGatewayAbort(String sessionKey) {
    return _aiGatewayAbortedSessionKeys.remove(
      _normalizedAssistantSessionKey(sessionKey),
    );
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

  String _singleAgentFallbackLabel(String? reason) {
    final detail = reason?.trim() ?? '';
    return detail.isEmpty
        ? appText(
            '未发现可用的外部 Agent ACP 端点，已回退到 AI Chat。',
            'No external Agent ACP endpoint is available. Falling back to AI Chat.',
          )
        : appText(
            '外部 Agent ACP 连接不可用，已回退到 AI Chat：$detail',
            'External Agent ACP connection is unavailable. Falling back to AI Chat: $detail',
          );
  }

  String _singleAgentUnavailableLabel(String sessionKey, String? reason) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final detail = reason?.trim() ?? '';
    final selection = singleAgentProviderForSession(normalizedSessionKey);
    if (singleAgentShouldSuggestAutoSwitchForSession(normalizedSessionKey)) {
      return detail.isEmpty
          ? appText(
              '当前线程固定为 ${selection.label}，但它在这台设备上不可用。检测到其他外部 Agent ACP 端点时不会自动改线，可切到 Auto。',
              'This thread is pinned to ${selection.label}, but it is unavailable on this device. XWorkmate will not reroute to another external Agent ACP endpoint automatically. Switch to Auto instead.',
            )
          : appText(
              '当前线程固定为 ${selection.label}：$detail 检测到其他外部 Agent ACP 端点时不会自动改线，可切到 Auto。',
              'This thread is pinned to ${selection.label}: $detail XWorkmate will not reroute to another external Agent ACP endpoint automatically. Switch to Auto instead.',
            );
    }
    if (singleAgentNeedsAiGatewayConfigurationForSession(
      normalizedSessionKey,
    )) {
      return detail.isEmpty
          ? appText(
              '当前没有可用的外部 Agent ACP 端点，也没有可用的 AI Chat fallback。请先配置外部 Agent 连接，或配置 LLM API。',
              'No external Agent ACP endpoint is available, and AI Chat fallback is not configured. Configure an external Agent connection or configure LLM API first.',
            )
          : appText(
              '$detail 当前没有可用的外部 Agent ACP 端点，也没有可用的 AI Chat fallback。请先配置外部 Agent 连接，或配置 LLM API。',
              '$detail No external Agent ACP endpoint is available, and AI Chat fallback is not configured. Configure an external Agent connection or configure LLM API first.',
            );
    }
    return detail.isEmpty
        ? appText(
            '当前线程的外部 Agent ACP 连接尚未就绪。',
            'The external Agent ACP connection for this thread is not ready yet.',
          )
        : appText(
            '当前线程的外部 Agent ACP 连接尚未就绪：$detail',
            'The external Agent ACP connection for this thread is not ready yet: $detail',
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

  Future<List<AssistantThreadSkillEntry>>
  _scanSingleAgentLocalSkillEntries() async {
    final dedupedByName = <String, AssistantThreadSkillEntry>{};
    for (final rootSpec in _singleAgentLocalSkillScanRoots) {
      final root = Directory(_resolveSingleAgentSkillRootPath(rootSpec.path));
      if (!await root.exists()) {
        continue;
      }
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || entity.uri.pathSegments.last != 'SKILL.md') {
          continue;
        }
        final entry = await _skillEntryFromFile(entity, rootSpec);
        final normalizedName = entry.label.trim().toLowerCase();
        if (normalizedName.isEmpty) {
          continue;
        }
        dedupedByName[normalizedName] = entry;
      }
    }
    final entries = dedupedByName.values.toList(growable: false);
    entries.sort((left, right) => left.label.compareTo(right.label));
    return entries;
  }

  List<_SingleAgentSkillScanRoot> _resolveDefaultSingleAgentSkillScanRoots() {
    return _defaultGatewayOnlySkillScanRoots.toList(growable: false);
  }

  _SingleAgentSkillScanRoot _singleAgentSkillScanRootFromOverride(
    String rawPath,
  ) {
    final normalizedPath = rawPath.trim();
    final lowered = normalizedPath.toLowerCase();
    final workspacePath = settings.workspacePath.trim();
    final normalizedWorkspace = workspacePath.endsWith('/')
        ? workspacePath
        : '$workspacePath/';
    final inferredWorkspace =
        lowered.contains('/workspace/.agents/') ||
        lowered.contains('/workspace/.claude/') ||
        lowered.contains('/workspace/.codex/');
    final scope = normalizedPath.startsWith('/etc/')
        ? 'system'
        : (workspacePath.isNotEmpty &&
                  (normalizedPath == workspacePath ||
                      normalizedPath.startsWith(normalizedWorkspace)) ||
              inferredWorkspace ||
              lowered.startsWith('.agents/') ||
              lowered.startsWith('.claude/') ||
              lowered.startsWith('.codex/'))
        ? 'workspace'
        : 'user';
    return _SingleAgentSkillScanRoot(
      path: normalizedPath,
      source: _sourceForSkillRootPath(lowered),
      scope: scope,
    );
  }

  String _resolveSingleAgentSkillRootPath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return trimmed;
    }
    if (trimmed.startsWith('~/')) {
      final home = Platform.environment['HOME']?.trim() ?? '';
      return home.isEmpty ? trimmed : '$home/${trimmed.substring(2)}';
    }
    final workspacePath = settings.workspacePath.trim();
    if (workspacePath.isNotEmpty) {
      return '$workspacePath/$trimmed';
    }
    final home = Platform.environment['HOME']?.trim() ?? '';
    return home.isEmpty ? trimmed : '$home/$trimmed';
  }

  String _sourceForSkillRootPath(String path) {
    if (path.startsWith('/etc/skills')) {
      return 'system';
    }
    if (_pathContainsSourceToken(path, 'workbuddy')) {
      return 'workbuddy';
    }
    if (_pathContainsSourceToken(path, 'opencode')) {
      return 'opencode';
    }
    if (_pathContainsSourceToken(path, 'claude')) {
      return 'claude';
    }
    if (_pathContainsSourceToken(path, 'agents')) {
      return 'agents';
    }
    return 'codex';
  }

  bool _pathContainsSourceToken(String path, String token) {
    final pattern = RegExp('(^|[./_-])$token([./_-]|\$)');
    return pattern.hasMatch(path);
  }

  Future<AssistantThreadSkillEntry> _skillEntryFromFile(
    File file,
    _SingleAgentSkillScanRoot root,
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
    final rootPath = _resolveSingleAgentSkillRootPath(root.path);
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
    final archivedKeys = settings.assistantArchivedTaskKeys
        .map(_normalizedAssistantSessionKey)
        .toSet();
    for (final record in records) {
      final sessionKey = _normalizedAssistantSessionKey(record.sessionKey);
      if (sessionKey.isEmpty) {
        continue;
      }
      final titleFromSettings = assistantCustomTaskTitle(sessionKey);
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
        workspaceRef: record.workspaceRef.trim().isEmpty
            ? _defaultWorkspaceRefForSession(sessionKey)
            : record.workspaceRef.trim(),
        workspaceRefKind: record.workspaceRef.trim().isEmpty
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
      if ((normalizedRecord.executionTarget ??
                  settings.assistantExecutionTarget) ==
              AssistantExecutionTarget.singleAgent &&
          normalizedRecord.importedSkills.isNotEmpty) {
        _singleAgentSharedImportedSkills = normalizedRecord.importedSkills;
      }
    }
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
      workspaceRef: workspaceRef ?? existing?.workspaceRef ?? '',
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
    for (final provider in kBuiltinExternalAcpProviders) {
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
    if (blocksAppStoreEmbeddedAgentProcesses(
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

  String? _resolveCodexWorkingDirectory() {
    final candidate = settings.workspacePath.trim();
    if (candidate.isEmpty) {
      return null;
    }
    final directory = Directory(candidate);
    return directory.existsSync() ? directory.path : null;
  }

  void _registerCodexExternalProvider() {
    final endpoint = _resolveSingleAgentEndpoint(SingleAgentProvider.codex);
    _runtimeCoordinator.registerExternalCodeAgent(
      ExternalCodeAgentProvider(
        id: 'codex',
        name: 'Codex ACP',
        command: 'xworkmate-agent-gateway',
        transport: ExternalAgentTransport.websocketJsonRpc,
        endpoint: endpoint?.toString() ?? '',
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
