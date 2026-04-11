part of 'runtime_controllers_settings.dart';

Future<void> saveGatewaySecretsSettingsInternal(
  SettingsController controller, {
  int? profileIndex,
  required String token,
  required String password,
}) async {
  final trimmedToken = token.trim();
  final trimmedPassword = password.trim();
  final resolvedProfileIndex = (profileIndex ?? kGatewayRemoteProfileIndex)
      .clamp(0, kGatewayProfileListLength - 1);
  if (trimmedToken.isNotEmpty) {
    await controller.storeInternal.saveSecretValueByRef(
      gatewayTokenRefForProfileSettingsInternal(
        controller,
        resolvedProfileIndex,
      ),
      trimmedToken,
    );
    await controller.appendAudit(
      SecretAuditEntry(
        timeLabel: controller.timeLabelInternal(),
        action: 'Updated',
        provider: 'Gateway',
        target: gatewayTokenRefForProfileSettingsInternal(
          controller,
          resolvedProfileIndex,
        ),
        module: 'Assistant',
        status: 'Success',
      ),
    );
  }
  if (trimmedPassword.isNotEmpty) {
    await controller.storeInternal.saveSecretValueByRef(
      gatewayPasswordRefForProfileSettingsInternal(
        controller,
        resolvedProfileIndex,
      ),
      trimmedPassword,
    );
    await controller.appendAudit(
      SecretAuditEntry(
        timeLabel: controller.timeLabelInternal(),
        action: 'Updated',
        provider: 'Gateway',
        target: gatewayPasswordRefForProfileSettingsInternal(
          controller,
          resolvedProfileIndex,
        ),
        module: 'Assistant',
        status: 'Success',
      ),
    );
  }
  await controller.reloadDerivedStateInternal();
  controller.notifyListeners();
}

Future<void> clearGatewaySecretsSettingsInternal(
  SettingsController controller, {
  int? profileIndex,
  bool token = false,
  bool password = false,
}) async {
  final resolvedProfileIndex = (profileIndex ?? kGatewayRemoteProfileIndex)
      .clamp(0, kGatewayProfileListLength - 1);
  if (token) {
    await controller.storeInternal.clearSecretValueByRef(
      gatewayTokenRefForProfileSettingsInternal(
        controller,
        resolvedProfileIndex,
      ),
    );
    await controller.appendAudit(
      SecretAuditEntry(
        timeLabel: controller.timeLabelInternal(),
        action: 'Cleared',
        provider: 'Gateway',
        target: gatewayTokenRefForProfileSettingsInternal(
          controller,
          resolvedProfileIndex,
        ),
        module: 'Assistant',
        status: 'Success',
      ),
    );
  }
  if (password) {
    await controller.storeInternal.clearSecretValueByRef(
      gatewayPasswordRefForProfileSettingsInternal(
        controller,
        resolvedProfileIndex,
      ),
    );
    await controller.appendAudit(
      SecretAuditEntry(
        timeLabel: controller.timeLabelInternal(),
        action: 'Cleared',
        provider: 'Gateway',
        target: gatewayPasswordRefForProfileSettingsInternal(
          controller,
          resolvedProfileIndex,
        ),
        module: 'Assistant',
        status: 'Success',
      ),
    );
  }
  await controller.reloadDerivedStateInternal();
  controller.notifyListeners();
}

Future<String> loadGatewayTokenSettingsInternal(
  SettingsController controller, {
  int? profileIndex,
}) async {
  if (profileIndex == null) {
    return (await controller.storeInternal.loadGatewayToken())?.trim() ?? '';
  }
  final refName = gatewayTokenRefForProfileSettingsInternal(
    controller,
    profileIndex,
  );
  final byRef =
      (await controller.storeInternal.loadSecretValueByRef(refName))?.trim() ??
      '';
  if (byRef.isNotEmpty) {
    return byRef;
  }
  if (refName == SecretStore.gatewayTokenRefKey(profileIndex)) {
    return (await controller.storeInternal.loadGatewayToken(
          profileIndex: profileIndex,
        ))?.trim() ??
        '';
  }
  return '';
}

