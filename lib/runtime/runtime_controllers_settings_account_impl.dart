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
        (await controller.storeInternal.loadAccountSessionIdentifier())?.trim() ??
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
  final sessionSummary = AccountSessionSummary(
    userId: _stringValue(user['id']),
    email: _stringValue(user['email']),
    name: _stringValue(user['name']).isNotEmpty
        ? _stringValue(user['name'])
        : _stringValue(user['username']),
    role: _stringValue(user['role']),
    mfaEnabled: user['mfaEnabled'] == true,
  );
  await controller.storeInternal.saveAccountSessionToken(token);
  await controller.storeInternal.saveAccountSessionExpiresAtMs(
    _parseExpiresAtMs(payload['expiresAt']),
  );
  await controller.storeInternal.saveAccountSessionUserId(sessionSummary.userId);
  await controller.storeInternal.saveAccountSessionIdentifier(identifier);
  await controller.storeInternal.saveAccountSessionSummary(sessionSummary);
  controller.accountStatusInternal = 'Signed in';
  await restoreAccountSessionSettingsInternal(
    controller,
    baseUrl: baseUrl,
    quiet: true,
  );
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
    final session = await client.loadSession(token: token);
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
}) async {
  final normalizedBaseUrl = normalizeAccountBaseUrlSettingsInternal(
    baseUrl,
    fallback: controller.snapshotInternal.accountBaseUrl,
  );
  final token =
      (await controller.storeInternal.loadAccountSessionToken())?.trim() ?? '';
  if (normalizedBaseUrl.isEmpty || token.isEmpty) {
    const result = AccountSyncResult(
      state: 'blocked',
      message: 'Account session is unavailable',
    );
    controller.accountStatusInternal = result.message;
    if (!quiet) {
      controller.notifyListeners();
    }
    return result;
  }

  if (!quiet) {
    controller.accountBusyInternal = true;
    controller.accountStatusInternal = 'Syncing remote defaults...';
    controller.notifyListeners();
  }

  try {
    final client = controller.buildAccountClient(normalizedBaseUrl);
    final response = await client.loadProfile(token: token);
    final previousState =
        await loadAccountSyncStateWithLegacyMigrationInternal(controller) ??
        AccountSyncState.defaults();
    final nextState = previousState.copyWith(
      syncedDefaults: response.profile,
      syncState: 'ready',
      syncMessage: 'Remote defaults synced',
      lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
      lastSyncSource: normalizedBaseUrl,
      lastSyncError: '',
      profileScope: response.profileScope,
      tokenConfigured: response.tokenConfigured,
    );
    await controller.storeInternal.saveAccountSyncState(nextState);
    await controller.storeInternal.clearAccountProfile();
    await applyAccountSyncedDefaultsSettingsInternal(
      controller,
      state: nextState,
    );
    await controller.reloadDerivedStateInternal();
    final email = controller.accountSessionInternal?.email.trim() ?? '';
    controller.accountStatusInternal = email.isEmpty
        ? 'Signed in'
        : 'Signed in as $email';
    return const AccountSyncResult(
      state: 'ready',
      message: 'Remote defaults synced',
    );
  } on AccountRuntimeException catch (error) {
    final previousState =
        await loadAccountSyncStateWithLegacyMigrationInternal(controller) ??
        AccountSyncState.defaults();
    final errorState = previousState.copyWith(
      syncState: 'error',
      syncMessage: error.message,
      lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
      lastSyncSource: normalizedBaseUrl,
      lastSyncError: error.message,
    );
    await controller.storeInternal.saveAccountSyncState(errorState);
    await controller.reloadDerivedStateInternal();
    controller.accountStatusInternal = error.message;
    return AccountSyncResult(state: 'error', message: error.message);
  } finally {
    if (!quiet) {
      controller.accountBusyInternal = false;
      controller.notifyListeners();
    }
  }
}

