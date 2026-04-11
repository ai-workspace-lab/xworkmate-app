// ignore_for_file: unused_import, unnecessary_import

import 'dart:convert';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import 'runtime_models_account.dart';
import 'runtime_models_connection.dart';
import 'runtime_models_profiles.dart';
import 'runtime_models_configs.dart';
import 'runtime_models_runtime_payloads.dart';
import 'runtime_models_gateway_entities.dart';
import 'runtime_models_multi_agent.dart';

const int settingsSnapshotSchemaVersion = 1;

class SettingsSnapshot {
  const SettingsSnapshot({
    required this.schemaVersion,
    required this.appLanguage,
    required this.appActive,
    required this.launchAtLogin,
    required this.showDockIcon,
    required this.workspacePath,
    required this.remoteProjectRoot,
    required this.cliPath,
    required this.codeAgentRuntimeMode,
    required this.codexCliPath,
    required this.defaultModel,
    required this.defaultProvider,
    required this.gatewayProfiles,
    required this.providerSyncDefinitions,
    required this.authorizedSkillDirectories,
    required this.ollamaLocal,
    required this.ollamaCloud,
    required this.vault,
    required this.aiGateway,
    required this.webSessionPersistence,
    required this.multiAgent,
    required this.experimentalCanvas,
    required this.experimentalBridge,
    required this.experimentalDebug,
    required this.accountBaseUrl,
    required this.accountUsername,
    required this.accountWorkspace,
    required this.accountWorkspaceFollowed,
    required this.accountLocalMode,
    required this.acpBridgeServerModeConfig,
    required this.linuxDesktop,
    required this.assistantExecutionTarget,
    required this.assistantPermissionLevel,
  });

  final int schemaVersion;
  final AppLanguage appLanguage;
  final bool appActive;
  final bool launchAtLogin;
  final bool showDockIcon;
  final String workspacePath;
  final String remoteProjectRoot;
  final String cliPath;
  final CodeAgentRuntimeMode codeAgentRuntimeMode;
  final String codexCliPath;
  final String defaultModel;
  final String defaultProvider;
  final List<GatewayConnectionProfile> gatewayProfiles;
  final List<ExternalAcpEndpointProfile> providerSyncDefinitions;
  final List<AuthorizedSkillDirectory> authorizedSkillDirectories;
  final OllamaLocalConfig ollamaLocal;
  final OllamaCloudConfig ollamaCloud;
  final VaultConfig vault;
  final AiGatewayProfile aiGateway;
  final WebSessionPersistenceConfig webSessionPersistence;
  final MultiAgentConfig multiAgent;
  final bool experimentalCanvas;
  final bool experimentalBridge;
  final bool experimentalDebug;
  final String accountBaseUrl;
  final String accountUsername;
  final String accountWorkspace;
  final bool accountWorkspaceFollowed;
  final bool accountLocalMode;
  final AcpBridgeServerModeConfig acpBridgeServerModeConfig;
  final LinuxDesktopConfig linuxDesktop;
  final AssistantExecutionTarget assistantExecutionTarget;
  final AssistantPermissionLevel assistantPermissionLevel;

  factory SettingsSnapshot.defaults() {
    return SettingsSnapshot(
      schemaVersion: settingsSnapshotSchemaVersion,
      appLanguage: AppLanguage.zh,
      appActive: true,
      launchAtLogin: false,
      showDockIcon: true,
      workspacePath: '',
      remoteProjectRoot: '',
      cliPath: 'openclaw',
      codeAgentRuntimeMode: CodeAgentRuntimeMode.externalCli,
      codexCliPath: '',
      defaultModel: '',
      defaultProvider: 'gateway',
      gatewayProfiles: normalizeGatewayProfiles(),
      providerSyncDefinitions: normalizeExternalAcpEndpoints(),
      authorizedSkillDirectories: normalizeAuthorizedSkillDirectories(),
      ollamaLocal: OllamaLocalConfig.defaults(),
      ollamaCloud: OllamaCloudConfig.defaults(),
      vault: VaultConfig.defaults(),
      aiGateway: AiGatewayProfile.defaults(),
      webSessionPersistence: WebSessionPersistenceConfig.defaults(),
      multiAgent: MultiAgentConfig.defaults(),
      experimentalCanvas: false,
      experimentalBridge: false,
      experimentalDebug: false,
      accountBaseUrl: 'https://accounts.svc.plus',
      accountUsername: '',
      accountWorkspace: 'Default Workspace',
      accountWorkspaceFollowed: false,
      accountLocalMode: true,
      acpBridgeServerModeConfig: AcpBridgeServerModeConfig.defaults(),
      linuxDesktop: LinuxDesktopConfig.defaults(),
      assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
      assistantPermissionLevel: AssistantPermissionLevel.defaultAccess,
    );
  }

