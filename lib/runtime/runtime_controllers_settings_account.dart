part of 'runtime_controllers_settings.dart';

extension SettingsControllerAccountExtension on SettingsController {
  AccountSessionSummary? get accountSession => accountSessionInternal;
  AccountRemoteProfile? get accountProfile => accountProfileInternal;
  bool get accountBusy => accountBusyInternal;
  String get accountStatus => accountStatusInternal;
  bool get accountSignedIn =>
      accountSessionTokenInternal.trim().isNotEmpty &&
      accountSessionInternal != null;
  bool get accountMfaRequired =>
      pendingAccountMfaTicketInternal.trim().isNotEmpty && !accountSignedIn;
  bool get hasEffectiveAiGatewayApiKey =>
      secureRefsInternal.containsKey('ai_gateway_api_key') ||
      (!snapshotInternal.accountLocalMode &&
          secureRefsInternal.containsKey(
            kAccountManagedSecretTargetAIGatewayAccessToken,
          ));

  String get effectiveAiGatewayBaseUrl {
    final local = snapshotInternal.aiGateway.baseUrl.trim();
    if (local.isNotEmpty) {
      return local;
    }
    if (snapshotInternal.accountLocalMode) {
      return '';
    }
    return accountProfileInternal?.apisixUrl.trim() ?? '';
  }

  List<String> get effectiveAiGatewayAvailableModels {
    final local = snapshotInternal.aiGateway.availableModels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (local.isNotEmpty) {
      return local;
    }
    if (snapshotInternal.accountLocalMode) {
      return const <String>[];
    }
    return accountProfileInternal?.aiGatewayAvailableModels ?? const <String>[];
  }

  AccountRuntimeClient buildAccountClient(String baseUrl) {
    return accountClientFactoryInternal?.call(baseUrl) ??
        AccountRuntimeClient(baseUrl: baseUrl);
  }

  Future<String> loadEffectiveAiGatewayApiKey() async {
    final localValue = await loadAiGatewayApiKey();
    if (localValue.trim().isNotEmpty) {
      return localValue;
    }
    if (snapshotInternal.accountLocalMode) {
      return '';
    }
    return (await storeInternal.loadAccountManagedSecret(
          target: kAccountManagedSecretTargetAIGatewayAccessToken,
        ))?.trim() ??
        '';
  }

  Future<String> loadEffectiveGatewayToken({int? profileIndex}) async {
    final localValue = await loadGatewayToken(profileIndex: profileIndex);
    if (localValue.trim().isNotEmpty) {
      return localValue;
    }
    if (snapshotInternal.accountLocalMode) {
      return '';
    }
    final resolvedIndex = profileIndex ?? kGatewayRemoteProfileIndex;
    if (resolvedIndex != kGatewayRemoteProfileIndex) {
      return '';
    }
    return (await storeInternal.loadAccountManagedSecret(
          target: kAccountManagedSecretTargetOpenclawGatewayToken,
        ))?.trim() ??
        '';
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

  Future<AccountSyncResult> syncAccountManagedSecrets({String baseUrl = ''}) =>
      syncAccountManagedSecretsSettingsInternal(this, baseUrl: baseUrl);

  Future<void> logoutAccount() => logoutAccountSettingsInternal(this);

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
        maskedValue: snapshotInternal.aiGateway.baseUrl.trim().isEmpty
            ? 'Not set'
            : snapshotInternal.aiGateway.baseUrl,
        status: snapshotInternal.aiGateway.syncState,
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
    accountProfileInternal = await storeInternal.loadAccountProfile();
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
    if (key.contains('openclaw')) {
      return 'Account';
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
    if (key.contains('openclaw')) {
      return 'Account';
    }
    if (key.contains('vault')) {
      return 'Secrets';
    }
    return 'Workspace';
  }
}
