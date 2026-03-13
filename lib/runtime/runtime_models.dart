import 'dart:convert';

import '../i18n/app_language.dart';

enum RuntimeConnectionMode { unconfigured, local, remote }

extension RuntimeConnectionModeCopy on RuntimeConnectionMode {
  String get label => switch (this) {
    RuntimeConnectionMode.unconfigured => appText('未配置', 'Unconfigured'),
    RuntimeConnectionMode.local => appText('本地', 'Local'),
    RuntimeConnectionMode.remote => appText('远程', 'Remote'),
  };

  static RuntimeConnectionMode fromJsonValue(String? value) {
    return RuntimeConnectionMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => RuntimeConnectionMode.unconfigured,
    );
  }
}

enum RuntimeConnectionStatus { offline, connecting, connected, error }

extension RuntimeConnectionStatusCopy on RuntimeConnectionStatus {
  String get label => switch (this) {
    RuntimeConnectionStatus.offline => appText('离线', 'Offline'),
    RuntimeConnectionStatus.connecting => appText('连接中', 'Connecting'),
    RuntimeConnectionStatus.connected => appText('已连接', 'Connected'),
    RuntimeConnectionStatus.error => appText('错误', 'Error'),
  };
}

enum AssistantExecutionTarget { local, remote }

extension AssistantExecutionTargetCopy on AssistantExecutionTarget {
  String get label => switch (this) {
    AssistantExecutionTarget.local => appText('本地', 'Local'),
    AssistantExecutionTarget.remote => appText('远程', 'Remote'),
  };

  String get promptValue => switch (this) {
    AssistantExecutionTarget.local => 'local',
    AssistantExecutionTarget.remote => 'remote',
  };

  static AssistantExecutionTarget fromJsonValue(String? value) {
    return AssistantExecutionTarget.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AssistantExecutionTarget.local,
    );
  }
}

enum AssistantPermissionLevel { defaultAccess, fullAccess }

extension AssistantPermissionLevelCopy on AssistantPermissionLevel {
  String get label => switch (this) {
    AssistantPermissionLevel.defaultAccess => appText('默认权限', 'Default Access'),
    AssistantPermissionLevel.fullAccess => appText('完全访问权限', 'Full Access'),
  };

  String get promptValue => switch (this) {
    AssistantPermissionLevel.defaultAccess => 'default',
    AssistantPermissionLevel.fullAccess => 'full-access',
  };

  static AssistantPermissionLevel fromJsonValue(String? value) {
    return AssistantPermissionLevel.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AssistantPermissionLevel.defaultAccess,
    );
  }
}

class GatewayConnectionProfile {
  const GatewayConnectionProfile({
    required this.mode,
    required this.useSetupCode,
    required this.setupCode,
    required this.host,
    required this.port,
    required this.tls,
    required this.selectedAgentId,
  });

  final RuntimeConnectionMode mode;
  final bool useSetupCode;
  final String setupCode;
  final String host;
  final int port;
  final bool tls;
  final String selectedAgentId;

  factory GatewayConnectionProfile.defaults() {
    return const GatewayConnectionProfile(
      mode: RuntimeConnectionMode.remote,
      useSetupCode: false,
      setupCode: '',
      host: 'openclaw.svc.plus',
      port: 443,
      tls: true,
      selectedAgentId: '',
    );
  }

  GatewayConnectionProfile copyWith({
    RuntimeConnectionMode? mode,
    bool? useSetupCode,
    String? setupCode,
    String? host,
    int? port,
    bool? tls,
    String? selectedAgentId,
  }) {
    final normalized = _normalizeGatewayManualEndpoint(
      host: host ?? this.host,
      port: port ?? this.port,
      tls: tls ?? this.tls,
    );
    return GatewayConnectionProfile(
      mode: mode ?? this.mode,
      useSetupCode: useSetupCode ?? this.useSetupCode,
      setupCode: setupCode ?? this.setupCode,
      host: normalized.host,
      port: normalized.port,
      tls: normalized.tls,
      selectedAgentId: selectedAgentId ?? this.selectedAgentId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.name,
      'useSetupCode': useSetupCode,
      'setupCode': setupCode,
      'host': host,
      'port': port,
      'tls': tls,
      'selectedAgentId': selectedAgentId,
    };
  }

  factory GatewayConnectionProfile.fromJson(Map<String, dynamic> json) {
    final defaults = GatewayConnectionProfile.defaults();
    final normalized = _normalizeGatewayManualEndpoint(
      host: json['host'] as String? ?? defaults.host,
      port: json['port'] as int? ?? defaults.port,
      tls: json['tls'] as bool? ?? defaults.tls,
    );
    return GatewayConnectionProfile(
      mode: RuntimeConnectionModeCopy.fromJsonValue(json['mode'] as String?),
      useSetupCode: json['useSetupCode'] as bool? ?? false,
      setupCode: json['setupCode'] as String? ?? '',
      host: normalized.host,
      port: normalized.port,
      tls: normalized.tls,
      selectedAgentId: json['selectedAgentId'] as String? ?? '',
    );
  }
}

