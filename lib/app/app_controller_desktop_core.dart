// ignore_for_file: unused_import, unnecessary_import

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
import '../runtime/account_runtime_client.dart';
import '../runtime/runtime_controllers.dart';
import '../runtime/runtime_models.dart';
import '../runtime/secure_config_store.dart';
import '../runtime/embedded_agent_launch_policy.dart';
import '../runtime/runtime_coordinator.dart';
import '../runtime/gateway_acp_client.dart';
import '../runtime/codex_runtime.dart';
import '../runtime/codex_config_bridge.dart';
import '../runtime/code_agent_node_orchestrator.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/desktop_thread_artifact_service.dart';
import '../runtime/external_code_agent_acp_desktop_transport.dart';
import '../runtime/go_task_service_client.dart';
import '../runtime/go_task_service_desktop_service.dart';
import '../runtime/go_multi_agent_mount_desktop_client.dart';
import '../runtime/go_runtime_dispatch_desktop_client.dart';
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/multi_agent_mounts.dart';
import '../runtime/multi_agent_orchestrator.dart';
import '../runtime/platform_environment.dart';
import '../runtime/single_agent_capabilities.dart';
import '../runtime/skill_directory_access.dart';
import 'task_thread_repositories.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_single_agent.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

enum CodexCooperationState { notStarted, bridgeOnly, registered }

class SingleAgentSkillScanRootInternal {
  const SingleAgentSkillScanRootInternal({
    required this.path,
    required this.source,
    required this.scope,
    this.bookmark = '',
  });

  final String path;
  final String source;
  final String scope;
  final String bookmark;

  SingleAgentSkillScanRootInternal copyWith({
    String? path,
    String? source,
    String? scope,
    String? bookmark,
  }) {
    return SingleAgentSkillScanRootInternal(
      path: path ?? this.path,
      source: source ?? this.source,
      scope: scope ?? this.scope,
      bookmark: bookmark ?? this.bookmark,
    );
  }
}

const String singleAgentLocalSkillsCacheRelativePathInternal =
    'cache/single-agent-local-skills.json';
const int singleAgentLocalSkillsCacheSchemaVersionInternal = 4;

