import 'account_runtime_client.dart';
import 'runtime_controllers_settings.dart';
import 'runtime_models.dart';

Future<void> loginAccountSettingsInternal(
  SettingsController controller, {
  required String baseUrl,
  required String identifier,
  required String password,
}) async {
  final normalizedBaseUrl = normalizeAccountBaseUrlSettingsInternal(
    baseUrl,
    fallback: controller.snapshotInternal.accountBaseUrl,
  );
  if (normalizedBaseUrl.isEmpty) {
    controller.accountStatusInternal = 'Account base URL is required';
    controller.notifyListeners();
    return;
  }
  if (identifier.trim().isEmpty || password.isEmpty) {
    controller.accountStatusInternal = 'Email and password are required';
    controller.notifyListeners();
    return;
  }

  controller.accountBusyInternal = true;
  controller.accountStatusInternal = 'Signing in...';
  controller.pendingAccountMfaTicketInternal = '';
  controller.pendingAccountBaseUrlInternal = '';
  controller.notifyListeners();

  try {
    final client = controller.buildAccountClient(normalizedBaseUrl);
    final payload = await client.login(
      identifier: identifier.trim(),
      password: password,
    );
    final requiresMfa =
        payload['mfaRequired'] == true || payload['mfa_required'] == true;
    if (requiresMfa) {
      controller.pendingAccountMfaTicketInternal =
          _stringValue(payload['mfaToken']).isNotEmpty
          ? _stringValue(payload['mfaToken'])
          : _stringValue(payload['mfaTicket']);
      controller.pendingAccountBaseUrlInternal = normalizedBaseUrl;
      controller.accountStatusInternal = 'MFA required';
      return;
    }

    await completeAccountSignInSettingsInternal(
      controller,
      baseUrl: normalizedBaseUrl,
      payload: payload,
      identifier: identifier.trim(),
    );
  } on AccountRuntimeException catch (error) {
    controller.accountStatusInternal = error.message;
  } finally {
    controller.accountBusyInternal = false;
    controller.notifyListeners();
  }
}

Future<void> verifyAccountMfaSettingsInternal(
  SettingsController controller, {
  required String baseUrl,
  required String code,
}) async {
  final normalizedBaseUrl = normalizeAccountBaseUrlSettingsInternal(
    baseUrl,
    fallback: controller.pendingAccountBaseUrlInternal.isNotEmpty
        ? controller.pendingAccountBaseUrlInternal
        : controller.snapshotInternal.accountBaseUrl,
  );
  if (normalizedBaseUrl.isEmpty) {
    controller.accountStatusInternal = 'Account base URL is required';
    controller.notifyListeners();
    return;
  }
  if (controller.pendingAccountMfaTicketInternal.trim().isEmpty) {
    controller.accountStatusInternal = 'MFA ticket is missing';
    controller.notifyListeners();
    return;
  }
  if (code.trim().isEmpty) {
    controller.accountStatusInternal = 'MFA code is required';
    controller.notifyListeners();
    return;
  }

  controller.accountBusyInternal = true;
  controller.accountStatusInternal = 'Verifying MFA...';
  controller.notifyListeners();

  try {
    final client = controller.buildAccountClient(normalizedBaseUrl);
    final payload = await client.verifyMfa(
      mfaToken: controller.pendingAccountMfaTicketInternal,
      code: code.trim(),
    );
    final identifier =
        (await controller.storeInternal.loadAccountSessionIdentifier())
            ?.trim() ??
        controller.snapshotInternal.accountUsername.trim();
    controller.pendingAccountMfaTicketInternal = '';
    controller.pendingAccountBaseUrlInternal = '';
    await completeAccountSignInSettingsInternal(
      controller,
      baseUrl: normalizedBaseUrl,
      payload: payload,
      identifier: identifier,
    );
  } on AccountRuntimeException catch (error) {
    controller.accountStatusInternal = error.message;
  } finally {
    controller.accountBusyInternal = false;
    controller.notifyListeners();
  }
}