Future<String> loadGatewayPasswordSettingsInternal(
  SettingsController controller, {
  int? profileIndex,
}) async {
  if (profileIndex == null) {
    return (await controller.storeInternal.loadGatewayPassword())?.trim() ?? '';
  }
  final refName = gatewayPasswordRefForProfileSettingsInternal(
    controller,
    profileIndex,
  );
  final byRef =
      (await controller.storeInternal.loadSecretValueByRef(refName))?.trim() ??
      '';
  if (byRef.isNotEmpty) {
    return byRef;
  }
  if (refName == SecretStore.gatewayPasswordRefKey(profileIndex)) {
    return (await controller.storeInternal.loadGatewayPassword(
          profileIndex: profileIndex,
        ))?.trim() ??
        '';
  }
  return '';
}

bool hasStoredGatewayTokenForProfileSettingsInternal(
  SettingsController controller,
  int profileIndex,
) =>
    controller.secureRefsInternal.containsKey(
      gatewayTokenRefForProfileSettingsInternal(controller, profileIndex),
    ) ||
    (!controller.snapshotInternal.accountLocalMode &&
        profileIndex == kGatewayRemoteProfileIndex &&
        controller.secureRefsInternal.containsKey(
          kAccountManagedSecretTargetBridgeAuthToken,
        ));

bool hasStoredGatewayPasswordForProfileSettingsInternal(
  SettingsController controller,
  int profileIndex,
) => controller.secureRefsInternal.containsKey(
  gatewayPasswordRefForProfileSettingsInternal(controller, profileIndex),
);

String? storedGatewayTokenMaskForProfileSettingsInternal(
  SettingsController controller,
  int profileIndex,
) =>
    controller.secureRefsInternal[gatewayTokenRefForProfileSettingsInternal(
      controller,
      profileIndex,
    )] ??
    (!controller.snapshotInternal.accountLocalMode &&
            profileIndex == kGatewayRemoteProfileIndex
        ? controller
              .secureRefsInternal[kAccountManagedSecretTargetBridgeAuthToken]
        : null);

String? storedGatewayPasswordMaskForProfileSettingsInternal(
  SettingsController controller,
  int profileIndex,
) =>
    controller.secureRefsInternal[gatewayPasswordRefForProfileSettingsInternal(
      controller,
      profileIndex,
    )];

String gatewayTokenRefForProfileSettingsInternal(
  SettingsController controller,
  int profileIndex,
) {
  final normalizedIndex = profileIndex.clamp(0, kGatewayProfileListLength - 1);
  final profile = controller.snapshotInternal.gatewayProfiles[normalizedIndex];
  final refName = profile.tokenRef.trim();
  if (refName.isNotEmpty) {
    return refName;
  }
  return SecretStore.gatewayTokenRefKey(normalizedIndex);
}

String gatewayPasswordRefForProfileSettingsInternal(
  SettingsController controller,
  int profileIndex,
) {
  final normalizedIndex = profileIndex.clamp(0, kGatewayProfileListLength - 1);
  final profile = controller.snapshotInternal.gatewayProfiles[normalizedIndex];
  final refName = profile.passwordRef.trim();
  if (refName.isNotEmpty) {
    return refName;
  }
  return SecretStore.gatewayPasswordRefKey(normalizedIndex);
}

String aiGatewayApiKeyRefSettingsInternal(
  SettingsController controller, [
  AiGatewayProfile? profile,
]) {
  final refName = (profile ?? controller.snapshotInternal.aiGateway).apiKeyRef
      .trim();
  return refName.isEmpty ? 'ai_gateway_api_key' : refName;
}

String vaultTokenRefSettingsInternal(
  SettingsController controller, [
  VaultConfig? profile,
]) {
  final refName = (profile ?? controller.snapshotInternal.vault).tokenRef
      .trim();
  return refName.isEmpty ? 'vault_token' : refName;
}

String ollamaCloudApiKeyRefSettingsInternal(
  SettingsController controller, [
  OllamaCloudConfig? profile,
]) {
  final refName = (profile ?? controller.snapshotInternal.ollamaCloud).apiKeyRef
      .trim();
  return refName.isEmpty ? 'ollama_cloud_api_key' : refName;
}

Future<void> saveOllamaCloudApiKeySettingsInternal(
  SettingsController controller,
  String value,
) async {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return;
  }
  await controller.storeInternal.saveSecretValueByRef(
    ollamaCloudApiKeyRefSettingsInternal(controller),
    trimmed,
  );
  await controller.appendAudit(
    SecretAuditEntry(
      timeLabel: controller.timeLabelInternal(),
      action: 'Updated',
      provider: 'Ollama Cloud',
      target: ollamaCloudApiKeyRefSettingsInternal(controller),
      module: 'Settings',
      status: 'Success',
    ),
  );
  await controller.reloadDerivedStateInternal();
  controller.notifyListeners();
}

