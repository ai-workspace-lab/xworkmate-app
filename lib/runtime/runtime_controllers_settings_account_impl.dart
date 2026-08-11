import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'account_runtime_client.dart';
import 'runtime_controllers_settings.dart';
import 'runtime_models.dart';

/// Records a failure message so the connector panels can render it as an error.
void _failAccountStatus(SettingsController controller, String message) {
  final trimmed = message.trim();
  controller.accountStatusInternal = trimmed.isEmpty
      ? 'Connection failed. Please try again.'
      : trimmed;
  controller.accountStatusIsErrorInternal = true;
}

/// Records a progress or steady-state message (signing in, signed out, ...).
void _progressAccountStatus(SettingsController controller, String message) {
  controller.accountStatusInternal = message;
  controller.accountStatusIsErrorInternal = false;
}

/// Turns any transport or protocol failure into a message a user can act on.
///
/// [AccountRuntimeClient] only wraps non-2xx responses; socket, TLS, timeout
/// and malformed-body failures arrive here as raw exceptions and must not be
/// surfaced as a bare `toString()`.
String describeAccountFailureInternal(Object error, {String endpoint = ''}) {
  final target = endpoint.trim();
  final suffix = target.isEmpty ? '' : ' ($target)';
  if (error is AccountRuntimeException) {
    final message = error.message.trim();
    if (message.isNotEmpty) {
      return message;
    }
    return switch (error.statusCode) {
      401 => 'Incorrect email or password.',
      403 => 'This account is not allowed to sign in.',
      404 => 'Sign-in endpoint not found$suffix. Check the service URL.',
      429 => 'Too many attempts. Please wait and try again.',
      >= 500 => 'The service is unavailable (HTTP ${error.statusCode}).',
      _ => 'Sign-in failed (HTTP ${error.statusCode}).',
    };
  }
  if (error is TimeoutException) {
    return 'The service did not respond in time$suffix.';
  }
  if (error is TlsException) {
    return 'TLS handshake with the service failed$suffix.';
  }
  if (error is SocketException) {
    final reason = error.osError?.message.trim() ?? '';
    return reason.isEmpty
        ? 'Cannot reach the service$suffix.'
        : 'Cannot reach the service$suffix: $reason';
  }
  if (error is FormatException) {
    return 'The service returned an unexpected response$suffix.';
  }
  return 'Sign-in failed$suffix: $error';
}

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
    _failAccountStatus(controller, 'Account base URL is required');
    controller.notifyListeners();
    return;
  }
  if (identifier.trim().isEmpty || password.isEmpty) {
    _failAccountStatus(controller, 'Email and password are required');
    controller.notifyListeners();
    return;
  }

  controller.accountBusyInternal = true;
  _progressAccountStatus(controller, 'Signing in...');
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
      _progressAccountStatus(controller, 'MFA required');
      return;
    }

    await completeAccountSignInSettingsInternal(
      controller,
      baseUrl: normalizedBaseUrl,
      payload: payload,
      identifier: identifier.trim(),
    );
  } on AccountRuntimeException catch (error) {
    _failAccountStatus(
      controller,
      describeAccountFailureInternal(error, endpoint: normalizedBaseUrl),
    );
  } catch (error, stackTrace) {
    debugPrint('Account login failed: $error\n$stackTrace');
    _failAccountStatus(
      controller,
      describeAccountFailureInternal(error, endpoint: normalizedBaseUrl),
    );
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
    _failAccountStatus(controller, 'Account base URL is required');
    controller.notifyListeners();
    return;
  }
  if (controller.pendingAccountMfaTicketInternal.trim().isEmpty) {
    _failAccountStatus(controller, 'MFA ticket is missing');
    controller.notifyListeners();
    return;
  }
  if (code.trim().isEmpty) {
    _failAccountStatus(controller, 'MFA code is required');
    controller.notifyListeners();
    return;
  }

  controller.accountBusyInternal = true;
  _progressAccountStatus(controller, 'Verifying MFA...');
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
    _failAccountStatus(
      controller,
      describeAccountFailureInternal(error, endpoint: normalizedBaseUrl),
    );
  } catch (error, stackTrace) {
    debugPrint('Account MFA verification failed: $error\n$stackTrace');
    _failAccountStatus(
      controller,
      describeAccountFailureInternal(error, endpoint: normalizedBaseUrl),
    );
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
    _failAccountStatus(controller, 'Account session token is missing');
    return;
  }
  final user = _asMap(payload['user']);
  final sessionSummary = _accountSessionSummaryFromUserPayload(user);
  controller.accountSessionTokenInternal = token;
  controller.accountSessionInternal = sessionSummary;
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
  _progressAccountStatus(
    controller,
    email.isEmpty ? 'Signed in' : 'Signed in as $email',
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
    _progressAccountStatus(controller, 'Restoring account session...');
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
    _progressAccountStatus(
      controller,
      session.email.trim().isEmpty
          ? 'Signed in'
          : 'Signed in as ${session.email.trim()}',
    );
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
      _failAccountStatus(
        controller,
        'Session restore failed: '
        '${describeAccountFailureInternal(error, endpoint: normalizedBaseUrl)}',
      );
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
    _progressAccountStatus(controller, 'Syncing bridge access...');
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
    final bridgeToken = _extractBridgeAuthTokenMetadata(syncPayload);
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
    final syncedBridgeServerUrl = _extractBridgeServerUrlMetadata(syncPayload);
    await controller.storeInternal.clearAccountManagedSecret(
      target: kAccountManagedSecretTargetAIGatewayAccessToken,
    );
    await controller.storeInternal.clearAccountManagedSecret(
      target: kAccountManagedSecretTargetOllamaCloudApiKey,
    );

    final nextState = AccountSyncState.defaults().copyWith(
      syncedDefaults: AccountRemoteProfile.defaults().copyWith(
        bridgeServerUrl: syncedBridgeServerUrl,
      ),
      syncState: 'ready',
      syncMessage: 'Bridge access synced',
      lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
      lastSyncSource: syncedBridgeServerUrl,
      lastSyncError: '',
      profileScope: 'bridge',
      tokenConfigured: const AccountTokenConfigured(bridge: true, vault: false),
    );
    await _persistAccountSyncStateInternal(controller, nextState);
    final currentSettings = controller.snapshotInternal;
    final currentModeConfig = currentSettings.acpBridgeServerModeConfig;

    final nextEffective = resolveAcpBridgeServerEffectiveConfigInternal(
      controller,
      config: currentModeConfig,
    );

    final identifier =
        (await controller.storeInternal.loadAccountSessionIdentifier())
            ?.trim() ??
        '';
    final nextModeConfig = currentModeConfig.copyWith(
      effective: nextEffective,
      cloudSynced: currentModeConfig.cloudSynced.copyWith(
        accountBaseUrl:
            currentModeConfig.cloudSynced.accountBaseUrl.trim().isEmpty
            ? normalizedBaseUrl
            : currentModeConfig.cloudSynced.accountBaseUrl,
        accountIdentifier:
            currentModeConfig.cloudSynced.accountIdentifier.trim().isEmpty
            ? identifier
            : currentModeConfig.cloudSynced.accountIdentifier,
        lastSyncAt: nextState.lastSyncAtMs,
        remoteServerSummary: currentModeConfig.cloudSynced.remoteServerSummary
            .copyWith(endpoint: syncedBridgeServerUrl),
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
      message: describeAccountFailureInternal(
        error,
        endpoint: normalizedBaseUrl,
      ),
      quiet: quiet,
    );
  } catch (error, stackTrace) {
    debugPrint('Account sync failed: $error\n$stackTrace');
    return _persistAccountSyncContractFailureInternal(
      controller,
      message: describeAccountFailureInternal(
        error,
        endpoint: normalizedBaseUrl,
      ),
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
        accountBaseUrl: quiet
            ? currentSnapshot
                  .acpBridgeServerModeConfig
                  .cloudSynced
                  .accountBaseUrl
            : '',
        accountIdentifier: quiet
            ? currentSnapshot
                  .acpBridgeServerModeConfig
                  .cloudSynced
                  .accountIdentifier
            : '',
        lastSyncAt: 0,
        remoteServerSummary: currentSnapshot
            .acpBridgeServerModeConfig
            .cloudSynced
            .remoteServerSummary
            .copyWith(endpoint: ''),
      );
  await controller.saveSnapshot(
    currentSnapshot.copyWith(
      acpBridgeServerModeConfig: currentSnapshot.acpBridgeServerModeConfig
          .copyWith(cloudSynced: clearedCloudSync),
    ),
  );
  _progressAccountStatus(controller, statusMessage);
  if (!quiet) {
    controller.accountBusyInternal = false;
    controller.notifyListeners();
  }
}

Future<AccountSyncResult> markAccountBridgeRuntimeUnavailableInternal(
  SettingsController controller, {
  required String message,
}) async {
  final current = controller.accountSyncStateInternal;
  final nextState = (current ?? AccountSyncState.defaults()).copyWith(
    syncState: 'blocked',
    syncMessage: message,
    lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
    lastSyncError: message,
    profileScope: 'bridge',
  );
  await _persistAccountSyncStateInternal(controller, nextState);
  _failAccountStatus(controller, message);
  controller.notifyListeners();
  return AccountSyncResult(state: 'blocked', message: message);
}

Future<void> cancelAccountMfaChallengeSettingsInternal(
  SettingsController controller,
) async {
  controller.pendingAccountMfaTicketInternal = '';
  controller.pendingAccountBaseUrlInternal = '';
  if (!controller.accountSignedIn) {
    _progressAccountStatus(controller, 'Signed out');
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
  if (summary.email.trim().isNotEmpty) {
    await controller.storeInternal.saveAccountSessionIdentifier(
      summary.email.trim(),
    );
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
  _failAccountStatus(controller, message);
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

String _extractBridgeServerUrlMetadata(Map<String, dynamic> payload) {
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

String _extractBridgeAuthTokenMetadata(Map<String, dynamic> payload) {
  // The Accounts sync contract returns a user-and-tenant-scoped credential.
  // This value is persisted only in the secure managed-secret store.
  final credential = _asMap(payload['bridgeCredential']);
  final token = _stringValue(credential['token']);
  if (token.isNotEmpty) {
    return token;
  }
  // Upgrade compatibility: pre-migration Accounts returns the same value in
  // BRIDGE_AUTH_TOKEN. This branch is removed after the UAT cutover window.
  return _stringValue(payload['BRIDGE_AUTH_TOKEN']);
}

AcpBridgeServerEffectiveConfig resolveAcpBridgeServerEffectiveConfigInternal(
  SettingsController controller, {
  required AcpBridgeServerModeConfig config,
}) {
  final accountSyncState = controller.accountSyncState;
  final managedBridgeReady =
      controller.accountSessionTokenInternal.trim().isNotEmpty &&
      accountSyncState?.syncState.trim().toLowerCase() == 'ready' &&
      accountSyncState?.tokenConfigured.bridge == true;
  if (managedBridgeReady) {
    return const AcpBridgeServerEffectiveConfig(
      endpoint: kManagedBridgeServerUrl,
      tokenRef: '',
      source: 'cloud',
      reason: 'Account sync is ready and the managed bridge token is available',
    );
  }

  if (config.selfHosted.isConfigured) {
    return AcpBridgeServerEffectiveConfig(
      endpoint: config.selfHosted.serverUrl,
      tokenRef: config.selfHosted.passwordRef,
      source: 'bridge',
      reason: 'Manual Bridge configuration is present and valid',
    );
  }

  return AcpBridgeServerEffectiveConfig(
    endpoint: '',
    tokenRef: '',
    source: 'default',
    reason: 'No active Bridge source is configured',
  );
}

Future<SettingsSnapshot> buildSavedAccountProfileSettingsInternal(
  SettingsController controller, {
  required SettingsSnapshot settings,
  required String accountBaseUrl,
  required String accountIdentifier,
  required String bridgeServerUrl,
  required String bridgeToken,
  required bool isManualBridge,
}) async {
  final bridgeConfig = settings.acpBridgeServerModeConfig;
  final trimmedBridgeServerUrl = bridgeServerUrl.trim();
  final trimmedBridgeToken = bridgeToken.trim();
  final existingBridgeToken = isManualBridge
      ? ((await controller.storeInternal.loadSecretValueByRef(
              bridgeConfig.selfHosted.passwordRef,
            ))?.trim() ??
            '')
      : '';
  if (isManualBridge) {
    _validateManualBridgeProfile(
      serverUrl: trimmedBridgeServerUrl,
      tokenConfigured:
          trimmedBridgeToken.isNotEmpty || existingBridgeToken.isNotEmpty,
    );
  }
  final nextBridgeConfig = bridgeConfig.copyWith(
    selfHosted: isManualBridge
        ? bridgeConfig.selfHosted.copyWith(
            serverUrl: trimmedBridgeServerUrl,
            username: 'admin',
          )
        : bridgeConfig.selfHosted,
  );
  final nextEffective = resolveAcpBridgeServerEffectiveConfigInternal(
    controller,
    config: nextBridgeConfig,
  );
  final nextSettings = settings.copyWith(
    accountBaseUrl: accountBaseUrl.trim(),
    accountUsername: accountIdentifier.trim(),
    acpBridgeServerModeConfig: nextBridgeConfig.copyWith(
      effective: nextEffective,
    ),
  );
  if (isManualBridge && trimmedBridgeToken.isNotEmpty) {
    await controller.saveSecretValueByRef(
      nextSettings.acpBridgeServerModeConfig.selfHosted.passwordRef,
      trimmedBridgeToken,
      provider: 'Bridge',
      module: 'Manual',
    );
  }
  return nextSettings;
}

void _validateManualBridgeProfile({
  required String serverUrl,
  required bool tokenConfigured,
}) {
  if (serverUrl.isEmpty) {
    throw ArgumentError.value(
      serverUrl,
      'bridgeServerUrl',
      'Bridge URL is required',
    );
  }
  if (!tokenConfigured) {
    throw ArgumentError.value(
      '',
      'bridgeToken',
      'Bridge auth token is required',
    );
  }
  final uri = Uri.tryParse(serverUrl);
  if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
    throw ArgumentError.value(
      serverUrl,
      'bridgeServerUrl',
      'Bridge URL must be a valid URL',
    );
  }
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final isLocalHttp =
      scheme == 'http' &&
      (host == '127.0.0.1' || host == 'localhost') &&
      uri.hasPort &&
      uri.port >= 1 &&
      uri.port <= 65535;
  if (isLocalHttp) {
    return;
  }
  if (scheme == 'https') {
    return;
  }
  throw ArgumentError.value(
    serverUrl,
    'bridgeServerUrl',
    'Manual Bridge URL must be http://127.0.0.1:<port> or http://localhost:<port> for local mode, or https:// for public custom bridge mode',
  );
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
