import 'dart:convert';

enum RuntimeConnectionMode { unconfigured, local, remote }

extension RuntimeConnectionModeCopy on RuntimeConnectionMode {
  String get label => switch (this) {
    RuntimeConnectionMode.unconfigured => 'Unconfigured',
    RuntimeConnectionMode.local => 'Local',
    RuntimeConnectionMode.remote => 'Remote',
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
    RuntimeConnectionStatus.offline => 'Offline',
    RuntimeConnectionStatus.connecting => 'Connecting',
    RuntimeConnectionStatus.connected => 'Connected',
    RuntimeConnectionStatus.error => 'Error',
  };
}

enum AssistantExecutionTarget { local, remote }

extension AssistantExecutionTargetCopy on AssistantExecutionTarget {
  String get label => switch (this) {
    AssistantExecutionTarget.local => '本地',
    AssistantExecutionTarget.remote => '远程',
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
    AssistantPermissionLevel.defaultAccess => '默认权限',
    AssistantPermissionLevel.fullAccess => '完全访问权限',
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
    return GatewayConnectionProfile(
      mode: mode ?? this.mode,
      useSetupCode: useSetupCode ?? this.useSetupCode,
      setupCode: setupCode ?? this.setupCode,
      host: host ?? this.host,
      port: port ?? this.port,
      tls: tls ?? this.tls,
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
    return GatewayConnectionProfile(
      mode: RuntimeConnectionModeCopy.fromJsonValue(json['mode'] as String?),
      useSetupCode: json['useSetupCode'] as bool? ?? false,
      setupCode: json['setupCode'] as String? ?? '',
      host: json['host'] as String? ?? GatewayConnectionProfile.defaults().host,
      port: json['port'] as int? ?? GatewayConnectionProfile.defaults().port,
      tls: json['tls'] as bool? ?? true,
      selectedAgentId: json['selectedAgentId'] as String? ?? '',
    );
  }
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

class ApisixYamlProfile {
  const ApisixYamlProfile({
    required this.name,
    required this.sourceType,
    required this.filePath,
    required this.inlineYaml,
    required this.validationState,
    required this.validationMessage,
  });

  final String name;
  final String sourceType;
  final String filePath;
  final String inlineYaml;
  final String validationState;
  final String validationMessage;

  factory ApisixYamlProfile.defaults() {
    return const ApisixYamlProfile(
      name: 'default',
      sourceType: 'workspace-file',
      filePath: '/opt/data/apisix/openclaw.yaml',
      inlineYaml: '',
      validationState: 'idle',
      validationMessage: 'Ready to validate',
    );
  }

  ApisixYamlProfile copyWith({
    String? name,
    String? sourceType,
    String? filePath,
    String? inlineYaml,
    String? validationState,
    String? validationMessage,
  }) {
    return ApisixYamlProfile(
      name: name ?? this.name,
      sourceType: sourceType ?? this.sourceType,
      filePath: filePath ?? this.filePath,
      inlineYaml: inlineYaml ?? this.inlineYaml,
      validationState: validationState ?? this.validationState,
      validationMessage: validationMessage ?? this.validationMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'sourceType': sourceType,
      'filePath': filePath,
      'inlineYaml': inlineYaml,
      'validationState': validationState,
      'validationMessage': validationMessage,
    };
  }

  factory ApisixYamlProfile.fromJson(Map<String, dynamic> json) {
    return ApisixYamlProfile(
      name: json['name'] as String? ?? ApisixYamlProfile.defaults().name,
      sourceType:
          json['sourceType'] as String? ??
          ApisixYamlProfile.defaults().sourceType,
      filePath:
          json['filePath'] as String? ?? ApisixYamlProfile.defaults().filePath,
      inlineYaml: json['inlineYaml'] as String? ?? '',
      validationState:
          json['validationState'] as String? ??
          ApisixYamlProfile.defaults().validationState,
      validationMessage:
          json['validationMessage'] as String? ??
          ApisixYamlProfile.defaults().validationMessage,
    );
  }
}

class SettingsSnapshot {
  const SettingsSnapshot({
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
    required this.apisix,
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
  final ApisixYamlProfile apisix;
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
      appActive: true,
      launchAtLogin: false,
      showDockIcon: true,
      workspacePath: '/opt/data',
      remoteProjectRoot: '/opt/data/workspace',
      cliPath: 'openclaw',
      defaultModel: 'gpt-5.4',
      defaultProvider: 'gateway',
      gateway: GatewayConnectionProfile.defaults(),
      ollamaLocal: OllamaLocalConfig.defaults(),
      ollamaCloud: OllamaCloudConfig.defaults(),
      vault: VaultConfig.defaults(),
      apisix: ApisixYamlProfile.defaults(),
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
    ApisixYamlProfile? apisix,
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
      apisix: apisix ?? this.apisix,
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
      'apisix': apisix.toJson(),
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
      apisix: ApisixYamlProfile.fromJson(
        (json['apisix'] as Map?)?.cast<String, dynamic>() ?? const {},
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
    required this.lastConnectedAtMs,
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
  final int? lastConnectedAtMs;
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
      lastConnectedAtMs: null,
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
    int? lastConnectedAtMs,
    bool? hasSharedAuth,
    bool? hasDeviceToken,
    Map<String, dynamic>? healthPayload,
    Map<String, dynamic>? statusPayload,
    bool clearServerName = false,
    bool clearRemoteAddress = false,
    bool clearMainSessionKey = false,
    bool clearLastError = false,
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
      lastConnectedAtMs: lastConnectedAtMs ?? this.lastConnectedAtMs,
      hasSharedAuth: hasSharedAuth ?? this.hasSharedAuth,
      hasDeviceToken: hasDeviceToken ?? this.hasDeviceToken,
      healthPayload: healthPayload ?? this.healthPayload,
      statusPayload: statusPayload ?? this.statusPayload,
    );
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
}
