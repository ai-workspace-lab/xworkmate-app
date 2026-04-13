part of 'runtime_controllers_settings.dart';

extension SettingsControllerAccountExtension on SettingsController {
  AccountSessionSummary? get accountSession => accountSessionInternal;
  AccountSyncState? get accountSyncState => accountSyncStateInternal;
  AccountRemoteProfile? get accountProfile =>
      accountSyncStateInternal?.syncedDefaults;
  bool get accountBusy => accountBusyInternal;
  String get accountStatus => accountStatusInternal;
  bool get accountSignedIn =>
      accountSessionTokenInternal.trim().isNotEmpty &&
      accountSessionInternal != null;
  bool get accountMfaRequired =>
      pendingAccountMfaTicketInternal.trim().isNotEmpty && !accountSignedIn;
  bool get hasEffectiveAiGatewayApiKey =>
      secureRefsInternal.containsKey(aiGatewayApiKeyRefInternal()) ||
      (aiGatewayApiKeyRefInternal() == 'ai_gateway_api_key' &&
          secureRefsInternal.containsKey('ai_gateway_api_key')) ||
      secureRefsInternal.containsKey(
        kAccountManagedSecretTargetAIGatewayAccessToken,
      );

  String get effectiveAiGatewayBaseUrl {
    final local = snapshotInternal.aiGateway.baseUrl.trim();
    if (local.isNotEmpty) {
      return local;
    }
    return '';
  }

  List<String> get effectiveAiGatewayAvailableModels {
    return snapshotInternal.aiGateway.availableModels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  AccountRuntimeClient buildAccountClient(String baseUrl) {
    return accountClientFactoryInternal?.call(baseUrl) ??
        AccountRuntimeClient(baseUrl: baseUrl);
  }

  Future<String> loadEffectiveAiGatewayApiKey() async {
    return resolveSecretValueInternal(
      refName: snapshotInternal.aiGateway.apiKeyRef,
      fallbackRefName: 'ai_gateway_api_key',
      accountTarget: kAccountManagedSecretTargetAIGatewayAccessToken,
    );
  }

  Future<String> loadEffectiveGatewayToken({int? profileIndex}) async {
    final resolvedProfileIndex = (profileIndex ?? kGatewayRemoteProfileIndex)
        .clamp(0, kGatewayProfileListLength - 1);
    return resolveSecretValueInternal(
      refName: gatewayTokenRefForProfileInternal(resolvedProfileIndex),
      fallbackRefName: SecretStore.gatewayTokenRefKey(resolvedProfileIndex),
      accountTarget: resolvedProfileIndex == kGatewayRemoteProfileIndex
          ? kAccountManagedSecretTargetBridgeAuthToken
          : '',
    );
  }

  Future<String> loadEffectiveGatewayPassword({int? profileIndex}) async {
    final resolvedProfileIndex = (profileIndex ?? kGatewayRemoteProfileIndex)
        .clamp(0, kGatewayProfileListLength - 1);
    return resolveSecretValueInternal(
      refName: gatewayPasswordRefForProfileInternal(resolvedProfileIndex),
      fallbackRefName: SecretStore.gatewayPasswordRefKey(resolvedProfileIndex),
      allowVaultLookup: true,
    );
  }

  Future<void> loginAccount({
    required String baseUrl,
    required String identifier,
    required String password,
  }) => loginAccountSettingsInternal(
    this,
    baseUrl: baseUrl,
    identifier: identifier,
    password: password,
  );

  Future<void> verifyAccountMfa({
    required String baseUrl,
    required String code,
  }) => verifyAccountMfaSettingsInternal(this, baseUrl: baseUrl, code: code);

  Future<void> restoreAccountSession({String baseUrl = ''}) =>
      restoreAccountSessionSettingsInternal(this, baseUrl: baseUrl);

  Future<AccountSyncResult> syncAccountSettings({String baseUrl = ''}) =>
      syncAccountSettingsInternal(this, baseUrl: baseUrl);

  Future<AccountSyncResult> syncAccountManagedSecrets({String baseUrl = ''}) =>
      syncAccountSettings(baseUrl: baseUrl);

  Future<void> logoutAccount() => logoutAccountSettingsInternal(this);

  Future<void> cancelAccountMfaChallenge() =>
      cancelAccountMfaChallengeSettingsInternal(this);

  List<SecretReferenceEntry> buildSecretReferences() {
    final entries = <SecretReferenceEntry>[
      ...secureRefsInternal.entries.map(
        (entry) => SecretReferenceEntry(
          name: entry.key,
          provider: providerNameForSecretInternal(entry.key),
          module: moduleForSecretInternal(entry.key),
          maskedValue: entry.value,
          status: 'In Use',
        ),
      ),
      SecretReferenceEntry(
        name: snapshotInternal.aiGateway.name,
        provider: 'LLM API',
        module: 'Settings',
        maskedValue: effectiveAiGatewayBaseUrl.trim().isEmpty
            ? 'Not set'
            : effectiveAiGatewayBaseUrl,
        status:
            accountSyncStateInternal?.syncState ??
            snapshotInternal.aiGateway.syncState,
      ),
    ];
    return entries;
  }

  Future<void> reloadDerivedStateInternal() async {
    final refs = await storeInternal.loadSecureRefs();
    secureRefsInternal = {
      for (final entry in refs.entries)
        entry.key: SecureConfigStore.maskValue(entry.value),
    };
    auditTrailInternal = await storeInternal.loadAuditTrail();
    accountSessionTokenInternal =
        (await storeInternal.loadAccountSessionToken())?.trim() ?? '';
    accountSessionInternal = await storeInternal.loadAccountSessionSummary();
    accountSyncStateInternal = await storeInternal.loadAccountSyncState();
    if (!accountBusyInternal) {
      if (accountSignedIn) {
        final email = accountSessionInternal?.email.trim() ?? '';
        accountStatusInternal = email.isEmpty
            ? 'Signed in'
            : 'Signed in as $email';
      } else if (accountMfaRequired) {
        accountStatusInternal = 'MFA required';
      } else {
        accountStatusInternal = 'Signed out';
      }
    }
  }

  String providerNameForSecretInternal(String key) {
    if (key.contains('vault')) {
      return 'Vault';
    }
    if (key.contains('ollama')) {
      return 'Ollama Cloud';
    }
    if (key.contains('ai_gateway')) {
      return 'LLM API';
    }
    if (key.contains('gateway')) {
      return 'Gateway';
    }
    return 'Local Store';
  }

  String moduleForSecretInternal(String key) {
    if (key.contains('gateway')) {
      return key.contains('device_token') ? 'Devices' : 'Assistant';
    }
    if (key.contains('ollama')) {
      return 'Settings';
    }
    if (key.contains('ai_gateway')) {
      return 'Settings';
    }
    if (key.contains('vault')) {
      return 'Secrets';
    }
    return 'Workspace';
  }
}
