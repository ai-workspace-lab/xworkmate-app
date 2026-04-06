import 'runtime_models_configs.dart';

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

class AccountTokenConfigured {
  const AccountTokenConfigured({
    required this.openclaw,
    required this.vault,
    required this.apisix,
  });

  final bool openclaw;
  final bool vault;
  final bool apisix;

  factory AccountTokenConfigured.defaults() {
    return const AccountTokenConfigured(
      openclaw: false,
      vault: false,
      apisix: false,
    );
  }

  AccountTokenConfigured copyWith({bool? openclaw, bool? vault, bool? apisix}) {
    return AccountTokenConfigured(
      openclaw: openclaw ?? this.openclaw,
      vault: vault ?? this.vault,
      apisix: apisix ?? this.apisix,
    );
  }

  Map<String, dynamic> toJson() {
    return {'openclaw': openclaw, 'vault': vault, 'apisix': apisix};
  }

  factory AccountTokenConfigured.fromJson(Map<String, dynamic> json) {
    return AccountTokenConfigured(
      openclaw: json['openclaw'] as bool? ?? false,
      vault: json['vault'] as bool? ?? false,
      apisix: json['apisix'] as bool? ?? false,
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
  });

  final String openclawUrl;
  final String openclawOrigin;
  final String vaultUrl;
  final String vaultNamespace;
  final String apisixUrl;
  final List<AccountSecretLocator> secretLocators;

  factory AccountRemoteProfile.defaults() {
    return const AccountRemoteProfile(
      openclawUrl: '',
      openclawOrigin: '',
      vaultUrl: '',
      vaultNamespace: '',
      apisixUrl: '',
      secretLocators: <AccountSecretLocator>[],
    );
  }

  AccountRemoteProfile copyWith({
    String? openclawUrl,
    String? openclawOrigin,
    String? vaultUrl,
    String? vaultNamespace,
    String? apisixUrl,
    List<AccountSecretLocator>? secretLocators,
  }) {
    return AccountRemoteProfile(
      openclawUrl: openclawUrl ?? this.openclawUrl,
      openclawOrigin: openclawOrigin ?? this.openclawOrigin,
      vaultUrl: vaultUrl ?? this.vaultUrl,
      vaultNamespace: vaultNamespace ?? this.vaultNamespace,
      apisixUrl: apisixUrl ?? this.apisixUrl,
      secretLocators: secretLocators ?? this.secretLocators,
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
    };
  }

  factory AccountRemoteProfile.fromJson(Map<String, dynamic> json) {
    List<AccountSecretLocator> decodeLocators(Object? value) {
      if (value is! List) {
        return const <AccountSecretLocator>[];
      }
      return value
          .whereType<Map>()
          .map(
            (item) =>
                AccountSecretLocator.fromJson(item.cast<String, dynamic>()),
          )
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
    );
  }

  AccountSecretLocator? locatorForTarget(String target) {
    final normalized = target.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final locator in secretLocators) {
      if (locator.target.trim() == normalized) {
        return locator;
      }
    }
    return null;
  }
}

class AccountProfileResponse {
  const AccountProfileResponse({
    required this.profile,
    required this.profileScope,
    required this.tokenConfigured,
  });

  final AccountRemoteProfile profile;
  final String profileScope;
  final AccountTokenConfigured tokenConfigured;
}

class AccountStoredSettingsSnapshot {
  const AccountStoredSettingsSnapshot({
    required this.gatewayRemoteProfile,
    required this.vaultAddress,
    required this.vaultNamespace,
    required this.aiGatewayBaseUrl,
    required this.aiGatewayApiKeyRef,
    required this.ollamaCloudApiKeyRef,
  });

  final GatewayConnectionProfile gatewayRemoteProfile;
  final String vaultAddress;
  final String vaultNamespace;
  final String aiGatewayBaseUrl;
  final String aiGatewayApiKeyRef;
  final String ollamaCloudApiKeyRef;