class AppController extends ChangeNotifier {
  static const List<SingleAgentSkillScanRootInternal>
  defaultSingleAgentGlobalSkillScanRootsInternal =
      <SingleAgentSkillScanRootInternal>[
        SingleAgentSkillScanRootInternal(
          path: '~/.agents/skills',
          source: 'agents',
          scope: 'user',
        ),
        SingleAgentSkillScanRootInternal(
          path: '~/.codex/skills',
          source: 'codex',
          scope: 'user',
        ),
        SingleAgentSkillScanRootInternal(
          path: '~/.workbuddy/skills',
          source: 'workbuddy',
          scope: 'user',
        ),
      ];
  static const List<SingleAgentSkillScanRootInternal>
  defaultSingleAgentWorkspaceSkillScanRootsInternal =
      <SingleAgentSkillScanRootInternal>[
        SingleAgentSkillScanRootInternal(
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
    AccountRuntimeClient Function(String baseUrl)? accountClientFactory,
    List<String>? singleAgentSharedSkillScanRootOverrides,
    List<SingleAgentProvider>? availableSingleAgentProvidersOverride,
    ArisBundleRepository? arisBundleRepository,
    GoTaskServiceClient? goTaskServiceClient,
    MultiAgentMountManager? multiAgentMountManager,
  }) {
    storeInternal = store ?? SecureConfigStore();
    uiFeatureManifestInternal =
        uiFeatureManifest ?? UiFeatureManifest.fallback();
    hostUiFeaturePlatformInternal = Platform.isIOS || Platform.isAndroid
        ? UiFeaturePlatform.mobile
        : UiFeaturePlatform.desktop;

    final resolvedRuntimeCoordinator =
        runtimeCoordinator ??
        RuntimeCoordinator(
          gateway: GatewayRuntime(
            store: storeInternal,
            identityStore: DeviceIdentityStore(storeInternal),
            allowDirectSocketFallbackOnSessionClientFailure:
                shouldBlockEmbeddedAgentLaunch(
                  isAppleHost: Platform.isIOS || Platform.isMacOS,
                ),
          ),
          codex: CodexRuntime(),
          configBridge: CodexConfigBridge(),
        );

    runtimeCoordinatorInternal = resolvedRuntimeCoordinator;
    codeAgentNodeOrchestratorInternal = CodeAgentNodeOrchestrator(
      runtimeCoordinatorInternal,
    );
    codeAgentBridgeRegistryInternal = AgentRegistry(
      runtimeCoordinatorInternal.gateway,
    );
    settingsControllerInternal = SettingsController(
      storeInternal,
      accountClientFactory: accountClientFactory,
    );
    agentsControllerInternal = GatewayAgentsController(
      runtimeCoordinatorInternal.gateway,
    );
    sessionsControllerInternal = GatewaySessionsController(
      runtimeCoordinatorInternal.gateway,
    );
    chatControllerInternal = GatewayChatController(
      runtimeCoordinatorInternal.gateway,
    );
    instancesControllerInternal = InstancesController(
      runtimeCoordinatorInternal.gateway,
    );
    skillsControllerInternal = SkillsController(
      runtimeCoordinatorInternal.gateway,
    );
    connectorsControllerInternal = ConnectorsController(
      runtimeCoordinatorInternal.gateway,
    );
    modelsControllerInternal = ModelsController(
      runtimeCoordinatorInternal.gateway,
      settingsControllerInternal,
    );
    cronJobsControllerInternal = CronJobsController(
      runtimeCoordinatorInternal.gateway,
    );
    devicesControllerInternal = DevicesController(
      runtimeCoordinatorInternal.gateway,
    );
    tasksControllerInternal = DerivedTasksController();
    desktopPlatformServiceInternal =
        desktopPlatformService ?? createDesktopPlatformService();
    skillDirectoryAccessServiceInternal =
        skillDirectoryAccessService ?? createSkillDirectoryAccessService();
    singleAgentSharedSkillScanRootOverridesInternal =
        singleAgentSharedSkillScanRootOverrides?.toList(growable: false);
    gatewayAcpClientInternal = GatewayAcpClient(
      endpointResolver: resolveGatewayAcpEndpointInternal,
      authorizationResolver: resolveSingleAgentAuthorizationHeaderInternal,
    );
    availableSingleAgentProvidersOverrideInternal =
        availableSingleAgentProvidersOverride;
    arisBundleRepositoryInternal =
        arisBundleRepository ?? ArisBundleRepository();
    goCoreLocatorInternal = GoCoreLocator();
    runtimeCoordinatorInternal.attachDispatchResolver(
      GoRuntimeDispatchDesktopClient(),
    );
    goTaskServiceClientInternal =
        goTaskServiceClient ??
        DesktopGoTaskService(
          gateway: runtimeCoordinatorInternal.gateway,
          acpTransport: ExternalCodeAgentAcpDesktopTransport(),
        );
    multiAgentOrchestratorInternal = MultiAgentOrchestrator(
      config: resolveMultiAgentConfigInternal(
        settingsControllerInternal.snapshot,
      ),
      arisBundleRepository: arisBundleRepositoryInternal,
      goCoreLocator: goCoreLocatorInternal,
    );
    multiAgentMountManagerInternal =
        multiAgentMountManager ??
        MultiAgentMountManager(
          arisBundleRepository: arisBundleRepositoryInternal,
          goCoreLocator: goCoreLocatorInternal,
          resolver: GoMultiAgentMountDesktopClient(),
        );

    attachChildListenersInternal();
    unawaited(initializeInternal());
  }

  @override
  void dispose() {
    if (disposedInternal) {
      return;
    }
    disposedInternal = true;
    unawaited(persistSharedSingleAgentLocalSkillsCacheInternal());
    runtimeEventsSubscriptionInternal?.cancel();
    detachChildListenersInternal();
    runtimeCoordinatorInternal.dispose();
    settingsControllerInternal.dispose();
    agentsControllerInternal.dispose();
    sessionsControllerInternal.dispose();
    chatControllerInternal.dispose();
    instancesControllerInternal.dispose();
    skillsControllerInternal.dispose();
    connectorsControllerInternal.dispose();
    modelsControllerInternal.dispose();
    cronJobsControllerInternal.dispose();
    devicesControllerInternal.dispose();
    tasksControllerInternal.dispose();
    storeInternal.dispose();
    desktopPlatformServiceInternal.dispose();
    unawaited(multiAgentMountManagerInternal.dispose());
    unawaited(goTaskServiceClientInternal.dispose());
    unawaited(gatewayAcpClientInternal.dispose());
    super.dispose();
  }

