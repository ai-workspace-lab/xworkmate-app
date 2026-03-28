part of 'app_controller_web.dart';

extension AppControllerWebGatewayConfig on AppController {
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
    _notifyChanged();
  }

  Future<AiGatewayConnectionCheck> testAiGatewayConnection({
    required String baseUrl,
    required String apiKey,
  }) async {
    _aiGatewayBusy = true;
    _notifyChanged();
    try {
      return await _aiGatewayClient.testConnection(
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
    } finally {
      _aiGatewayBusy = false;
      _notifyChanged();
    }
  }

  Future<void> syncAiGatewayModels({
    required String name,
    required String baseUrl,
    required String provider,
    required String apiKey,
  }) async {
    _aiGatewayBusy = true;
    _notifyChanged();
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
      _notifyChanged();
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
    _notifyChanged();
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
}