  SettingsSnapshot copyWith({
    int? schemaVersion,
    AppLanguage? appLanguage,
    bool? appActive,
    bool? launchAtLogin,
    bool? showDockIcon,
    String? workspacePath,
    String? remoteProjectRoot,
    String? cliPath,
    CodeAgentRuntimeMode? codeAgentRuntimeMode,
    String? codexCliPath,
    String? defaultModel,
    String? defaultProvider,
    List<GatewayConnectionProfile>? gatewayProfiles,
    List<ExternalAcpEndpointProfile>? providerSyncDefinitions,
    List<AuthorizedSkillDirectory>? authorizedSkillDirectories,
    OllamaLocalConfig? ollamaLocal,
    OllamaCloudConfig? ollamaCloud,
    VaultConfig? vault,
    AiGatewayProfile? aiGateway,
    WebSessionPersistenceConfig? webSessionPersistence,
    MultiAgentConfig? multiAgent,
    bool? experimentalCanvas,
    bool? experimentalBridge,
    bool? experimentalDebug,
    String? accountBaseUrl,
    String? accountUsername,
    String? accountWorkspace,
    bool? accountWorkspaceFollowed,
    bool? accountLocalMode,
    AcpBridgeServerModeConfig? acpBridgeServerModeConfig,
    LinuxDesktopConfig? linuxDesktop,
    AssistantExecutionTarget? assistantExecutionTarget,
    AssistantPermissionLevel? assistantPermissionLevel,
  }) {
    final resolvedGatewayProfiles = gatewayProfiles != null
        ? normalizeGatewayProfiles(profiles: gatewayProfiles)
        : this.gatewayProfiles;
    final resolvedProviderSyncDefinitions = providerSyncDefinitions != null
        ? normalizeExternalAcpEndpoints(profiles: providerSyncDefinitions)
        : this.providerSyncDefinitions;
    final resolvedAuthorizedSkillDirectories =
        authorizedSkillDirectories != null
        ? normalizeAuthorizedSkillDirectories(
            directories: authorizedSkillDirectories,
          )
        : this.authorizedSkillDirectories;
    return SettingsSnapshot(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      appLanguage: appLanguage ?? this.appLanguage,
      appActive: appActive ?? this.appActive,
      launchAtLogin: launchAtLogin ?? this.launchAtLogin,
      showDockIcon: showDockIcon ?? this.showDockIcon,
      workspacePath: workspacePath ?? this.workspacePath,
      remoteProjectRoot: remoteProjectRoot ?? this.remoteProjectRoot,
      cliPath: cliPath ?? this.cliPath,
      codeAgentRuntimeMode: codeAgentRuntimeMode ?? this.codeAgentRuntimeMode,
      codexCliPath: codexCliPath ?? this.codexCliPath,
      defaultModel: defaultModel ?? this.defaultModel,
      defaultProvider: defaultProvider ?? this.defaultProvider,
      gatewayProfiles: resolvedGatewayProfiles,
      providerSyncDefinitions: resolvedProviderSyncDefinitions,
      authorizedSkillDirectories: resolvedAuthorizedSkillDirectories,
      ollamaLocal: ollamaLocal ?? this.ollamaLocal,
      ollamaCloud: ollamaCloud ?? this.ollamaCloud,
      vault: vault ?? this.vault,
      aiGateway: aiGateway ?? this.aiGateway,
      webSessionPersistence:
          webSessionPersistence ?? this.webSessionPersistence,
      multiAgent: multiAgent ?? this.multiAgent,
      experimentalCanvas: experimentalCanvas ?? this.experimentalCanvas,
      experimentalBridge: experimentalBridge ?? this.experimentalBridge,
      experimentalDebug: experimentalDebug ?? this.experimentalDebug,
      accountBaseUrl: accountBaseUrl ?? this.accountBaseUrl,
      accountUsername: accountUsername ?? this.accountUsername,
      accountWorkspace: accountWorkspace ?? this.accountWorkspace,
      accountWorkspaceFollowed:
          accountWorkspaceFollowed ?? this.accountWorkspaceFollowed,
      accountLocalMode: accountLocalMode ?? this.accountLocalMode,
      acpBridgeServerModeConfig:
          acpBridgeServerModeConfig ?? this.acpBridgeServerModeConfig,
      linuxDesktop: linuxDesktop ?? this.linuxDesktop,
      assistantExecutionTarget:
          assistantExecutionTarget ?? this.assistantExecutionTarget,
      assistantPermissionLevel:
          assistantPermissionLevel ?? this.assistantPermissionLevel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'appLanguage': appLanguage.name,
      'appActive': appActive,
      'launchAtLogin': launchAtLogin,
      'showDockIcon': showDockIcon,
      'workspacePath': workspacePath,
      'remoteProjectRoot': remoteProjectRoot,
      'cliPath': cliPath,
      'codeAgentRuntimeMode': codeAgentRuntimeMode.name,
      'codexCliPath': codexCliPath,
      'defaultModel': defaultModel,
      'defaultProvider': defaultProvider,
      'gatewayProfiles': gatewayProfiles
          .map((item) => item.toJson())
          .toList(growable: false),
      'providerSyncDefinitions': providerSyncDefinitions
          .map((item) => item.toJson())
          .toList(growable: false),
      'authorizedSkillDirectories': authorizedSkillDirectories
          .map((item) => item.toJson())
          .toList(growable: false),
      'ollamaLocal': ollamaLocal.toJson(),
      'ollamaCloud': ollamaCloud.toJson(),
      'vault': vault.toJson(),
      'aiGateway': aiGateway.toJson(),
      'webSessionPersistence': webSessionPersistence.toJson(),
      'multiAgent': multiAgent.toJson(),
      'experimentalCanvas': experimentalCanvas,
      'experimentalBridge': experimentalBridge,
      'experimentalDebug': experimentalDebug,
      'accountBaseUrl': accountBaseUrl,
      'accountUsername': accountUsername,
      'accountWorkspace': accountWorkspace,
      'accountWorkspaceFollowed': accountWorkspaceFollowed,
      'accountLocalMode': accountLocalMode,
      'acpBridgeServerModeConfig': acpBridgeServerModeConfig.toJson(),
      'linuxDesktop': linuxDesktop.toJson(),
      'assistantExecutionTarget': assistantExecutionTarget.name,
      'assistantPermissionLevel': assistantPermissionLevel.name,
    };
  }