  factory AccountStoredSettingsSnapshot.defaults() {
    return AccountStoredSettingsSnapshot(
      gatewayRemoteProfile: GatewayConnectionProfile.defaultsRemote(),
      vaultAddress: '',
      vaultNamespace: '',
      aiGatewayBaseUrl: '',
      aiGatewayApiKeyRef: AiGatewayProfile.defaults().apiKeyRef,
      ollamaCloudApiKeyRef: OllamaCloudConfig.defaults().apiKeyRef,
    );
  }

  AccountStoredSettingsSnapshot copyWith({
    GatewayConnectionProfile? gatewayRemoteProfile,
    String? vaultAddress,
    String? vaultNamespace,
    String? aiGatewayBaseUrl,
    String? aiGatewayApiKeyRef,
    String? ollamaCloudApiKeyRef,
  }) {
    return AccountStoredSettingsSnapshot(
      gatewayRemoteProfile: gatewayRemoteProfile ?? this.gatewayRemoteProfile,
      vaultAddress: vaultAddress ?? this.vaultAddress,
      vaultNamespace: vaultNamespace ?? this.vaultNamespace,
      aiGatewayBaseUrl: aiGatewayBaseUrl ?? this.aiGatewayBaseUrl,
      aiGatewayApiKeyRef: aiGatewayApiKeyRef ?? this.aiGatewayApiKeyRef,
      ollamaCloudApiKeyRef: ollamaCloudApiKeyRef ?? this.ollamaCloudApiKeyRef,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'gatewayRemoteProfile': gatewayRemoteProfile.toJson(),
      'vaultAddress': vaultAddress,
      'vaultNamespace': vaultNamespace,
      'aiGatewayBaseUrl': aiGatewayBaseUrl,
      'aiGatewayApiKeyRef': aiGatewayApiKeyRef,
      'ollamaCloudApiKeyRef': ollamaCloudApiKeyRef,
    };
  }