({String host, int port, bool tls}) _normalizeGatewayManualEndpoint({
  required String host,
  required int port,
  required bool tls,
}) {
  final trimmedHost = host.trim();
  if (trimmedHost.isEmpty) {
    return (host: trimmedHost, port: port, tls: tls);
  }
  final normalizedInput = trimmedHost.contains('://')
      ? trimmedHost
      : '${tls ? 'https' : 'http'}://$trimmedHost:${port > 0 ? port : (tls ? 443 : 18789)}';
  final uri = Uri.tryParse(normalizedInput);
  final normalizedHost = uri?.host.trim() ?? trimmedHost;
  if (normalizedHost.isEmpty) {
    return (host: trimmedHost, port: port, tls: tls);
  }
  final scheme = uri?.scheme.trim().toLowerCase() ?? (tls ? 'https' : 'http');
  final normalizedTls = switch (scheme) {
    'ws' || 'http' => false,
    _ => true,
  };
  final normalizedPort = uri?.hasPort == true
      ? uri!.port
      : normalizedTls
      ? 443
      : 18789;
  return (
    host: normalizedHost,
    port: normalizedPort > 0 ? normalizedPort : port,
    tls: normalizedTls,
  );
}

class OllamaLocalConfig {
  const OllamaLocalConfig({
    required this.endpoint,
    required this.defaultModel,
    required this.autoDiscover,
  });

  final String endpoint;
  final String defaultModel;
  final bool autoDiscover;

  factory OllamaLocalConfig.defaults() {
    return const OllamaLocalConfig(
      endpoint: 'http://127.0.0.1:11434',
      defaultModel: 'qwen2.5-coder:latest',
      autoDiscover: true,
    );
  }

  OllamaLocalConfig copyWith({
    String? endpoint,
    String? defaultModel,
    bool? autoDiscover,
  }) {
    return OllamaLocalConfig(
      endpoint: endpoint ?? this.endpoint,
      defaultModel: defaultModel ?? this.defaultModel,
      autoDiscover: autoDiscover ?? this.autoDiscover,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'endpoint': endpoint,
      'defaultModel': defaultModel,
      'autoDiscover': autoDiscover,
    };
  }

  factory OllamaLocalConfig.fromJson(Map<String, dynamic> json) {
    return OllamaLocalConfig(
      endpoint:
          json['endpoint'] as String? ?? OllamaLocalConfig.defaults().endpoint,
      defaultModel:
          json['defaultModel'] as String? ??
          OllamaLocalConfig.defaults().defaultModel,
      autoDiscover: json['autoDiscover'] as bool? ?? true,
    );
  }
}

class OllamaCloudConfig {
  const OllamaCloudConfig({
    required this.baseUrl,
    required this.organization,
    required this.workspace,
    required this.defaultModel,
    required this.apiKeyRef,
  });

  final String baseUrl;
  final String organization;
  final String workspace;
  final String defaultModel;
  final String apiKeyRef;

  factory OllamaCloudConfig.defaults() {
    return const OllamaCloudConfig(
      baseUrl: 'https://ollama.svc.plus',
      organization: '',
      workspace: '',
      defaultModel: 'gpt-oss:120b',
      apiKeyRef: 'ollama_cloud_api_key',
    );
  }

  OllamaCloudConfig copyWith({
    String? baseUrl,
    String? organization,
    String? workspace,
    String? defaultModel,
    String? apiKeyRef,
  }) {
    return OllamaCloudConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      organization: organization ?? this.organization,
      workspace: workspace ?? this.workspace,
      defaultModel: defaultModel ?? this.defaultModel,
      apiKeyRef: apiKeyRef ?? this.apiKeyRef,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'organization': organization,
      'workspace': workspace,
      'defaultModel': defaultModel,
      'apiKeyRef': apiKeyRef,
    };
  }

  factory OllamaCloudConfig.fromJson(Map<String, dynamic> json) {
    return OllamaCloudConfig(
      baseUrl:
          json['baseUrl'] as String? ?? OllamaCloudConfig.defaults().baseUrl,
      organization: json['organization'] as String? ?? '',
      workspace: json['workspace'] as String? ?? '',
      defaultModel:
          json['defaultModel'] as String? ??
          OllamaCloudConfig.defaults().defaultModel,
      apiKeyRef:
          json['apiKeyRef'] as String? ??
          OllamaCloudConfig.defaults().apiKeyRef,
    );
  }
}

class VaultConfig {
  const VaultConfig({
    required this.address,
    required this.namespace,
    required this.authMode,
    required this.tokenRef,
  });

  final String address;
  final String namespace;
  final String authMode;
  final String tokenRef;