  late final SecureConfigStore storeInternal;
  late final UiFeatureManifest uiFeatureManifestInternal;
  late final UiFeaturePlatform hostUiFeaturePlatformInternal;

  late final RuntimeCoordinator runtimeCoordinatorInternal;
  late final CodeAgentNodeOrchestrator codeAgentNodeOrchestratorInternal;
  late final AgentRegistry codeAgentBridgeRegistryInternal;
  late final SettingsController settingsControllerInternal;
  late final GatewayAgentsController agentsControllerInternal;
  late final GatewaySessionsController sessionsControllerInternal;
  late final GatewayChatController chatControllerInternal;
  late final InstancesController instancesControllerInternal;
  late final SkillsController skillsControllerInternal;
  late final ConnectorsController connectorsControllerInternal;
  late final ModelsController modelsControllerInternal;
  late final CronJobsController cronJobsControllerInternal;
  late final DevicesController devicesControllerInternal;
  late final DerivedTasksController tasksControllerInternal;
  late final DesktopPlatformService desktopPlatformServiceInternal;
  late final SkillDirectoryAccessService skillDirectoryAccessServiceInternal;
  late final List<String>? singleAgentSharedSkillScanRootOverridesInternal;
  late final GatewayAcpClient gatewayAcpClientInternal;
  late final List<SingleAgentProvider>?
  availableSingleAgentProvidersOverrideInternal;
  late final ArisBundleRepository arisBundleRepositoryInternal;
  late final GoCoreLocator goCoreLocatorInternal;
  late final GoTaskServiceClient goTaskServiceClientInternal;
  late final MultiAgentOrchestrator multiAgentOrchestratorInternal;
  late final MultiAgentMountManager multiAgentMountManagerInternal;
  Map<SingleAgentProvider, SingleAgentCapabilities>
  singleAgentCapabilitiesByProviderInternal =
      const <SingleAgentProvider, SingleAgentCapabilities>{};
  List<SingleAgentProvider> bridgeAdvertisedProvidersInternal =
      const <SingleAgentProvider>[];
  final Map<String, List<GatewayChatMessage>> assistantThreadMessagesInternal =
      <String, List<GatewayChatMessage>>{};
  late final DesktopTaskThreadRepository taskThreadRepositoryInternal =
      DesktopTaskThreadRepository(saveRecords: storeInternal.saveTaskThreads);
  final Map<String, List<GatewayChatMessage>> localSessionMessagesInternal =
      <String, List<GatewayChatMessage>>{};
  final Map<String, List<GatewayChatMessage>> gatewayHistoryCacheInternal =
      <String, List<GatewayChatMessage>>{};
  final Map<String, String> aiGatewayStreamingTextBySessionInternal =
      <String, String>{};
  final Map<String, ExternalCodeAgentAcpSyncedProvider>
  syncedGoAgentProvidersInternal =
      <String, ExternalCodeAgentAcpSyncedProvider>{};
  final DesktopThreadArtifactService threadArtifactServiceInternal =
      DesktopThreadArtifactService();
  List<AssistantThreadSkillEntry> singleAgentSharedImportedSkillsInternal =
      const <AssistantThreadSkillEntry>[];
  bool singleAgentLocalSkillsHydratedInternal = false;
  Future<void>? singleAgentSharedSkillsRefreshInFlightInternal;
  final Map<String, HttpClient> aiGatewayStreamingClientsInternal =
      <String, HttpClient>{};
  final Set<String> aiGatewayPendingSessionKeysInternal = <String>{};
  final Set<String> aiGatewayAbortedSessionKeysInternal = <String>{};
  final Set<String> singleAgentExternalCliPendingSessionKeysInternal =
      <String>{};
  final Map<String, Future<void>> assistantThreadTurnQueuesInternal =
      <String, Future<void>>{};
  bool multiAgentRunPendingInternal = false;
  int localMessageCounterInternal = 0;

