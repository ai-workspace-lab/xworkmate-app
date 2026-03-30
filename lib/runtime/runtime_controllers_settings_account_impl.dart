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
    controller.pendingAccountMfaTicketInternal = '';
    controller.pendingAccountBaseUrlInternal = '';
    await completeAccountSignInSettingsInternal(
      controller,
      baseUrl: normalizedBaseUrl,
      payload: payload,
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
}) async {
  final token = _stringValue(payload['token']).isNotEmpty
      ? _stringValue(payload['token'])
      : _stringValue(payload['access_token']);
  if (token.isEmpty) {
    controller.accountStatusInternal = 'Account session token is missing';
    return;
  }
  await controller.storeInternal.saveAccountSessionToken(token);
  final user = _asMap(payload['user']);
  if (user.isNotEmpty) {
    await controller.storeInternal.saveAccountSessionSummary(
      AccountSessionSummary(
        userId: _stringValue(user['id']),
        email: _stringValue(user['email']),
        name: _stringValue(user['name']).isNotEmpty
            ? _stringValue(user['name'])
            : _stringValue(user['username']),
        role: _stringValue(user['role']),
        mfaEnabled: user['mfaEnabled'] as bool? ?? false,
      ),
    );
  }
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
    controller.accountStatusInternal = session.email.trim().isEmpty
        ? 'Signed in'
        : 'Signed in as ${session.email}';
    await syncAccountManagedSecretsSettingsInternal(
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

Future<AccountSyncResult> syncAccountManagedSecretsSettingsInternal(
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
    final result = const AccountSyncResult(
      state: 'blocked',
      message: 'Account session is unavailable',
      storedTargets: <String>[],
      skippedTargets: <String>[],
    );
    controller.accountStatusInternal = result.message;
    if (!quiet) {
      controller.notifyListeners();
    }
    return result;
  }

  if (!quiet) {
    controller.accountBusyInternal = true;
    controller.accountStatusInternal = 'Syncing account-managed secrets...';
    controller.notifyListeners();
  }

  try {
    final client = controller.buildAccountClient(normalizedBaseUrl);
    final remoteProfile = await client.loadProfile(token: token);
    final vaultToken =
        (await controller.storeInternal.loadVaultToken())?.trim() ?? '';
    if (vaultToken.isEmpty) {
      final blockedProfile = remoteProfile.copyWith(
        syncState: 'blocked',
        syncMessage: 'Vault token is required to sync remote secrets',
        lastSyncedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await controller.storeInternal.saveAccountProfile(blockedProfile);
      await controller.reloadDerivedStateInternal();
      return const AccountSyncResult(
        state: 'blocked',
        message: 'Vault token is required to sync remote secrets',
        storedTargets: <String>[],
        skippedTargets: <String>[],
      );
    }

    final storedTargets = <String>[];
    final skippedTargets = <String>[];
    final syncedValues = <String, String>{};

    for (final locator in remoteProfile.secretLocators) {
      final provider = locator.provider.trim().toLowerCase();
      final target = locator.target.trim();
      if (provider != 'vault' ||
          !isSupportedAccountManagedSecretTarget(target)) {
        skippedTargets.add(target);
        continue;
      }
      try {
        final value = await client.readVaultSecretValue(
          vaultUrl: remoteProfile.vaultUrl,
          namespace: remoteProfile.vaultNamespace,
          vaultToken: vaultToken,
          secretPath: locator.secretPath,
          secretKey: locator.secretKey,
        );
        if (value.trim().isEmpty) {
          skippedTargets.add(target);
          continue;
        }
        await controller.storeInternal.saveAccountManagedSecret(
          target: target,
          value: value.trim(),
        );
        syncedValues[target] = value.trim();
        storedTargets.add(target);
      } catch (_) {
        skippedTargets.add(target);
      }
    }

    final aiGatewayCatalog =
        await loadAccountManagedAiGatewayModelsSettingsInternal(
          controller,
          profile: remoteProfile,
          syncedValues: syncedValues,
        );
    final hasSkips = skippedTargets.isNotEmpty;
    final state = hasSkips ? 'partial' : 'ready';
    final message = hasSkips
        ? 'Synced ${storedTargets.length} secret(s) with ${skippedTargets.length} skipped'
        : 'Synced ${storedTargets.length} secret(s)';
    final nextProfile = remoteProfile.copyWith(
      syncState: state,
      syncMessage: message,
      aiGatewayAvailableModels: aiGatewayCatalog.$1,
      aiGatewaySyncMessage: aiGatewayCatalog.$2,
      lastSyncedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await controller.storeInternal.saveAccountProfile(nextProfile);
    await controller.reloadDerivedStateInternal();
    return AccountSyncResult(
      state: state,
      message: message,
      storedTargets: storedTargets,
      skippedTargets: skippedTargets,
    );
  } on AccountRuntimeException catch (error) {
    final profile =
        (await controller.storeInternal.loadAccountProfile()) ??
        AccountRemoteProfile.defaults();
    await controller.storeInternal.saveAccountProfile(
      profile.copyWith(
        syncState: 'error',
        syncMessage: error.message,
        lastSyncedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await controller.reloadDerivedStateInternal();
    return AccountSyncResult(
      state: 'error',
      message: error.message,
      storedTargets: const <String>[],
      skippedTargets: const <String>[],
    );
  } finally {
    if (!quiet) {
      controller.accountBusyInternal = false;
      controller.notifyListeners();
    }
  }
}

Future<(List<String>, String)>
loadAccountManagedAiGatewayModelsSettingsInternal(
  SettingsController controller, {
  required AccountRemoteProfile profile,
  required Map<String, String> syncedValues,
}) async {
  final localBaseUrl = controller.snapshotInternal.aiGateway.baseUrl.trim();
  final effectiveBaseUrl = localBaseUrl.isNotEmpty
      ? localBaseUrl
      : controller.snapshotInternal.accountLocalMode
      ? ''
      : profile.apisixUrl.trim();
  final localApiKey =
      (await controller.storeInternal.loadAiGatewayApiKey())?.trim() ?? '';
  final effectiveApiKey = localApiKey.isNotEmpty
      ? localApiKey
      : syncedValues[kAccountManagedSecretTargetAIGatewayAccessToken] ?? '';
  if (effectiveBaseUrl.isEmpty || effectiveApiKey.isEmpty) {
    return (const <String>[], 'Model catalog not synced yet');
  }
  final normalizedBaseUrl = controller.normalizeAiGatewayBaseUrlInternal(
    effectiveBaseUrl,
  );
  if (normalizedBaseUrl == null) {
    return (const <String>[], 'Invalid LLM API Endpoint');
  }
  try {
    final models = await controller.requestAiGatewayModelsInternal(
      uri: controller.aiGatewayModelsUriInternal(normalizedBaseUrl),
      apiKey: effectiveApiKey,
    );
    return (
      models.map((item) => item.id).toList(growable: false),
      'Loaded ${models.length} model(s)',
    );
  } catch (error) {
    return (const <String>[], controller.networkErrorLabelInternal(error));
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
  await controller.storeInternal.clearAccountSessionSummary();
  await controller.storeInternal.clearAccountProfile();
  await controller.storeInternal.clearAccountManagedSecrets();
  await controller.reloadDerivedStateInternal();
  controller.accountStatusInternal = statusMessage;
  if (!quiet) {
    controller.accountBusyInternal = false;
    controller.notifyListeners();
  }
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