  factory VaultConfig.defaults() {
    return const VaultConfig(
      address: 'http://127.0.0.1:8200',
      namespace: 'default',
      authMode: 'token',
      tokenRef: 'vault_token',
    );
  }

  VaultConfig copyWith({
    String? address,
    String? namespace,
    String? authMode,
    String? tokenRef,
  }) {
    return VaultConfig(
      address: address ?? this.address,
      namespace: namespace ?? this.namespace,
      authMode: authMode ?? this.authMode,
      tokenRef: tokenRef ?? this.tokenRef,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'namespace': namespace,
      'authMode': authMode,
      'tokenRef': tokenRef,
    };
  }

  factory VaultConfig.fromJson(Map<String, dynamic> json) {
    return VaultConfig(
      address: json['address'] as String? ?? VaultConfig.defaults().address,
      namespace:
          json['namespace'] as String? ?? VaultConfig.defaults().namespace,
      authMode: json['authMode'] as String? ?? VaultConfig.defaults().authMode,
      tokenRef: json['tokenRef'] as String? ?? VaultConfig.defaults().tokenRef,
    );
  }
}

class AiGatewayProfile {
  const AiGatewayProfile({
    required this.name,
    required this.baseUrl,
    required this.apiKeyRef,
    required this.availableModels,
    required this.selectedModels,
    required this.syncState,
    required this.syncMessage,
  });

  final String name;
  final String baseUrl;
  final String apiKeyRef;
  final List<String> availableModels;
  final List<String> selectedModels;
  final String syncState;
  final String syncMessage;

  factory AiGatewayProfile.defaults() {
    return const AiGatewayProfile(
      name: 'AI Gateway',
      baseUrl: '',
      apiKeyRef: 'ai_gateway_api_key',
      availableModels: <String>[],
      selectedModels: <String>[],
      syncState: 'idle',
      syncMessage: 'Ready to sync models',
    );
  }

  AiGatewayProfile copyWith({
    String? name,
    String? baseUrl,
    String? apiKeyRef,
    List<String>? availableModels,
    List<String>? selectedModels,
    String? syncState,
    String? syncMessage,
  }) {
    return AiGatewayProfile(
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKeyRef: apiKeyRef ?? this.apiKeyRef,
      availableModels: availableModels ?? this.availableModels,
      selectedModels: selectedModels ?? this.selectedModels,
      syncState: syncState ?? this.syncState,
      syncMessage: syncMessage ?? this.syncMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'baseUrl': baseUrl,
      'apiKeyRef': apiKeyRef,
      'availableModels': availableModels,
      'selectedModels': selectedModels,
      'syncState': syncState,
      'syncMessage': syncMessage,
    };
  }

  factory AiGatewayProfile.fromJson(Map<String, dynamic> json) {
    List<String> normalizeList(Object? value) {
      if (value is! List) {
        return const <String>[];
      }
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    final defaults = AiGatewayProfile.defaults();
    final availableModels = normalizeList(json['availableModels']);
    final selectedModels = normalizeList(json['selectedModels'])
        .where(
          (item) => availableModels.isEmpty || availableModels.contains(item),
        )
        .toList(growable: false);
    final legacyFilePath = json['filePath'] as String?;
    final legacyBaseUrl =
        legacyFilePath != null && legacyFilePath.trim().startsWith('http')
        ? legacyFilePath.trim()
        : null;
    return AiGatewayProfile(
      name: json['name'] as String? ?? defaults.name,
      baseUrl: json['baseUrl'] as String? ?? legacyBaseUrl ?? defaults.baseUrl,
      apiKeyRef: json['apiKeyRef'] as String? ?? defaults.apiKeyRef,
      availableModels: availableModels,
      selectedModels: selectedModels,
      syncState: json['syncState'] as String? ?? defaults.syncState,
      syncMessage: json['syncMessage'] as String? ?? defaults.syncMessage,
    );
  }
}

class AiGatewayConnectionCheck {
  const AiGatewayConnectionCheck({
    required this.state,
    required this.message,
    required this.endpoint,
    required this.modelCount,
  });

  final String state;
  final String message;
  final String endpoint;
  final int modelCount;

  bool get success => state == 'ready' || state == 'empty';
}

class SettingsSnapshot {
  const SettingsSnapshot({
    required this.appLanguage,
    required this.appActive,
    required this.launchAtLogin,
    required this.showDockIcon,
    required this.workspacePath,
    required this.remoteProjectRoot,
    required this.cliPath,
    required this.defaultModel,
    required this.defaultProvider,
    required this.gateway,
    required this.ollamaLocal,
    required this.ollamaCloud,
    required this.vault,
    required this.aiGateway,
    required this.experimentalCanvas,
    required this.experimentalBridge,
    required this.experimentalDebug,
    required this.accountBaseUrl,
    required this.accountUsername,
    required this.accountWorkspace,
    required this.accountLocalMode,
    required this.assistantExecutionTarget,
    required this.assistantPermissionLevel,
  });