Future<void> completeAccountSignInSettingsInternal(
  SettingsController controller, {
  required String baseUrl,
  required Map<String, dynamic> payload,
  required String identifier,
}) async {
  final token = _stringValue(payload['token']).isNotEmpty
      ? _stringValue(payload['token'])
      : _stringValue(payload['access_token']);
  if (token.isEmpty) {
    controller.accountStatusInternal = 'Account session token is missing';
    return;
  }
  final user = _asMap(payload['user']);
  final sessionSummary = _accountSessionSummaryFromUserPayload(user);
  await controller.storeInternal.saveAccountSessionToken(token);
  await controller.storeInternal.saveAccountSessionExpiresAtMs(
    _parseExpiresAtMs(payload['expiresAt']),
  );
  await controller.storeInternal.saveAccountSessionUserId(
    sessionSummary.userId,
  );
  await controller.storeInternal.saveAccountSessionIdentifier(identifier);
  await controller.storeInternal.saveAccountSessionSummary(sessionSummary);
  await syncAccountSettingsInternal(
    controller,
    baseUrl: baseUrl,
    profilePayloadOverride: payload,
    quiet: true,
  );
  await controller.reloadDerivedStateInternal();
  final email = controller.accountSessionInternal?.email.trim() ?? '';
  controller.accountStatusInternal = email.isEmpty
      ? 'Signed in'
      : 'Signed in as $email';
}

Future<void> restoreAccountSessionSettingsInternal(
  SettingsController controller, {
  String baseUrl = '',
  bool quiet = false,
}) async {
  final normalizedBaseUrl = normalizeAccountBaseUrlSettingsInternal(
    baseUrl,
    fallback: controller.snapshotInternal.accountBaseUrl,
  );
  final token =
      (await controller.storeInternal.loadAccountSessionToken())?.trim() ?? '';
  if (normalizedBaseUrl.isEmpty || token.isEmpty) {
    return;
  }

  if (!quiet) {
    controller.accountBusyInternal = true;
    controller.accountStatusInternal = 'Restoring account session...';
    controller.notifyListeners();
  }

  try {
    final client = controller.buildAccountClient(normalizedBaseUrl);
    final payload = await client.loadProfile(token: token);
    final session = _accountSessionSummaryFromUserPayload(
      _asMap(payload['user']),
    );
    await controller.storeInternal.saveAccountSessionSummary(session);
    if (session.userId.trim().isNotEmpty) {
      await controller.storeInternal.saveAccountSessionUserId(session.userId);
    }
    final identifier = session.email.trim().isNotEmpty
        ? session.email.trim()
        : (await controller.storeInternal.loadAccountSessionIdentifier())
                  ?.trim() ??
              '';
    if (identifier.isNotEmpty) {
      await controller.storeInternal.saveAccountSessionIdentifier(identifier);
    }
    controller.accountStatusInternal = session.email.trim().isEmpty
        ? 'Signed in'
        : 'Signed in as ${session.email.trim()}';
    await syncAccountSettingsInternal(
      controller,
      baseUrl: normalizedBaseUrl,
      profilePayloadOverride: payload,
      quiet: true,
    );
  } on AccountRuntimeException catch (error) {
    if (error.statusCode == 401) {
      await logoutAccountSettingsInternal(
        controller,
        statusMessage: 'Session expired',
        quiet: true,
      );
    } else {
      controller.accountStatusInternal =
          'Session restore failed: ${error.message}';
    }
  } finally {
    if (!quiet) {
      controller.accountBusyInternal = false;
      controller.notifyListeners();
    }
  }
}