  factory SettingsSnapshot.fromJson(Map<String, dynamic> json) {
    final parsedSchemaVersion = (json['schemaVersion'] as num?)?.toInt() ?? -1;
    if (parsedSchemaVersion != settingsSnapshotSchemaVersion) {
      throw const FormatException(
        'Unsupported settings snapshot schema version.',
      );
    }
    final gatewayProfiles = normalizeGatewayProfiles(
      profiles: ((json['gatewayProfiles'] as List?) ?? const <Object>[])
          .whereType<Map>()
          .map(
            (item) =>
                GatewayConnectionProfile.fromJson(item.cast<String, dynamic>()),
          ),
    );
    final providerSyncDefinitions = normalizeExternalAcpEndpoints(
      profiles: ((json['providerSyncDefinitions'] as List?) ?? const <Object>[])
          .whereType<Map>()
          .map(
            (item) => ExternalAcpEndpointProfile.fromJson(
              item.cast<String, dynamic>(),
            ),
          ),
    );
    final authorizedSkillDirectories = normalizeAuthorizedSkillDirectories(
      directories:
          ((json['authorizedSkillDirectories'] as List?) ?? const <Object>[])
              .whereType<Map>()
              .map(
                (item) => AuthorizedSkillDirectory.fromJson(
                  item.cast<String, dynamic>(),
                ),
              ),
    );
    return SettingsSnapshot(
      schemaVersion: parsedSchemaVersion,
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
      codeAgentRuntimeMode: CodeAgentRuntimeModeCopy.fromJsonValue(
        json['codeAgentRuntimeMode'] as String?,
      ),
      codexCliPath:
          json['codexCliPath'] as String? ??
          SettingsSnapshot.defaults().codexCliPath,
      defaultModel:
          json['defaultModel'] as String? ??
          SettingsSnapshot.defaults().defaultModel,
      defaultProvider:
          json['defaultProvider'] as String? ??
          SettingsSnapshot.defaults().defaultProvider,
      gatewayProfiles: gatewayProfiles,
      providerSyncDefinitions: providerSyncDefinitions,
      authorizedSkillDirectories: authorizedSkillDirectories,
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
      webSessionPersistence: WebSessionPersistenceConfig.fromJson(
        (json['webSessionPersistence'] as Map?)?.cast<String, dynamic>() ??
            const {},
      ),
      multiAgent: MultiAgentConfig.fromJson(
        (json['multiAgent'] as Map?)?.cast<String, dynamic>() ?? const {},
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
      accountWorkspaceFollowed:
          json['accountWorkspaceFollowed'] as bool? ?? false,
      accountLocalMode: json['accountLocalMode'] as bool? ?? true,
      acpBridgeServerModeConfig: AcpBridgeServerModeConfig.fromJson(
        (json['acpBridgeServerModeConfig'] as Map?)?.cast<String, dynamic>() ??
            const {},
      ),
      linuxDesktop: LinuxDesktopConfig.fromJson(
        (json['linuxDesktop'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
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

  GatewayConnectionProfile get primaryLocalGatewayProfile =>
      gatewayProfiles[kGatewayLocalProfileIndex];

  GatewayConnectionProfile get primaryRemoteGatewayProfile =>
      gatewayProfiles[kGatewayRemoteProfileIndex];

  GatewayConnectionProfile? gatewayProfileForExecutionTarget(
    AssistantExecutionTarget target,
  ) {
    return switch (target) {
      AssistantExecutionTarget.singleAgent => null,
      AssistantExecutionTarget.local => primaryLocalGatewayProfile,
      AssistantExecutionTarget.remote => primaryRemoteGatewayProfile,
    };
  }

  SettingsSnapshot copyWithGatewayProfileAt(
    int index,
    GatewayConnectionProfile profile,
  ) {
    return copyWith(
      gatewayProfiles: replaceGatewayProfileAt(gatewayProfiles, index, profile),
    );
  }

  SettingsSnapshot copyWithGatewayProfileForExecutionTarget(
    AssistantExecutionTarget target,
    GatewayConnectionProfile profile,
  ) {
    final index = switch (target) {
      AssistantExecutionTarget.local => kGatewayLocalProfileIndex,
      AssistantExecutionTarget.remote => kGatewayRemoteProfileIndex,
      AssistantExecutionTarget.singleAgent => null,
    };
    if (index == null) {
      return this;
    }
    return copyWithGatewayProfileAt(index, profile);
  }

  ExternalAcpEndpointProfile providerSyncDefinitionForProvider(
    SingleAgentProvider provider,
  ) {
    return providerSyncDefinitionForProviderId(provider.providerId) ??
        ExternalAcpEndpointProfile.defaultsForProvider(provider);
  }

  ExternalAcpEndpointProfile? providerSyncDefinitionForProviderId(
    String providerId,
  ) {
    final normalized = normalizeSingleAgentProviderId(providerId);
    if (normalized.isEmpty) {
      return null;
    }
    for (final item in providerSyncDefinitions) {
      if (item.providerKey == normalized) {
        return item;
      }
    }
    return null;
  }

  SingleAgentProvider resolveSingleAgentProvider(SingleAgentProvider provider) {
    if (provider.isAuto) {
      return SingleAgentProvider.auto;
    }
    final profile = providerSyncDefinitionForProviderId(provider.providerId);
    if (profile != null) {
      return profile.toProvider();
    }
    return provider;
  }

  SingleAgentProvider singleAgentProviderForId(String providerId) {
    final resolved = normalizeSingleAgentProviderId(providerId);
    if (resolved.isEmpty || resolved == SingleAgentProvider.auto.providerId) {
      return SingleAgentProvider.auto;
    }
    final normalizedSelection = SingleAgentProvider.fromJsonValue(resolved);
    final profile = providerSyncDefinitionForProviderId(
      normalizedSelection.providerId,
    );
    if (profile != null) {
      return profile.toProvider();
    }
    return normalizedSelection;
  }

  SingleAgentProvider sanitizeSingleAgentProviderSelection(
    SingleAgentProvider provider,
  ) {
    final resolved = resolveSingleAgentProvider(provider);
    if (resolved.isAuto) {
      return SingleAgentProvider.auto;
    }
    if (kKnownSingleAgentProviders.any(
      (item) => item.providerId == resolved.providerId,
    )) {
      return resolved;
    }
    return resolved;
  }

  SettingsSnapshot copyWithProviderSyncDefinitionForProvider(
    SingleAgentProvider provider,
    ExternalAcpEndpointProfile profile,
  ) {
    return copyWith(
      providerSyncDefinitions: replaceExternalAcpEndpointForProvider(
        providerSyncDefinitions,
        provider,
        profile,
      ),
    );
  }

  SettingsSnapshot captureAcpBridgeServerAdvancedOverrides() {
    return copyWith(
      acpBridgeServerModeConfig: acpBridgeServerModeConfig.copyWith(
        advancedOverrides: AcpBridgeServerAdvancedOverrides(
          gatewayProfiles: gatewayProfiles,
          vault: vault,
          aiGateway: aiGateway,
          acpBridgeServerProfiles: providerSyncDefinitions,
          authorizedSkillDirectories: authorizedSkillDirectories,
        ),
      ),
    );
  }
}