  final AppLanguage appLanguage;
  final bool appActive;
  final bool launchAtLogin;
  final bool showDockIcon;
  final String workspacePath;
  final String remoteProjectRoot;
  final String cliPath;
  final String defaultModel;
  final String defaultProvider;
  final GatewayConnectionProfile gateway;
  final OllamaLocalConfig ollamaLocal;
  final OllamaCloudConfig ollamaCloud;
  final VaultConfig vault;
  final AiGatewayProfile aiGateway;
  final bool experimentalCanvas;
  final bool experimentalBridge;
  final bool experimentalDebug;
  final String accountBaseUrl;
  final String accountUsername;
  final String accountWorkspace;
  final bool accountLocalMode;
  final AssistantExecutionTarget assistantExecutionTarget;
  final AssistantPermissionLevel assistantPermissionLevel;

  factory SettingsSnapshot.defaults() {
    return SettingsSnapshot(
      appLanguage: AppLanguage.zh,
      appActive: true,
      launchAtLogin: false,
      showDockIcon: true,
      workspacePath: '/opt/data',
      remoteProjectRoot: '/opt/data/workspace',
      cliPath: 'openclaw',
      defaultModel: '',
      defaultProvider: 'gateway',
      gateway: GatewayConnectionProfile.defaults(),
      ollamaLocal: OllamaLocalConfig.defaults(),
      ollamaCloud: OllamaCloudConfig.defaults(),
      vault: VaultConfig.defaults(),
      aiGateway: AiGatewayProfile.defaults(),
      experimentalCanvas: false,
      experimentalBridge: false,
      experimentalDebug: false,
      accountBaseUrl: 'https://accounts.svc.plus',
      accountUsername: '',
      accountWorkspace: 'Default Workspace',
      accountLocalMode: true,
      assistantExecutionTarget: AssistantExecutionTarget.local,
      assistantPermissionLevel: AssistantPermissionLevel.defaultAccess,
    );
  }

  SettingsSnapshot copyWith({
    AppLanguage? appLanguage,
    bool? appActive,
    bool? launchAtLogin,
    bool? showDockIcon,
    String? workspacePath,
    String? remoteProjectRoot,
    String? cliPath,
    String? defaultModel,
    String? defaultProvider,
    GatewayConnectionProfile? gateway,
    OllamaLocalConfig? ollamaLocal,
    OllamaCloudConfig? ollamaCloud,
    VaultConfig? vault,
    AiGatewayProfile? aiGateway,
    bool? experimentalCanvas,
    bool? experimentalBridge,
    bool? experimentalDebug,
    String? accountBaseUrl,
    String? accountUsername,
    String? accountWorkspace,
    bool? accountLocalMode,
    AssistantExecutionTarget? assistantExecutionTarget,
    AssistantPermissionLevel? assistantPermissionLevel,
  }) {
    return SettingsSnapshot(
      appLanguage: appLanguage ?? this.appLanguage,
      appActive: appActive ?? this.appActive,
      launchAtLogin: launchAtLogin ?? this.launchAtLogin,
      showDockIcon: showDockIcon ?? this.showDockIcon,
      workspacePath: workspacePath ?? this.workspacePath,
      remoteProjectRoot: remoteProjectRoot ?? this.remoteProjectRoot,
      cliPath: cliPath ?? this.cliPath,
      defaultModel: defaultModel ?? this.defaultModel,
      defaultProvider: defaultProvider ?? this.defaultProvider,
      gateway: gateway ?? this.gateway,
      ollamaLocal: ollamaLocal ?? this.ollamaLocal,
      ollamaCloud: ollamaCloud ?? this.ollamaCloud,
      vault: vault ?? this.vault,
      aiGateway: aiGateway ?? this.aiGateway,
      experimentalCanvas: experimentalCanvas ?? this.experimentalCanvas,
      experimentalBridge: experimentalBridge ?? this.experimentalBridge,
      experimentalDebug: experimentalDebug ?? this.experimentalDebug,
      accountBaseUrl: accountBaseUrl ?? this.accountBaseUrl,
      accountUsername: accountUsername ?? this.accountUsername,
      accountWorkspace: accountWorkspace ?? this.accountWorkspace,
      accountLocalMode: accountLocalMode ?? this.accountLocalMode,
      assistantExecutionTarget:
          assistantExecutionTarget ?? this.assistantExecutionTarget,
      assistantPermissionLevel:
          assistantPermissionLevel ?? this.assistantPermissionLevel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'appLanguage': appLanguage.name,
      'appActive': appActive,
      'launchAtLogin': launchAtLogin,
      'showDockIcon': showDockIcon,
      'workspacePath': workspacePath,
      'remoteProjectRoot': remoteProjectRoot,
      'cliPath': cliPath,
      'defaultModel': defaultModel,
      'defaultProvider': defaultProvider,
      'gateway': gateway.toJson(),
      'ollamaLocal': ollamaLocal.toJson(),
      'ollamaCloud': ollamaCloud.toJson(),
      'vault': vault.toJson(),
      'aiGateway': aiGateway.toJson(),
      'experimentalCanvas': experimentalCanvas,
      'experimentalBridge': experimentalBridge,
      'experimentalDebug': experimentalDebug,
      'accountBaseUrl': accountBaseUrl,
      'accountUsername': accountUsername,
      'accountWorkspace': accountWorkspace,
      'accountLocalMode': accountLocalMode,
      'assistantExecutionTarget': assistantExecutionTarget.name,
      'assistantPermissionLevel': assistantPermissionLevel.name,
    };
  }

