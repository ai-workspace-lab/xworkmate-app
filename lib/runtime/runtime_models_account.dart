import 'runtime_models_configs.dart';
import 'runtime_models_profiles.dart';

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

enum AcpBridgeServerMode { cloudSynced }

class AcpBridgeServerRemoteServerSummary {
  const AcpBridgeServerRemoteServerSummary({
    required this.endpoint,
    required this.hasAdvancedOverrides,
  });

  final String endpoint;
  final bool hasAdvancedOverrides;

  factory AcpBridgeServerRemoteServerSummary.defaults() {
    return const AcpBridgeServerRemoteServerSummary(
      endpoint: '',
      hasAdvancedOverrides: false,
    );
  }

  AcpBridgeServerRemoteServerSummary copyWith({
    String? endpoint,
    bool? hasAdvancedOverrides,
  }) {
    return AcpBridgeServerRemoteServerSummary(
      endpoint: endpoint ?? this.endpoint,
      hasAdvancedOverrides: hasAdvancedOverrides ?? this.hasAdvancedOverrides,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'endpoint': endpoint,
      'hasAdvancedOverrides': hasAdvancedOverrides,
    };
  }

  factory AcpBridgeServerRemoteServerSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return AcpBridgeServerRemoteServerSummary(
      endpoint: json['endpoint'] as String? ?? '',
      hasAdvancedOverrides: json['hasAdvancedOverrides'] as bool? ?? false,
    );
  }
}

class AcpBridgeServerCloudSyncConfig {
  const AcpBridgeServerCloudSyncConfig({
    required this.accountBaseUrl,
    required this.accountIdentifier,
    required this.lastSyncAt,
    required this.remoteServerSummary,
  });

  final String accountBaseUrl;
  final String accountIdentifier;
  final int lastSyncAt;
  final AcpBridgeServerRemoteServerSummary remoteServerSummary;

  factory AcpBridgeServerCloudSyncConfig.defaults() {
    return AcpBridgeServerCloudSyncConfig(
      accountBaseUrl: '',
      accountIdentifier: '',
      lastSyncAt: 0,
      remoteServerSummary: AcpBridgeServerRemoteServerSummary.defaults(),
    );
  }

  AcpBridgeServerCloudSyncConfig copyWith({
    String? accountBaseUrl,
    String? accountIdentifier,
    int? lastSyncAt,
    AcpBridgeServerRemoteServerSummary? remoteServerSummary,
  }) {
    return AcpBridgeServerCloudSyncConfig(
      accountBaseUrl: accountBaseUrl ?? this.accountBaseUrl,
      accountIdentifier: accountIdentifier ?? this.accountIdentifier,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      remoteServerSummary: remoteServerSummary ?? this.remoteServerSummary,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'accountBaseUrl': accountBaseUrl,
      'accountIdentifier': accountIdentifier,
      'lastSyncAt': lastSyncAt,
      'remoteServerSummary': remoteServerSummary.toJson(),
    };
  }

