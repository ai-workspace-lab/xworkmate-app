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
import '../runtime/file_store_support.dart';
import '../runtime/runtime_bootstrap.dart';
import '../runtime/desktop_platform_service.dart';
import '../runtime/gateway_runtime.dart';
import '../runtime/account_runtime_client.dart';
import '../runtime/runtime_controllers.dart';
import '../runtime/runtime_models.dart';
import '../runtime/secret_store.dart';
import '../runtime/settings_store.dart';
import '../runtime/secure_config_store.dart';
import '../runtime/embedded_agent_launch_policy.dart';
import '../runtime/runtime_coordinator.dart';
import '../runtime/runtime_dispatch_resolver.dart';
import '../runtime/gateway_acp_client.dart';
import '../runtime/codex_runtime.dart';
import '../runtime/codex_config_bridge.dart';
import '../runtime/code_agent_node_orchestrator.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/desktop_thread_artifact_service.dart';
import '../runtime/external_code_agent_acp_desktop_transport.dart';
import '../runtime/go_task_service_client.dart';

import '../runtime/go_runtime_dispatch_desktop_client.dart';
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/platform_environment.dart';
import 'task_thread_repositories.dart';
import 'app_controller_openclaw_task_queue.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

enum CodexCooperationState { notStarted, bridgeOnly, registered }

class AppController extends ChangeNotifier {
  static const String draftAiGatewayApiKeyKeyInternal = 'ai_gateway_api_key';
  static const String draftVaultTokenKeyInternal = 'vault_token';
  static const String draftOllamaApiKeyKeyInternal = 'ollama_cloud_api_key';