Future<AccountSyncResult> syncAccountSettingsInternal(
  SettingsController controller, {
  String baseUrl = '',
  bool quiet = false,
  Map<String, dynamic> profilePayloadOverride = const <String, dynamic>{},
}) async {
  final normalizedBaseUrl = normalizeAccountBaseUrlSettingsInternal(
    baseUrl,
    fallback: controller.snapshotInternal.accountBaseUrl,
  );
  final sessionToken =
      (await controller.storeInternal.loadAccountSessionToken())?.trim() ?? '';
  if (sessionToken.isEmpty) {
    return _persistAccountSyncFailureInternal(
      controller,
      state: 'blocked',
      message: 'Account session is unavailable',
      quiet: quiet,
    );
  }

  if (!quiet) {
    controller.accountBusyInternal = true;
    controller.accountStatusInternal = 'Syncing bridge access...';
    controller.notifyListeners();
  }

  try {
    if (normalizedBaseUrl.isEmpty) {
      return _persistAccountSyncContractFailureInternal(
        controller,
        message: 'Account base URL is required',
        quiet: quiet,
      );
    }

    final client = controller.buildAccountClient(normalizedBaseUrl);
    Map<String, dynamic> profilePayload = profilePayloadOverride;
    if (profilePayload.isEmpty) {
      profilePayload = await client.loadProfile(token: sessionToken);
    }
    await _persistAccountSessionSummaryFromProfilePayloadInternal(
      controller,
      profilePayload,
    );

    final syncPayload = await client.loadXWorkmateProfileSync(
      token: sessionToken,
    );
    final bridgeToken = _stringValue(syncPayload['BRIDGE_AUTH_TOKEN']);
    if (bridgeToken.isEmpty) {
      return _persistAccountSyncContractFailureInternal(
        controller,
        message: 'Bridge authorization is unavailable',
        quiet: quiet,
      );
    }

    await controller.storeInternal.saveAccountManagedSecret(
      target: kAccountManagedSecretTargetBridgeAuthToken,
      value: bridgeToken,
    );
    final syncedBridgeServerUrl = _resolveBridgeServerUrl(syncPayload);
    if (!isSupportedExternalAcpEndpoint(syncedBridgeServerUrl)) {
      return _persistAccountSyncContractFailureInternal(
        controller,
        message: 'Bridge endpoint is unavailable',
        quiet: quiet,
      );
    }
    final resolvedBridgeServerUrl = _resolveCurrentBridgeServerUrl(
      controller,
      bridgeServerUrlOverride: syncedBridgeServerUrl,
    );
    await controller.storeInternal.clearAccountManagedSecret(
      target: kAccountManagedSecretTargetAIGatewayAccessToken,
    );
    await controller.storeInternal.clearAccountManagedSecret(
      target: kAccountManagedSecretTargetOllamaCloudApiKey,
    );

    final nextState = AccountSyncState.defaults().copyWith(
      syncedDefaults: AccountRemoteProfile.defaults().copyWith(
        bridgeServerUrl: resolvedBridgeServerUrl,
      ),
      syncState: 'ready',
      syncMessage: 'Bridge access synced',
      lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
      lastSyncSource: resolvedBridgeServerUrl,
      lastSyncError: '',
      profileScope: 'bridge',
      tokenConfigured: const AccountTokenConfigured(
        bridge: true,
        vault: false,
        apisix: false,
      ),
    );
    await controller.storeInternal.saveAccountSyncState(nextState);
    final currentSettings = controller.snapshotInternal;
    final currentModeConfig = currentSettings.acpBridgeServerModeConfig;
    final nextModeConfig = currentModeConfig.copyWith(
      cloudSynced: currentModeConfig.cloudSynced.copyWith(
        accountBaseUrl: '',
        accountIdentifier: '',
        lastSyncAt: nextState.lastSyncAtMs,
        remoteServerSummary: currentModeConfig.cloudSynced.remoteServerSummary
            .copyWith(
              endpoint: resolvedBridgeServerUrl,
              hasAdvancedOverrides: false,
            ),
      ),
    );
    final sanitizedSettings = _sanitizeBridgeOnlyAccountSyncSettings(
      currentSettings.copyWith(acpBridgeServerModeConfig: nextModeConfig),
    );
    // Always save the snapshot after a successful sync to ensure Token and URL updates
    // are correctly persisted in the store and reflected in the UI.
    await controller.saveSnapshot(sanitizedSettings);

    await controller.reloadDerivedStateInternal();
    final email = controller.accountSessionInternal?.email.trim() ?? '';
    controller.accountStatusInternal = email.isEmpty
        ? 'Signed in'
        : 'Signed in as $email';
    if (!quiet) {
      controller.accountBusyInternal = false;
      controller.notifyListeners();
    }
    return const AccountSyncResult(
      state: 'ready',
      message: 'Bridge access synced',
    );
  } on AccountRuntimeException catch (error) {
    return _persistAccountSyncContractFailureInternal(
      controller,
      message: error.message,
      quiet: quiet,
    );
  } catch (error) {
    return _persistAccountSyncContractFailureInternal(
      controller,
      message: error.toString(),
      quiet: quiet,
    );
  }
}