  factory AccountStoredSettingsSnapshot.fromJson(Map<String, dynamic> json) {
    return AccountStoredSettingsSnapshot(
      gatewayRemoteProfile: GatewayConnectionProfile.fromJson(
        (json['gatewayRemoteProfile'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      vaultAddress: json['vaultAddress'] as String? ?? '',
      vaultNamespace: json['vaultNamespace'] as String? ?? '',
      aiGatewayBaseUrl: json['aiGatewayBaseUrl'] as String? ?? '',
      aiGatewayApiKeyRef:
          json['aiGatewayApiKeyRef'] as String? ??
          AiGatewayProfile.defaults().apiKeyRef,
      ollamaCloudApiKeyRef:
          json['ollamaCloudApiKeyRef'] as String? ??
          OllamaCloudConfig.defaults().apiKeyRef,
    );
  }
}

class AccountSyncState {
  const AccountSyncState({
    required this.syncedDefaults,
    required this.localSettings,
    required this.overrideFlags,
    required this.syncState,
    required this.syncMessage,
    required this.lastSyncAtMs,
    required this.lastSyncSource,
    required this.lastSyncError,
    required this.profileScope,
    required this.tokenConfigured,
  });

  final AccountRemoteProfile syncedDefaults;
  final AccountStoredSettingsSnapshot localSettings;
  final Map<String, bool> overrideFlags;
  final String syncState;
  final String syncMessage;
  final int lastSyncAtMs;
  final String lastSyncSource;
  final String lastSyncError;
  final String profileScope;
  final AccountTokenConfigured tokenConfigured;

  factory AccountSyncState.defaults() {
    return AccountSyncState(
      syncedDefaults: AccountRemoteProfile.defaults(),
      localSettings: AccountStoredSettingsSnapshot.defaults(),
      overrideFlags: const <String, bool>{},
      syncState: 'idle',
      syncMessage: 'Remote config not synced yet',
      lastSyncAtMs: 0,
      lastSyncSource: '',
      lastSyncError: '',
      profileScope: '',
      tokenConfigured: AccountTokenConfigured.defaults(),
    );
  }

  AccountSyncState copyWith({
    AccountRemoteProfile? syncedDefaults,
    AccountStoredSettingsSnapshot? localSettings,
    Map<String, bool>? overrideFlags,
    String? syncState,
    String? syncMessage,
    int? lastSyncAtMs,
    String? lastSyncSource,
    String? lastSyncError,
    String? profileScope,
    AccountTokenConfigured? tokenConfigured,
  }) {
    return AccountSyncState(
      syncedDefaults: syncedDefaults ?? this.syncedDefaults,
      localSettings: localSettings ?? this.localSettings,
      overrideFlags: overrideFlags ?? this.overrideFlags,
      syncState: syncState ?? this.syncState,
      syncMessage: syncMessage ?? this.syncMessage,
      lastSyncAtMs: lastSyncAtMs ?? this.lastSyncAtMs,
      lastSyncSource: lastSyncSource ?? this.lastSyncSource,
      lastSyncError: lastSyncError ?? this.lastSyncError,
      profileScope: profileScope ?? this.profileScope,
      tokenConfigured: tokenConfigured ?? this.tokenConfigured,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'syncedDefaults': syncedDefaults.toJson(),
      'localSettings': localSettings.toJson(),
      'overrideFlags': overrideFlags,
      'syncState': syncState,
      'syncMessage': syncMessage,
      'lastSyncAtMs': lastSyncAtMs,
      'lastSyncSource': lastSyncSource,
      'lastSyncError': lastSyncError,
      'profileScope': profileScope,
      'tokenConfigured': tokenConfigured.toJson(),
    };
  }

  factory AccountSyncState.fromJson(Map<String, dynamic> json) {
    Map<String, bool> decodeOverrideFlags(Object? value) {
      if (value is! Map) {
        return const <String, bool>{};
      }
      return value.map<String, bool>((key, entry) {
        return MapEntry(key.toString(), entry == true);
      });
    }

    return AccountSyncState(
      syncedDefaults: AccountRemoteProfile.fromJson(
        (json['syncedDefaults'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      localSettings: AccountStoredSettingsSnapshot.fromJson(
        (json['localSettings'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      overrideFlags: decodeOverrideFlags(json['overrideFlags']),
      syncState: json['syncState'] as String? ?? 'idle',
      syncMessage:
          json['syncMessage'] as String? ?? 'Remote config not synced yet',
      lastSyncAtMs: (json['lastSyncAtMs'] as num?)?.toInt() ?? 0,
      lastSyncSource: json['lastSyncSource'] as String? ?? '',
      lastSyncError: json['lastSyncError'] as String? ?? '',
      profileScope: json['profileScope'] as String? ?? '',
      tokenConfigured: AccountTokenConfigured.fromJson(
        (json['tokenConfigured'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}

class AccountSyncResult {
  const AccountSyncResult({required this.state, required this.message});

  final String state;
  final String message;
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

const String kAccountOverrideGatewayRemoteEndpoint = 'gateway.remote.endpoint';
const String kAccountOverrideVaultAddress = 'vault.address';
const String kAccountOverrideVaultNamespace = 'vault.namespace';
const String kAccountOverrideAiGatewayBaseUrl = 'aiGateway.baseUrl';
const String kAccountOverrideAiGatewayApiKeyRef = 'aiGateway.apiKeyRef';
const String kAccountOverrideOllamaCloudApiKeyRef = 'ollamaCloud.apiKeyRef';

const List<String> kAccountOverrideFieldKeys = <String>[
  kAccountOverrideGatewayRemoteEndpoint,
  kAccountOverrideVaultAddress,
  kAccountOverrideVaultNamespace,
  kAccountOverrideAiGatewayBaseUrl,
  kAccountOverrideAiGatewayApiKeyRef,
  kAccountOverrideOllamaCloudApiKeyRef,
];