  factory SettingsSnapshot.fromJson(Map<String, dynamic> json) {
    return SettingsSnapshot(
      appLanguage: AppLanguageCopy.fromJsonValue(
        json['appLanguage'] as String?,
      ),
      appActive: json['appActive'] as bool? ?? true,
      launchAtLogin: json['launchAtLogin'] as bool? ?? false,
      showDockIcon: json['showDockIcon'] as bool? ?? true,
      workspacePath:
          json['workspacePath'] as String? ??
          SettingsSnapshot.defaults().workspacePath,
      remoteProjectRoot:
          json['remoteProjectRoot'] as String? ??
          SettingsSnapshot.defaults().remoteProjectRoot,
      cliPath:
          json['cliPath'] as String? ?? SettingsSnapshot.defaults().cliPath,
      defaultModel:
          json['defaultModel'] as String? ??
          SettingsSnapshot.defaults().defaultModel,
      defaultProvider:
          json['defaultProvider'] as String? ??
          SettingsSnapshot.defaults().defaultProvider,
      gateway: GatewayConnectionProfile.fromJson(
        (json['gateway'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      ollamaLocal: OllamaLocalConfig.fromJson(
        (json['ollamaLocal'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      ollamaCloud: OllamaCloudConfig.fromJson(
        (json['ollamaCloud'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      vault: VaultConfig.fromJson(
        (json['vault'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      aiGateway: AiGatewayProfile.fromJson(
        (json['aiGateway'] as Map?)?.cast<String, dynamic>() ??
            (json['apisix'] as Map?)?.cast<String, dynamic>() ??
            const {},
      ),
      experimentalCanvas: json['experimentalCanvas'] as bool? ?? false,
      experimentalBridge: json['experimentalBridge'] as bool? ?? false,
      experimentalDebug: json['experimentalDebug'] as bool? ?? false,
      accountBaseUrl:
          json['accountBaseUrl'] as String? ??
          SettingsSnapshot.defaults().accountBaseUrl,
      accountUsername: json['accountUsername'] as String? ?? '',
      accountWorkspace:
          json['accountWorkspace'] as String? ??
          SettingsSnapshot.defaults().accountWorkspace,
      accountLocalMode: json['accountLocalMode'] as bool? ?? true,
      assistantExecutionTarget: AssistantExecutionTargetCopy.fromJsonValue(
        json['assistantExecutionTarget'] as String?,
      ),
      assistantPermissionLevel: AssistantPermissionLevelCopy.fromJsonValue(
        json['assistantPermissionLevel'] as String?,
      ),
    );
  }

  static SettingsSnapshot fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return SettingsSnapshot.defaults();
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return SettingsSnapshot.fromJson(decoded);
    } catch (_) {
      return SettingsSnapshot.defaults();
    }
  }

  String toJsonString() => jsonEncode(toJson());
}

class GatewayConnectionSnapshot {
  const GatewayConnectionSnapshot({
    required this.status,
    required this.mode,
    required this.statusText,
    required this.serverName,
    required this.remoteAddress,
    required this.mainSessionKey,
    required this.lastError,
    required this.lastErrorCode,
    required this.lastErrorDetailCode,
    required this.lastConnectedAtMs,
    required this.deviceId,
    required this.authRole,
    required this.authScopes,
    required this.connectAuthMode,
    required this.connectAuthFields,
    required this.connectAuthSources,
    required this.hasSharedAuth,
    required this.hasDeviceToken,
    required this.healthPayload,
    required this.statusPayload,
  });

  final RuntimeConnectionStatus status;
  final RuntimeConnectionMode mode;
  final String statusText;
  final String? serverName;
  final String? remoteAddress;
  final String? mainSessionKey;
  final String? lastError;
  final String? lastErrorCode;
  final String? lastErrorDetailCode;
  final int? lastConnectedAtMs;
  final String? deviceId;
  final String? authRole;
  final List<String> authScopes;
  final String? connectAuthMode;
  final List<String> connectAuthFields;
  final List<String> connectAuthSources;
  final bool hasSharedAuth;
  final bool hasDeviceToken;
  final Map<String, dynamic>? healthPayload;
  final Map<String, dynamic>? statusPayload;

  factory GatewayConnectionSnapshot.initial({
    RuntimeConnectionMode mode = RuntimeConnectionMode.unconfigured,
  }) {
    return GatewayConnectionSnapshot(
      status: RuntimeConnectionStatus.offline,
      mode: mode,
      statusText: 'Offline',
      serverName: null,
      remoteAddress: null,
      mainSessionKey: null,
      lastError: null,
      lastErrorCode: null,
      lastErrorDetailCode: null,
      lastConnectedAtMs: null,
      deviceId: null,
      authRole: null,
      authScopes: const <String>[],
      connectAuthMode: null,
      connectAuthFields: const <String>[],
      connectAuthSources: const <String>[],
      hasSharedAuth: false,
      hasDeviceToken: false,
      healthPayload: null,
      statusPayload: null,
    );
  }

  GatewayConnectionSnapshot copyWith({
    RuntimeConnectionStatus? status,
    RuntimeConnectionMode? mode,
    String? statusText,
    String? serverName,
    String? remoteAddress,
    String? mainSessionKey,
    String? lastError,
    String? lastErrorCode,
    String? lastErrorDetailCode,
    int? lastConnectedAtMs,
    String? deviceId,
    String? authRole,
    List<String>? authScopes,
    String? connectAuthMode,
    List<String>? connectAuthFields,
    List<String>? connectAuthSources,
    bool? hasSharedAuth,
    bool? hasDeviceToken,
    Map<String, dynamic>? healthPayload,
    Map<String, dynamic>? statusPayload,
    bool clearServerName = false,
    bool clearRemoteAddress = false,
    bool clearMainSessionKey = false,
    bool clearLastError = false,
    bool clearLastErrorCode = false,
    bool clearLastErrorDetailCode = false,
  }) {
    return GatewayConnectionSnapshot(
      status: status ?? this.status,
      mode: mode ?? this.mode,
      statusText: statusText ?? this.statusText,
      serverName: clearServerName ? null : (serverName ?? this.serverName),
      remoteAddress: clearRemoteAddress
          ? null
          : (remoteAddress ?? this.remoteAddress),
      mainSessionKey: clearMainSessionKey
          ? null
          : (mainSessionKey ?? this.mainSessionKey),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastErrorCode: clearLastErrorCode
          ? null
          : (lastErrorCode ?? this.lastErrorCode),
      lastErrorDetailCode: clearLastErrorDetailCode
          ? null
          : (lastErrorDetailCode ?? this.lastErrorDetailCode),
      lastConnectedAtMs: lastConnectedAtMs ?? this.lastConnectedAtMs,
      deviceId: deviceId ?? this.deviceId,
      authRole: authRole ?? this.authRole,
      authScopes: authScopes ?? this.authScopes,
      connectAuthMode: connectAuthMode ?? this.connectAuthMode,
      connectAuthFields: connectAuthFields ?? this.connectAuthFields,
      connectAuthSources: connectAuthSources ?? this.connectAuthSources,
      hasSharedAuth: hasSharedAuth ?? this.hasSharedAuth,
      hasDeviceToken: hasDeviceToken ?? this.hasDeviceToken,
      healthPayload: healthPayload ?? this.healthPayload,
      statusPayload: statusPayload ?? this.statusPayload,
    );
  }

  bool get pairingRequired {
    final detailCode = lastErrorDetailCode?.trim().toUpperCase();
    final errorCode = lastErrorCode?.trim().toUpperCase();
    final errorText = lastError?.toLowerCase() ?? '';
    return status != RuntimeConnectionStatus.connected &&
        (detailCode == 'PAIRING_REQUIRED' ||
            errorCode == 'NOT_PAIRED' ||
            errorText.contains('pairing required'));
  }

  bool get gatewayTokenMissing {
    final detailCode = lastErrorDetailCode?.trim().toUpperCase();
    final errorText = lastError?.toLowerCase() ?? '';
    return detailCode == 'AUTH_TOKEN_MISSING' ||
        errorText.contains('gateway token missing');
  }

  String get connectAuthSummary {
    final mode = connectAuthMode?.trim() ?? 'none';
    final fields = connectAuthFields.isEmpty
        ? 'none'
        : connectAuthFields.join(', ');
    final sources = connectAuthSources.isEmpty
        ? 'none'
        : connectAuthSources.join(' · ');
    return '$mode | fields: $fields | sources: $sources';
  }
}

class RuntimePackageInfo {
  const RuntimePackageInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
  });

  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;
}

class RuntimeDeviceInfo {
  const RuntimeDeviceInfo({
    required this.platform,
    required this.platformVersion,
    required this.deviceFamily,
    required this.modelIdentifier,
  });

  final String platform;
  final String platformVersion;
  final String deviceFamily;
  final String modelIdentifier;

  String get platformLabel {
    final version = platformVersion.trim();
    if (version.isEmpty) {
      return platform;
    }
    return '$platform $version';
  }
}

class RuntimeLogEntry {
  const RuntimeLogEntry({
    required this.timestampMs,
    required this.level,
    required this.category,
    required this.message,
  });

  final int timestampMs;
  final String level;
  final String category;
  final String message;

  String get timeLabel {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  String get line => '[$timeLabel] ${level.toUpperCase()} $category $message';
}

class GatewayAgentSummary {
  const GatewayAgentSummary({
    required this.id,
    required this.name,
    required this.emoji,
    required this.theme,
  });

  final String id;
  final String name;
  final String emoji;
  final String theme;
}

class GatewaySessionSummary {
  const GatewaySessionSummary({
    required this.key,
    required this.kind,
    required this.displayName,
    required this.surface,
    required this.subject,
    required this.room,
    required this.space,
    required this.updatedAtMs,
    required this.sessionId,
    required this.systemSent,
    required this.abortedLastRun,
    required this.thinkingLevel,
    required this.verboseLevel,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.model,
    required this.contextTokens,
    required this.derivedTitle,
    required this.lastMessagePreview,
  });

  final String key;
  final String? kind;
  final String? displayName;
  final String? surface;
  final String? subject;
  final String? room;
  final String? space;
  final double? updatedAtMs;
  final String? sessionId;
  final bool? systemSent;
  final bool? abortedLastRun;
  final String? thinkingLevel;
  final String? verboseLevel;
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final String? model;
  final int? contextTokens;
  final String? derivedTitle;
  final String? lastMessagePreview;

  String get label {
    final candidates = [derivedTitle, displayName, subject, room, space, key];
    return candidates.firstWhere(
      (item) => item != null && item.trim().isNotEmpty,
      orElse: () => key,
    )!;
  }
}

class GatewayChatMessage {
  const GatewayChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestampMs,
    required this.toolCallId,
    required this.toolName,
    required this.stopReason,
    required this.pending,
    required this.error,
  });

  final String id;
  final String role;
  final String text;
  final double? timestampMs;
  final String? toolCallId;
  final String? toolName;
  final String? stopReason;
  final bool pending;
  final bool error;

  GatewayChatMessage copyWith({
    String? id,
    String? role,
    String? text,
    double? timestampMs,
    String? toolCallId,
    String? toolName,
    String? stopReason,
    bool? pending,
    bool? error,
  }) {
    return GatewayChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      timestampMs: timestampMs ?? this.timestampMs,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      stopReason: stopReason ?? this.stopReason,
      pending: pending ?? this.pending,
      error: error ?? this.error,
    );
  }
}

class GatewayChatAttachmentPayload {
  const GatewayChatAttachmentPayload({
    required this.type,
    required this.mimeType,
    required this.fileName,
    required this.content,
  });

  final String type;
  final String mimeType;
  final String fileName;
  final String content;

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'mimeType': mimeType,
      'fileName': fileName,
      'content': content,
    };
  }
}

class GatewayInstanceSummary {
  const GatewayInstanceSummary({
    required this.id,
    required this.host,
    required this.ip,
    required this.version,
    required this.platform,
    required this.deviceFamily,
    required this.modelIdentifier,
    required this.lastInputSeconds,
    required this.mode,
    required this.reason,
    required this.text,
    required this.timestampMs,
  });

  final String id;
  final String? host;
  final String? ip;
  final String? version;
  final String? platform;
  final String? deviceFamily;
  final String? modelIdentifier;
  final int? lastInputSeconds;
  final String? mode;
  final String? reason;
  final String text;
  final double timestampMs;
}

class GatewaySkillSummary {
  const GatewaySkillSummary({
    required this.name,
    required this.description,
    required this.source,
    required this.skillKey,
    required this.primaryEnv,
    required this.eligible,
    required this.disabled,
    required this.missingBins,
    required this.missingEnv,
    required this.missingConfig,
  });

  final String name;
  final String description;
  final String source;
  final String skillKey;
  final String? primaryEnv;
  final bool eligible;
  final bool disabled;
  final List<String> missingBins;
  final List<String> missingEnv;
  final List<String> missingConfig;
}

class GatewayConnectorSummary {
  const GatewayConnectorSummary({
    required this.id,
    required this.label,
    required this.detailLabel,
    required this.accountName,
    required this.configured,
    required this.enabled,
    required this.running,
    required this.connected,
    required this.status,
    required this.lastError,
    required this.meta,
  });

  final String id;
  final String label;
  final String detailLabel;
  final String? accountName;
  final bool configured;
  final bool enabled;
  final bool running;
  final bool connected;
  final String status;
  final String? lastError;
  final List<String> meta;
}

class GatewayModelSummary {
  const GatewayModelSummary({
    required this.id,
    required this.name,
    required this.provider,
    required this.contextWindow,
    required this.maxOutputTokens,
  });

  final String id;
  final String name;
  final String provider;
  final int? contextWindow;
  final int? maxOutputTokens;
}

class GatewayCronJobSummary {
  const GatewayCronJobSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
    required this.agentId,
    required this.scheduleLabel,
    required this.nextRunAtMs,
    required this.lastRunAtMs,
    required this.lastStatus,
    required this.lastError,
  });

  final String id;
  final String name;
  final String? description;
  final bool enabled;
  final String? agentId;
  final String scheduleLabel;
  final int? nextRunAtMs;
  final int? lastRunAtMs;
  final String? lastStatus;
  final String? lastError;
}

class GatewayDevicePairingList {
  const GatewayDevicePairingList({required this.pending, required this.paired});

  final List<GatewayPendingDevice> pending;
  final List<GatewayPairedDevice> paired;

  const GatewayDevicePairingList.empty()
    : pending = const <GatewayPendingDevice>[],
      paired = const <GatewayPairedDevice>[];
}

class GatewayPendingDevice {
  const GatewayPendingDevice({
    required this.requestId,
    required this.deviceId,
    required this.displayName,
    required this.role,
    required this.scopes,
    required this.remoteIp,
    required this.isRepair,
    required this.requestedAtMs,
  });

  final String requestId;
  final String deviceId;
  final String? displayName;
  final String? role;
  final List<String> scopes;
  final String? remoteIp;
  final bool isRepair;
  final int? requestedAtMs;

  String get label {
    final display = displayName?.trim() ?? '';
    return display.isEmpty ? deviceId : display;
  }
}

class GatewayPairedDevice {
  const GatewayPairedDevice({
    required this.deviceId,
    required this.displayName,
    required this.roles,
    required this.scopes,
    required this.remoteIp,
    required this.tokens,
    required this.createdAtMs,
    required this.approvedAtMs,
    required this.currentDevice,
  });

  final String deviceId;
  final String? displayName;
  final List<String> roles;
  final List<String> scopes;
  final String? remoteIp;
  final List<GatewayDeviceTokenSummary> tokens;
  final int? createdAtMs;
  final int? approvedAtMs;
  final bool currentDevice;

  String get label {
    final display = displayName?.trim() ?? '';
    return display.isEmpty ? deviceId : display;
  }
}

class GatewayDeviceTokenSummary {
  const GatewayDeviceTokenSummary({
    required this.role,
    required this.scopes,
    required this.createdAtMs,
    required this.rotatedAtMs,
    required this.revokedAtMs,
    required this.lastUsedAtMs,
  });

  final String role;
  final List<String> scopes;
  final int? createdAtMs;
  final int? rotatedAtMs;
  final int? revokedAtMs;
  final int? lastUsedAtMs;

  bool get revoked => revokedAtMs != null;
}

class SecretReferenceEntry {
  const SecretReferenceEntry({
    required this.name,
    required this.provider,
    required this.module,
    required this.maskedValue,
    required this.status,
  });

  final String name;
  final String provider;
  final String module;
  final String maskedValue;
  final String status;
}

class SecretAuditEntry {
  const SecretAuditEntry({
    required this.timeLabel,
    required this.action,
    required this.provider,
    required this.target,
    required this.module,
    required this.status,
  });

  final String timeLabel;
  final String action;
  final String provider;
  final String target;
  final String module;
  final String status;

  Map<String, dynamic> toJson() {
    return {
      'timeLabel': timeLabel,
      'action': action,
      'provider': provider,
      'target': target,
      'module': module,
      'status': status,
    };
  }

  factory SecretAuditEntry.fromJson(Map<String, dynamic> json) {
    return SecretAuditEntry(
      timeLabel: json['timeLabel'] as String? ?? '',
      action: json['action'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      target: json['target'] as String? ?? '',
      module: json['module'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }
}

class DerivedTaskItem {
  const DerivedTaskItem({
    required this.id,
    required this.title,
    required this.owner,
    required this.status,
    required this.surface,
    required this.startedAtLabel,
    required this.durationLabel,
    required this.summary,
    required this.sessionKey,
  });

  final String id;
  final String title;
  final String owner;
  final String status;
  final String surface;
  final String startedAtLabel;
  final String durationLabel;
  final String summary;
  final String sessionKey;
}

class LocalDeviceIdentity {
  const LocalDeviceIdentity({
    required this.deviceId,
    required this.publicKeyBase64Url,
    required this.privateKeyBase64Url,
    required this.createdAtMs,
  });

  final String deviceId;
  final String publicKeyBase64Url;
  final String privateKeyBase64Url;
  final int createdAtMs;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deviceId': deviceId,
      'publicKeyBase64Url': publicKeyBase64Url,
      'privateKeyBase64Url': privateKeyBase64Url,
      'createdAtMs': createdAtMs,
    };
  }

  factory LocalDeviceIdentity.fromJson(Map<String, dynamic> json) {
    return LocalDeviceIdentity(
      deviceId: json['deviceId'] as String? ?? '',
      publicKeyBase64Url: json['publicKeyBase64Url'] as String? ?? '',
      privateKeyBase64Url: json['privateKeyBase64Url'] as String? ?? '',
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}