  WorkspaceDestination destinationInternal = WorkspaceDestination.assistant;
  ThemeMode themeModeInternal = ThemeMode.light;
  AppSidebarState sidebarStateInternal = AppSidebarState.expanded;
  ModulesTab modulesTabInternal = ModulesTab.nodes;
  SecretsTab secretsTabInternal = SecretsTab.vault;
  AiGatewayTab aiGatewayTabInternal = AiGatewayTab.models;
  SettingsTab settingsTabInternal = SettingsTab.general;
  SettingsDetailPage? settingsDetailInternal;
  SettingsNavigationContext? settingsNavigationContextInternal;
  DetailPanelData? detailPanelInternal;
  SettingsSnapshot settingsDraftInternal = SettingsSnapshot.defaults();
  SettingsSnapshot lastAppliedSettingsInternal = SettingsSnapshot.defaults();
  final Map<String, String> draftSecretValuesInternal = <String, String>{};
  bool settingsDraftInitializedInternal = false;
  bool pendingSettingsApplyInternal = false;
  bool pendingGatewayApplyInternal = false;
  bool pendingAiGatewayApplyInternal = false;
  String settingsDraftStatusMessageInternal = '';
  bool initializingInternal = true;
  String? bootstrapErrorInternal;
  String? startupTaskThreadWarningInternal;

  Map<String, TaskThread> get assistantThreadRecordsInternal =>
      taskThreadRepositoryInternal.recordsView;
  StreamSubscription<GatewayPushEvent>? runtimeEventsSubscriptionInternal;
  bool disposedInternal = false;
  String resolvedUserHomeDirectoryInternal = resolveUserHomeDirectory();
  SettingsSnapshot lastObservedSettingsSnapshotInternal =
      SettingsSnapshot.defaults();
  Future<void> assistantThreadPersistQueueInternal = Future<void>.value();
  Future<void> settingsObservationQueueInternal = Future<void>.value();

  List<SingleAgentSkillScanRootInternal>
  get singleAgentSharedSkillScanRootsInternal {
    final configuredRoots =
        (singleAgentSharedSkillScanRootOverridesInternal?.map(
          singleAgentSharedSkillScanRootFromOverrideInternal,
        ))?.toList(growable: false) ??
        defaultSingleAgentGlobalSkillScanRootsInternal;
    final authorizedByPath = <String, AuthorizedSkillDirectory>{
      for (final directory in settings.authorizedSkillDirectories)
        normalizeAuthorizedSkillDirectoryPath(directory.path): directory,
    };
    final resolvedRoots = <SingleAgentSkillScanRootInternal>[];
    final seenPaths = <String>{};
    for (final root in configuredRoots) {
      final resolvedPath = resolveSingleAgentSkillRootPathInternal(root.path);
      if (resolvedPath.isEmpty || !seenPaths.add(resolvedPath)) {
        continue;
      }
      final authorizedDirectory = authorizedByPath.remove(resolvedPath);
      final bookmark = authorizedDirectory?.bookmark.trim() ?? '';
      resolvedRoots.add(root.copyWith(bookmark: bookmark));
    }
    for (final directory in authorizedByPath.values) {
      resolvedRoots.add(
        singleAgentSharedSkillScanRootFromAuthorizedDirectoryInternal(
          directory,
        ),
      );
    }
    return resolvedRoots;
  }