Future<String> loadOllamaCloudApiKeySettingsInternal(
  SettingsController controller,
) async {
  final refName = ollamaCloudApiKeyRefSettingsInternal(controller);
  final byRef =
      (await controller.storeInternal.loadSecretValueByRef(refName))?.trim() ??
      '';
  if (byRef.isNotEmpty) {
    return byRef;
  }
  if (refName == 'ollama_cloud_api_key') {
    return (await controller.storeInternal.loadOllamaCloudApiKey())?.trim() ??
        '';
  }
  return '';
}

Future<void> saveVaultTokenSettingsInternal(
  SettingsController controller,
  String value,
) async {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return;
  }
  await controller.storeInternal.saveSecretValueByRef(
    vaultTokenRefSettingsInternal(controller),
    trimmed,
  );
  await controller.appendAudit(
    SecretAuditEntry(
      timeLabel: controller.timeLabelInternal(),
      action: 'Updated',
      provider: 'Vault',
      target: vaultTokenRefSettingsInternal(controller),
      module: 'Secrets',
      status: 'Success',
    ),
  );
  await controller.reloadDerivedStateInternal();
  controller.notifyListeners();
}

Future<String> loadVaultTokenSettingsInternal(
  SettingsController controller,
) async {
  final refName = vaultTokenRefSettingsInternal(controller);
  final byRef =
      (await controller.storeInternal.loadSecretValueByRef(refName))?.trim() ??
      '';
  if (byRef.isNotEmpty) {
    return byRef;
  }
  if (refName == 'vault_token') {
    return (await controller.storeInternal.loadVaultToken())?.trim() ?? '';
  }
  return '';
}

Future<void> saveAiGatewayApiKeySettingsInternal(
  SettingsController controller,
  String value,
) async {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return;
  }
  await controller.storeInternal.saveSecretValueByRef(
    aiGatewayApiKeyRefSettingsInternal(controller),
    trimmed,
  );
  await controller.appendAudit(
    SecretAuditEntry(
      timeLabel: controller.timeLabelInternal(),
      action: 'Updated',
      provider: 'LLM API',
      target: aiGatewayApiKeyRefSettingsInternal(controller),
      module: 'Settings',
      status: 'Success',
    ),
  );
  await controller.reloadDerivedStateInternal();
  controller.notifyListeners();
}

Future<String> loadAiGatewayApiKeySettingsInternal(
  SettingsController controller,
) async {
  final refName = aiGatewayApiKeyRefSettingsInternal(controller);
  final byRef =
      (await controller.storeInternal.loadSecretValueByRef(refName))?.trim() ??
      '';
  if (byRef.isNotEmpty) {
    return byRef;
  }
  if (refName == 'ai_gateway_api_key') {
    return (await controller.storeInternal.loadAiGatewayApiKey())?.trim() ?? '';
  }
  return '';
}

Future<void> clearAiGatewayApiKeySettingsInternal(
  SettingsController controller,
) async {
  await controller.storeInternal.clearSecretValueByRef(
    aiGatewayApiKeyRefSettingsInternal(controller),
  );
  await controller.reloadDerivedStateInternal();
  controller.notifyListeners();
}

Future<void> saveSecretValueByRefSettingsInternal(
  SettingsController controller,
  String refName,
  String value, {
  required String provider,
  required String module,
}) async {
  final trimmedRef = refName.trim();
  final trimmedValue = value.trim();
  if (trimmedRef.isEmpty || trimmedValue.isEmpty) {
    return;
  }
  await controller.storeInternal.saveSecretValueByRef(trimmedRef, trimmedValue);
  await controller.appendAudit(
    SecretAuditEntry(
      timeLabel: controller.timeLabelInternal(),
      action: 'Updated',
      provider: provider,
      target: trimmedRef,
      module: module,
      status: 'Success',
    ),
  );
  await controller.reloadDerivedStateInternal();
  controller.notifyListeners();
}

Future<String> loadSecretValueByRefSettingsInternal(
  SettingsController controller,
  String refName,
) async {
  return (await controller.storeInternal.loadSecretValueByRef(
        refName,
      ))?.trim() ??
      '';
}

