// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/runtime_models.dart';
import '../web/web_acp_client.dart';
import '../web/web_ai_gateway_client.dart';
import '../web/web_artifact_proxy_client.dart';
import '../web/web_relay_gateway_client.dart';
import '../web/web_session_repository.dart';
import '../web/web_store.dart';
import '../web/web_workspace_controllers.dart';
import 'app_capabilities.dart';
import 'ui_feature_manifest.dart';
import 'app_controller_web_sessions.dart';
import 'app_controller_web_workspace.dart';
import 'app_controller_web_session_actions.dart';
import 'app_controller_web_gateway_config.dart';
import 'app_controller_web_gateway_relay.dart';
import 'app_controller_web_gateway_chat.dart';
import 'app_controller_web_helpers.dart';

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
  }) : storeInternal = store ?? WebStore(),
       uiFeatureManifestInternal =
           uiFeatureManifest ?? UiFeatureManifest.fallback(),
       aiGatewayClientInternal = aiGatewayClient ?? const WebAiGatewayClient(),
       acpClientInternal = acpClient ?? const WebAcpClient(),
       remoteSessionRepositoryBuilderInternal =
           remoteSessionRepositoryBuilder ??
           defaultRemoteSessionRepositoryInternal {
    relayClientInternal = relayClient ?? WebRelayGatewayClient(storeInternal);
    artifactProxyClientInternal = WebArtifactProxyClient(relayClientInternal);
    relayEventsSubscriptionInternal = relayClientInternal.events.listen(
      handleRelayEventInternal,
    );
    unawaited(initializeInternal());
  }

  final WebStore storeInternal;
  final UiFeatureManifest uiFeatureManifestInternal;
  final WebAiGatewayClient aiGatewayClientInternal;
  final WebAcpClient acpClientInternal;
  final RemoteWebSessionRepositoryBuilder
  remoteSessionRepositoryBuilderInternal;
  late final WebRelayGatewayClient relayClientInternal;
  late final WebArtifactProxyClient artifactProxyClientInternal;
  late final BrowserWebSessionRepository browserSessionRepositoryInternal =
      BrowserWebSessionRepository(storeInternal);

  late final StreamSubscription<GatewayPushEvent>
  relayEventsSubscriptionInternal;

  SettingsSnapshot settingsInternal = SettingsSnapshot.defaults();
  SettingsSnapshot settingsDraftInternal = SettingsSnapshot.defaults();
  ThemeMode themeModeInternal = ThemeMode.light;
  WorkspaceDestination destinationInternal = WorkspaceDestination.assistant;
  SettingsTab settingsTabInternal = SettingsTab.general;
  bool settingsDraftInitializedInternal = false;
  bool pendingSettingsApplyInternal = false;
  String settingsDraftStatusMessageInternal = '';
  final Map<String, String> draftSecretValuesInternal = <String, String>{};
  bool initializingInternal = true;
  String? bootstrapErrorInternal;
  bool relayBusyInternal = false;
  bool aiGatewayBusyInternal = false;
  bool acpBusyInternal = false;
  bool multiAgentRunPendingInternal = false;
  final Map<String, AssistantThreadRecord> threadRecordsInternal =
      <String, AssistantThreadRecord>{};
  final Set<String> pendingSessionKeysInternal = <String>{};
  final Map<String, String> streamingTextBySessionInternal = <String, String>{};
  final Map<String, Future<void>> threadTurnQueuesInternal =
      <String, Future<void>>{};
  final Map<String, String> singleAgentRuntimeModelBySessionInternal =
      <String, String>{};
  final WebTasksController tasksControllerInternal = WebTasksController();
  String currentSessionKeyInternal = '';
  String? lastAssistantErrorInternal;
  String webSessionApiTokenCacheInternal = '';
  String webSessionClientIdInternal = '';
  String sessionPersistenceStatusMessageInternal = '';
  WebAcpCapabilities acpCapabilitiesInternal = const WebAcpCapabilities.empty();
  List<GatewayAgentSummary> relayAgentsInternal = const <GatewayAgentSummary>[];
  List<GatewayInstanceSummary> relayInstancesInternal =
      const <GatewayInstanceSummary>[];
  List<GatewayConnectorSummary> relayConnectorsInternal =
      const <GatewayConnectorSummary>[];
  List<GatewayModelSummary> relayModelsInternal = const <GatewayModelSummary>[];
  List<GatewayCronJobSummary> relayCronJobsInternal =
      const <GatewayCronJobSummary>[];
  late final WebSkillsController skillsControllerInternal = WebSkillsController(
    refreshVisibleSkills,
  );

  UiFeatureManifest get uiFeatureManifest => uiFeatureManifestInternal;
  AppCapabilities get capabilities =>
      AppCapabilities.fromFeatureAccess(featuresFor(UiFeaturePlatform.web));
  WorkspaceDestination get destination => destinationInternal;
  SettingsTab get settingsTab => settingsTabInternal;
  ThemeMode get themeMode => themeModeInternal;
  bool get initializing => initializingInternal;
  String? get bootstrapError => bootstrapErrorInternal;
  SettingsSnapshot get settings => settingsInternal;
  SettingsSnapshot get settingsDraft => settingsDraftInitializedInternal
      ? settingsDraftInternal
      : settingsInternal;
  bool get supportsSkillDirectoryAuthorization => false;
  List<AuthorizedSkillDirectory> get authorizedSkillDirectories =>
      settingsInternal.authorizedSkillDirectories;
  List<String> get recommendedAuthorizedSkillDirectoryPaths => const <String>[
    '~/.agents/skills',
    '~/.codex/skills',
    '~/.workbuddy/skills',
  ];
  String get userHomeDirectory => '';
  String get settingsYamlPath => '';
  bool get hasSettingsDraftChanges =>
      settingsDraft.toJsonString() != settingsInternal.toJsonString() ||
      draftSecretValuesInternal.isNotEmpty;
  bool get hasPendingSettingsApply => pendingSettingsApplyInternal;
  String get settingsDraftStatusMessage => settingsDraftStatusMessageInternal;
  AppLanguage get appLanguage => settingsInternal.appLanguage;
  AssistantPermissionLevel get assistantPermissionLevel =>
      settingsInternal.assistantPermissionLevel;
  List<AssistantFocusEntry> get assistantNavigationDestinations =>
      settingsInternal.assistantNavigationDestinations
          .where(supportsAssistantFocusEntry)
          .toList(growable: false);
  bool supportsAssistantFocusEntry(AssistantFocusEntry entry) {
    final destination = entry.destination;
    if (destination != null) {
      return capabilities.supportsDestination(destination);
    }
    return capabilities.supportsDestination(WorkspaceDestination.settings);
  }

  GatewayConnectionSnapshot get connection => relayClientInternal.snapshot;
  bool get relayBusy => relayBusyInternal;
  bool get aiGatewayBusy => aiGatewayBusyInternal;
  bool get acpBusy => acpBusyInternal;
  bool get isMultiAgentRunPending => multiAgentRunPendingInternal;
  String? get lastAssistantError => lastAssistantErrorInternal;
  String get currentSessionKey => currentSessionKeyInternal;
  WebSessionPersistenceConfig get webSessionPersistence =>
      settingsInternal.webSessionPersistence;
  String get sessionPersistenceStatusMessage =>
      sessionPersistenceStatusMessageInternal;
  bool get supportsDesktopIntegration => false;
  WebTasksController get tasksController => tasksControllerInternal;
  WebSkillsController get skillsController => skillsControllerInternal;
  List<GatewayAgentSummary> get agents => relayAgentsInternal;
  List<GatewayInstanceSummary> get instances => relayInstancesInternal;
  List<GatewayConnectorSummary> get connectors => relayConnectorsInternal;
  List<GatewayCronJobSummary> get cronJobs => relayCronJobsInternal;
  String get selectedAgentId => '';
  String get activeAgentName {
    final current = relayAgentsInternal.where(
      (item) => item.name.trim().isNotEmpty,
    );
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
      WebStore.maskValue(
        (relayTokenByProfileInternal[profileIndex] ?? '').trim(),
      );
  String? storedRelayPasswordMaskForProfile(int profileIndex) =>
      WebStore.maskValue(
        (relayPasswordByProfileInternal[profileIndex] ?? '').trim(),
      );
  bool hasStoredGatewayTokenForProfile(int profileIndex) =>
      ((relayTokenByProfileInternal[profileIndex] ?? '').trim().isNotEmpty);
  bool hasStoredGatewayPasswordForProfile(int profileIndex) =>
      ((relayPasswordByProfileInternal[profileIndex] ?? '').trim().isNotEmpty);
  String? get storedRelayTokenMask => WebStore.maskValue(
    (relayTokenByProfileInternal[kGatewayRemoteProfileIndex] ?? '').trim(),
  );
  String? get storedRelayPasswordMask => WebStore.maskValue(
    (relayPasswordByProfileInternal[kGatewayRemoteProfileIndex] ?? '').trim(),
  );
  String? get storedAiGatewayApiKeyMask => WebStore.maskValue(
    aiGatewayApiKeyCacheInternal.trim().isEmpty
        ? ''
        : aiGatewayApiKeyCacheInternal,
  );
  String? get storedWebSessionApiTokenMask => WebStore.maskValue(
    webSessionApiTokenCacheInternal.trim().isEmpty
        ? ''
        : webSessionApiTokenCacheInternal,
  );
  bool get usesRemoteSessionPersistence =>
      webSessionPersistence.mode == WebSessionPersistenceMode.remote &&
      RemoteWebSessionRepository.normalizeBaseUrl(
            webSessionPersistence.remoteBaseUrl,
          ) !=
          null;

  final Map<int, String> relayTokenByProfileInternal = <int, String>{};
  final Map<int, String> relayPasswordByProfileInternal = <int, String>{};
  String aiGatewayApiKeyCacheInternal = '';

  static const String draftAiGatewayApiKeyKeyInternal = 'ai_gateway_api_key';
  static const String draftVaultTokenKeyInternal = 'vault_token';
  static const String draftOllamaApiKeyKeyInternal = 'ollama_cloud_api_key';

  UiFeatureAccess featuresFor(UiFeaturePlatform platform) {
    return uiFeatureManifestInternal.forPlatform(platform);
  }

  WebAcpCapabilities get acpCapabilities => acpCapabilitiesInternal;

  void notifyChangedInternal() {
    notifyListeners();
  }

  void recomputeDerivedWorkspaceStateInternal() {
    if (threadRecordsInternal.isEmpty) {
      currentSessionKeyInternal = '';
      tasksControllerInternal.recompute(
        threads: const <AssistantThreadRecord>[],
        cronJobs: relayCronJobsInternal,
        currentSessionKey: currentSessionKeyInternal,
        pendingSessionKeys: pendingSessionKeysInternal,
      );
      return;
    }

    if (currentSessionKeyInternal.trim().isEmpty ||
        !threadRecordsInternal.containsKey(currentSessionKeyInternal)) {
      final preferredSession = settingsInternal.assistantLastSessionKey.trim();
      if (preferredSession.isNotEmpty &&
          threadRecordsInternal.containsKey(preferredSession)) {
        currentSessionKeyInternal = preferredSession;
      } else {
        currentSessionKeyInternal = threadRecordsInternal.keys.first;
      }
    }

    tasksControllerInternal.recompute(
      threads: threadRecordsInternal.values.toList(growable: false),
      cronJobs: relayCronJobsInternal,
      currentSessionKey: currentSessionKeyInternal,
      pendingSessionKeys: pendingSessionKeysInternal,
    );
  }

  GatewaySkillSummary gatewaySkillFromThreadEntryInternal(
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

  Future<void> prepareForExit() async {
    // Web doesn't have native termination handling.
    // Best effort flush if session persistence is configured.
    if (usesRemoteSessionPersistence) {
      // Remote sessions are persisted server-side.
    }
  }

  Map<String, dynamic> desktopStatusSnapshot() {
    final runningTasks = tasksControllerInternal.running.length;
    final queuedTasks = tasksControllerInternal.queue.length;
    final failedTasks = tasksControllerInternal.failed.length;
    final scheduledTasks = tasksControllerInternal.scheduled.length;
    return <String, dynamic>{
      'connectionStatus': connection.status.name,
      'connectionLabel': connection.status.label,
      'runningTasks': runningTasks,
      'pausedTasks': 0,
      'timedOutTasks': 0,
      'queuedTasks': queuedTasks,
      'scheduledTasks': scheduledTasks,
      'failedTasks': failedTasks,
      'totalTasks': tasksControllerInternal.totalCount,
      'badgeCount': runningTasks + queuedTasks,
    };
  }

  @override
  void dispose() {
    unawaited(relayEventsSubscriptionInternal.cancel());
    unawaited(relayClientInternal.dispose());
    super.dispose();
  }
}
