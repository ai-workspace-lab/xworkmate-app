import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/legacy_settings_recovery.dart';
import '../runtime/runtime_models.dart';
import '../web/web_ai_gateway_client.dart';
import '../web/web_relay_gateway_client.dart';
import '../web/web_session_repository.dart';
import '../web/web_store.dart';
import 'app_capabilities.dart';
import 'ui_feature_manifest.dart';

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
    WebRelayGatewayClient? relayClient,
    RemoteWebSessionRepositoryBuilder? remoteSessionRepositoryBuilder,
    UiFeatureManifest? uiFeatureManifest,
  }) : _store = store ?? WebStore(),
       _uiFeatureManifest = uiFeatureManifest ?? UiFeatureManifest.fallback(),
       _aiGatewayClient = aiGatewayClient ?? const WebAiGatewayClient(),
       _remoteSessionRepositoryBuilder =
           remoteSessionRepositoryBuilder ?? _defaultRemoteSessionRepository {
    _relayClient = relayClient ?? WebRelayGatewayClient(_store);
    _relayEventsSubscription = _relayClient.events.listen(_handleRelayEvent);
    unawaited(_initialize());
  }

  final WebStore _store;
  final UiFeatureManifest _uiFeatureManifest;
  final WebAiGatewayClient _aiGatewayClient;
  final RemoteWebSessionRepositoryBuilder _remoteSessionRepositoryBuilder;
  late final WebRelayGatewayClient _relayClient;
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
  final Map<String, AssistantThreadRecord> _threadRecords =
      <String, AssistantThreadRecord>{};
  final Set<String> _pendingSessionKeys = <String>{};
  final Map<String, String> _streamingTextBySession = <String, String>{};
  String _currentSessionKey = '';
  String? _lastAssistantError;
  String _webSessionApiTokenCache = '';
  String _webSessionClientId = '';
  String _sessionPersistenceStatusMessage = '';

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
  bool get hasSettingsDraftChanges =>
      settingsDraft.toJsonString() != _settings.toJsonString() ||
      _draftSecretValues.isNotEmpty;
  bool get hasPendingSettingsApply => _pendingSettingsApply;
  String get settingsDraftStatusMessage => _settingsDraftStatusMessage;
  LegacyRecoveryReport get legacyRecoveryReport => const LegacyRecoveryReport();
  AppLanguage get appLanguage => _settings.appLanguage;
  GatewayConnectionSnapshot get connection => _relayClient.snapshot;
  bool get relayBusy => _relayBusy;
  bool get aiGatewayBusy => _aiGatewayBusy;
  String? get lastAssistantError => _lastAssistantError;
  String get currentSessionKey => _currentSessionKey;
  WebSessionPersistenceConfig get webSessionPersistence =>
      _settings.webSessionPersistence;
  String get sessionPersistenceStatusMessage =>
      _sessionPersistenceStatusMessage;
  bool get supportsDesktopIntegration => false;
  bool get hasStoredGatewayToken => storedRelayTokenMask != null;
  bool get hasStoredAiGatewayApiKey => storedAiGatewayApiKeyMask != null;
  String? get storedGatewayTokenMask => storedRelayTokenMask;
  String? get storedRelayTokenMask => WebStore.maskValue(
    _relayTokenCache.trim().isEmpty ? '' : _relayTokenCache,
  );
  String? get storedRelayPasswordMask => WebStore.maskValue(
    _relayPasswordCache.trim().isEmpty ? '' : _relayPasswordCache,
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

  String _relayTokenCache = '';
  String _relayPasswordCache = '';
  String _aiGatewayApiKeyCache = '';

  static const String _draftAiGatewayApiKeyKey = 'ai_gateway_api_key';
  static const String _draftVaultTokenKey = 'vault_token';
  static const String _draftOllamaApiKeyKey = 'ollama_cloud_api_key';

  UiFeatureAccess featuresFor(UiFeaturePlatform platform) {
    return _uiFeatureManifest.forPlatform(platform);
  }

  AssistantExecutionTarget get assistantExecutionTarget =>
      _currentRecord.executionTarget ?? _settings.assistantExecutionTarget;
  AssistantExecutionTarget get currentAssistantExecutionTarget =>
      assistantExecutionTarget;
  bool get isSingleAgentMode =>
      assistantExecutionTarget == AssistantExecutionTarget.singleAgent;
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
    final entries =
        _threadRecords.values
            .map(
              (record) => WebConversationSummary(
                sessionKey: record.sessionKey,
                title: _titleForRecord(record),
                preview: _previewForRecord(record),
                updatedAtMs:
                    record.updatedAtMs ??
                    DateTime.now().millisecondsSinceEpoch.toDouble(),
                executionTarget:
                    _sanitizeTarget(record.executionTarget) ??
                    AssistantExecutionTarget.singleAgent,
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

  AssistantThreadConnectionState get currentAssistantConnectionState {
    final target = currentAssistantExecutionTarget;
    if (target == AssistantExecutionTarget.singleAgent) {
      final host = _hostLabel(_settings.aiGateway.baseUrl);
      final model = resolvedAiGatewayModel;
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
    return AssistantThreadConnectionState(
      executionTarget: target,
      status: connection.status,
      primaryLabel: connection.status.label,
      detailLabel:
          connection.remoteAddress ?? appText('Relay 未连接', 'Relay offline'),
      ready: connection.status == RuntimeConnectionStatus.connected,
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
      _relayTokenCache = await _store.loadRelayToken();
      _relayPasswordCache = await _store.loadRelayPassword();
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
      _currentSessionKey = conversations.first.sessionKey;
      _settingsDraft = _settings;
      _settingsDraftInitialized = true;
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
    return (
      state: 'unsupported',
      message: 'Gateway test unavailable on web',
      endpoint: '',
    );
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
    final resolvedTarget =
        _sanitizeTarget(target) ?? _settings.assistantExecutionTarget;
    final record = _newRecord(target: resolvedTarget);
    _threadRecords[record.sessionKey] = record;
    _currentSessionKey = record.sessionKey;
    _lastAssistantError = null;
    await _persistThreads();
    notifyListeners();
  }

  Future<void> switchConversation(String sessionKey) async {
    if (!_threadRecords.containsKey(sessionKey)) {
      return;
    }
    _currentSessionKey = sessionKey;
    _lastAssistantError = null;
    notifyListeners();
    final record = _threadRecords[sessionKey]!;
    if (_sanitizeTarget(record.executionTarget) ==
            AssistantExecutionTarget.remote &&
        connection.status == RuntimeConnectionStatus.connected) {
      await refreshRelayHistory(sessionKey: sessionKey);
    }
  }

  Future<void> setAssistantExecutionTarget(
    AssistantExecutionTarget target,
  ) async {
    final resolvedTarget =
        _sanitizeTarget(target) ?? AssistantExecutionTarget.singleAgent;
    _settings = _settings.copyWith(assistantExecutionTarget: resolvedTarget);
    _replaceCurrentRecord(
      _currentRecord.copyWith(executionTarget: resolvedTarget),
    );
    await _persistSettings();
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
    } catch (error) {
      _settings = _settings.copyWith(
        aiGateway: _settings.aiGateway.copyWith(
          syncState: 'error',
          syncMessage: _aiGatewayClient.networkErrorLabel(error),
        ),
      );
      await _persistSettings();
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
  }) async {
    final remoteProfile = _settings.primaryRemoteGatewayProfile;
    _settings = _settings.copyWith(
      gatewayProfiles: replaceGatewayProfileAt(
        _settings.gatewayProfiles,
        kGatewayRemoteProfileIndex,
        remoteProfile.copyWith(
          mode: RuntimeConnectionMode.remote,
          useSetupCode: false,
          setupCode: '',
          host: host.trim(),
          port: port,
          tls: tls,
        ),
      ),
    );
    _relayTokenCache = token.trim();
    _relayPasswordCache = password.trim();
    await _store.saveRelayToken(_relayTokenCache);
    await _store.saveRelayPassword(_relayPasswordCache);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> connectRelay() async {
    _relayBusy = true;
    notifyListeners();
    try {
      final remoteProfile = _settings.primaryRemoteGatewayProfile.copyWith(
        mode: RuntimeConnectionMode.remote,
        useSetupCode: false,
        setupCode: '',
      );
      await _relayClient.connect(
        profile: remoteProfile,
        authToken: _relayTokenCache,
        authPassword: _relayPasswordCache,
      );
      await refreshRelaySessions();
      await refreshRelayModels();
      if (_sanitizeTarget(_currentRecord.executionTarget) ==
          AssistantExecutionTarget.remote) {
        await refreshRelayHistory(sessionKey: _currentSessionKey);
      }
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
    } finally {
      _relayBusy = false;
      notifyListeners();
    }
  }

  Future<void> refreshRelaySessions() async {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    final sessions = await _relayClient.listSessions(limit: 50);
    for (final session in sessions) {
      final existing = _threadRecords[session.key];
      final next = AssistantThreadRecord(
        sessionKey: session.key,
        messages: existing?.messages ?? const <GatewayChatMessage>[],
        updatedAtMs:
            session.updatedAtMs ??
            existing?.updatedAtMs ??
            DateTime.now().millisecondsSinceEpoch.toDouble(),
        title: (session.derivedTitle ?? session.displayName ?? session.key)
            .trim(),
        archived: false,
        executionTarget: AssistantExecutionTarget.remote,
        messageViewMode:
            existing?.messageViewMode ?? AssistantMessageViewMode.rendered,
      );
      _threadRecords[session.key] = next;
    }
    await _persistThreads();
    notifyListeners();
  }

  Future<void> refreshRelayModels() async {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    final models = await _relayClient.listModels();
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
    notifyListeners();
  }

  Future<void> refreshRelayHistory({String? sessionKey}) async {
    final resolvedKey = (sessionKey ?? _currentSessionKey).trim();
    if (resolvedKey.isEmpty ||
        connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    final messages = await _relayClient.loadHistory(resolvedKey, limit: 120);
    final existing = _threadRecords[resolvedKey];
    final next =
        (existing ?? _newRecord(target: AssistantExecutionTarget.remote))
            .copyWith(
              sessionKey: resolvedKey,
              messages: messages,
              updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
              title: _deriveThreadTitle(
                existing?.title ?? '',
                messages,
                fallback: resolvedKey,
              ),
              executionTarget: AssistantExecutionTarget.remote,
            );
    _threadRecords[resolvedKey] = next;
    _streamingTextBySession.remove(resolvedKey);
    await _persistThreads();
    notifyListeners();
  }

  Future<void> sendMessage(String rawMessage) async {
    final trimmed = rawMessage.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _lastAssistantError = null;
    final target = assistantExecutionTarget;
    final current = _currentRecord;
    final updatedMessages = <GatewayChatMessage>[
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
    _replaceCurrentRecord(
      current.copyWith(
        messages: updatedMessages,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        title: _deriveThreadTitle(current.title, updatedMessages),
        executionTarget: target,
      ),
    );
    _pendingSessionKeys.add(_currentSessionKey);
    await _persistThreads();
    notifyListeners();

    try {
      if (target == AssistantExecutionTarget.singleAgent) {
        if (!canUseAiGatewayConversation) {
          throw Exception(
            appText(
              '请先在 Settings 配置单机智能体所需的 AI Gateway 地址、API Key 和默认模型。',
              'Configure the Single Agent AI Gateway endpoint, API key, and default model first.',
            ),
          );
        }
        final reply = await _aiGatewayClient.completeChat(
          baseUrl: _settings.aiGateway.baseUrl,
          apiKey: _aiGatewayApiKeyCache,
          model: resolvedAiGatewayModel,
          history: updatedMessages,
        );
        _appendAssistantMessage(
          sessionKey: _currentSessionKey,
          text: reply,
          error: false,
        );
      } else {
        if (connection.status != RuntimeConnectionStatus.connected) {
          throw Exception(
            appText(
              'Relay OpenClaw Gateway 尚未连接。',
              'Relay OpenClaw Gateway is not connected.',
            ),
          );
        }
        await _relayClient.sendChat(
          sessionKey: _currentSessionKey,
          message: trimmed,
          thinking: 'medium',
        );
      }
    } catch (error) {
      _appendAssistantMessage(
        sessionKey: _currentSessionKey,
        text: error.toString(),
        error: true,
      );
      _lastAssistantError = error.toString();
      _pendingSessionKeys.remove(_currentSessionKey);
      _streamingTextBySession.remove(_currentSessionKey);
      await _persistThreads();
      notifyListeners();
    }
  }

  Future<void> selectDirectModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _settings = _settings.copyWith(defaultModel: trimmed);
    await _persistSettings();
    notifyListeners();
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
    final target =
        _sanitizeTarget(snapshot.assistantExecutionTarget) ??
        AssistantExecutionTarget.singleAgent;
    final normalizedSessionBaseUrl =
        RemoteWebSessionRepository.normalizeBaseUrl(
          snapshot.webSessionPersistence.remoteBaseUrl,
        )?.toString() ??
        '';
    return snapshot.copyWith(
      assistantExecutionTarget: target,
      gatewayProfiles: replaceGatewayProfileAt(
        snapshot.gatewayProfiles,
        kGatewayRemoteProfileIndex,
        snapshot.primaryRemoteGatewayProfile.copyWith(
          mode: RuntimeConnectionMode.remote,
          useSetupCode: false,
          setupCode: '',
        ),
      ),
      webSessionPersistence: snapshot.webSessionPersistence.copyWith(
        remoteBaseUrl: normalizedSessionBaseUrl,
      ),
      assistantNavigationDestinations: const <WorkspaceDestination>[],
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
    );
  }

  AssistantExecutionTarget? _sanitizeTarget(AssistantExecutionTarget? target) {
    return switch (target) {
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
    final prefix = target == AssistantExecutionTarget.remote
        ? 'relay'
        : 'direct';
    return AssistantThreadRecord(
      sessionKey: '$prefix:$timestamp',
      messages: const <GatewayChatMessage>[],
      updatedAtMs: timestamp.toDouble(),
      title: title ?? appText('新对话', 'New conversation'),
      archived: false,
      executionTarget: target,
      messageViewMode: AssistantMessageViewMode.rendered,
    );
  }

  void _replaceCurrentRecord(AssistantThreadRecord record) {
    _threadRecords[record.sessionKey] = record;
    _currentSessionKey = record.sessionKey;
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
  }

  void _handleRelayEvent(GatewayPushEvent event) {
    if (event.event != 'chat') {
      return;
    }
    final payload = _castMap(event.payload);
    final sessionKey = (payload['sessionKey']?.toString().trim() ?? '').trim();
    if (sessionKey.isEmpty) {
      return;
    }
    final state = payload['state']?.toString().trim() ?? '';
    final message = _castMap(payload['message']);
    final text = _extractMessageText(message);
    if (text.isNotEmpty && (state == 'delta' || state == 'final')) {
      _streamingTextBySession[sessionKey] = text;
    }
    if (state == 'final' || state == 'aborted' || state == 'error') {
      _pendingSessionKeys.remove(sessionKey);
      unawaited(refreshRelaySessions());
      unawaited(refreshRelayHistory(sessionKey: sessionKey));
    }
    notifyListeners();
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