  WorkspaceDestination get destination => destinationInternal;
  UiFeatureManifest get uiFeatureManifest => uiFeatureManifestInternal;
  AppCapabilities get capabilities => AppCapabilities.fromFeatureAccess(
    featuresFor(hostUiFeaturePlatformInternal),
  );
  ThemeMode get themeMode => themeModeInternal;
  AppSidebarState get sidebarState => sidebarStateInternal;
  ModulesTab get modulesTab => modulesTabInternal;
  SecretsTab get secretsTab => secretsTabInternal;
  AiGatewayTab get aiGatewayTab => aiGatewayTabInternal;
  SettingsTab get settingsTab => settingsTabInternal;
  SettingsDetailPage? get settingsDetail => settingsDetailInternal;
  SettingsNavigationContext? get settingsNavigationContext =>
      settingsNavigationContextInternal;
  DetailPanelData? get detailPanel => detailPanelInternal;
  bool get initializing => initializingInternal;
  String? get bootstrapError => bootstrapErrorInternal;
  String? get startupTaskThreadWarning => startupTaskThreadWarningInternal;

  void dismissStartupTaskThreadWarning() {
    if ((startupTaskThreadWarningInternal ?? '').trim().isEmpty) {
      return;
    }
    startupTaskThreadWarningInternal = null;
    notifyIfActiveInternal();
  }

  UiFeatureAccess featuresFor(UiFeaturePlatform platform) {
    final manifest = applyAppleAppStorePolicy(
      uiFeatureManifestInternal,
      hostPlatform: platform,
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    );
    return manifest.forPlatform(platform);
  }

  RuntimeCoordinator get runtimeCoordinator => runtimeCoordinatorInternal;
  GatewayRuntime get runtimeInternal => runtimeCoordinatorInternal.gateway;
  GatewayRuntime get runtime => runtimeInternal;

  /// Whether Codex bridge is enabled and configured
  bool get isCodexBridgeEnabled => isCodexBridgeEnabledInternal;
  bool isCodexBridgeEnabledInternal = false;
  bool isCodexBridgeBusyInternal = false;
  String? codexBridgeErrorInternal;
  String? codexRuntimeWarningInternal;
  String? resolvedCodexCliPathInternal;
  CodexCooperationState codexCooperationStateInternal =
      CodexCooperationState.notStarted;
  SettingsController get settingsController => settingsControllerInternal;
  GatewayAgentsController get agentsController => agentsControllerInternal;
  GatewaySessionsController get sessionsController =>
      sessionsControllerInternal;
  MultiAgentOrchestrator get multiAgentOrchestrator =>
      multiAgentOrchestratorInternal;
  MultiAgentMountManager get multiAgentMountManager =>
      multiAgentMountManagerInternal;
  GatewayChatController get chatController => chatControllerInternal;
  InstancesController get instancesController => instancesControllerInternal;
  SkillsController get skillsController => skillsControllerInternal;
  ConnectorsController get connectorsController => connectorsControllerInternal;
  ModelsController get modelsController => modelsControllerInternal;
  CronJobsController get cronJobsController => cronJobsControllerInternal;
  DevicesController get devicesController => devicesControllerInternal;
  DerivedTasksController get tasksController => tasksControllerInternal;
  DesktopIntegrationState get desktopIntegration =>
      desktopPlatformServiceInternal.state;
  bool get supportsDesktopIntegration => desktopIntegration.isSupported;
  bool get desktopPlatformBusy => desktopPlatformBusyInternal;