  AppController({
    SecureConfigStore? store,
    RuntimeCoordinator? runtimeCoordinator,
    DesktopPlatformService? desktopPlatformService,
    UiFeatureManifest? uiFeatureManifest,
    List<SingleAgentProvider>? initialBridgeProviderCatalog,
    List<SingleAgentProvider>? initialGatewayProviderCatalog,
    List<AssistantExecutionTarget>? initialAvailableExecutionTargets,
    AccountRuntimeClient Function(String baseUrl)? accountClientFactory,
    Map<String, String>? environmentOverride,
    GoTaskServiceClient? goTaskServiceClient,
    RuntimeDispatchResolver? dispatchResolver,
  }) {
    environmentOverrideInternal = environmentOverride == null
        ? null
        : Map<String, String>.unmodifiable(environmentOverride);
    if (environmentOverrideInternal != null) {
      resolvedUserHomeDirectoryInternal =
          resolveUserHomeDirectoryFromControllerEnvironmentInternal(
            environmentOverrideInternal,
          );
    }
    storeInternal =
        store ??
        createDefaultSecureConfigStoreForControllerEnvironmentInternal(
          resolvedUserHomeDirectoryInternal,
          environmentOverride: environmentOverrideInternal,
        );
    uiFeatureManifestInternal =
        uiFeatureManifest ?? loadRepoUiFeatureManifestSyncInternal();
    hostUiFeaturePlatformInternal = Platform.isIOS || Platform.isAndroid
        ? UiFeaturePlatform.mobile
        : UiFeaturePlatform.desktop;
    settingsControllerInternal = SettingsController(
      storeInternal,
      accountClientFactory: accountClientFactory,
    );
    gatewayAcpClientInternal = GatewayAcpClient(
      endpointResolver: resolveGatewayAcpEndpointInternal,
      authorizationResolver: resolveGatewayAcpAuthorizationHeaderInternal,
    );

    final resolvedRuntimeCoordinator =
        runtimeCoordinator ??
        RuntimeCoordinator(
          gateway: GatewayRuntime(
            store: storeInternal,
            identityStore: DeviceIdentityStore(storeInternal),
            sessionClient: GatewayAcpRuntimeSessionClient(
              client: gatewayAcpClientInternal,
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
    agentsControllerInternal = GatewayAgentsController(
      runtimeCoordinatorInternal.gateway,
    );
    sessionsControllerInternal = GatewaySessionsController(
      runtimeCoordinatorInternal.gateway,
    );
    chatControllerInternal = GatewayChatController(
      runtimeCoordinatorInternal.gateway,
    );
    skillsControllerInternal = SkillsController(
      runtimeCoordinatorInternal.gateway,
    );
    modelsControllerInternal = ModelsController(
      runtimeCoordinatorInternal.gateway,
      settingsControllerInternal,
    );
    cronJobsControllerInternal = CronJobsController(
      runtimeCoordinatorInternal.gateway,
    );
    dogsControllerInternal = DevicesController(
      runtimeCoordinatorInternal.gateway,
    );
    devicesControllerInternal = dogsControllerInternal;
    tasksControllerInternal = DerivedTasksController();
    desktopPlatformServiceInternal =
        desktopPlatformService ?? createDesktopPlatformService();
    runtimeCoordinatorInternal.attachDispatchResolver(
      dispatchResolver ??
          GoRuntimeDispatchDesktopClient(
            client: gatewayAcpClientInternal,
            endpointResolver: resolveGatewayAcpEndpointInternal,
          ),
    );
    goTaskServiceClientInternal =
        goTaskServiceClient ??
        ExternalCodeAgentAcpDesktopTransport(
          client: gatewayAcpClientInternal,
          endpointResolver: resolveExternalAcpEndpointForTargetInternal,
          taskEndpointResolver: resolveExternalAcpEndpointForRequestInternal,
          recoveryMaxAttempts: 1800,
        );
    bridgeAgentProviderCatalogInternal = normalizeSingleAgentProviderList(
      initialBridgeProviderCatalog ?? const <SingleAgentProvider>[],
    );
    bridgeGatewayProviderCatalogInternal = normalizeSingleAgentProviderList(
      initialGatewayProviderCatalog ?? const <SingleAgentProvider>[],
    );
    bridgeAvailableExecutionTargetsInternal =
        initialAvailableExecutionTargets ?? const <AssistantExecutionTarget>[];
    bridgeCapabilitiesRefreshAttemptedInternal =
        bridgeAgentProviderCatalogInternal.isNotEmpty ||
        bridgeGatewayProviderCatalogInternal.isNotEmpty;

    attachChildListenersInternal();
    unawaited(initializeInternal());
  }

  @override
  void dispose() {
    if (disposedInternal) {
      return;
    }
    disposedInternal = true;
    for (final turn in openClawGatewayQueuedTurnsInternal) {
      turn.cancelled = true;
    }
    for (final turn in openClawGatewayActiveTurnsInternal.values) {
      turn.cancelled = true;
    }
    openClawGatewayQueuedTurnsInternal.clear();
    openClawGatewayQueuedTurnsBySessionInternal.clear();
    openClawGatewayActiveTurnsInternal.clear();
    runtimeEventsSubscriptionInternal?.cancel();
    detachChildListenersInternal();
    runtimeCoordinatorInternal.dispose();
    settingsControllerInternal.dispose();
    agentsControllerInternal.dispose();
    sessionsControllerInternal.dispose();
    chatControllerInternal.dispose();
    skillsControllerInternal.dispose();
    modelsControllerInternal.dispose();
    cronJobsControllerInternal.dispose();
    devicesControllerInternal.dispose();
    tasksControllerInternal.dispose();
    storeInternal.dispose();
    desktopPlatformServiceInternal.dispose();
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
  late final SkillsController skillsControllerInternal;
  late final ModelsController modelsControllerInternal;
  late final CronJobsController cronJobsControllerInternal;
  late final DevicesController devicesControllerInternal;
  late final DevicesController dogsControllerInternal;
  late final DerivedTasksController tasksControllerInternal;
  late final DesktopPlatformService desktopPlatformServiceInternal;
  late final GatewayAcpClient gatewayAcpClientInternal;
  late final GoTaskServiceClient goTaskServiceClientInternal;
  GoTaskServiceClient get goTaskServiceClientForTest =>
      goTaskServiceClientInternal;

  GatewayAcpClient get gatewayAcpClientForTest => gatewayAcpClientInternal;

  List<SingleAgentProvider> bridgeAgentProviderCatalogInternal =
      const <SingleAgentProvider>[];
  List<SingleAgentProvider> bridgeGatewayProviderCatalogInternal =
      const <SingleAgentProvider>[];
  List<AssistantExecutionTarget> bridgeAvailableExecutionTargetsInternal =
      const <AssistantExecutionTarget>[];
  bool bridgeCapabilitiesRefreshAttemptedInternal = false;
  String bridgeCapabilitiesRefreshErrorInternal = '';
  final Map<String, List<GatewayChatMessage>> assistantThreadMessagesInternal =
      <String, List<GatewayChatMessage>>{};
  late final DesktopTaskThreadRepository taskThreadRepositoryInternal =
      DesktopTaskThreadRepository(saveRecords: storeInternal.saveTaskThreads);
  final Map<String, List<GatewayChatMessage>> localSessionMessagesInternal =
      <String, List<GatewayChatMessage>>{};
  final Map<String, String> aiGatewayStreamingTextBySessionInternal =
      <String, String>{};
  final DesktopThreadArtifactService threadArtifactServiceInternal =
      DesktopThreadArtifactService();
  final Map<String, HttpClient> aiGatewayStreamingClientsInternal =
      <String, HttpClient>{};
  final Set<String> aiGatewayPendingSessionKeysInternal = <String>{};
  final Set<String> aiGatewayAbortedSessionKeysInternal = <String>{};
  final Map<String, Future<void>> assistantThreadTurnQueuesInternal =
      <String, Future<void>>{};
  final List<OpenClawGatewayQueuedTurnInternal>
  openClawGatewayQueuedTurnsInternal = <OpenClawGatewayQueuedTurnInternal>[];
  final Map<String, List<OpenClawGatewayQueuedTurnInternal>>
  openClawGatewayQueuedTurnsBySessionInternal =
      <String, List<OpenClawGatewayQueuedTurnInternal>>{};
  final Map<String, OpenClawGatewayQueuedTurnInternal>
  openClawGatewayActiveTurnsInternal =
      <String, OpenClawGatewayQueuedTurnInternal>{};

  int localMessageCounterInternal = 0;
  int assistantDraftSessionCounterInternal = 0;

  WorkspaceDestination destinationInternal = WorkspaceDestination.assistant;
  ThemeMode themeModeInternal = ThemeMode.light;
  AppSidebarState sidebarStateInternal = AppSidebarState.expanded;
  SettingsTab settingsTabInternal = SettingsTab.gateway;
  DetailPanelData? detailPanelInternal;
  AppUiState appUiStateInternal = AppUiState.defaults();
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
  Map<String, String>? environmentOverrideInternal;
  SettingsSnapshot lastObservedSettingsSnapshotInternal =
      SettingsSnapshot.defaults();
  Future<void> assistantThreadPersistQueueInternal = Future<void>.value();
  Future<void> settingsObservationQueueInternal = Future<void>.value();

  AppUiState get appUiState => appUiStateInternal;

  WorkspaceDestination get destination => destinationInternal;
  UiFeatureManifest get uiFeatureManifest => uiFeatureManifestInternal;
  AppCapabilities get capabilities => AppCapabilities.fromFeatureAccess(
    featuresFor(hostUiFeaturePlatformInternal),
  );
  ThemeMode get themeMode => themeModeInternal;
  AppSidebarState get sidebarState => sidebarStateInternal;
  SettingsTab get settingsTab => settingsTabInternal;
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

  bool get isCodexBridgeEnabled => isCodexBridgeEnabledInternal;
  bool isCodexBridgeEnabledInternal = false;
  bool isCodexBridgeBusyInternal = false;
  String? codexBridgeErrorInternal;
  CodexCooperationState codexCooperationStateInternal =
      CodexCooperationState.notStarted;
  SettingsController get settingsController => settingsControllerInternal;
  GatewayAgentsController get agentsController => agentsControllerInternal;
  GatewaySessionsController get sessionsController =>
      sessionsControllerInternal;
  GatewayChatController get chatController => chatControllerInternal;
  SkillsController get skillsController => skillsControllerInternal;
  ModelsController get modelsController => modelsControllerInternal;
  CronJobsController get cronJobsController => cronJobsControllerInternal;
  DevicesController get devicesController => devicesControllerInternal;
  DerivedTasksController get tasksController => tasksControllerInternal;
  DesktopIntegrationState get desktopIntegration =>
      desktopPlatformServiceInternal.state;
  bool get supportsDesktopIntegration => desktopIntegration.isSupported;
  bool get desktopPlatformBusy => _desktopPlatformBusyInternal;
  set desktopPlatformBusyInternal(bool value) {
    _desktopPlatformBusyInternal = value;
    notifyListeners();
  }

  bool _desktopPlatformBusyInternal = false;

  GatewayConnectionSnapshot get connection => runtimeInternal.snapshot;
  SettingsSnapshot get settings => settingsControllerInternal.snapshot;
  SettingsSnapshot get settingsDraft =>
      settingsDraftInitializedInternal ? settingsDraftInternal : settings;
  String get userHomeDirectory => resolvedUserHomeDirectoryInternal;
  String get settingsYamlPath => defaultUserSettingsFilePath() ?? '';
  bool get hasSettingsDraftChanges =>
      settingsDraft.toJsonString() != settings.toJsonString() ||
      draftSecretValuesInternal.isNotEmpty;
  bool get hasPendingSettingsApply => pendingSettingsApplyInternal;
  String get settingsDraftStatusMessage => settingsDraftStatusMessageInternal;
  List<GatewayAgentSummary> get agents => agentsControllerInternal.agents;
  List<GatewaySessionSummary> get sessions =>
      sessionsControllerInternal.sessions;
  List<GatewaySessionSummary> get assistantSessions =>
      assistantSessionsInternal();
  List<GatewaySessionSummary> get archivedAssistantSessions =>
      archivedAssistantSessionsInternal();
  List<GatewaySkillSummary> get skills => skillsControllerInternal.items;
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
  String get aiGatewayUrl =>
      settingsControllerInternal.effectiveAiGatewayBaseUrl.trim();
  bool get hasStoredAiGatewayApiKey =>
      settingsControllerInternal.hasEffectiveAiGatewayApiKey;
  CodeAgentRuntimeMode get effectiveCodeAgentRuntimeMode =>
      settings.codeAgentRuntimeMode;
  bool get hasAssistantPendingRun =>
      assistantSessionHasPendingRun(currentSessionKey);

  List<String> get aiGatewayConversationModelChoices {
    final availableModels =
        settingsControllerInternal.effectiveAiGatewayAvailableModels;
    final selected = settings.aiGateway.selectedModels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && availableModels.contains(item))
        .toList(growable: false);
    if (selected.isNotEmpty) return selected;
    return availableModels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  int get activeGatewayProfileIndexInternal =>
      gatewayProfileIndexForExecutionTargetInternal(
        currentAssistantExecutionTarget,
      );

  bool hasStoredGatewayTokenForProfile(int profileIndex) =>
      settingsControllerInternal.hasStoredGatewayTokenForProfile(profileIndex);

  bool hasStoredGatewayPasswordForProfile(int profileIndex) =>
      settingsControllerInternal.hasStoredGatewayPasswordForProfile(
        profileIndex,
      );

  List<SingleAgentProvider> get bridgeProviderCatalog =>
      normalizeSingleAgentProviderList(<SingleAgentProvider>[
        ...bridgeAgentProviderCatalogInternal,
        ...bridgeGatewayProviderCatalogInternal,
      ]);

  List<SingleAgentProvider> get assistantProviderCatalog =>
      normalizeSingleAgentProviderList(
        bridgeAgentProviderCatalogInternal.where(
          (provider) =>
              provider.providerId != kCanonicalGatewayProviderId &&
              !provider.supportedTargets.contains(
                AssistantExecutionTarget.gateway,
              ),
        ),
      );

  List<SingleAgentProvider> get gatewayProviderCatalog =>
      normalizeSingleAgentProviderList(<SingleAgentProvider>[
        ...bridgeGatewayProviderCatalogInternal,
        ...bridgeAgentProviderCatalogInternal.where(
          (provider) =>
              provider.providerId == kCanonicalGatewayProviderId ||
              provider.supportedTargets.contains(
                AssistantExecutionTarget.gateway,
              ),
        ),
      ]);

  List<AssistantExecutionTarget> get bridgeAvailableExecutionTargets {
    final targets = <AssistantExecutionTarget>[
      ...bridgeAvailableExecutionTargetsInternal,
    ];
    if (assistantProviderCatalog.isNotEmpty &&
        !targets.contains(AssistantExecutionTarget.agent)) {
      targets.add(AssistantExecutionTarget.agent);
    }
    if (gatewayProviderCatalog.isNotEmpty &&
        !targets.contains(AssistantExecutionTarget.gateway)) {
      targets.add(AssistantExecutionTarget.gateway);
    }
    return AssistantExecutionTarget.values
        .where(targets.contains)
        .toList(growable: false);
  }

  List<SingleAgentProvider> providerCatalogForExecutionTarget(
    AssistantExecutionTarget executionTarget,
  ) {
    final source = executionTarget.isGateway
        ? gatewayProviderCatalog
        : assistantProviderCatalog;
    if (executionTarget.isGateway) {
      return source
          .where(
            (provider) => provider.providerId == kCanonicalGatewayProviderId,
          )
          .toList(growable: false);
    }
    return source
        .where(
          (provider) =>
              provider.supportedTargets.isEmpty ||
              provider.supportedTargets.contains(executionTarget),
        )
        .toList(growable: false);
  }

  SingleAgentProvider resolveProviderForExecutionTarget(
    String? providerId, {
    required AssistantExecutionTarget executionTarget,
    bool defaultToCatalog = false,
  }) {
    final normalizedId = normalizeSingleAgentProviderId(providerId ?? '');
    final catalog = providerCatalogForExecutionTarget(executionTarget);

    if (normalizedId.isNotEmpty) {
      for (final p in catalog) {
        if (p.providerId == normalizedId) return p;
      }

      return SingleAgentProvider.unspecified;
    }
    return (defaultToCatalog && catalog.isNotEmpty)
        ? catalog.first
        : SingleAgentProvider.unspecified;
  }

  SingleAgentProvider assistantProviderForSession(String sessionKey) {
    final normalizedKey = normalizedAssistantSessionKeyInternal(sessionKey);
    final thread = taskThreadForSessionInternal(normalizedKey);
    final target = assistantExecutionTargetForSession(normalizedKey);
    return resolveProviderForExecutionTarget(
      thread?.executionBinding.providerId,
      executionTarget: target,
      defaultToCatalog: target.isGateway,
    );
  }

  UiFeatureManifest loadRepoUiFeatureManifestSyncInternal() {
    final file = File(UiFeatureManifest.assetPath);
    if (!file.existsSync()) {
      throw StateError(
        'UiFeatureManifest is required and "${UiFeatureManifest.assetPath}" is missing.',
      );
    }
    return UiFeatureManifest.fromYamlString(file.readAsStringSync());
  }

  List<AssistantExecutionTarget> visibleAssistantExecutionTargets(
    Iterable<AssistantExecutionTarget> supportedTargets,
  ) {
    final visible = compactAssistantExecutionTargets(supportedTargets);
    final bridgeVisible = bridgeAvailableExecutionTargets;
    if (bridgeVisible.isEmpty) return visible;
    return visible.where((item) => bridgeVisible.contains(item)).toList();
  }

  String resolvedAssistantModelForTargetInternal(
    AssistantExecutionTarget target,
  ) => resolvedDefaultModel.trim();

  void navigateTo(WorkspaceDestination destination) =>
      AppControllerDesktopNavigation(this).navigateTo(destination);

  void navigateHome() => AppControllerDesktopNavigation(this).navigateHome();

  void openSettings({SettingsTab tab = SettingsTab.gateway}) =>
      AppControllerDesktopNavigation(this).openSettings(tab: tab);

  void openDetail(DetailPanelData detailPanel) =>
      AppControllerDesktopNavigation(this).openDetail(detailPanel);

  Future<void> sendChatMessage(
    String message, {
    String? sessionKey,
    String thinking = 'off',
    List<GatewayChatAttachmentPayload> attachments = const [],
    List<CollaborationAttachment> localAttachments = const [],
    List<String> selectedSkillLabels = const [],
  }) => AppControllerDesktopThreadActions(this).sendChatMessage(
    message,
    sessionKey: sessionKey,
    thinking: thinking,
    attachments: attachments,
    localAttachments: localAttachments,
    selectedSkillLabels: selectedSkillLabels,
  );

  Future<bool> removeAssistantUserMessage(
    String sessionKey,
    String messageId,
  ) async => AppControllerDesktopThreadStorage(
    this,
  ).removeAssistantUserMessageInternal(sessionKey, messageId);

  Future<bool> updateAssistantUserMessage(
    String sessionKey,
    String messageId,
    String text,
  ) async => AppControllerDesktopThreadStorage(
    this,
  ).updateAssistantUserMessageInternal(sessionKey, messageId, text);

  double get assistantSkillCount => skills.length.toDouble();
  int get currentAssistantSkillCount => skills.length;
}

String resolveUserHomeDirectoryFromControllerEnvironmentInternal(
  Map<String, String>? environment,
) {
  if (environment == null) {
    return resolveUserHomeDirectory();
  }
  final resolved = resolveUserHomeDirectory(environment: environment);
  if (resolved.isNotEmpty) {
    return resolved;
  }
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    return Directory.systemTemp
        .createTempSync('xworkmate-test-home-$suffix-')
        .path;
  }
  return '';
}

SecureConfigStore
createDefaultSecureConfigStoreForControllerEnvironmentInternal(
  String resolvedUserHomeDirectory, {
  required Map<String, String>? environmentOverride,
}) {
  if (environmentOverride == null || resolvedUserHomeDirectory.trim().isEmpty) {
    return SecureConfigStore();
  }
  final supportRoot =
      defaultUserSettingsRootPath(
        environment: <String, String>{
          ...environmentOverride,
          'HOME': resolvedUserHomeDirectory,
        },
        operatingSystem: Platform.operatingSystem,
      ) ??
      '${resolvedUserHomeDirectory.trim()}/.xworkmate';
  return SecureConfigStore(
    appDataRootPathResolver: () async => supportRoot,
    supportRootPathResolver: () async => supportRoot,
    secretRootPathResolver: () async => '$supportRoot/secrets',
    enableSecureStorage: false,
  );
}