Future<String> loadVaultTokenForSecretReadsSettingsInternal(
  SettingsController controller, {
  String tokenOverride = '',
}) async {
  final override = tokenOverride.trim();
  if (override.isNotEmpty) {
    return override;
  }
  final token = await loadVaultTokenSettingsInternal(controller);
  if (token.isNotEmpty) {
    return token;
  }
  final refName = vaultTokenRefSettingsInternal(controller);
  if (refName == 'vault_token') {
    return (await controller.storeInternal.loadVaultToken())?.trim() ?? '';
  }
  return '';
}

Future<String> readVaultSecretByRefSettingsInternal(
  SettingsController controller,
  String refName,
) async {
  final normalizedRef = refName.trim();
  if (normalizedRef.isEmpty) {
    return '';
  }
  final vaultAddress = controller.snapshotInternal.vault.address.trim();
  if (vaultAddress.isEmpty) {
    return '';
  }
  final vaultToken = await loadVaultTokenForSecretReadsSettingsInternal(
    controller,
  );
  if (vaultToken.isEmpty) {
    return '';
  }
  final client = controller.buildAccountClient(
    controller.snapshotInternal.accountBaseUrl,
  );
  return client.readVaultSecretValue(
    vaultUrl: vaultAddress,
    namespace: controller.snapshotInternal.vault.namespace,
    vaultToken: vaultToken,
    secretPath: 'kv/$normalizedRef',
    secretKey: 'value',
  );
}

Future<String> resolveSecretValueSettingsInternal(
  SettingsController controller, {
  String explicitValue = '',
  String refName = '',
  String fallbackRefName = '',
  String accountTarget = '',
  bool allowVaultLookup = true,
  bool persistExplicitValue = true,
}) async {
  final trimmedExplicit = explicitValue.trim();
  final normalizedRef = refName.trim().isNotEmpty
      ? refName.trim()
      : fallbackRefName.trim();
  if (trimmedExplicit.isNotEmpty) {
    if (persistExplicitValue && normalizedRef.isNotEmpty) {
      await controller.storeInternal.saveSecretValueByRef(
        normalizedRef,
        trimmedExplicit,
      );
    }
    return trimmedExplicit;
  }
  if (normalizedRef.isNotEmpty) {
    final local = await loadSecretValueByRefSettingsInternal(
      controller,
      normalizedRef,
    );
    if (local.isNotEmpty) {
      return local;
    }
    if (allowVaultLookup) {
      try {
        final vaultValue = (await readVaultSecretByRefSettingsInternal(
          controller,
          normalizedRef,
        )).trim();
        if (vaultValue.isNotEmpty) {
          await controller.storeInternal.saveSecretValueByRef(
            normalizedRef,
            vaultValue,
          );
          return vaultValue;
        }
      } catch (_) {
        // Keep account-managed fallback available even when Vault lookup fails.
      }
    }
  }
  final normalizedTarget = accountTarget.trim();
  if (normalizedTarget.isEmpty) {
    return '';
  }
  final localManaged =
      (await controller.storeInternal.loadAccountManagedSecret(
        target: normalizedTarget,
      ))?.trim() ??
      '';
  if (localManaged.isNotEmpty) {
    if (normalizedRef.isNotEmpty) {
      await controller.storeInternal.saveSecretValueByRef(
        normalizedRef,
        localManaged,
      );
    }
    return localManaged;
  }
  final locator = controller.accountSyncStateInternal?.syncedDefaults
      .locatorForTarget(normalizedTarget);
  if (locator == null) {
    return '';
  }
  final vaultAddress = controller.snapshotInternal.vault.address.trim();
  final vaultToken = await loadVaultTokenForSecretReadsSettingsInternal(
    controller,
  );
  if (vaultAddress.isEmpty || vaultToken.isEmpty) {
    return '';
  }
  final client = controller.buildAccountClient(
    controller.snapshotInternal.accountBaseUrl,
  );
  final remoteValue = (await client.readVaultSecretValue(
    vaultUrl: vaultAddress,
    namespace: controller.snapshotInternal.vault.namespace,
    vaultToken: vaultToken,
    secretPath: locator.secretPath,
    secretKey: locator.secretKey,
  )).trim();
  if (remoteValue.isEmpty) {
    return '';
  }
  await controller.storeInternal.saveAccountManagedSecret(
    target: normalizedTarget,
    value: remoteValue,
  );
  if (normalizedRef.isNotEmpty) {
    await controller.storeInternal.saveSecretValueByRef(
      normalizedRef,
      remoteValue,
    );
  }
  return remoteValue;
}