Future<void> logoutAccountSettingsInternal(
  SettingsController controller, {
  String statusMessage = 'Signed out',
  bool quiet = false,
}) async {
  if (!quiet) {
    controller.accountBusyInternal = true;
    controller.notifyListeners();
  }
  controller.pendingAccountMfaTicketInternal = '';
  controller.pendingAccountBaseUrlInternal = '';
  await controller.storeInternal.clearAccountSessionToken();
  await controller.storeInternal.clearAccountSessionExpiresAtMs();
  await controller.storeInternal.clearAccountSessionUserId();
  await controller.storeInternal.clearAccountSessionIdentifier();
  await controller.storeInternal.clearAccountSessionSummary();
  await controller.storeInternal.clearAccountSyncState();
  await controller.storeInternal.clearAccountManagedSecrets();
  final currentSnapshot = controller.snapshotInternal;
  final clearedCloudSync = currentSnapshot.acpBridgeServerModeConfig.cloudSynced
      .copyWith(
        accountBaseUrl: '',
        accountIdentifier: '',
        lastSyncAt: 0,
        remoteServerSummary: currentSnapshot
            .acpBridgeServerModeConfig
            .cloudSynced
            .remoteServerSummary
            .copyWith(endpoint: '', hasAdvancedOverrides: false),
      );
  await controller.saveSnapshot(
    currentSnapshot.copyWith(
      acpBridgeServerModeConfig: currentSnapshot.acpBridgeServerModeConfig
          .copyWith(cloudSynced: clearedCloudSync),
    ),
  );
  controller.accountStatusInternal = statusMessage;
  if (!quiet) {
    controller.accountBusyInternal = false;
    controller.notifyListeners();
  }
}

Future<void> cancelAccountMfaChallengeSettingsInternal(
  SettingsController controller,
) async {
  controller.pendingAccountMfaTicketInternal = '';
  controller.pendingAccountBaseUrlInternal = '';
  if (!controller.accountSignedIn) {
    controller.accountStatusInternal = 'Signed out';
  }
  controller.notifyListeners();
}

AccountSessionSummary _accountSessionSummaryFromUserPayload(
  Map<String, dynamic> user,
) {
  final mfa = _asMap(user['mfa']);
  final totpEnabled = mfa['totpEnabled'] as bool? ?? false;
  final totpPending = mfa['totpPending'] as bool? ?? false;
  return AccountSessionSummary(
    userId: _stringValue(user['id']),
    email: _stringValue(user['email']),
    name: _stringValue(user['name']).isNotEmpty
        ? _stringValue(user['name'])
        : _stringValue(user['username']),
    role: _stringValue(user['role']),
    mfaEnabled: user['mfaEnabled'] as bool? ?? totpEnabled,
    totpEnabled: totpEnabled,
    totpPending: totpPending,
  );
}

String normalizeAccountBaseUrlSettingsInternal(
  String raw, {
  String fallback = '',
}) {
  final candidate = raw.trim().isNotEmpty ? raw.trim() : fallback.trim();
  if (candidate.isEmpty) {
    return '';
  }
  return candidate.endsWith('/')
      ? candidate.substring(0, candidate.length - 1)
      : candidate;
}

SettingsSnapshot _sanitizeBridgeOnlyAccountSyncSettings(
  SettingsSnapshot settings,
) {
  final normalizedAiGatewayRef =
      settings.aiGateway.apiKeyRef.trim() ==
          kAccountManagedSecretTargetAIGatewayAccessToken
      ? AiGatewayProfile.defaults().apiKeyRef
      : settings.aiGateway.apiKeyRef;
  final normalizedOllamaRef =
      settings.ollamaCloud.apiKeyRef.trim() ==
          kAccountManagedSecretTargetOllamaCloudApiKey
      ? OllamaCloudConfig.defaults().apiKeyRef
      : settings.ollamaCloud.apiKeyRef;
  return settings.copyWith(
    aiGateway: settings.aiGateway.copyWith(apiKeyRef: normalizedAiGatewayRef),
    ollamaCloud: settings.ollamaCloud.copyWith(apiKeyRef: normalizedOllamaRef),
  );
}