Future<void> applyAccountSyncedDefaultsSettingsInternal(
  SettingsController controller, {
  required AccountSyncState state,
}) async {
  final previous = controller.snapshotInternal;
  var next = previous;
  final defaults = state.syncedDefaults;
  final overrideFlags = state.overrideFlags;

  if (_isOverrideDisabled(
        overrideFlags,
        kAccountOverrideGatewayRemoteEndpoint,
      ) &&
      defaults.openclawUrl.trim().isNotEmpty) {
    final remoteProfile = previous.gatewayProfiles[kGatewayRemoteProfileIndex];
    final normalized = normalizeGatewayManualEndpointInternal(
      host: defaults.openclawUrl,
      port: remoteProfile.port,
      tls: remoteProfile.tls,
    );
    next = next.copyWithGatewayProfileAt(
      kGatewayRemoteProfileIndex,
      remoteProfile.copyWith(
        mode: RuntimeConnectionMode.remote,
        useSetupCode: false,
        setupCode: '',
        host: normalized.host,
        port: normalized.port,
        tls: normalized.tls,
      ),
    );
  }

  if (_isOverrideDisabled(overrideFlags, kAccountOverrideVaultAddress) &&
      defaults.vaultUrl.trim().isNotEmpty) {
    next = next.copyWith(
      vault: next.vault.copyWith(address: defaults.vaultUrl.trim()),
    );
  }

  if (_isOverrideDisabled(overrideFlags, kAccountOverrideVaultNamespace) &&
      defaults.vaultNamespace.trim().isNotEmpty) {
    next = next.copyWith(
      vault: next.vault.copyWith(namespace: defaults.vaultNamespace.trim()),
    );
  }

  if (_isOverrideDisabled(overrideFlags, kAccountOverrideAiGatewayBaseUrl) &&
      defaults.apisixUrl.trim().isNotEmpty) {
    next = next.copyWith(
      aiGateway: next.aiGateway.copyWith(baseUrl: defaults.apisixUrl.trim()),
    );
  }

  final aiGatewayLocator = defaults.locatorForTarget(
    kAccountManagedSecretTargetAIGatewayAccessToken,
  );
  if (_isOverrideDisabled(overrideFlags, kAccountOverrideAiGatewayApiKeyRef) &&
      aiGatewayLocator != null) {
    next = next.copyWith(
      aiGateway: next.aiGateway.copyWith(apiKeyRef: aiGatewayLocator.target),
    );
  }

  final ollamaLocator = defaults.locatorForTarget(
    kAccountManagedSecretTargetOllamaCloudApiKey,
  );
  if (_isOverrideDisabled(
        overrideFlags,
        kAccountOverrideOllamaCloudApiKeyRef,
      ) &&
      ollamaLocator != null) {
    next = next.copyWith(
      ollamaCloud: next.ollamaCloud.copyWith(apiKeyRef: ollamaLocator.target),
    );
  }

  if (next.accountLocalMode) {
    next = next.copyWith(accountLocalMode: false);
  }

  if (next.toJsonString() != previous.toJsonString()) {
    await controller.saveSnapshot(next, recordAccountOverrides: false);
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
  if (!controller.snapshotInternal.accountLocalMode) {
    await controller.saveSnapshot(
      controller.snapshotInternal.copyWith(accountLocalMode: true),
      recordAccountOverrides: false,
    );
  } else {
    await controller.reloadDerivedStateInternal();
  }
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

Future<AccountSyncState?> loadAccountSyncStateWithLegacyMigrationInternal(
  SettingsController controller,
) async {
  final current = await controller.storeInternal.loadAccountSyncState();
  if (current != null) {
    return current;
  }
  final legacy = await controller.storeInternal.loadAccountProfile();
  if (legacy == null) {
    return null;
  }
  final migrated = AccountSyncState.defaults().copyWith(
    syncedDefaults: legacy,
    syncState: 'ready',
    syncMessage: 'Remote config migrated',
    lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
  );
  await controller.storeInternal.saveAccountSyncState(migrated);
  await controller.storeInternal.clearAccountProfile();
  return migrated;
}

Future<void> markAccountOverrideSettingsInternal(
  SettingsController controller, {
  required String fieldKey,
}) async {
  if (!kAccountOverrideFieldKeys.contains(fieldKey)) {
    return;
  }
  final current = await loadAccountSyncStateWithLegacyMigrationInternal(controller);
  if (current == null) {
    return;
  }
  if (current.overrideFlags[fieldKey] == true) {
    return;
  }
  final nextFlags = Map<String, bool>.from(current.overrideFlags)
    ..[fieldKey] = true;
  await controller.storeInternal.saveAccountSyncState(
    current.copyWith(overrideFlags: nextFlags),
  );
  await controller.reloadDerivedStateInternal();
  controller.notifyListeners();
}

Future<void> clearAccountOverrideSettingsInternal(
  SettingsController controller, {
  required String fieldKey,
}) async {
  if (!kAccountOverrideFieldKeys.contains(fieldKey)) {
    return;
  }
  final current = await loadAccountSyncStateWithLegacyMigrationInternal(controller);
  if (current == null || current.overrideFlags[fieldKey] != true) {
    return;
  }
  final nextFlags = Map<String, bool>.from(current.overrideFlags)
    ..remove(fieldKey);
  await controller.storeInternal.saveAccountSyncState(
    current.copyWith(overrideFlags: nextFlags),
  );
  await controller.reloadDerivedStateInternal();
  controller.notifyListeners();
}

Future<void> recordAccountOverridesForSnapshotChangeSettingsInternal(
  SettingsController controller, {
  required SettingsSnapshot previous,
  required SettingsSnapshot current,
}) async {
  final syncState =
      await loadAccountSyncStateWithLegacyMigrationInternal(controller);
  if (syncState == null) {
    return;
  }

  final nextFlags = Map<String, bool>.from(syncState.overrideFlags);
  var changed = false;

  if (_remoteGatewayEndpointChanged(previous, current)) {
    changed = _markOverrideFlag(
          nextFlags,
          kAccountOverrideGatewayRemoteEndpoint,
        ) ||
        changed;
  }
  if (previous.vault.address != current.vault.address) {
    changed = _markOverrideFlag(nextFlags, kAccountOverrideVaultAddress) || changed;
  }
  if (previous.vault.namespace != current.vault.namespace) {
    changed =
        _markOverrideFlag(nextFlags, kAccountOverrideVaultNamespace) || changed;
  }
  if (previous.aiGateway.baseUrl != current.aiGateway.baseUrl) {
    changed =
        _markOverrideFlag(nextFlags, kAccountOverrideAiGatewayBaseUrl) || changed;
  }
  if (previous.aiGateway.apiKeyRef != current.aiGateway.apiKeyRef) {
    changed = _markOverrideFlag(
          nextFlags,
          kAccountOverrideAiGatewayApiKeyRef,
        ) ||
        changed;
  }
  if (previous.ollamaCloud.apiKeyRef != current.ollamaCloud.apiKeyRef) {
    changed = _markOverrideFlag(
          nextFlags,
          kAccountOverrideOllamaCloudApiKeyRef,
        ) ||
        changed;
  }

  if (!changed) {
    return;
  }

  await controller.storeInternal.saveAccountSyncState(
    syncState.copyWith(overrideFlags: nextFlags),
  );
}

bool _isOverrideDisabled(Map<String, bool> flags, String fieldKey) {
  return flags[fieldKey] != true;
}

bool _markOverrideFlag(Map<String, bool> flags, String fieldKey) {
  if (flags[fieldKey] == true) {
    return false;
  }
  flags[fieldKey] = true;
  return true;
}

bool _remoteGatewayEndpointChanged(
  SettingsSnapshot previous,
  SettingsSnapshot current,
) {
  final previousProfile = previous.gatewayProfiles[kGatewayRemoteProfileIndex];
  final currentProfile = current.gatewayProfiles[kGatewayRemoteProfileIndex];
  return previousProfile.mode != currentProfile.mode ||
      previousProfile.useSetupCode != currentProfile.useSetupCode ||
      previousProfile.setupCode != currentProfile.setupCode ||
      previousProfile.host != currentProfile.host ||
      previousProfile.port != currentProfile.port ||
      previousProfile.tls != currentProfile.tls;
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
