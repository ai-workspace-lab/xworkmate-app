class AccountSessionSummary {
  const AccountSessionSummary({
    required this.userId,
    required this.email,
    required this.name,
    required this.role,
    required this.mfaEnabled,
  });

  final String userId;
  final String email;
  final String name;
  final String role;
  final bool mfaEnabled;

  AccountSessionSummary copyWith({
    String? userId,
    String? email,
    String? name,
    String? role,
    bool? mfaEnabled,
  }) {
    return AccountSessionSummary(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      mfaEnabled: mfaEnabled ?? this.mfaEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'email': email,
      'name': name,
      'role': role,
      'mfaEnabled': mfaEnabled,
    };
  }

  factory AccountSessionSummary.fromJson(Map<String, dynamic> json) {
    return AccountSessionSummary(
      userId: json['userId'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      mfaEnabled: json['mfaEnabled'] as bool? ?? false,
    );
  }
}

class AccountSecretLocator {
  const AccountSecretLocator({
    required this.id,
    required this.provider,
    required this.secretPath,
    required this.secretKey,
    required this.target,
    required this.required,
  });

  final String id;
  final String provider;
  final String secretPath;
  final String secretKey;
  final String target;
  final bool required;

  AccountSecretLocator copyWith({
    String? id,
    String? provider,
    String? secretPath,
    String? secretKey,
    String? target,
    bool? required,
  }) {
    return AccountSecretLocator(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      secretPath: secretPath ?? this.secretPath,
      secretKey: secretKey ?? this.secretKey,
      target: target ?? this.target,
      required: required ?? this.required,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'provider': provider,
      'secretPath': secretPath,
      'secretKey': secretKey,
      'target': target,
      'required': required,
    };
  }

  factory AccountSecretLocator.fromJson(Map<String, dynamic> json) {
    return AccountSecretLocator(
      id: json['id'] as String? ?? '',
      provider: json['provider'] as String? ?? 'vault',
      secretPath: json['secretPath'] as String? ?? '',
      secretKey: json['secretKey'] as String? ?? '',
      target: json['target'] as String? ?? '',
      required: json['required'] as bool? ?? false,
    );
  }
}

class AccountRemoteProfile {
  const AccountRemoteProfile({
    required this.openclawUrl,
    required this.openclawOrigin,
    required this.vaultUrl,
    required this.vaultNamespace,
    required this.apisixUrl,
    required this.secretLocators,
    required this.syncState,
    required this.syncMessage,
    required this.aiGatewayAvailableModels,
    required this.aiGatewaySyncMessage,
    required this.lastSyncedAtMs,
  });

  final String openclawUrl;
  final String openclawOrigin;
  final String vaultUrl;
  final String vaultNamespace;
  final String apisixUrl;
  final List<AccountSecretLocator> secretLocators;
  final String syncState;
  final String syncMessage;
  final List<String> aiGatewayAvailableModels;
  final String aiGatewaySyncMessage;
  final int lastSyncedAtMs;

  factory AccountRemoteProfile.defaults() {
    return const AccountRemoteProfile(
      openclawUrl: '',
      openclawOrigin: '',
      vaultUrl: '',
      vaultNamespace: '',
      apisixUrl: '',
      secretLocators: <AccountSecretLocator>[],
      syncState: 'idle',
      syncMessage: 'Ready to sync',
      aiGatewayAvailableModels: <String>[],
      aiGatewaySyncMessage: 'Model catalog not synced yet',
      lastSyncedAtMs: 0,
    );
  }

  AccountRemoteProfile copyWith({
    String? openclawUrl,
    String? openclawOrigin,
    String? vaultUrl,
    String? vaultNamespace,
    String? apisixUrl,
    List<AccountSecretLocator>? secretLocators,
    String? syncState,
    String? syncMessage,
    List<String>? aiGatewayAvailableModels,
    String? aiGatewaySyncMessage,
    int? lastSyncedAtMs,
  }) {
    return AccountRemoteProfile(
      openclawUrl: openclawUrl ?? this.openclawUrl,
      openclawOrigin: openclawOrigin ?? this.openclawOrigin,
      vaultUrl: vaultUrl ?? this.vaultUrl,
      vaultNamespace: vaultNamespace ?? this.vaultNamespace,
      apisixUrl: apisixUrl ?? this.apisixUrl,
      secretLocators: secretLocators ?? this.secretLocators,
      syncState: syncState ?? this.syncState,
      syncMessage: syncMessage ?? this.syncMessage,
      aiGatewayAvailableModels:
          aiGatewayAvailableModels ?? this.aiGatewayAvailableModels,
      aiGatewaySyncMessage:
          aiGatewaySyncMessage ?? this.aiGatewaySyncMessage,
      lastSyncedAtMs: lastSyncedAtMs ?? this.lastSyncedAtMs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'openclawUrl': openclawUrl,
      'openclawOrigin': openclawOrigin,
      'vaultUrl': vaultUrl,
      'vaultNamespace': vaultNamespace,
      'apisixUrl': apisixUrl,
      'secretLocators': secretLocators
          .map((item) => item.toJson())
          .toList(growable: false),
      'syncState': syncState,
      'syncMessage': syncMessage,
      'aiGatewayAvailableModels': aiGatewayAvailableModels,
      'aiGatewaySyncMessage': aiGatewaySyncMessage,
      'lastSyncedAtMs': lastSyncedAtMs,
    };
  }

  factory AccountRemoteProfile.fromJson(Map<String, dynamic> json) {
    List<AccountSecretLocator> decodeLocators(Object? value) {
      if (value is! List) {
        return const <AccountSecretLocator>[];
      }
      return value
          .whereType<Map>()
          .map((item) => AccountSecretLocator.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false);
    }

    List<String> decodeModels(Object? value) {
      if (value is! List) {
        return const <String>[];
      }
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    final defaults = AccountRemoteProfile.defaults();
    return AccountRemoteProfile(
      openclawUrl: json['openclawUrl'] as String? ?? defaults.openclawUrl,
      openclawOrigin:
          json['openclawOrigin'] as String? ?? defaults.openclawOrigin,
      vaultUrl: json['vaultUrl'] as String? ?? defaults.vaultUrl,
      vaultNamespace:
          json['vaultNamespace'] as String? ?? defaults.vaultNamespace,
      apisixUrl: json['apisixUrl'] as String? ?? defaults.apisixUrl,
      secretLocators: decodeLocators(json['secretLocators']),
      syncState: json['syncState'] as String? ?? defaults.syncState,
      syncMessage: json['syncMessage'] as String? ?? defaults.syncMessage,
      aiGatewayAvailableModels: decodeModels(json['aiGatewayAvailableModels']),
      aiGatewaySyncMessage:
          json['aiGatewaySyncMessage'] as String? ??
          defaults.aiGatewaySyncMessage,
      lastSyncedAtMs:
          (json['lastSyncedAtMs'] as num?)?.toInt() ?? defaults.lastSyncedAtMs,
    );
  }
}

class AccountSyncResult {
  const AccountSyncResult({
    required this.state,
    required this.message,
    required this.storedTargets,
    required this.skippedTargets,
  });

  final String state;
  final String message;
  final List<String> storedTargets;
  final List<String> skippedTargets;
}

const String kAccountManagedSecretTargetOpenclawGatewayToken =
    'openclaw.gateway_token';
const String kAccountManagedSecretTargetAIGatewayAccessToken =
    'ai_gateway.access_token';
const String kAccountManagedSecretTargetOllamaCloudApiKey =
    'ollama_cloud.api_key';
const List<String> kAccountManagedSecretTargets = <String>[
  kAccountManagedSecretTargetOpenclawGatewayToken,
  kAccountManagedSecretTargetAIGatewayAccessToken,
  kAccountManagedSecretTargetOllamaCloudApiKey,
];

bool isSupportedAccountManagedSecretTarget(String target) {
  return kAccountManagedSecretTargets.contains(target.trim());
}