  GatewayConnectionSnapshot get connection => runtimeInternal.snapshot;
  SettingsSnapshot get settings => settingsControllerInternal.snapshot;
  SettingsSnapshot get settingsDraft =>
      settingsDraftInitializedInternal ? settingsDraftInternal : settings;
  bool get supportsSkillDirectoryAuthorization =>
      skillDirectoryAccessServiceInternal.isSupported;
  List<AuthorizedSkillDirectory> get authorizedSkillDirectories =>
      settings.authorizedSkillDirectories;
  List<String> get recommendedAuthorizedSkillDirectoryPaths =>
      defaultSingleAgentGlobalSkillScanRootsInternal
          .map((item) => item.path)
          .toList(growable: false);
  String get userHomeDirectory => resolvedUserHomeDirectoryInternal;
  String get settingsYamlPath => defaultUserSettingsFilePath() ?? '';
  bool get hasSettingsDraftChanges =>
      settingsDraft.toJsonString() != settings.toJsonString() ||
      draftSecretValuesInternal.isNotEmpty;
  bool get hasPendingSettingsApply => pendingSettingsApplyInternal;
  String get settingsDraftStatusMessage => settingsDraftStatusMessageInternal;
  List<GatewayAgentSummary> get agents => agentsControllerInternal.agents;
  List<GatewaySessionSummary> get sessions => isSingleAgentMode
      ? assistantSessionSummariesInternal()
      : sessionsControllerInternal.sessions;
  List<GatewaySessionSummary> get assistantSessions =>
      assistantSessionsInternal();
  List<GatewayInstanceSummary> get instances =>
      instancesControllerInternal.items;
  List<GatewaySkillSummary> get skills => skillsControllerInternal.items;
  List<GatewayConnectorSummary> get connectors =>
      connectorsControllerInternal.items;
  List<GatewayModelSummary> get models => modelsControllerInternal.items;
  List<GatewayCronJobSummary> get cronJobs => cronJobsControllerInternal.items;
  GatewayDevicePairingList get devices => devicesControllerInternal.items;
  String get selectedAgentId => agentsControllerInternal.selectedAgentId;
  String get activeAgentName => agentsControllerInternal.activeAgentName;
  String get currentSessionKey => sessionsControllerInternal.currentSessionKey;
  String? get activeRunId => chatControllerInternal.activeRunId;
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
      hasStoredGatewayTokenForProfile(activeGatewayProfileIndexInternal) ||
      hasStoredGatewayPasswordForProfile(activeGatewayProfileIndexInternal) ||
      settingsControllerInternal.secureRefs.containsKey(
        'gateway_device_token_operator',
      );
  bool get hasStoredGatewayToken =>
      hasStoredGatewayTokenForProfile(activeGatewayProfileIndexInternal);
  String? get storedGatewayTokenMask =>
      storedGatewayTokenMaskForProfile(activeGatewayProfileIndexInternal);
  String get aiGatewayUrl =>
      settingsControllerInternal.effectiveAiGatewayBaseUrl.trim();
  bool get hasStoredAiGatewayApiKey =>
      settingsControllerInternal.hasEffectiveAiGatewayApiKey;
  bool get isSingleAgentMode =>
      currentAssistantExecutionTarget == AssistantExecutionTarget.singleAgent;
  bool get isCodexBridgeBusy => isCodexBridgeBusyInternal;
  String? get codexBridgeError => codexBridgeErrorInternal;
  String? get codexRuntimeWarning => codexRuntimeWarningInternal;
  String? get resolvedCodexCliPath => resolvedCodexCliPathInternal;
  bool get hasDetectedCodexCli => resolvedCodexCliPathInternal != null;
  String get configuredCodexCliPath => settings.codexCliPath.trim();
  CodeAgentRuntimeMode get configuredCodeAgentRuntimeMode =>
      settings.codeAgentRuntimeMode;
  CodeAgentRuntimeMode get effectiveCodeAgentRuntimeMode =>
      configuredCodeAgentRuntimeMode;
  CodexCooperationState get codexCooperationState =>
      codexCooperationStateInternal;
  bool get isMultiAgentRunPending => multiAgentRunPendingInternal;
  bool get showsSingleAgentRuntimeDebugMessagesInternal =>
      settings.experimentalDebug;
  bool desktopPlatformBusyInternal = false;

  static const String draftAiGatewayApiKeyKeyInternal = 'ai_gateway_api_key';
  static const String draftVaultTokenKeyInternal = 'vault_token';
  static const String draftOllamaApiKeyKeyInternal = 'ollama_cloud_api_key';

  bool get hasAssistantPendingRun =>
      assistantSessionHasPendingRun(currentSessionKey);

  bool get canUseAiGatewayConversation =>
      aiGatewayUrl.isNotEmpty &&
      hasStoredAiGatewayApiKey &&
      resolvedAiGatewayModel.isNotEmpty;

  int get activeGatewayProfileIndexInternal {
    final target = currentAssistantExecutionTarget;
    if (target == AssistantExecutionTarget.singleAgent) {
      return kGatewayRemoteProfileIndex;
    }
    return gatewayProfileIndexForExecutionTargetInternal(target);
  }

  bool hasStoredGatewayTokenForProfile(int profileIndex) =>
      settingsControllerInternal.hasStoredGatewayTokenForProfile(profileIndex);

