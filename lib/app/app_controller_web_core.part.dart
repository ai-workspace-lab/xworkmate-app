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

  AssistantExecutionTarget assistantExecutionTargetForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final recordTarget = _sanitizeTarget(
      _threadRecords[normalizedSessionKey]?.executionTarget,
    );
    final fallback = _sanitizeTarget(_settings.assistantExecutionTarget);
    return recordTarget ?? fallback ?? AssistantExecutionTarget.singleAgent;
  }

  AssistantExecutionTarget get assistantExecutionTarget =>
      assistantExecutionTargetForSession(_currentSessionKey);
  AssistantExecutionTarget get currentAssistantExecutionTarget =>
      assistantExecutionTarget;
  bool get isSingleAgentMode =>
      assistantExecutionTarget == AssistantExecutionTarget.singleAgent;

  AssistantMessageViewMode assistantMessageViewModeForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    return _threadRecords[normalizedSessionKey]?.messageViewMode ??
        AssistantMessageViewMode.rendered;
  }

  AssistantMessageViewMode get currentAssistantMessageViewMode =>
      assistantMessageViewModeForSession(_currentSessionKey);

  String assistantWorkspaceRefForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final recordRef =
        _threadRecords[normalizedSessionKey]?.workspaceRef.trim() ?? '';
    if (recordRef.isNotEmpty) {
      return recordRef;
    }
    return _defaultWorkspaceRefForSession(normalizedSessionKey);
  }

  WorkspaceRefKind assistantWorkspaceRefKindForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final record = _threadRecords[normalizedSessionKey];
    if (record != null && record.workspaceRef.trim().isNotEmpty) {
      return record.workspaceRefKind;
    }
    return WorkspaceRefKind.objectStore;
  }

  Future<AssistantArtifactSnapshot> loadAssistantArtifactSnapshot({
    String? sessionKey,
  }) {
    final resolvedSessionKey = _normalizedSessionKey(
      sessionKey ?? _currentSessionKey,
    );
    return _artifactProxyClient.loadSnapshot(
      sessionKey: resolvedSessionKey,
      workspaceRef: assistantWorkspaceRefForSession(resolvedSessionKey),
      workspaceRefKind: assistantWorkspaceRefKindForSession(resolvedSessionKey),
    );
  }

  Future<AssistantArtifactPreview> loadAssistantArtifactPreview(
    AssistantArtifactEntry entry, {
    String? sessionKey,
  }) {
    final resolvedSessionKey = _normalizedSessionKey(
      sessionKey ?? _currentSessionKey,
    );
    return _artifactProxyClient.loadPreview(
      sessionKey: resolvedSessionKey,
      entry: entry,
    );
  }

  SingleAgentProvider singleAgentProviderForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final stored =
        _threadRecords[normalizedSessionKey]?.singleAgentProvider ??
        SingleAgentProvider.auto;
    return _settings.resolveSingleAgentProvider(stored);
  }

  SingleAgentProvider get currentSingleAgentProvider =>
      singleAgentProviderForSession(_currentSessionKey);

  List<SingleAgentProvider> get singleAgentProviderOptions =>
      <SingleAgentProvider>[
        SingleAgentProvider.auto,
        ..._settings.availableSingleAgentProviders,
      ];

  bool singleAgentUsesAiChatFallbackForSession(String sessionKey) {
    final provider = singleAgentProviderForSession(sessionKey);
    return provider == SingleAgentProvider.auto && canUseAiGatewayConversation;
  }

  bool get currentSingleAgentUsesAiChatFallback =>
      singleAgentUsesAiChatFallbackForSession(_currentSessionKey);

  String singleAgentRuntimeModelForSession(String sessionKey) {
    return _singleAgentRuntimeModelBySession[_normalizedSessionKey(sessionKey)]
            ?.trim() ??
        '';
  }

  String get currentSingleAgentRuntimeModel =>
      singleAgentRuntimeModelForSession(_currentSessionKey);

  String assistantModelForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    final recordModel =
        _threadRecords[normalizedSessionKey]?.assistantModelId.trim() ?? '';
    if (target == AssistantExecutionTarget.singleAgent) {
      if (singleAgentUsesAiChatFallbackForSession(normalizedSessionKey)) {
        if (recordModel.isNotEmpty) {
          return recordModel;
        }
        return resolvedAiGatewayModel;
      }
      final runtimeModel = singleAgentRuntimeModelForSession(
        normalizedSessionKey,
      );
      if (runtimeModel.isNotEmpty) {
        return runtimeModel;
      }
      if (recordModel.isNotEmpty) {
        return recordModel;
      }
      return resolvedAiGatewayModel;
    }
    if (recordModel.isNotEmpty) {
      return recordModel;
    }
    return _settings.defaultModel.trim();
  }

  String get resolvedAssistantModel =>
      assistantModelForSession(_currentSessionKey);

  List<String> assistantModelChoicesForSession(String sessionKey) {
    final target = assistantExecutionTargetForSession(sessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      if (singleAgentUsesAiChatFallbackForSession(sessionKey)) {
        return aiGatewayConversationModelChoices;
      }
      final runtime = singleAgentRuntimeModelForSession(sessionKey);
      if (runtime.isNotEmpty) {
        return <String>[runtime];
      }
      final recordModel = assistantModelForSession(sessionKey);
      if (recordModel.isNotEmpty) {
        return <String>[recordModel];
      }
      return aiGatewayConversationModelChoices;
    }
    final model = _settings.defaultModel.trim();
    if (model.isEmpty) {
      return const <String>[];
    }
    return <String>[model];
  }

  List<String> get assistantModelChoices =>
      assistantModelChoicesForSession(_currentSessionKey);

  List<AssistantThreadSkillEntry> assistantImportedSkillsForSession(
    String sessionKey,
  ) {
    return _threadRecords[_normalizedSessionKey(sessionKey)]?.importedSkills ??
        const <AssistantThreadSkillEntry>[];
  }

  List<String> assistantSelectedSkillKeysForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final importedKeys = assistantImportedSkillsForSession(
      normalizedSessionKey,
    ).map((item) => item.key).toSet();
    final selected =
        _threadRecords[normalizedSessionKey]?.selectedSkillKeys ??
        const <String>[];
    return selected
        .where((item) => importedKeys.contains(item))
        .toList(growable: false);
  }

  int get currentAssistantSkillCount {
    final target = assistantExecutionTargetForSession(_currentSessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      return assistantImportedSkillsForSession(_currentSessionKey).length;
    }
    return assistantImportedSkillsForSession(_currentSessionKey).length;
  }

  String _defaultWorkspaceRefForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    return 'object://thread/$normalizedSessionKey';
  }

  void _syncThreadWorkspaceRef(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final nextWorkspaceRef = _defaultWorkspaceRefForSession(
      normalizedSessionKey,
    );
    final existing = _threadRecords[normalizedSessionKey];
    if (existing != null &&
        existing.workspaceRef == nextWorkspaceRef &&
        existing.workspaceRefKind == WorkspaceRefKind.objectStore) {
      return;
    }
    _upsertThreadRecord(
      normalizedSessionKey,
      workspaceRef: nextWorkspaceRef,
      workspaceRefKind: WorkspaceRefKind.objectStore,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
  }

  List<GatewaySkillSummary> get skills => assistantImportedSkillsForSession(
    _currentSessionKey,
  ).map(_gatewaySkillFromThreadEntry).toList(growable: false);

  List<GatewayModelSummary> get models {
    if (_relayModels.isNotEmpty &&
        assistantExecutionTargetForSession(_currentSessionKey) !=
            AssistantExecutionTarget.singleAgent) {
      return _relayModels;
    }
    return aiGatewayConversationModelChoices
        .map(
          (item) => GatewayModelSummary(
            id: item,
            name: item,
            provider: _settings.defaultProvider.trim().isEmpty
                ? 'gateway'
                : _settings.defaultProvider.trim(),
            contextWindow: null,
            maxOutputTokens: null,
          ),
        )
        .toList(growable: false);
  }

  bool get currentSingleAgentNeedsAiGatewayConfiguration =>
      currentSingleAgentUsesAiChatFallback && !canUseAiGatewayConversation;

  List<SecretReferenceEntry> get secretReferences {
    final entries = <SecretReferenceEntry>[
      if (storedRelayTokenMaskForProfile(kGatewayLocalProfileIndex) != null)
        SecretReferenceEntry(
          name: 'gateway_token.local',
          provider: 'Gateway',
          module: 'Assistant',
          maskedValue: storedRelayTokenMaskForProfile(
            kGatewayLocalProfileIndex,
          )!,
          status: 'In Use',
        ),
      if (storedRelayPasswordMaskForProfile(kGatewayLocalProfileIndex) != null)
        SecretReferenceEntry(
          name: 'gateway_password.local',
          provider: 'Gateway',
          module: 'Assistant',
          maskedValue: storedRelayPasswordMaskForProfile(
            kGatewayLocalProfileIndex,
          )!,
          status: 'In Use',
        ),
      if (storedRelayTokenMaskForProfile(kGatewayRemoteProfileIndex) != null)
        SecretReferenceEntry(
          name: 'gateway_token.remote',
          provider: 'Gateway',
          module: 'Assistant',
          maskedValue: storedRelayTokenMaskForProfile(
            kGatewayRemoteProfileIndex,
          )!,
          status: 'In Use',
        ),
      if (storedRelayPasswordMaskForProfile(kGatewayRemoteProfileIndex) != null)
        SecretReferenceEntry(
          name: 'gateway_password.remote',
          provider: 'Gateway',
          module: 'Assistant',
          maskedValue: storedRelayPasswordMaskForProfile(
            kGatewayRemoteProfileIndex,
          )!,
          status: 'In Use',
        ),
      if (storedAiGatewayApiKeyMask != null)
        SecretReferenceEntry(
          name: _settings.aiGateway.apiKeyRef,
          provider: 'LLM API',
          module: 'Settings',
          maskedValue: storedAiGatewayApiKeyMask!,
          status: 'In Use',
        ),
      SecretReferenceEntry(
        name: _settings.aiGateway.name,
        provider: 'LLM API',
        module: 'Settings',
        maskedValue: _settings.aiGateway.baseUrl.trim().isEmpty
            ? 'Not set'
            : _settings.aiGateway.baseUrl.trim(),
        status: _settings.aiGateway.syncState,
      ),
    ];
    return entries;
  }

  List<GatewayChatMessage> get chatMessages {
    final base = List<GatewayChatMessage>.from(_currentRecord.messages);
    final streaming = _streamingTextBySession[_currentSessionKey]?.trim() ?? '';
    if (streaming.isNotEmpty) {
      base.add(
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
    return base;
  }

  List<WebConversationSummary> get conversations {
    final archivedKeys = _settings.assistantArchivedTaskKeys
        .map(_normalizedSessionKey)
        .toSet();
    final entries =
        _threadRecords.values
            .where(
              (record) =>
                  !record.archived &&
                  !archivedKeys.contains(
                    _normalizedSessionKey(record.sessionKey),
                  ),
            )
            .map(
              (record) => WebConversationSummary(
                sessionKey: record.sessionKey,
                title: _titleForRecord(record),
                preview: _previewForRecord(record),
                updatedAtMs:
                    record.updatedAtMs ??
                    DateTime.now().millisecondsSinceEpoch.toDouble(),
                executionTarget: assistantExecutionTargetForSession(
                  record.sessionKey,
                ),
                pending: _pendingSessionKeys.contains(record.sessionKey),
                current: record.sessionKey == _currentSessionKey,
              ),
            )
            .toList(growable: true)
          ..sort((left, right) {
            if (left.current != right.current) {
              return left.current ? -1 : 1;
            }
            return right.updatedAtMs.compareTo(left.updatedAtMs);
          });
    return entries;
  }

  List<WebConversationSummary> conversationsForTarget(
    AssistantExecutionTarget target,
  ) {
    return conversations
        .where((item) => item.executionTarget == target)
        .toList(growable: false);
  }

  String get aiGatewayUrl => _settings.aiGateway.baseUrl.trim();
  String get resolvedAiGatewayModel {
    final current = _settings.defaultModel.trim();
    final choices = aiGatewayConversationModelChoices;
    if (choices.contains(current)) {
      return current;
    }
    if (choices.isNotEmpty) {
      return choices.first;
    }
    return '';
  }

  List<String> get aiGatewayConversationModelChoices {
    final selected = _settings.aiGateway.selectedModels
        .map((item) => item.trim())
        .where(
          (item) =>
              item.isNotEmpty &&
              _settings.aiGateway.availableModels.contains(item),
        )
        .toList(growable: false);
    if (selected.isNotEmpty) {
      return selected;
    }
    return _settings.aiGateway.availableModels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  bool get canUseAiGatewayConversation =>
      aiGatewayUrl.isNotEmpty &&
      _aiGatewayApiKeyCache.trim().isNotEmpty &&
      resolvedAiGatewayModel.isNotEmpty;

  AssistantThreadConnectionState get currentAssistantConnectionState =>
      assistantConnectionStateForSession(_currentSessionKey);

  AssistantThreadConnectionState assistantConnectionStateForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      final provider = singleAgentProviderForSession(normalizedSessionKey);
      final model = assistantModelForSession(normalizedSessionKey);
      final host = _hostLabel(_settings.aiGateway.baseUrl);
      if (provider == SingleAgentProvider.auto) {
        final detail = _joinConnectionParts(<String>[model, host]);
        return AssistantThreadConnectionState(
          executionTarget: target,
          status: canUseAiGatewayConversation
              ? RuntimeConnectionStatus.connected
              : RuntimeConnectionStatus.offline,
          primaryLabel: target.label,
          detailLabel: detail.isEmpty
              ? appText('单机智能体未配置', 'Single Agent not configured')
              : detail,
          ready: canUseAiGatewayConversation,
          pairingRequired: false,
          gatewayTokenMissing: false,
          lastError: null,
        );
      }
      final remoteAddress = _gatewayAddressLabel(
        _settings.primaryRemoteGatewayProfile,
      );
      final remoteReady =
          connection.status == RuntimeConnectionStatus.connected &&
          connection.mode == RuntimeConnectionMode.remote;
      return AssistantThreadConnectionState(
        executionTarget: target,
        status: remoteReady
            ? RuntimeConnectionStatus.connected
            : RuntimeConnectionStatus.offline,
        primaryLabel: target.label,
        detailLabel: remoteReady
            ? _joinConnectionParts(<String>[provider.label, model])
            : appText(
                '${provider.label} 需要 Remote ACP（${remoteAddress.isEmpty ? 'Remote Gateway' : remoteAddress}）',
                '${provider.label} requires Remote ACP (${remoteAddress.isEmpty ? 'Remote Gateway' : remoteAddress}).',
              ),
        ready: remoteReady,
        pairingRequired: false,
        gatewayTokenMissing: false,
        lastError: null,
      );
    }
    final expectedMode = target == AssistantExecutionTarget.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    final profile = target == AssistantExecutionTarget.local
        ? _settings.primaryLocalGatewayProfile
        : _settings.primaryRemoteGatewayProfile;
    final matchesTarget = connection.mode == expectedMode;
    final detail = matchesTarget
        ? (connection.remoteAddress?.trim().isNotEmpty == true
              ? connection.remoteAddress!.trim()
              : _gatewayAddressLabel(profile))
        : _gatewayAddressLabel(profile);
    return AssistantThreadConnectionState(
      executionTarget: target,
      status: matchesTarget
          ? connection.status
          : RuntimeConnectionStatus.offline,
      primaryLabel:
          (matchesTarget ? connection.status : RuntimeConnectionStatus.offline)
              .label,
      detailLabel: detail.isEmpty
          ? appText('Relay 未连接', 'Relay offline')
          : detail,
      ready:
          matchesTarget &&
          connection.status == RuntimeConnectionStatus.connected,
      pairingRequired: false,
      gatewayTokenMissing: false,
      lastError: null,
    );
  }

  String get assistantConnectionStatusLabel =>
      currentAssistantConnectionState.primaryLabel;

  String get assistantConnectionTargetLabel {
    return currentAssistantConnectionState.detailLabel;
  }

  String _joinConnectionParts(List<String> parts) {
    return parts
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(' · ');
  }

  String get conversationPersistenceSummary {
    if (usesRemoteSessionPersistence) {
      return appText(
        '当前会话会同步到远端 Session API，并在浏览器中保留一份本地缓存用于恢复。',
        'Conversation history syncs to the remote session API and keeps a browser cache for local recovery.',
      );
    }
    return appText(
      '当前会话列表会在浏览器本地保存，刷新后仍可恢复单机智能体 / Relay 的历史入口。',
      'Conversation history is stored in this browser so Single Agent and Relay entries remain available after reload.',
    );
  }

  String get currentConversationTitle => _titleForRecord(_currentRecord);

  AssistantThreadRecord get _currentRecord {
    final existing = _threadRecords[_currentSessionKey];
    if (existing != null) {
      return existing;
    }
    final target =
        _sanitizeTarget(_settings.assistantExecutionTarget) ??
        AssistantExecutionTarget.singleAgent;
    final record = _newRecord(target: target);
    _threadRecords[record.sessionKey] = record;
    _currentSessionKey = record.sessionKey;
    return record;
  }

  Future<void> _initialize() async {
    try {
      await _store.initialize();
      _themeMode = await _store.loadThemeMode();
      _settings = _sanitizeSettings(await _store.loadSettingsSnapshot());
      _aiGatewayApiKeyCache = await _store.loadAiGatewayApiKey();
      for (final profileIndex in <int>[
        kGatewayLocalProfileIndex,
        kGatewayRemoteProfileIndex,
      ]) {
        _relayTokenByProfile[profileIndex] = await _store.loadRelayToken(
          profileIndex: profileIndex,
        );
        _relayPasswordByProfile[profileIndex] = await _store.loadRelayPassword(
          profileIndex: profileIndex,
        );
      }
      _webSessionClientId = await _store.loadOrCreateWebSessionClientId();
      final records = await _loadThreadRecords();
      for (final record in records) {
        final sanitized = _sanitizeRecord(record);
        _threadRecords[sanitized.sessionKey] = sanitized;
      }
      if (_threadRecords.isEmpty) {
        final record = _newRecord(
          target: _settings.assistantExecutionTarget,
          title: appText('新对话', 'New conversation'),
        );
        _threadRecords[record.sessionKey] = record;
      }
      final preferredSession = _normalizedSessionKey(
        _settings.assistantLastSessionKey,
      );
      if (preferredSession.isNotEmpty &&
          _threadRecords.containsKey(preferredSession)) {
        _currentSessionKey = preferredSession;
      } else {
        final visible = conversations;
        if (visible.isNotEmpty) {
          _currentSessionKey = visible.first.sessionKey;
        } else {
          _currentSessionKey = _threadRecords.keys.first;
        }
      }
      _settingsDraft = _settings;
      _settingsDraftInitialized = true;
      _recomputeDerivedWorkspaceState();
    } catch (error) {
      _bootstrapError = '$error';
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  void navigateTo(WorkspaceDestination destination) {
    if (!capabilities.supportsDestination(destination)) {
      return;
    }
    _destination = destination;
    notifyListeners();
  }

  Future<void> saveWebSessionPersistenceConfiguration({
    required WebSessionPersistenceMode mode,
    required String remoteBaseUrl,
    required String apiToken,
  }) async {
    final trimmedRemoteBaseUrl = remoteBaseUrl.trim();
    final normalizedRemoteBaseUrl = RemoteWebSessionRepository.normalizeBaseUrl(
      trimmedRemoteBaseUrl,
    );
    if (mode == WebSessionPersistenceMode.remote &&
        trimmedRemoteBaseUrl.isNotEmpty &&
        normalizedRemoteBaseUrl == null) {
      _sessionPersistenceStatusMessage = appText(
        'Session API URL 必须使用 HTTPS；仅 localhost / 127.0.0.1 允许 HTTP 作为开发回路。',
        'Session API URLs must use HTTPS. HTTP is allowed only for localhost or 127.0.0.1 during development.',
      );
      notifyListeners();
      return;
    }
    _settings = _settings.copyWith(
      webSessionPersistence: _settings.webSessionPersistence.copyWith(
        mode: mode,
        remoteBaseUrl:
            normalizedRemoteBaseUrl?.toString() ?? trimmedRemoteBaseUrl,
      ),
    );
    _webSessionApiTokenCache = apiToken.trim();
    await _persistSettings();
    await _persistThreads();
    notifyListeners();
  }

  void navigateHome() {
    navigateTo(WorkspaceDestination.assistant);
  }

  void openSettings({SettingsTab tab = SettingsTab.general}) {
    _destination = WorkspaceDestination.settings;
    _settingsTab = _sanitizeSettingsTab(tab);
    notifyListeners();
  }

  void setSettingsTab(SettingsTab tab) {
    _settingsTab = _sanitizeSettingsTab(tab);
    notifyListeners();
  }

  List<DerivedTaskItem> taskItemsForTab(String tab) => switch (tab) {
    'Queue' => _tasksController.queue,
    'Running' => _tasksController.running,
    'History' => _tasksController.history,
    'Failed' => _tasksController.failed,
    'Scheduled' => _tasksController.scheduled,
    _ => _tasksController.queue,
  };

  Future<void> refreshSessions() async {
    if (connection.status == RuntimeConnectionStatus.connected) {
      await refreshRelaySessions();
      await refreshRelayWorkspaceResources();
      await refreshRelayHistory(sessionKey: _currentSessionKey);
      await refreshRelaySkillsForSession(_currentSessionKey);
    } else {
      _recomputeDerivedWorkspaceState();
      notifyListeners();
    }
  }

  Future<void> refreshAgents() async {
    await refreshRelayWorkspaceResources();
  }

  Future<void> refreshGatewayHealth() async {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    await refreshRelayWorkspaceResources();
  }

  Future<void> refreshVisibleSkills(String? agentId) async {
    final target = assistantExecutionTargetForSession(_currentSessionKey);
    if (target == AssistantExecutionTarget.local ||
        target == AssistantExecutionTarget.remote) {
      await refreshRelaySkillsForSession(_currentSessionKey);
      return;
    }
    await _refreshSingleAgentSkillsForSession(_currentSessionKey);
  }

  Future<void> toggleAssistantNavigationDestination(
    AssistantFocusEntry destination,
  ) async {
    if (!kAssistantNavigationDestinationCandidates.contains(destination) ||
        !supportsAssistantFocusEntry(destination)) {
      return;
    }
    final current = assistantNavigationDestinations;
    final next = current.contains(destination)
        ? current.where((item) => item != destination).toList(growable: false)
        : <AssistantFocusEntry>[...current, destination];
    _settings = _settings.copyWith(assistantNavigationDestinations: next);
    if (_settingsDraftInitialized) {
      _settingsDraft = settingsDraft.copyWith(
        assistantNavigationDestinations: next,
      );
    }
    notifyListeners();
    await _persistSettings();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }
    _themeMode = mode;
    await _store.saveThemeMode(mode);
    notifyListeners();
  }

  Future<void> saveSettingsDraft(SettingsSnapshot snapshot) async {
    _settingsDraft = snapshot;
    _settingsDraftInitialized = true;
    _settingsDraftStatusMessage = appText(
      '草稿已更新，点击顶部保存持久化。',
      'Draft updated. Use the top Save button to persist it.',
    );
    notifyListeners();
  }

  Future<AuthorizedSkillDirectory?> authorizeSkillDirectory({
    String suggestedPath = '',
  }) async {
    return null;
  }

  Future<List<AuthorizedSkillDirectory>> authorizeSkillDirectories({
    List<String> suggestedPaths = const <String>[],
  }) async {
    return const <AuthorizedSkillDirectory>[];
  }

  Future<void> saveAuthorizedSkillDirectories(
    List<AuthorizedSkillDirectory> directories,
  ) async {
    _settings = _settings.copyWith(
      authorizedSkillDirectories: normalizeAuthorizedSkillDirectories(
        directories: directories,
      ),
    );
    if (_settingsDraftInitialized) {
      _settingsDraft = _settingsDraft.copyWith(
        authorizedSkillDirectories: _settings.authorizedSkillDirectories,
      );
    }
    await _persistSettings();
    notifyListeners();
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

  Future<String> testOllamaConnection({required bool cloud}) async {
    return cloud
        ? 'Cloud test unavailable on web'
        : 'Local test unavailable on web';
  }

  Future<String> testOllamaConnectionDraft({
    required bool cloud,
    required SettingsSnapshot snapshot,
    String apiKeyOverride = '',
  }) async {
    return testOllamaConnection(cloud: cloud);
  }

  Future<String> testVaultConnection() async {
    return 'Vault test unavailable on web';
  }

  Future<String> testVaultConnectionDraft({
    required SettingsSnapshot snapshot,
    String tokenOverride = '',
  }) async {
    return testVaultConnection();
  }

  Future<({String state, String message, String endpoint})>
  testGatewayConnectionDraft({
    required GatewayConnectionProfile profile,
    required AssistantExecutionTarget executionTarget,
    String tokenOverride = '',
    String passwordOverride = '',
  }) async {
    final resolvedTarget =
        _sanitizeTarget(executionTarget) ?? AssistantExecutionTarget.remote;
    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      return (
        state: 'error',
        message: appText(
          'Single Agent 不需要 Gateway 连通性测试。',
          'Single Agent does not require a gateway connectivity test.',
        ),
        endpoint: '',
      );
    }
    final expectedMode = resolvedTarget == AssistantExecutionTarget.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    final candidateProfile = profile.copyWith(
      mode: expectedMode,
      useSetupCode: false,
      setupCode: '',
      tls: expectedMode == RuntimeConnectionMode.local ? false : profile.tls,
    );
    final endpoint = _gatewayAddressLabel(candidateProfile);
    final client = WebRelayGatewayClient(_store);
    try {
      await client.connect(
        profile: candidateProfile,
        authToken: tokenOverride.trim(),
        authPassword: passwordOverride.trim(),
      );
      return (
        state: 'connected',
        message: appText('连接测试成功。', 'Connection test succeeded.'),
        endpoint: endpoint,
      );
    } catch (error) {
      return (state: 'error', message: error.toString(), endpoint: endpoint);
    } finally {
      await client.dispose();
    }
  }

  Future<void> persistSettingsDraft() async {
    if (!hasSettingsDraftChanges) {
      _settingsDraftStatusMessage = appText(
        '没有需要保存的更改。',
        'There are no changes to save.',
      );
      notifyListeners();
      return;
    }
    _settings = settingsDraft;
    await _persistDraftSecrets();
    await _persistSettings();
    _settingsDraft = _settings;
    _settingsDraftInitialized = true;
    _pendingSettingsApply = true;
    _settingsDraftStatusMessage = appText(
      '已保存配置，不立即生效。',
      'Settings saved. They do not take effect until Apply.',
    );
    notifyListeners();
  }

  Future<void> applySettingsDraft() async {
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
    _settingsDraft = _settings;
    _settingsDraftInitialized = true;
    _pendingSettingsApply = false;
    _settingsDraftStatusMessage = appText(
      '已按当前配置生效。',
      'The current configuration is now in effect.',
    );
    notifyListeners();
  }

  Future<void> toggleAppLanguage() async {
    final next = _settings.appLanguage == AppLanguage.zh
        ? AppLanguage.en
        : AppLanguage.zh;
    _settings = _settings.copyWith(appLanguage: next);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> createConversation({AssistantExecutionTarget? target}) async {
    final inheritedTarget =
        _sanitizeTarget(target) ??
        assistantExecutionTargetForSession(_currentSessionKey);
    final inheritedRecord =
        _threadRecords[_normalizedSessionKey(_currentSessionKey)];
    final baseRecord = _newRecord(
      target: inheritedTarget,
      title: appText('新对话', 'New conversation'),
    );
    final record = baseRecord.copyWith(
      messageViewMode:
          inheritedRecord?.messageViewMode ?? AssistantMessageViewMode.rendered,
      singleAgentProvider:
          inheritedRecord?.singleAgentProvider ?? SingleAgentProvider.auto,
      assistantModelId: inheritedRecord?.assistantModelId ?? '',
      importedSkills: inheritedRecord?.importedSkills ?? const [],
      selectedSkillKeys: inheritedRecord?.selectedSkillKeys ?? const [],
      gatewayEntryState: _gatewayEntryStateForTarget(inheritedTarget),
      workspaceRef: inheritedRecord?.workspaceRef.trim().isNotEmpty == true
          ? inheritedRecord!.workspaceRef
          : _defaultWorkspaceRefForSession(baseRecord.sessionKey),
      workspaceRefKind:
          inheritedRecord?.workspaceRefKind ?? WorkspaceRefKind.objectStore,
    );
    _threadRecords[record.sessionKey] = record;
    _currentSessionKey = record.sessionKey;
    _lastAssistantError = null;
    _settings = _settings.copyWith(assistantLastSessionKey: record.sessionKey);
    _recomputeDerivedWorkspaceState();
    await _persistSettings();
    await _persistThreads();
    notifyListeners();
  }

  Future<void> switchConversation(String sessionKey) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    if (!_threadRecords.containsKey(normalizedSessionKey)) {
      return;
    }
    final previousSessionKey = _normalizedSessionKey(_currentSessionKey);
    if (previousSessionKey == normalizedSessionKey) {
      return;
    }
    if (assistantExecutionTargetForSession(previousSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      _streamingTextBySession.remove(previousSessionKey);
    }
    _currentSessionKey = normalizedSessionKey;
    _lastAssistantError = null;
    _settings = _settings.copyWith(
      assistantLastSessionKey: normalizedSessionKey,
    );
    _syncThreadWorkspaceRef(normalizedSessionKey);
    await _persistSettings();
    notifyListeners();
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    await _applyAssistantExecutionTarget(
      target,
      sessionKey: normalizedSessionKey,
      persistDefaultSelection: false,
    );
    if (target == AssistantExecutionTarget.singleAgent) {
      await _refreshSingleAgentSkillsForSession(normalizedSessionKey);
      return;
    }
    if (target == AssistantExecutionTarget.local ||
        target == AssistantExecutionTarget.remote) {
      await refreshRelayHistory(sessionKey: normalizedSessionKey);
      await refreshRelaySkillsForSession(normalizedSessionKey);
    }
  }

  Future<void> setAssistantExecutionTarget(
    AssistantExecutionTarget target,
  ) async {
    final resolvedTarget =
        _sanitizeTarget(target) ??
        assistantExecutionTargetForSession(_currentSessionKey);
    final sessionKey = _normalizedSessionKey(_currentSessionKey);
    _upsertThreadRecord(
      sessionKey,
      executionTarget: resolvedTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      gatewayEntryState: _gatewayEntryStateForTarget(resolvedTarget),
      workspaceRef: _defaultWorkspaceRefForSession(sessionKey),
      workspaceRefKind: WorkspaceRefKind.objectStore,
    );
    _settings = _settings.copyWith(assistantExecutionTarget: resolvedTarget);
    await _persistSettings();
    await _persistThreads();
    notifyListeners();
    await _applyAssistantExecutionTarget(
      resolvedTarget,
      sessionKey: sessionKey,
      persistDefaultSelection: true,
    );
    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      await _refreshSingleAgentSkillsForSession(sessionKey);
    } else if (resolvedTarget == AssistantExecutionTarget.local ||
        resolvedTarget == AssistantExecutionTarget.remote) {
      await refreshRelaySkillsForSession(sessionKey);
    }
    notifyListeners();
  }

  Future<void> setSingleAgentProvider(SingleAgentProvider provider) async {
    final resolvedProvider = _settings.resolveSingleAgentProvider(provider);
    if (!singleAgentProviderOptions.contains(resolvedProvider)) {
      return;
    }
    final sessionKey = _normalizedSessionKey(_currentSessionKey);
    if (singleAgentProviderForSession(sessionKey) == resolvedProvider) {
      return;
    }
    _singleAgentRuntimeModelBySession.remove(sessionKey);
    _upsertThreadRecord(
      sessionKey,
      singleAgentProvider: resolvedProvider,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _persistThreads();
    notifyListeners();
    if (assistantExecutionTargetForSession(sessionKey) ==
        AssistantExecutionTarget.singleAgent) {
      await _refreshSingleAgentSkillsForSession(sessionKey);
    }
  }

  Future<void> setAssistantMessageViewMode(
    AssistantMessageViewMode mode,
  ) async {
    final sessionKey = _normalizedSessionKey(_currentSessionKey);
    if (assistantMessageViewModeForSession(sessionKey) == mode) {
      return;
    }
    _upsertThreadRecord(
      sessionKey,
      messageViewMode: mode,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _persistThreads();
    notifyListeners();
  }

  Future<void> selectAssistantModelForSession(
    String sessionKey,
    String modelId,
  ) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    if (assistantModelForSession(normalizedSessionKey) == trimmed) {
      return;
    }
    _upsertThreadRecord(
      normalizedSessionKey,
      assistantModelId: trimmed,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _persistThreads();
    notifyListeners();
  }

  Future<void> selectAssistantModel(String modelId) async {
    await selectAssistantModelForSession(_currentSessionKey, modelId);
  }

  Future<void> saveAssistantTaskTitle(String sessionKey, String title) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    if (!_threadRecords.containsKey(normalizedSessionKey)) {
      return;
    }
    final trimmedTitle = title.trim();
    final nextTitles = Map<String, String>.from(
      _settings.assistantCustomTaskTitles,
    );
    if (trimmedTitle.isEmpty) {
      nextTitles.remove(normalizedSessionKey);
    } else {
      nextTitles[normalizedSessionKey] = trimmedTitle;
    }
    _settings = _settings.copyWith(assistantCustomTaskTitles: nextTitles);
    _upsertThreadRecord(normalizedSessionKey, title: trimmedTitle);
    await _persistSettings();
    await _persistThreads();
    notifyListeners();
  }

  bool isAssistantTaskArchived(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final archivedKeys = _settings.assistantArchivedTaskKeys
        .map(_normalizedSessionKey)
        .toSet();
    if (archivedKeys.contains(normalizedSessionKey)) {
      return true;
    }
    return _threadRecords[normalizedSessionKey]?.archived ?? false;
  }

  Future<void> saveAssistantTaskArchived(
    String sessionKey,
    bool archived,
  ) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    if (!_threadRecords.containsKey(normalizedSessionKey)) {
      return;
    }
    final archivedKeys = _settings.assistantArchivedTaskKeys
        .map(_normalizedSessionKey)
        .toSet();
    if (archived) {
      archivedKeys.add(normalizedSessionKey);
    } else {
      archivedKeys.remove(normalizedSessionKey);
    }
    _settings = _settings.copyWith(
      assistantArchivedTaskKeys: archivedKeys.toList(growable: false),
    );
    _upsertThreadRecord(
      normalizedSessionKey,
      archived: archived,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    if (archived && _currentSessionKey == normalizedSessionKey) {
      final fallback = _threadRecords.values
          .where(
            (record) =>
                !record.archived && record.sessionKey != normalizedSessionKey,
          )
          .toList(growable: false);
      if (fallback.isNotEmpty) {
        _currentSessionKey = fallback.first.sessionKey;
      } else {
        final newRecord = _newRecord(
          target: _settings.assistantExecutionTarget,
          title: appText('新对话', 'New conversation'),
        );
        _threadRecords[newRecord.sessionKey] = newRecord;
        _currentSessionKey = newRecord.sessionKey;
      }
    }
    _recomputeDerivedWorkspaceState();
    await _persistSettings();
    await _persistThreads();
    notifyListeners();
  }

  Future<void> toggleAssistantSkillForSession(
    String sessionKey,
    String skillKey,
  ) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
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
    final selected = assistantSelectedSkillKeysForSession(
      normalizedSessionKey,
    ).toSet();
    if (!selected.add(normalizedSkillKey)) {
      selected.remove(normalizedSkillKey);
    }
    _upsertThreadRecord(
      normalizedSessionKey,
      selectedSkillKeys: selected.toList(growable: false),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _persistThreads();
    notifyListeners();
  }

  Future<void> saveAiGatewayConfiguration({
    required String name,
    required String baseUrl,
    required String provider,
    required String apiKey,
    required String defaultModel,
  }) async {
    final normalizedBaseUrl = _aiGatewayClient.normalizeBaseUrl(baseUrl);
    _settings = _settings.copyWith(
      defaultProvider: provider.trim().isEmpty ? 'gateway' : provider.trim(),
      defaultModel: defaultModel.trim(),
      aiGateway: _settings.aiGateway.copyWith(
        name: name.trim().isEmpty ? 'Single Agent' : name.trim(),
        baseUrl: normalizedBaseUrl?.toString() ?? baseUrl.trim(),
      ),
    );
    _aiGatewayApiKeyCache = apiKey.trim();
    await _store.saveAiGatewayApiKey(_aiGatewayApiKeyCache);
    await _persistSettings();
    notifyListeners();
  }

  Future<AiGatewayConnectionCheck> testAiGatewayConnection({
    required String baseUrl,
    required String apiKey,
  }) async {
    _aiGatewayBusy = true;
    notifyListeners();
    try {
      return await _aiGatewayClient.testConnection(
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
    } finally {
      _aiGatewayBusy = false;
      notifyListeners();
    }
  }

  Future<void> syncAiGatewayModels({
    required String name,
    required String baseUrl,
    required String provider,
    required String apiKey,
  }) async {
    _aiGatewayBusy = true;
    notifyListeners();
    try {
      final models = await _aiGatewayClient.loadModels(
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      final availableModels = models
          .map((item) => item.id)
          .toList(growable: false);
      final selectedModels = availableModels.take(5).toList(growable: false);
      final resolvedDefaultModel =
          _settings.defaultModel.trim().isNotEmpty &&
              availableModels.contains(_settings.defaultModel.trim())
          ? _settings.defaultModel.trim()
          : selectedModels.isNotEmpty
          ? selectedModels.first
          : '';
      _settings = _settings.copyWith(
        defaultProvider: provider.trim().isEmpty ? 'gateway' : provider.trim(),
        defaultModel: resolvedDefaultModel,
        aiGateway: _settings.aiGateway.copyWith(
          name: name.trim().isEmpty ? 'Single Agent' : name.trim(),
          baseUrl:
              _aiGatewayClient.normalizeBaseUrl(baseUrl)?.toString() ??
              baseUrl.trim(),
          availableModels: availableModels,
          selectedModels: selectedModels,
          syncState: 'ready',
          syncMessage: 'Loaded ${availableModels.length} model(s)',
        ),
      );
      _aiGatewayApiKeyCache = apiKey.trim();
      await _store.saveAiGatewayApiKey(_aiGatewayApiKeyCache);
      await _persistSettings();
      _recomputeDerivedWorkspaceState();
    } catch (error) {
      _settings = _settings.copyWith(
        aiGateway: _settings.aiGateway.copyWith(
          syncState: 'error',
          syncMessage: _aiGatewayClient.networkErrorLabel(error),
        ),
      );
      await _persistSettings();
      _recomputeDerivedWorkspaceState();
      rethrow;
    } finally {
      _aiGatewayBusy = false;
      notifyListeners();
    }
  }

  Future<void> saveRelayConfiguration({
    required String host,
    required int port,
    required bool tls,
    required String token,
    required String password,
    int profileIndex = kGatewayRemoteProfileIndex,
  }) async {
    final baseProfile = profileIndex == kGatewayLocalProfileIndex
        ? _settings.primaryLocalGatewayProfile
        : _settings.primaryRemoteGatewayProfile;
    final mode = profileIndex == kGatewayLocalProfileIndex
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    _settings = _settings.copyWith(
      gatewayProfiles: replaceGatewayProfileAt(
        _settings.gatewayProfiles,
        profileIndex,
        baseProfile.copyWith(
          mode: mode,
          useSetupCode: false,
          setupCode: '',
          host: host.trim(),
          port: port,
          tls: mode == RuntimeConnectionMode.local ? false : tls,
        ),
      ),
    );
    _relayTokenByProfile[profileIndex] = token.trim();
    _relayPasswordByProfile[profileIndex] = password.trim();
    await _store.saveRelayToken(
      _relayTokenByProfile[profileIndex] ?? '',
      profileIndex: profileIndex,
    );
    await _store.saveRelayPassword(
      _relayPasswordByProfile[profileIndex] ?? '',
      profileIndex: profileIndex,
    );
    await _persistSettings();
    notifyListeners();
  }

  Future<void> applyRelayConfiguration({
    required int profileIndex,
    required String host,
    required int port,
    required bool tls,
    required String token,
    required String password,
  }) async {
    await saveRelayConfiguration(
      profileIndex: profileIndex,
      host: host,
      port: port,
      tls: tls,
      token: token,
      password: password,
    );
    final currentTarget = assistantExecutionTargetForSession(
      _currentSessionKey,
    );
    final currentProfileIndex = _profileIndexForTarget(currentTarget);
    if (currentProfileIndex == profileIndex) {
      await connectRelay(target: currentTarget);
    }
  }

  Future<void> connectRelay({AssistantExecutionTarget? target}) async {
    _relayBusy = true;
    notifyListeners();
    try {
      final resolvedTarget =
          _sanitizeTarget(target) ??
          (() {
            final current = assistantExecutionTargetForSession(
              _currentSessionKey,
            );
            return current == AssistantExecutionTarget.local ||
                    current == AssistantExecutionTarget.remote
                ? current
                : AssistantExecutionTarget.remote;
          })();
      final profileIndex = _profileIndexForTarget(resolvedTarget);
      final profile = _profileForTarget(resolvedTarget).copyWith(
        mode: resolvedTarget == AssistantExecutionTarget.local
            ? RuntimeConnectionMode.local
            : RuntimeConnectionMode.remote,
        useSetupCode: false,
        setupCode: '',
      );
      await _relayClient.connect(
        profile: profile,
        authToken: (_relayTokenByProfile[profileIndex] ?? '').trim(),
        authPassword: (_relayPasswordByProfile[profileIndex] ?? '').trim(),
      );
      final acpEndpoint = _acpEndpointForTarget(resolvedTarget);
      if (acpEndpoint != null) {
        await _refreshAcpCapabilities(acpEndpoint);
      }
      await refreshRelaySessions();
      await refreshRelayWorkspaceResources();
      await refreshRelayHistory(sessionKey: _currentSessionKey);
      await refreshRelaySkillsForSession(_currentSessionKey);
    } finally {
      _relayBusy = false;
      notifyListeners();
    }
  }

  Future<void> disconnectRelay() async {
    _relayBusy = true;
    notifyListeners();
    try {
      await _relayClient.disconnect();
      _relayAgents = const <GatewayAgentSummary>[];
      _relayInstances = const <GatewayInstanceSummary>[];
      _relayConnectors = const <GatewayConnectorSummary>[];
      _relayModels = const <GatewayModelSummary>[];
      _relayCronJobs = const <GatewayCronJobSummary>[];
      _recomputeDerivedWorkspaceState();
    } finally {
      _relayBusy = false;
      notifyListeners();
    }
  }

  Future<void> refreshRelaySessions() async {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    final target = _assistantExecutionTargetForMode(connection.mode);
    final sessions = await _relayClient.listSessions(limit: 50);
    for (final session in sessions) {
      final sessionKey = _normalizedSessionKey(session.key);
      final existing = _threadRecords[sessionKey];
      final next = AssistantThreadRecord(
        sessionKey: sessionKey,
        messages: existing?.messages ?? const <GatewayChatMessage>[],
        updatedAtMs:
            session.updatedAtMs ??
            existing?.updatedAtMs ??
            DateTime.now().millisecondsSinceEpoch.toDouble(),
        title: (session.derivedTitle ?? session.displayName ?? session.key)
            .trim(),
        archived: false,
        executionTarget: existing?.executionTarget ?? target,
        messageViewMode:
            existing?.messageViewMode ?? AssistantMessageViewMode.rendered,
        importedSkills: existing?.importedSkills ?? const [],
        selectedSkillKeys: existing?.selectedSkillKeys ?? const [],
        assistantModelId: existing?.assistantModelId ?? '',
        singleAgentProvider:
            existing?.singleAgentProvider ?? SingleAgentProvider.auto,
        gatewayEntryState:
            existing?.gatewayEntryState ?? _gatewayEntryStateForTarget(target),
        workspaceRef: existing?.workspaceRef.trim().isNotEmpty == true
            ? existing!.workspaceRef
            : _defaultWorkspaceRefForSession(sessionKey),
        workspaceRefKind:
            existing?.workspaceRefKind ?? WorkspaceRefKind.objectStore,
      );
      _threadRecords[sessionKey] = next;
    }
    await _persistThreads();
    _recomputeDerivedWorkspaceState();
    notifyListeners();
  }

  Future<void> refreshRelayModels() async {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    final models = await _relayClient.listModels();
    _relayModels = models;
    final availableModels = models
        .map((item) => item.id.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (availableModels.isEmpty) {
      return;
    }
    final defaultModel = _settings.defaultModel.trim().isNotEmpty
        ? _settings.defaultModel.trim()
        : availableModels.first;
    _settings = _settings.copyWith(
      defaultModel: defaultModel,
      aiGateway: _settings.aiGateway.copyWith(
        availableModels: _settings.aiGateway.availableModels.isEmpty
            ? availableModels
            : _settings.aiGateway.availableModels,
      ),
    );
    await _persistSettings();
    _recomputeDerivedWorkspaceState();
    notifyListeners();
  }

  Future<void> refreshRelayWorkspaceResources() async {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    try {
      _relayAgents = await _relayClient.listAgents();
    } catch (_) {
      _relayAgents = const <GatewayAgentSummary>[];
    }
    try {
      _relayInstances = await _relayClient.listInstances();
    } catch (_) {
      _relayInstances = const <GatewayInstanceSummary>[];
    }
    try {
      _relayConnectors = await _relayClient.listConnectors();
    } catch (_) {
      _relayConnectors = const <GatewayConnectorSummary>[];
    }
    try {
      _relayCronJobs = await _relayClient.listCronJobs();
    } catch (_) {
      _relayCronJobs = const <GatewayCronJobSummary>[];
    }
    await refreshRelayModels();
    _recomputeDerivedWorkspaceState();
    notifyListeners();
  }

  Future<void> refreshRelayHistory({String? sessionKey}) async {
    final resolvedKey = _normalizedSessionKey(sessionKey ?? _currentSessionKey);
    if (resolvedKey.isEmpty ||
        connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    final target = _assistantExecutionTargetForMode(connection.mode);
    final messages = await _relayClient.loadHistory(resolvedKey, limit: 120);
    final existing = _threadRecords[resolvedKey];
    final next = (existing ?? _newRecord(target: target)).copyWith(
      sessionKey: resolvedKey,
      messages: messages,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      title: _deriveThreadTitle(
        existing?.title ?? '',
        messages,
        fallback: resolvedKey,
      ),
      executionTarget: existing?.executionTarget ?? target,
      gatewayEntryState:
          existing?.gatewayEntryState ?? _gatewayEntryStateForTarget(target),
    );
    _threadRecords[resolvedKey] = next;
    _streamingTextBySession.remove(resolvedKey);
    await _persistThreads();
    _recomputeDerivedWorkspaceState();
    notifyListeners();
  }

  Future<void> refreshRelaySkillsForSession(String sessionKey) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    if ((target != AssistantExecutionTarget.local &&
            target != AssistantExecutionTarget.remote) ||
        connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    try {
      final payload = _castMap(await _relayClient.request('skills.status'));
      final skills = (payload['skills'] as List<dynamic>? ?? const <dynamic>[])
          .map(_castMap)
          .map(
            (item) => AssistantThreadSkillEntry(
              key: item['skillKey']?.toString().trim().isNotEmpty == true
                  ? item['skillKey'].toString().trim()
                  : (item['name']?.toString().trim() ?? ''),
              label: item['name']?.toString().trim() ?? '',
              description: item['description']?.toString().trim() ?? '',
              source: item['source']?.toString().trim() ?? 'gateway',
              sourcePath: '',
              scope: 'session',
              sourceLabel: item['source']?.toString().trim() ?? 'gateway',
            ),
          )
          .where((entry) => entry.key.isNotEmpty && entry.label.isNotEmpty)
          .toList(growable: false);
      final importedKeys = skills.map((item) => item.key).toSet();
      final nextSelected =
          (_threadRecords[normalizedSessionKey]?.selectedSkillKeys ??
                  const <String>[])
              .where(importedKeys.contains)
              .toList(growable: false);
      _upsertThreadRecord(
        normalizedSessionKey,
        importedSkills: skills,
        selectedSkillKeys: nextSelected,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
      await _persistThreads();
      _recomputeDerivedWorkspaceState();
      notifyListeners();
    } catch (_) {
      // Best effort: skill discovery should not block chat flows.
    }
  }

  Future<void> _refreshSingleAgentSkillsForSession(String sessionKey) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return;
    }
    final endpoint = _acpEndpointForTarget(AssistantExecutionTarget.remote);
    if (endpoint == null) {
      await _replaceThreadSkillsForSession(
        normalizedSessionKey,
        const <AssistantThreadSkillEntry>[],
      );
      return;
    }
    final provider = singleAgentProviderForSession(normalizedSessionKey);
    try {
      await _refreshAcpCapabilities(endpoint);
      final response = await _acpClient.request(
        endpoint: endpoint,
        method: 'skills.status',
        params: <String, dynamic>{
          'sessionId': normalizedSessionKey,
          'threadId': normalizedSessionKey,
          'mode': 'single-agent',
          'provider': provider.providerId,
        },
      );
      final result = _castMap(response['result']);
      final payload = result.isNotEmpty ? result : response;
      final skills = (payload['skills'] as List<dynamic>? ?? const <dynamic>[])
          .map(_castMap)
          .map(
            (item) => AssistantThreadSkillEntry(
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
              sourceLabel:
                  item['sourceLabel']?.toString().trim().isNotEmpty == true
                  ? item['sourceLabel'].toString().trim()
                  : (item['source']?.toString().trim().isNotEmpty == true
                        ? item['source'].toString().trim()
                        : provider.label),
            ),
          )
          .where((entry) => entry.key.isNotEmpty && entry.label.isNotEmpty)
          .toList(growable: false);
      await _replaceThreadSkillsForSession(normalizedSessionKey, skills);
    } on WebAcpException catch (error) {
      if (_unsupportedAcpSkillsStatus(error)) {
        await _replaceThreadSkillsForSession(
          normalizedSessionKey,
          const <AssistantThreadSkillEntry>[],
        );
      }
    } catch (_) {
      // Keep current skills when transient ACP failures happen.
    }
  }

  Future<void> _replaceThreadSkillsForSession(
    String sessionKey,
    List<AssistantThreadSkillEntry> importedSkills,
  ) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final importedKeys = importedSkills.map((item) => item.key).toSet();
    final nextSelected =
        (_threadRecords[normalizedSessionKey]?.selectedSkillKeys ??
                const <String>[])
            .where(importedKeys.contains)
            .toList(growable: false);
    _upsertThreadRecord(
      normalizedSessionKey,
      importedSkills: importedSkills,
      selectedSkillKeys: nextSelected,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _persistThreads();
    _recomputeDerivedWorkspaceState();
    notifyListeners();
  }

  Future<void> sendMessage(
    String rawMessage, {
    String thinking = 'medium',
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    List<String> selectedSkillLabels = const <String>[],
    bool useMultiAgent = false,
  }) async {
    final trimmed = rawMessage.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _syncThreadWorkspaceRef(_currentSessionKey);
    const maxAttachmentBytes = 10 * 1024 * 1024;
    final totalAttachmentBytes = attachments.fold<int>(
      0,
      (total, item) => total + _base64Size(item.content),
    );
    if (totalAttachmentBytes > maxAttachmentBytes) {
      _lastAssistantError = appText(
        '附件总大小超过 10MB，请减少附件后重试。',
        'Attachments exceed the 10MB limit. Remove some files and try again.',
      );
      notifyListeners();
      return;
    }
    final sessionKey = _normalizedSessionKey(_currentSessionKey);
    await _enqueueThreadTurn<void>(sessionKey, () async {
      _lastAssistantError = null;
      final target = assistantExecutionTargetForSession(sessionKey);
      final current = _threadRecords[sessionKey] ?? _newRecord(target: target);
      final nextMessages = <GatewayChatMessage>[
        ...current.messages,
        GatewayChatMessage(
          id: _messageId(),
          role: 'user',
          text: trimmed,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      ];
      _upsertThreadRecord(
        sessionKey,
        messages: nextMessages,
        executionTarget: target,
        title: _deriveThreadTitle(current.title, nextMessages),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
      _pendingSessionKeys.add(sessionKey);
      await _persistThreads();
      notifyListeners();

      try {
        if (useMultiAgent && _settings.multiAgent.enabled) {
          await runMultiAgentCollaboration(
            rawPrompt: trimmed,
            composedPrompt: trimmed,
            attachments: attachments,
            selectedSkillLabels: selectedSkillLabels,
          );
          return;
        }
        if (target == AssistantExecutionTarget.singleAgent) {
          final provider = singleAgentProviderForSession(sessionKey);
          if (provider == SingleAgentProvider.auto) {
            if (!canUseAiGatewayConversation) {
              throw Exception(
                appText(
                  '请先在 Settings 配置单机智能体所需的 LLM API Endpoint、LLM API Token 和默认模型。',
                  'Configure the Single Agent LLM API Endpoint, LLM API Token, and default model first.',
                ),
              );
            }
            final directPrompt = attachments.isEmpty
                ? trimmed
                : _augmentPromptWithAttachments(trimmed, attachments);
            final directHistory = List<GatewayChatMessage>.from(nextMessages);
            if (directHistory.isNotEmpty) {
              final last = directHistory.removeLast();
              directHistory.add(
                last.copyWith(text: directPrompt, role: 'user', error: false),
              );
            }
            final reply = await _aiGatewayClient.completeChat(
              baseUrl: _settings.aiGateway.baseUrl,
              apiKey: _aiGatewayApiKeyCache,
              model: assistantModelForSession(sessionKey),
              history: directHistory,
            );
            _appendAssistantMessage(
              sessionKey: sessionKey,
              text: reply,
              error: false,
            );
          } else {
            await _sendSingleAgentViaAcp(
              sessionKey: sessionKey,
              prompt: trimmed,
              provider: provider,
              model: assistantModelForSession(sessionKey),
              thinking: thinking,
              attachments: attachments,
              selectedSkillLabels: selectedSkillLabels,
            );
          }
        } else {
          final expectedMode = target == AssistantExecutionTarget.local
              ? RuntimeConnectionMode.local
              : RuntimeConnectionMode.remote;
          if (connection.status != RuntimeConnectionStatus.connected ||
              connection.mode != expectedMode) {
            throw Exception(
              appText(
                '当前线程目标网关未连接。',
                'The gateway for this thread target is not connected.',
              ),
            );
          }
          await _relayClient.sendChat(
            sessionKey: sessionKey,
            message: attachments.isEmpty
                ? trimmed
                : _augmentPromptWithAttachments(trimmed, attachments),
            thinking: thinking,
            attachments: attachments,
            metadata: <String, dynamic>{
              if (selectedSkillLabels.isNotEmpty)
                'selectedSkills': selectedSkillLabels,
            },
          );
        }
      } catch (error) {
        _appendAssistantMessage(
          sessionKey: sessionKey,
          text: error.toString(),
          error: true,
        );
        _lastAssistantError = error.toString();
        _pendingSessionKeys.remove(sessionKey);
        _streamingTextBySession.remove(sessionKey);
        await _persistThreads();
        notifyListeners();
      }
    });
  }

  Future<void> runMultiAgentCollaboration({
    required String rawPrompt,
    required String composedPrompt,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<String> selectedSkillLabels,
  }) async {
    final sessionKey = _normalizedSessionKey(_currentSessionKey);
    await _enqueueThreadTurn<void>(sessionKey, () async {
      _multiAgentRunPending = true;
      _acpBusy = true;
      _pendingSessionKeys.add(sessionKey);
      notifyListeners();
      try {
        final target = assistantExecutionTargetForSession(sessionKey);
        final endpoint = _acpEndpointForTarget(
          target == AssistantExecutionTarget.singleAgent
              ? AssistantExecutionTarget.remote
              : target,
        );
        if (endpoint == null) {
          throw Exception(
            appText(
              '当前线程的 ACP 端点不可用，请先配置并连接 Gateway。',
              'ACP endpoint is unavailable for this thread. Configure and connect Gateway first.',
            ),
          );
        }
        await _refreshAcpCapabilities(endpoint);
        final inlineAttachments = attachments
            .map(
              (item) => <String, dynamic>{
                'name': item.fileName,
                'mimeType': item.mimeType,
                'content': item.content,
                'sizeBytes': _base64Size(item.content),
              },
            )
            .toList(growable: false);
        final params = <String, dynamic>{
          'sessionId': sessionKey,
          'threadId': sessionKey,
          'mode': 'multi-agent',
          'taskPrompt': composedPrompt,
          'workingDirectory': '',
          'selectedSkills': selectedSkillLabels,
          'attachments': attachments
              .map(
                (item) => <String, dynamic>{
                  'name': item.fileName,
                  'description': item.mimeType,
                  'path': '',
                },
              )
              .toList(growable: false),
          if (inlineAttachments.isNotEmpty)
            'inlineAttachments': inlineAttachments,
          'aiGatewayBaseUrl': _settings.aiGateway.baseUrl.trim(),
          'aiGatewayApiKey': _aiGatewayApiKeyCache.trim(),
        };
        String? summary;
        final response = await _requestAcpSessionMessage(
          endpoint: endpoint,
          params: params,
          hasInlineAttachments: inlineAttachments.isNotEmpty,
          onNotification: (notification) {
            final update = _acpSessionUpdateFromNotification(
              notification,
              sessionKey: sessionKey,
            );
            if (update == null) {
              return;
            }
            if (update.type == 'delta' && update.text.isNotEmpty) {
              _appendStreamingText(sessionKey, update.text);
              notifyListeners();
              return;
            }
            if (update.message.isNotEmpty &&
                (update.type == 'step' || update.type == 'status')) {
              _appendAssistantMessage(
                sessionKey: sessionKey,
                text: update.message,
                error: update.error,
              );
              notifyListeners();
            }
          },
        );
        final result = _castMap(response['result']);
        summary = result['summary']?.toString().trim().isNotEmpty == true
            ? result['summary'].toString().trim()
            : result['output']?.toString().trim();
        _clearStreamingText(sessionKey);
        _appendAssistantMessage(
          sessionKey: sessionKey,
          text: (summary ?? '').trim().isNotEmpty
              ? summary!.trim()
              : appText(
                  '多 Agent 协作完成。',
                  'Multi-agent collaboration completed.',
                ),
          error: false,
        );
      } catch (error) {
        _clearStreamingText(sessionKey);
        _appendAssistantMessage(
          sessionKey: sessionKey,
          text: error.toString(),
          error: true,
        );
        _lastAssistantError = error.toString();
      } finally {
        _multiAgentRunPending = false;
        _acpBusy = false;
        _pendingSessionKeys.remove(sessionKey);
        await _persistThreads();
        notifyListeners();
      }
    });
  }

  Future<void> abortRun() async {
    final sessionKey = _normalizedSessionKey(_currentSessionKey);
    if (_multiAgentRunPending || _acpBusy) {
      final target = assistantExecutionTargetForSession(sessionKey);
      final endpoint = _acpEndpointForTarget(
        target == AssistantExecutionTarget.singleAgent
            ? AssistantExecutionTarget.remote
            : target,
      );
      if (endpoint != null) {
        try {
          await _acpClient.cancelSession(
            endpoint: endpoint,
            sessionId: sessionKey,
            threadId: sessionKey,
          );
        } catch (_) {
          // Best effort.
        }
      }
      _multiAgentRunPending = false;
      _acpBusy = false;
      _pendingSessionKeys.remove(sessionKey);
      _clearStreamingText(sessionKey);
      notifyListeners();
      return;
    }
  }

  Future<void> prepareForExit() async {
    try {
      await abortRun();
    } catch (_) {
      // Web and placeholder desktop hooks only need a best-effort cancel.
    }
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

  Future<void> selectDirectModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await selectAssistantModel(trimmed);
    _settings = _settings.copyWith(defaultModel: trimmed);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> _sendSingleAgentViaAcp({
    required String sessionKey,
    required String prompt,
    required SingleAgentProvider provider,
    required String model,
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<String> selectedSkillLabels,
  }) async {
    final endpoint = _acpEndpointForTarget(AssistantExecutionTarget.remote);
    if (endpoint == null) {
      throw Exception(
        appText(
          'Remote ACP 端点不可用，请先配置 Remote Gateway。',
          'Remote ACP endpoint is unavailable. Configure Remote Gateway first.',
        ),
      );
    }
    await _refreshAcpCapabilities(endpoint);
    if (_acpCapabilities.providers.isNotEmpty &&
        !_acpCapabilities.providers.contains(provider)) {
      throw Exception(
        appText(
          '${provider.label} 在当前 Remote ACP 端点不可用。',
          '${provider.label} is unavailable on the current Remote ACP endpoint.',
        ),
      );
    }
    _acpBusy = true;
    notifyListeners();
    try {
      String streamed = '';
      String output = '';
      final inlineAttachments = attachments
          .map(
            (item) => <String, dynamic>{
              'name': item.fileName,
              'mimeType': item.mimeType,
              'content': item.content,
              'sizeBytes': _base64Size(item.content),
            },
          )
          .toList(growable: false);
      final response = await _requestAcpSessionMessage(
        endpoint: endpoint,
        params: <String, dynamic>{
          'sessionId': sessionKey,
          'threadId': sessionKey,
          'mode': 'single-agent',
          'provider': provider.providerId,
          'model': model.trim(),
          'thinking': thinking,
          'taskPrompt': prompt,
          'workingDirectory': '',
          'selectedSkills': selectedSkillLabels,
          'attachments': attachments
              .map(
                (item) => <String, dynamic>{
                  'name': item.fileName,
                  'description': item.mimeType,
                  'path': '',
                },
              )
              .toList(growable: false),
          if (inlineAttachments.isNotEmpty)
            'inlineAttachments': inlineAttachments,
        },
        hasInlineAttachments: inlineAttachments.isNotEmpty,
        onNotification: (notification) {
          final update = _acpSessionUpdateFromNotification(
            notification,
            sessionKey: sessionKey,
          );
          if (update == null) {
            return;
          }
          if (update.type == 'delta' && update.text.isNotEmpty) {
            streamed += update.text;
            _appendStreamingText(sessionKey, update.text);
            notifyListeners();
          }
        },
      );
      final result = _castMap(response['result']);
      output = result['output']?.toString().trim().isNotEmpty == true
          ? result['output'].toString().trim()
          : streamed.trim();
      _singleAgentRuntimeModelBySession[sessionKey] =
          (result['model']?.toString().trim() ?? model.trim());
      _clearStreamingText(sessionKey);
      final finalOutput = output.trim();
      _appendAssistantMessage(
        sessionKey: sessionKey,
        text: finalOutput.isEmpty
            ? appText('执行完成。', 'Completed.')
            : finalOutput,
        error: false,
      );
    } finally {
      _acpBusy = false;
      notifyListeners();
    }
  }

  void _recomputeDerivedWorkspaceState() {
    final archivedKeys = _settings.assistantArchivedTaskKeys
        .map(_normalizedSessionKey)
        .toSet();
    final visibleThreads = _threadRecords.values
        .where((record) {
          return !record.archived &&
              !archivedKeys.contains(_normalizedSessionKey(record.sessionKey));
        })
        .toList(growable: false);
    _tasksController.recompute(
      threads: visibleThreads,
      cronJobs: _relayCronJobs,
      currentSessionKey: _currentSessionKey,
      pendingSessionKeys: _pendingSessionKeys,
    );
  }

  GatewaySkillSummary _gatewaySkillFromThreadEntry(
    AssistantThreadSkillEntry item,
  ) {
    return GatewaySkillSummary(
      name: item.label,
      description: item.description,
      source: item.source,
      skillKey: item.key,
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

  SettingsTab _sanitizeSettingsTab(SettingsTab tab) {
    return switch (tab) {
      SettingsTab.workspace ||
      SettingsTab.agents ||
      SettingsTab.diagnostics ||
      SettingsTab.experimental => SettingsTab.gateway,
      _ => tab,
    };
  }

  SettingsSnapshot _sanitizeSettings(SettingsSnapshot snapshot) {
    final allowedDestinations = featuresFor(
      UiFeaturePlatform.web,
    ).allowedDestinations;
    final target = featuresFor(UiFeaturePlatform.web).sanitizeExecutionTarget(
      _sanitizeTarget(snapshot.assistantExecutionTarget),
    );
    final assistantNavigationDestinations =
        normalizeAssistantNavigationDestinations(
              snapshot.assistantNavigationDestinations,
            )
            .where((entry) {
              final destination = entry.destination;
              if (destination != null) {
                return allowedDestinations.contains(destination);
              }
              return allowedDestinations.contains(
                WorkspaceDestination.settings,
              );
            })
            .toList(growable: false);
    final normalizedSessionBaseUrl =
        RemoteWebSessionRepository.normalizeBaseUrl(
          snapshot.webSessionPersistence.remoteBaseUrl,
        )?.toString() ??
        '';
    final localProfile = snapshot.primaryLocalGatewayProfile.copyWith(
      mode: RuntimeConnectionMode.local,
      useSetupCode: false,
      setupCode: '',
      tls: false,
    );
    final remoteProfile = snapshot.primaryRemoteGatewayProfile.copyWith(
      mode: RuntimeConnectionMode.remote,
      useSetupCode: false,
      setupCode: '',
    );
    return snapshot.copyWith(
      assistantExecutionTarget: target,
      gatewayProfiles: replaceGatewayProfileAt(
        replaceGatewayProfileAt(
          snapshot.gatewayProfiles,
          kGatewayLocalProfileIndex,
          localProfile,
        ),
        kGatewayRemoteProfileIndex,
        remoteProfile,
      ),
      webSessionPersistence: snapshot.webSessionPersistence.copyWith(
        remoteBaseUrl: normalizedSessionBaseUrl,
      ),
      assistantNavigationDestinations: assistantNavigationDestinations,
    );
  }

  AssistantThreadRecord _sanitizeRecord(AssistantThreadRecord record) {
    final target =
        _sanitizeTarget(record.executionTarget) ??
        AssistantExecutionTarget.singleAgent;
    return record.copyWith(
      executionTarget: target,
      title: record.title.trim().isEmpty
          ? appText('新对话', 'New conversation')
          : record.title.trim(),
      workspaceRef: record.workspaceRef.trim().isEmpty
          ? _defaultWorkspaceRefForSession(record.sessionKey)
          : record.workspaceRef.trim(),
      workspaceRefKind: record.workspaceRef.trim().isEmpty
          ? WorkspaceRefKind.objectStore
          : record.workspaceRefKind,
    );
  }

  AssistantExecutionTarget? _sanitizeTarget(AssistantExecutionTarget? target) {
    return switch (target) {
      AssistantExecutionTarget.local => AssistantExecutionTarget.local,
      AssistantExecutionTarget.remote => AssistantExecutionTarget.remote,
      AssistantExecutionTarget.singleAgent =>
        AssistantExecutionTarget.singleAgent,
      _ => AssistantExecutionTarget.singleAgent,
    };
  }

  AssistantThreadRecord _newRecord({
    required AssistantExecutionTarget target,
    String? title,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final prefix = switch (target) {
      AssistantExecutionTarget.singleAgent => 'single',
      AssistantExecutionTarget.local => 'local',
      AssistantExecutionTarget.remote => 'remote',
    };
    return AssistantThreadRecord(
      sessionKey: '$prefix:$timestamp',
      messages: const <GatewayChatMessage>[],
      updatedAtMs: timestamp.toDouble(),
      title: title ?? appText('新对话', 'New conversation'),
      archived: false,
      executionTarget: target,
      messageViewMode: AssistantMessageViewMode.rendered,
      workspaceRef: 'object://thread/$prefix:$timestamp',
      workspaceRefKind: WorkspaceRefKind.objectStore,
    );
  }

  void _appendAssistantMessage({
    required String sessionKey,
    required String text,
    required bool error,
  }) {
    final existing =
        _threadRecords[sessionKey] ??
        _newRecord(target: assistantExecutionTarget);
    final messages = <GatewayChatMessage>[
      ...existing.messages,
      GatewayChatMessage(
        id: _messageId(),
        role: 'assistant',
        text: text,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        toolCallId: null,
        toolName: null,
        stopReason: error ? 'error' : null,
        pending: false,
        error: error,
      ),
    ];
    _threadRecords[sessionKey] = existing.copyWith(
      messages: messages,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      title: _deriveThreadTitle(existing.title, messages, fallback: sessionKey),
    );
    _pendingSessionKeys.remove(sessionKey);
    _streamingTextBySession.remove(sessionKey);
    _recomputeDerivedWorkspaceState();
  }

  void _handleRelayEvent(GatewayPushEvent event) {
    if (event.event != 'chat') {
      return;
    }
    final payload = _castMap(event.payload);
    final sessionKey = _normalizedSessionKey(
      payload['sessionKey']?.toString() ?? '',
    );
    if (sessionKey.isEmpty) {
      return;
    }
    final state = payload['state']?.toString().trim() ?? '';
    final message = _castMap(payload['message']);
    final text = _extractMessageText(message);
    if (text.isNotEmpty && state == 'delta') {
      _appendStreamingText(sessionKey, text);
    } else if (text.isNotEmpty && state == 'final') {
      _clearStreamingText(sessionKey);
      _appendAssistantMessage(sessionKey: sessionKey, text: text, error: false);
    }
    if (state == 'final' || state == 'aborted' || state == 'error') {
      _pendingSessionKeys.remove(sessionKey);
      if (state == 'error' && text.isNotEmpty) {
        _appendAssistantMessage(
          sessionKey: sessionKey,
          text: text,
          error: true,
        );
      }
      _clearStreamingText(sessionKey);
      unawaited(refreshRelaySessions());
      unawaited(refreshRelayHistory(sessionKey: sessionKey));
    }
    notifyListeners();
  }

  String _normalizedSessionKey(String sessionKey) {
    final trimmed = sessionKey.trim();
    return trimmed.isEmpty ? 'main' : trimmed;
  }

  AssistantExecutionTarget _assistantExecutionTargetForMode(
    RuntimeConnectionMode mode,
  ) {
    return switch (mode) {
      RuntimeConnectionMode.local => AssistantExecutionTarget.local,
      RuntimeConnectionMode.remote => AssistantExecutionTarget.remote,
      RuntimeConnectionMode.unconfigured => AssistantExecutionTarget.remote,
    };
  }

  int _profileIndexForTarget(AssistantExecutionTarget target) {
    return switch (target) {
      AssistantExecutionTarget.local => kGatewayLocalProfileIndex,
      AssistantExecutionTarget.remote => kGatewayRemoteProfileIndex,
      AssistantExecutionTarget.singleAgent => kGatewayRemoteProfileIndex,
    };
  }

  GatewayConnectionProfile _profileForTarget(AssistantExecutionTarget target) {
    return switch (target) {
      AssistantExecutionTarget.local => _settings.primaryLocalGatewayProfile,
      AssistantExecutionTarget.remote => _settings.primaryRemoteGatewayProfile,
      AssistantExecutionTarget.singleAgent =>
        _settings.primaryRemoteGatewayProfile,
    };
  }

  String _gatewayAddressLabel(GatewayConnectionProfile profile) {
    final host = profile.host.trim();
    if (host.isEmpty || profile.port <= 0) {
      return appText('未连接目标', 'No target');
    }
    return '$host:${profile.port}';
  }

  String _gatewayEntryStateForTarget(AssistantExecutionTarget target) {
    return target.promptValue;
  }

  void _upsertThreadRecord(
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
    bool clearGatewayEntryState = false,
    String? workspaceRef,
    WorkspaceRefKind? workspaceRefKind,
  }) {
    final key = _normalizedSessionKey(sessionKey);
    final resolvedTarget =
        _sanitizeTarget(executionTarget) ??
        assistantExecutionTargetForSession(key);
    final existing = _threadRecords[key] ?? _newRecord(target: resolvedTarget);
    _threadRecords[key] = existing.copyWith(
      sessionKey: key,
      messages: messages ?? existing.messages,
      updatedAtMs: updatedAtMs ?? existing.updatedAtMs,
      title: title ?? existing.title,
      archived: archived ?? existing.archived,
      executionTarget: resolvedTarget,
      messageViewMode: messageViewMode ?? existing.messageViewMode,
      importedSkills: importedSkills ?? existing.importedSkills,
      selectedSkillKeys: selectedSkillKeys ?? existing.selectedSkillKeys,
      assistantModelId: assistantModelId ?? existing.assistantModelId,
      singleAgentProvider: singleAgentProvider ?? existing.singleAgentProvider,
      gatewayEntryState: gatewayEntryState ?? existing.gatewayEntryState,
      clearGatewayEntryState: clearGatewayEntryState,
      workspaceRef: workspaceRef ?? existing.workspaceRef,
      workspaceRefKind: workspaceRefKind ?? existing.workspaceRefKind,
    );
    _recomputeDerivedWorkspaceState();
  }

  Future<void> _applyAssistantExecutionTarget(
    AssistantExecutionTarget target, {
    required String sessionKey,
    required bool persistDefaultSelection,
  }) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final resolvedTarget =
        _sanitizeTarget(target) ??
        assistantExecutionTargetForSession(normalizedSessionKey);
    _upsertThreadRecord(
      normalizedSessionKey,
      executionTarget: resolvedTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      gatewayEntryState: _gatewayEntryStateForTarget(resolvedTarget),
    );
    if (persistDefaultSelection) {
      _settings = _settings.copyWith(
        assistantExecutionTarget: resolvedTarget,
        assistantLastSessionKey: normalizedSessionKey,
      );
      await _persistSettings();
      await _persistThreads();
    } else {
      await _persistThreads();
    }
    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      return;
    }
    final targetProfile = _profileForTarget(resolvedTarget);
    if (targetProfile.host.trim().isEmpty || targetProfile.port <= 0) {
      return;
    }
    final expectedMode = resolvedTarget == AssistantExecutionTarget.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    if (connection.status == RuntimeConnectionStatus.connected &&
        connection.mode == expectedMode) {
      return;
    }
    try {
      await connectRelay(target: resolvedTarget);
    } catch (error) {
      _lastAssistantError = error.toString();
    }
  }

  Future<T> _enqueueThreadTurn<T>(String threadId, Future<T> Function() task) {
    final normalizedThreadId = _normalizedSessionKey(threadId);
    final previous =
        _threadTurnQueues[normalizedThreadId] ?? Future<void>.value();
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
          if (identical(_threadTurnQueues[normalizedThreadId], next)) {
            _threadTurnQueues.remove(normalizedThreadId);
          }
        });
    _threadTurnQueues[normalizedThreadId] = next;
    return completer.future;
  }

  String _augmentPromptWithAttachments(
    String prompt,
    List<GatewayChatAttachmentPayload> attachments,
  ) {
    if (attachments.isEmpty) {
      return prompt;
    }
    final buffer = StringBuffer(prompt.trim());
    buffer.write('\n\n');
    buffer.writeln(appText('附件（仅供本轮参考）：', 'Attachments (for this turn only):'));
    for (final item in attachments) {
      final name = item.fileName.trim().isEmpty ? 'attachment' : item.fileName;
      final mime = item.mimeType.trim().isEmpty
          ? 'application/octet-stream'
          : item.mimeType;
      buffer.writeln('- $name ($mime)');
    }
    return buffer.toString().trim();
  }

  Uri? _acpEndpointForTarget(AssistantExecutionTarget target) {
    final resolvedTarget = target == AssistantExecutionTarget.singleAgent
        ? AssistantExecutionTarget.remote
        : target;
    final profile = _profileForTarget(resolvedTarget);
    final host = profile.host.trim();
    if (host.isEmpty) {
      return null;
    }
    final candidate = host.contains('://')
        ? host
        : '${profile.tls ? 'https' : 'http'}://$host:${profile.port}';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    final scheme = uri.scheme.trim().isEmpty
        ? (profile.tls ? 'https' : 'http')
        : uri.scheme.trim().toLowerCase();
    final resolvedPort = uri.hasPort
        ? uri.port
        : (scheme == 'https' ? 443 : 80);
    return uri.replace(
      scheme: scheme,
      port: resolvedPort,
      path: '',
      query: null,
      fragment: null,
    );
  }

  Future<Map<String, dynamic>> _requestAcpSessionMessage({
    required Uri endpoint,
    required Map<String, dynamic> params,
    required bool hasInlineAttachments,
    void Function(Map<String, dynamic> notification)? onNotification,
  }) async {
    try {
      return await _acpClient.request(
        endpoint: endpoint,
        method: 'session.message',
        params: params,
        onNotification: onNotification,
      );
    } on WebAcpException catch (error) {
      if (!hasInlineAttachments || !_canFallbackInlineAttachments(error)) {
        rethrow;
      }
      final fallbackParams = Map<String, dynamic>.from(params)
        ..remove('inlineAttachments');
      try {
        return await _acpClient.request(
          endpoint: endpoint,
          method: 'session.message',
          params: fallbackParams,
          onNotification: onNotification,
        );
      } on Object catch (fallbackError) {
        throw Exception(
          appText(
            'ACP 暂不支持 inline 附件，回退旧协议也失败：$fallbackError',
            'ACP does not support inline attachments, and fallback to legacy attachment payload failed: $fallbackError',
          ),
        );
      }
    }
  }

  Future<void> _refreshAcpCapabilities(Uri endpoint) async {
    try {
      _acpCapabilities = await _acpClient.loadCapabilities(endpoint: endpoint);
    } catch (_) {
      _acpCapabilities = const WebAcpCapabilities.empty();
    }
  }

  bool _canFallbackInlineAttachments(WebAcpException error) {
    final code = (error.code ?? '').trim();
    if (code == '-32602' || code == 'INVALID_PARAMS') {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('inlineattachment') ||
        message.contains('unexpected field') ||
        message.contains('unknown field') ||
        message.contains('invalid params');
  }

  bool _unsupportedAcpSkillsStatus(WebAcpException error) {
    final code = (error.code ?? '').trim();
    if (code == '-32601' || code == 'METHOD_NOT_FOUND') {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('unknown method') ||
        message.contains('method not found') ||
        message.contains('skills.status');
  }

  int _base64Size(String base64) {
    final normalized = base64.trim().split(',').last.trim();
    if (normalized.isEmpty) {
      return 0;
    }
    final padding = normalized.endsWith('==')
        ? 2
        : (normalized.endsWith('=') ? 1 : 0);
    return (normalized.length * 3 ~/ 4) - padding;
  }

  _AcpSessionUpdate? _acpSessionUpdateFromNotification(
    Map<String, dynamic> notification, {
    required String sessionKey,
  }) {
    final method =
        notification['method']?.toString().trim().toLowerCase() ?? '';
    final params = _castMap(notification['params']);
    final payload = params.isNotEmpty
        ? params
        : _castMap(notification['payload']);
    final event = payload['event']?.toString().trim().toLowerCase() ?? method;
    final type =
        payload['type']?.toString().trim().toLowerCase() ??
        payload['state']?.toString().trim().toLowerCase() ??
        event;
    final payloadSession = _normalizedSessionKey(
      payload['sessionId']?.toString() ??
          payload['threadId']?.toString() ??
          payload['sessionKey']?.toString() ??
          sessionKey,
    );
    if (payloadSession != _normalizedSessionKey(sessionKey)) {
      return null;
    }
    final messageMap = _castMap(payload['message']);
    final messageText = _extractMessageText(messageMap).trim().isNotEmpty
        ? _extractMessageText(messageMap).trim()
        : payload['message']?.toString().trim() ?? '';
    final text =
        payload['delta']?.toString() ??
        payload['text']?.toString() ??
        payload['outputDelta']?.toString() ??
        '';
    final error =
        (payload['error'] is bool && payload['error'] as bool) ||
        type == 'error' ||
        event.contains('error');
    return _AcpSessionUpdate(
      type: type,
      text: text,
      message: messageText,
      error: error,
    );
  }

  void _appendStreamingText(String sessionKey, String delta) {
    if (delta.isEmpty) {
      return;
    }
    final key = _normalizedSessionKey(sessionKey);
    final current = _streamingTextBySession[key] ?? '';
    _streamingTextBySession[key] = '$current$delta';
  }

  void _clearStreamingText(String sessionKey) {
    _streamingTextBySession.remove(_normalizedSessionKey(sessionKey));
  }

  Future<void> _persistSettings() async {
    await _store.saveSettingsSnapshot(_settings);
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

  Future<void> _persistDraftSecrets() async {
    final aiGatewayApiKey = _draftSecretValues[_draftAiGatewayApiKeyKey];
    if ((aiGatewayApiKey ?? '').isNotEmpty) {
      _aiGatewayApiKeyCache = aiGatewayApiKey!;
      await _store.saveAiGatewayApiKey(_aiGatewayApiKeyCache);
    }
    _draftSecretValues.clear();
  }

  Future<void> _persistThreads() async {
    final records = _threadRecords.values.toList(growable: false);
    await _browserSessionRepository.saveThreadRecords(records);
    final invalidRemoteConfigMessage = _invalidRemoteSessionConfigMessage();
    if (invalidRemoteConfigMessage != null) {
      _sessionPersistenceStatusMessage = invalidRemoteConfigMessage;
      return;
    }
    final remoteRepository = _resolveRemoteSessionRepository();
    if (remoteRepository == null) {
      _sessionPersistenceStatusMessage = '';
      return;
    }
    try {
      await remoteRepository.saveThreadRecords(records);
      _sessionPersistenceStatusMessage = appText(
        '远端 Session API 已同步，浏览器缓存仍保留一份本地副本。',
        'Remote session API synced successfully; the browser cache remains as a local fallback.',
      );
    } catch (error) {
      _sessionPersistenceStatusMessage = _sessionPersistenceErrorLabel(error);
    }
  }

  Future<List<AssistantThreadRecord>> _loadThreadRecords() async {
    final browserRecords = await _browserSessionRepository.loadThreadRecords();
    final invalidRemoteConfigMessage = _invalidRemoteSessionConfigMessage();
    if (invalidRemoteConfigMessage != null) {
      _sessionPersistenceStatusMessage = invalidRemoteConfigMessage;
      return browserRecords;
    }
    final remoteRepository = _resolveRemoteSessionRepository();
    if (remoteRepository == null) {
      _sessionPersistenceStatusMessage = '';
      return browserRecords;
    }
    try {
      final remoteRecords = await remoteRepository.loadThreadRecords();
      if (remoteRecords.isNotEmpty) {
        _sessionPersistenceStatusMessage = appText(
          '远端 Session API 已启用，并覆盖浏览器中的本地缓存。',
          'Remote session API is active and overrides the browser cache.',
        );
        await _browserSessionRepository.saveThreadRecords(remoteRecords);
        return remoteRecords;
      }
      _sessionPersistenceStatusMessage = appText(
        '远端 Session API 已启用，但当前为空；浏览器缓存不会自动导入远端。',
        'The remote session API is active but empty, and the browser cache will not be imported automatically.',
      );
      return const <AssistantThreadRecord>[];
    } catch (error) {
      _sessionPersistenceStatusMessage = _sessionPersistenceErrorLabel(error);
      return browserRecords;
    }
  }

  WebSessionRepository? _resolveRemoteSessionRepository() {
    final config = _settings.webSessionPersistence;
    if (config.mode != WebSessionPersistenceMode.remote) {
      return null;
    }
    final normalizedBaseUrl = RemoteWebSessionRepository.normalizeBaseUrl(
      config.remoteBaseUrl,
    );
    if (normalizedBaseUrl == null) {
      return null;
    }
    return _remoteSessionRepositoryBuilder(
      config.copyWith(remoteBaseUrl: normalizedBaseUrl.toString()),
      _webSessionClientId,
      _webSessionApiTokenCache,
    );
  }

  String? _invalidRemoteSessionConfigMessage() {
    final config = _settings.webSessionPersistence;
    if (config.mode != WebSessionPersistenceMode.remote ||
        config.remoteBaseUrl.trim().isEmpty) {
      return null;
    }
    if (RemoteWebSessionRepository.normalizeBaseUrl(config.remoteBaseUrl) !=
        null) {
      return null;
    }
    return appText(
      'Session API URL 无效。请使用 HTTPS，或仅在 localhost / 127.0.0.1 开发环境中使用 HTTP。',
      'The Session API URL is invalid. Use HTTPS, or HTTP only for localhost / 127.0.0.1 during development.',
    );
  }

  String _sessionPersistenceErrorLabel(Object error) {
    return appText(
      '远端 Session API 当前不可用，已回退到浏览器缓存。${error.toString()}',
      'The remote session API is unavailable, so XWorkmate fell back to the browser cache. ${error.toString()}',
    );
  }

  static WebSessionRepository _defaultRemoteSessionRepository(
    WebSessionPersistenceConfig config,
    String clientId,
    String accessToken,
  ) {
    return RemoteWebSessionRepository(
      baseUrl: config.remoteBaseUrl,
      clientId: clientId,
      accessToken: accessToken,
    );
  }

  String _titleForRecord(AssistantThreadRecord record) {
    final customTitle =
        _settings
            .assistantCustomTaskTitles[_normalizedSessionKey(record.sessionKey)]
            ?.trim() ??
        '';
    if (customTitle.isNotEmpty) {
      return customTitle;
    }
    final title = record.title.trim();
    if (title.isNotEmpty) {
      return title;
    }
    return _deriveThreadTitle('', record.messages, fallback: record.sessionKey);
  }

  String _previewForRecord(AssistantThreadRecord record) {
    for (final message in record.messages.reversed) {
      final text = message.text.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return appText(
      '等待描述这个任务的第一条消息',
      'Waiting for the first message of this task',
    );
  }

  String _deriveThreadTitle(
    String currentTitle,
    List<GatewayChatMessage> messages, {
    String fallback = '',
  }) {
    final trimmedCurrent = currentTitle.trim();
    if (trimmedCurrent.isNotEmpty &&
        trimmedCurrent != appText('新对话', 'New conversation')) {
      return trimmedCurrent;
    }
    for (final message in messages) {
      if (message.role.trim().toLowerCase() != 'user') {
        continue;
      }
      final text = message.text.trim();
      if (text.isEmpty) {
        continue;
      }
      return text.length <= 32 ? text : '${text.substring(0, 32)}...';
    }
    return fallback.isEmpty ? appText('新对话', 'New conversation') : fallback;
  }

  String _hostLabel(String rawUrl) {
    final normalized = _aiGatewayClient.normalizeBaseUrl(rawUrl);
    return normalized?.host.trim() ?? '';
  }

  String _messageId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  Map<String, dynamic> _castMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  String _extractMessageText(Map<String, dynamic> message) {
    final directContent = message['content'];
    if (directContent is String) {
      return directContent;
    }
    final parts = <String>[];
    if (directContent is List) {
      for (final part in directContent) {
        final map = _castMap(part);
        final text = map['text']?.toString().trim();
        if (text != null && text.isNotEmpty) {
          parts.add(text);
        }
      }
    }
    return parts.join('\n').trim();
  }
}

class _AcpSessionUpdate {
  const _AcpSessionUpdate({
    required this.type,
    required this.text,
    required this.message,
    required this.error,
  });

  final String type;
  final String text;
  final String message;
  final bool error;
}

class WebConversationSummary {
  const WebConversationSummary({
    required this.sessionKey,
    required this.title,
    required this.preview,
    required this.updatedAtMs,
    required this.executionTarget,
    required this.pending,
    required this.current,
  });

  final String sessionKey;
  final String title;
  final String preview;
  final double updatedAtMs;
  final AssistantExecutionTarget executionTarget;
  final bool pending;
  final bool current;
}