Future<void> _persistAccountSessionSummaryFromProfilePayloadInternal(
  SettingsController controller,
  Map<String, dynamic> payload,
) async {
  final user = _asMap(payload['user']);
  if (user.isEmpty) {
    return;
  }
  final summary = _accountSessionSummaryFromUserPayload(user);
  final hasSessionDetails =
      summary.userId.trim().isNotEmpty ||
      summary.email.trim().isNotEmpty ||
      summary.name.trim().isNotEmpty ||
      summary.role.trim().isNotEmpty;
  if (!hasSessionDetails) {
    return;
  }
  await controller.storeInternal.saveAccountSessionSummary(summary);
  if (summary.userId.trim().isNotEmpty) {
    await controller.storeInternal.saveAccountSessionUserId(summary.userId);
  }
  final identifier = summary.email.trim().isNotEmpty
      ? summary.email.trim()
      : (await controller.storeInternal.loadAccountSessionIdentifier())
                ?.trim() ??
            controller.snapshotInternal.accountUsername.trim();
  if (identifier.isNotEmpty) {
    await controller.storeInternal.saveAccountSessionIdentifier(identifier);
  }
}

Future<AccountSyncResult> _persistAccountSyncFailureInternal(
  SettingsController controller, {
  required String state,
  required String message,
  required bool quiet,
}) async {
  await _persistAccountSyncStateInternal(
    controller,
    AccountSyncState.defaults().copyWith(
      syncState: state,
      syncMessage: message,
      lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
      lastSyncError: message,
      profileScope: 'bridge',
    ),
  );
  controller.accountStatusInternal = message;
  if (!quiet) {
    controller.accountBusyInternal = false;
    controller.notifyListeners();
  }
  return AccountSyncResult(state: state, message: message);
}

Future<AccountSyncResult> _persistAccountSyncContractFailureInternal(
  SettingsController controller, {
  required String message,
  required bool quiet,
}) async {
  await controller.storeInternal.clearAccountManagedSecret(
    target: kAccountManagedSecretTargetBridgeAuthToken,
  );
  return _persistAccountSyncFailureInternal(
    controller,
    state: 'blocked',
    message: message,
    quiet: quiet,
  );
}

String _resolveBridgeServerUrl(Map<String, dynamic> payload) {
  final explicit = _stringValue(payload['BRIDGE_SERVER_URL']);
  if (explicit.isNotEmpty) {
    return explicit;
  }
  final camelCase = _stringValue(payload['bridgeServerUrl']);
  if (camelCase.isNotEmpty) {
    return camelCase;
  }
  return '';
}

String _resolveCurrentBridgeServerUrl(
  SettingsController controller, {
  String bridgeServerUrlOverride = '',
}) {
  final explicit = bridgeServerUrlOverride.trim();
  if (isSupportedExternalAcpEndpoint(explicit)) {
    return explicit;
  }
  final syncedBridgeServerUrl =
      controller.accountSyncStateInternal?.syncedDefaults.bridgeServerUrl
          .trim() ??
      '';
  if (isSupportedExternalAcpEndpoint(syncedBridgeServerUrl)) {
    return syncedBridgeServerUrl;
  }
  return kManagedBridgeServerUrl;
}

int _parseExpiresAtMs(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  final raw = _stringValue(value);
  if (raw.isEmpty) {
    return 0;
  }
  final asInt = int.tryParse(raw);
  if (asInt != null) {
    return asInt;
  }
  return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

String _stringValue(Object? value) {
  return value?.toString().trim() ?? '';
}

Future<void> _persistAccountSyncStateInternal(
  SettingsController controller,
  AccountSyncState value,
) async {
  await controller.storeInternal.saveAccountSyncState(value);
  controller.accountSyncStateInternal = value;
}