  bool hasStoredGatewayPasswordForProfile(int profileIndex) =>
      settingsControllerInternal.hasStoredGatewayPasswordForProfile(
        profileIndex,
      );

  String? storedGatewayTokenMaskForProfile(int profileIndex) =>
      settingsControllerInternal.storedGatewayTokenMaskForProfile(profileIndex);

  String? storedGatewayPasswordMaskForProfile(int profileIndex) =>
      settingsControllerInternal.storedGatewayPasswordMaskForProfile(
        profileIndex,
      );

  List<SingleAgentProvider> get configuredSingleAgentProviders =>
      normalizeSingleAgentProviderList(
        (availableSingleAgentProvidersOverrideInternal ??
                bridgeAdvertisedProvidersInternal)
            .where((item) => item != SingleAgentProvider.auto)
            .map(settings.resolveSingleAgentProvider),
      );

  List<SingleAgentProvider> get availableSingleAgentProviders =>
      configuredSingleAgentProviders
          .where(canUseSingleAgentProviderInternal)
          .toList(growable: false);

  List<AssistantExecutionTarget> visibleAssistantExecutionTargets(
    Iterable<AssistantExecutionTarget> supportedTargets,
  ) {
    final visible = settings.visibleAssistantExecutionTargets(
      supportedTargets: supportedTargets,
      availableSingleAgentProviders: availableSingleAgentProviders,
    );
    if (!supportedTargets.contains(AssistantExecutionTarget.singleAgent) ||
        visible.contains(AssistantExecutionTarget.singleAgent)) {
      return visible;
    }
    return <AssistantExecutionTarget>[
      AssistantExecutionTarget.singleAgent,
      ...visible.where(
        (target) => target != AssistantExecutionTarget.singleAgent,
      ),
    ];
  }

  bool get hasAnyAvailableSingleAgentProvider =>
      availableSingleAgentProviders.isNotEmpty;

  bool canUseSingleAgentProviderInternal(SingleAgentProvider provider) {
    final override = availableSingleAgentProvidersOverrideInternal;
    if (override != null) {
      return provider != SingleAgentProvider.auto &&
          override.contains(provider);
    }
    if (provider == SingleAgentProvider.auto) {
      return hasAnyAvailableSingleAgentProvider;
    }
    final capabilities = singleAgentCapabilitiesByProviderInternal[provider];
    return capabilities?.available == true &&
        capabilities!.supportsProvider(provider);
  }

  SingleAgentProvider? resolvedSingleAgentProviderInternal(
    SingleAgentProvider selection,
  ) {
    if (selection != SingleAgentProvider.auto) {
      final resolvedSelection = settings.resolveSingleAgentProvider(selection);
      return canUseSingleAgentProviderInternal(resolvedSelection)
          ? resolvedSelection
          : null;
    }
    for (final provider in configuredSingleAgentProviders) {
      if (canUseSingleAgentProviderInternal(provider)) {
        return provider;
      }
    }
    return null;
  }

  List<String> get aiGatewayConversationModelChoices {
    final availableModels =
        settingsControllerInternal.effectiveAiGatewayAvailableModels;
    final selected = settings.aiGateway.selectedModels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && availableModels.contains(item))
        .toList(growable: false);
    if (selected.isNotEmpty) {
      return selected;
    }
    final available = availableModels
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

  String resolvedAssistantModelForTargetInternal(
    AssistantExecutionTarget target,
  ) {
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
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    return assistantThreadRecordsInternal[normalizedSessionKey]
            ?.importedSkills ??
        const <AssistantThreadSkillEntry>[];
  }

  // Keep these public navigation APIs as class members for cross-library callers.
  void navigateTo(WorkspaceDestination destination) =>
      AppControllerDesktopNavigation(this).navigateTo(destination);

  void navigateHome() => AppControllerDesktopNavigation(this).navigateHome();

  void openModules({ModulesTab tab = ModulesTab.nodes}) =>
      AppControllerDesktopNavigation(this).openModules(tab: tab);

  void openSettings({
    SettingsTab tab = SettingsTab.gateway,
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