  factory AcpBridgeServerCloudSyncConfig.fromJson(Map<String, dynamic> json) {
    return AcpBridgeServerCloudSyncConfig(
      accountBaseUrl: json['accountBaseUrl'] as String? ?? '',
      accountIdentifier: json['accountIdentifier'] as String? ?? '',
      lastSyncAt: (json['lastSyncAt'] as num?)?.toInt() ?? 0,
      remoteServerSummary: AcpBridgeServerRemoteServerSummary.fromJson(
        (json['remoteServerSummary'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}

class AcpBridgeServerSelfHostedConfig {
  const AcpBridgeServerSelfHostedConfig({
    required this.serverUrl,
    required this.username,
    required this.passwordRef,
  });

  final String serverUrl;
  final String username;
  final String passwordRef;

  factory AcpBridgeServerSelfHostedConfig.defaults() {
    return const AcpBridgeServerSelfHostedConfig(
      serverUrl: '',
      username: '',
      passwordRef: 'acp_bridge_server_password',
    );
  }

  AcpBridgeServerSelfHostedConfig copyWith({
    String? serverUrl,
    String? username,
    String? passwordRef,
  }) {
    return AcpBridgeServerSelfHostedConfig(
      serverUrl: (serverUrl ?? this.serverUrl).trim(),
      username: (username ?? this.username).trim(),
      passwordRef: (passwordRef ?? this.passwordRef).trim(),
    );
  }

  bool get isConfigured =>
      serverUrl.trim().isNotEmpty && username.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'serverUrl': serverUrl,
      'username': username,
      'passwordRef': passwordRef,
    };
  }

  factory AcpBridgeServerSelfHostedConfig.fromJson(Map<String, dynamic> json) {
    return AcpBridgeServerSelfHostedConfig(
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      passwordRef:
          json['passwordRef'] as String? ??
          AcpBridgeServerSelfHostedConfig.defaults().passwordRef,
    );
  }
}

class AcpBridgeServerAdvancedOverrides {
  const AcpBridgeServerAdvancedOverrides({
    required this.gatewayProfiles,
    required this.vault,
    required this.aiGateway,
    required this.acpBridgeServerProfiles,
    required this.authorizedSkillDirectories,
  });

  final List<GatewayConnectionProfile> gatewayProfiles;
  final VaultConfig vault;
  final AiGatewayProfile aiGateway;
  final List<ExternalAcpEndpointProfile> acpBridgeServerProfiles;
  final List<AuthorizedSkillDirectory> authorizedSkillDirectories;

  factory AcpBridgeServerAdvancedOverrides.defaults() {
    return AcpBridgeServerAdvancedOverrides(
      gatewayProfiles: normalizeGatewayProfiles(),
      vault: VaultConfig.defaults(),
      aiGateway: AiGatewayProfile.defaults(),
      acpBridgeServerProfiles: normalizeExternalAcpEndpoints(),
      authorizedSkillDirectories: normalizeAuthorizedSkillDirectories(),
    );
  }

  AcpBridgeServerAdvancedOverrides copyWith({
    List<GatewayConnectionProfile>? gatewayProfiles,
    VaultConfig? vault,
    AiGatewayProfile? aiGateway,
    List<ExternalAcpEndpointProfile>? acpBridgeServerProfiles,
    List<AuthorizedSkillDirectory>? authorizedSkillDirectories,
  }) {
    return AcpBridgeServerAdvancedOverrides(
      gatewayProfiles: gatewayProfiles != null
          ? normalizeGatewayProfiles(profiles: gatewayProfiles)
          : this.gatewayProfiles,
      vault: vault ?? this.vault,
      aiGateway: aiGateway ?? this.aiGateway,
      acpBridgeServerProfiles: acpBridgeServerProfiles != null
          ? normalizeExternalAcpEndpoints(profiles: acpBridgeServerProfiles)
          : this.acpBridgeServerProfiles,
      authorizedSkillDirectories: authorizedSkillDirectories != null
          ? normalizeAuthorizedSkillDirectories(
              directories: authorizedSkillDirectories,
            )
          : this.authorizedSkillDirectories,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'gatewayProfiles': gatewayProfiles
          .map((item) => item.toJson())
          .toList(growable: false),
      'vault': vault.toJson(),
      'aiGateway': aiGateway.toJson(),
      'acpBridgeServerProfiles': acpBridgeServerProfiles
          .map((item) => item.toJson())
          .toList(growable: false),
      'authorizedSkillDirectories': authorizedSkillDirectories
          .map((item) => item.toJson())
          .toList(growable: false),
    };
  }

  factory AcpBridgeServerAdvancedOverrides.fromJson(Map<String, dynamic> json) {
    return AcpBridgeServerAdvancedOverrides(
      gatewayProfiles: normalizeGatewayProfiles(
        profiles: ((json['gatewayProfiles'] as List?) ?? const <Object>[])
            .whereType<Map>()
            .map(
              (item) => GatewayConnectionProfile.fromJson(
                item.cast<String, dynamic>(),
              ),
            ),
      ),
      vault: VaultConfig.fromJson(
        (json['vault'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      aiGateway: AiGatewayProfile.fromJson(
        (json['aiGateway'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      acpBridgeServerProfiles: normalizeExternalAcpEndpoints(
        profiles:
            ((json['acpBridgeServerProfiles'] as List?) ?? const <Object>[])
                .whereType<Map>()
                .map(
                  (item) => ExternalAcpEndpointProfile.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                ),
      ),
      authorizedSkillDirectories: normalizeAuthorizedSkillDirectories(
        directories:
            ((json['authorizedSkillDirectories'] as List?) ?? const <Object>[])
                .whereType<Map>()
                .map(
                  (item) => AuthorizedSkillDirectory.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                ),
      ),
    );
  }
}

class AcpBridgeServerModeConfig {
  const AcpBridgeServerModeConfig({
    required this.mode,
    required this.cloudSynced,
    required this.selfHosted,
    required this.advancedOverrides,
  });

  final AcpBridgeServerMode mode;
  final AcpBridgeServerCloudSyncConfig cloudSynced;
  final AcpBridgeServerSelfHostedConfig selfHosted;
  final AcpBridgeServerAdvancedOverrides advancedOverrides;

  factory AcpBridgeServerModeConfig.defaults() {
    return AcpBridgeServerModeConfig(
      mode: AcpBridgeServerMode.cloudSynced,
      cloudSynced: AcpBridgeServerCloudSyncConfig.defaults(),
      selfHosted: AcpBridgeServerSelfHostedConfig.defaults(),
      advancedOverrides: AcpBridgeServerAdvancedOverrides.defaults(),
    );
  }

  AcpBridgeServerModeConfig copyWith({
    AcpBridgeServerMode? mode,
    AcpBridgeServerCloudSyncConfig? cloudSynced,
    AcpBridgeServerSelfHostedConfig? selfHosted,
    AcpBridgeServerAdvancedOverrides? advancedOverrides,
  }) {
    return AcpBridgeServerModeConfig(
      mode: mode ?? this.mode,
      cloudSynced: cloudSynced ?? this.cloudSynced,
      selfHosted: selfHosted ?? this.selfHosted,
      advancedOverrides: advancedOverrides ?? this.advancedOverrides,
    );
  }

  bool get usesSelfHostedBase => false;

  bool get usesCloudSyncBase => true;

  String get sourceTag => 'cloudSynced';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'mode': mode.name,
      'cloudSynced': cloudSynced.toJson(),
      'selfHosted': selfHosted.toJson(),
      'advancedOverrides': advancedOverrides.toJson(),
    };
  }

  factory AcpBridgeServerModeConfig.fromJson(Map<String, dynamic> json) {
    return AcpBridgeServerModeConfig(
      mode: AcpBridgeServerMode.cloudSynced,
      cloudSynced: AcpBridgeServerCloudSyncConfig.fromJson(
        (json['cloudSynced'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      selfHosted: AcpBridgeServerSelfHostedConfig.fromJson(
        (json['selfHosted'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      advancedOverrides: AcpBridgeServerAdvancedOverrides.fromJson(
        (json['advancedOverrides'] as Map?)?.cast<String, dynamic>() ??
            const {},
      ),
    );
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

class AccountSyncState {
  const AccountSyncState({
    required this.syncedDefaults,
    required this.syncState,
    required this.syncMessage,
    required this.lastSyncAtMs,
    required this.lastSyncSource,
    required this.lastSyncError,
    required this.profileScope,
    required this.tokenConfigured,
  });

  final AccountRemoteProfile syncedDefaults;
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
    return AccountSyncState(
      syncedDefaults: AccountRemoteProfile.fromJson(
        (json['syncedDefaults'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
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
