part of 'runtime_models.dart';

class SettingsSnapshot {
  const SettingsSnapshot({
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
    required this.externalAcpEndpoints,
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
    required this.accountLocalMode,
    required this.linuxDesktop,
    required this.assistantExecutionTarget,
    required this.assistantPermissionLevel,
    required this.assistantNavigationDestinations,
    required this.assistantCustomTaskTitles,
    required this.assistantArchivedTaskKeys,
    required this.assistantLastSessionKey,
  });

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
  final List<ExternalAcpEndpointProfile> externalAcpEndpoints;
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
  final bool accountLocalMode;
  final LinuxDesktopConfig linuxDesktop;
  final AssistantExecutionTarget assistantExecutionTarget;
  final AssistantPermissionLevel assistantPermissionLevel;
  final List<AssistantFocusEntry> assistantNavigationDestinations;
  final Map<String, String> assistantCustomTaskTitles;
  final List<String> assistantArchivedTaskKeys;
  final String assistantLastSessionKey;

  factory SettingsSnapshot.defaults() {
    return SettingsSnapshot(
      appLanguage: AppLanguage.zh,
      appActive: true,
      launchAtLogin: false,
      showDockIcon: true,
      workspacePath: '/opt/data',
      remoteProjectRoot: '/opt/data/workspace',
      cliPath: 'openclaw',
      codeAgentRuntimeMode: CodeAgentRuntimeMode.externalCli,
      codexCliPath: '',
      defaultModel: '',
      defaultProvider: 'gateway',
      gatewayProfiles: normalizeGatewayProfiles(),
      externalAcpEndpoints: normalizeExternalAcpEndpoints(),
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
      accountLocalMode: true,
      linuxDesktop: LinuxDesktopConfig.defaults(),
      assistantExecutionTarget: AssistantExecutionTarget.local,
      assistantPermissionLevel: AssistantPermissionLevel.defaultAccess,
      assistantNavigationDestinations: kAssistantNavigationDestinationDefaults,
      assistantCustomTaskTitles: const <String, String>{},
      assistantArchivedTaskKeys: const <String>[],
      assistantLastSessionKey: '',
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
    CodeAgentRuntimeMode? codeAgentRuntimeMode,
    String? codexCliPath,
    String? defaultModel,
    String? defaultProvider,
    List<GatewayConnectionProfile>? gatewayProfiles,
    List<ExternalAcpEndpointProfile>? externalAcpEndpoints,
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
    bool? accountLocalMode,
    LinuxDesktopConfig? linuxDesktop,
    AssistantExecutionTarget? assistantExecutionTarget,
    AssistantPermissionLevel? assistantPermissionLevel,
    List<AssistantFocusEntry>? assistantNavigationDestinations,
    Map<String, String>? assistantCustomTaskTitles,
    List<String>? assistantArchivedTaskKeys,
    String? assistantLastSessionKey,
  }) {
    final resolvedGatewayProfiles = gatewayProfiles != null
        ? normalizeGatewayProfiles(profiles: gatewayProfiles)
        : this.gatewayProfiles;
    final resolvedExternalAcpEndpoints = externalAcpEndpoints != null
        ? normalizeExternalAcpEndpoints(profiles: externalAcpEndpoints)
        : this.externalAcpEndpoints;
    final resolvedAuthorizedSkillDirectories =
        authorizedSkillDirectories != null
        ? normalizeAuthorizedSkillDirectories(
            directories: authorizedSkillDirectories,
          )
        : this.authorizedSkillDirectories;
    return SettingsSnapshot(
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
      externalAcpEndpoints: resolvedExternalAcpEndpoints,
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
      accountLocalMode: accountLocalMode ?? this.accountLocalMode,
      linuxDesktop: linuxDesktop ?? this.linuxDesktop,
      assistantExecutionTarget:
          assistantExecutionTarget ?? this.assistantExecutionTarget,
      assistantPermissionLevel:
          assistantPermissionLevel ?? this.assistantPermissionLevel,
      assistantNavigationDestinations:
          assistantNavigationDestinations ??
          this.assistantNavigationDestinations,
      assistantCustomTaskTitles:
          assistantCustomTaskTitles ?? this.assistantCustomTaskTitles,
      assistantArchivedTaskKeys:
          assistantArchivedTaskKeys ?? this.assistantArchivedTaskKeys,
      assistantLastSessionKey:
          assistantLastSessionKey ?? this.assistantLastSessionKey,
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
      'codeAgentRuntimeMode': codeAgentRuntimeMode.name,
      'codexCliPath': codexCliPath,
      'defaultModel': defaultModel,
      'defaultProvider': defaultProvider,
      'gatewayProfiles': gatewayProfiles
          .map((item) => item.toJson())
          .toList(growable: false),
      'externalAcpEndpoints': externalAcpEndpoints
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
      'accountLocalMode': accountLocalMode,
      'linuxDesktop': linuxDesktop.toJson(),
      'assistantExecutionTarget': assistantExecutionTarget.name,
      'assistantPermissionLevel': assistantPermissionLevel.name,
      'assistantNavigationDestinations': assistantNavigationDestinations
          .map((item) => item.name)
          .toList(growable: false),
      'assistantCustomTaskTitles': assistantCustomTaskTitles,
      'assistantArchivedTaskKeys': assistantArchivedTaskKeys,
      'assistantLastSessionKey': assistantLastSessionKey,
    };
  }

  factory SettingsSnapshot.fromJson(Map<String, dynamic> json) {
    Map<String, String> normalizeTaskTitles(Object? value) {
      if (value is! Map) {
        return const <String, String>{};
      }
      final normalized = <String, String>{};
      value.forEach((key, title) {
        final normalizedKey = key.toString().trim();
        final normalizedTitle = title.toString().trim();
        if (normalizedKey.isEmpty || normalizedTitle.isEmpty) {
          return;
        }
        normalized[normalizedKey] = normalizedTitle;
      });
      return normalized;
    }

    List<String> normalizeTaskKeys(Object? value) {
      if (value is! List) {
        return const <String>[];
      }
      final normalized = <String>[];
      final seen = <String>{};
      for (final item in value) {
        final normalizedKey = item?.toString().trim() ?? '';
        if (normalizedKey.isEmpty || !seen.add(normalizedKey)) {
          continue;
        }
        normalized.add(normalizedKey);
      }
      return normalized;
    }

    final rawAssistantNavigationDestinations =
        json['assistantNavigationDestinations'];
    final assistantNavigationDestinations =
        rawAssistantNavigationDestinations is List
        ? normalizeAssistantNavigationDestinations(
            rawAssistantNavigationDestinations
                .map(
                  (item) =>
                      AssistantFocusEntryCopy.fromJsonValue(item?.toString()),
                )
                .whereType<AssistantFocusEntry>(),
          )
        : kAssistantNavigationDestinationDefaults;
    final gatewayProfiles = normalizeGatewayProfiles(
      profiles: ((json['gatewayProfiles'] as List?) ?? const <Object>[])
          .whereType<Map>()
          .map(
            (item) =>
                GatewayConnectionProfile.fromJson(item.cast<String, dynamic>()),
          ),
    );
    final externalAcpEndpoints = normalizeExternalAcpEndpoints(
      profiles: ((json['externalAcpEndpoints'] as List?) ?? const <Object>[])
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
      externalAcpEndpoints: externalAcpEndpoints,
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
      accountLocalMode: json['accountLocalMode'] as bool? ?? true,
      linuxDesktop: LinuxDesktopConfig.fromJson(
        (json['linuxDesktop'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      assistantExecutionTarget: AssistantExecutionTargetCopy.fromJsonValue(
        json['assistantExecutionTarget'] as String?,
      ),
      assistantPermissionLevel: AssistantPermissionLevelCopy.fromJsonValue(
        json['assistantPermissionLevel'] as String?,
      ),
      assistantNavigationDestinations: assistantNavigationDestinations,
      assistantCustomTaskTitles: normalizeTaskTitles(
        json['assistantCustomTaskTitles'],
      ),
      assistantArchivedTaskKeys: normalizeTaskKeys(
        json['assistantArchivedTaskKeys'],
      ),
      assistantLastSessionKey: json['assistantLastSessionKey'] as String? ?? '',
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

  ExternalAcpEndpointProfile externalAcpEndpointForProvider(
    SingleAgentProvider provider,
  ) {
    return externalAcpEndpointForProviderId(provider.providerId) ??
        ExternalAcpEndpointProfile.defaultsForProvider(provider);
  }

  ExternalAcpEndpointProfile? externalAcpEndpointForProviderId(
    String providerId,
  ) {
    final normalized = normalizeSingleAgentProviderId(providerId);
    if (normalized.isEmpty) {
      return null;
    }
    for (final item in externalAcpEndpoints) {
      if (item.providerKey == normalized) {
        return item;
      }
    }
    if (kLegacyExternalAcpProviderIds.contains(normalized)) {
      final canonical = SingleAgentProvider.fromJsonValue(normalized);
      for (final item in externalAcpEndpoints) {
        if (!item.isPreset &&
            item.label.trim() == canonical.label &&
            item.badge.trim() == canonical.badge) {
          return item;
        }
      }
    }
    return null;
  }

  SingleAgentProvider resolveSingleAgentProvider(SingleAgentProvider provider) {
    final normalizedSelection = normalizeSingleAgentProviderSelection(provider);
    if (normalizedSelection.isAuto) {
      return SingleAgentProvider.auto;
    }
    final profile = externalAcpEndpointForProviderId(
      normalizedSelection.providerId,
    );
    if (profile != null) {
      return profile.toProvider();
    }
    return normalizedSelection;
  }

  SingleAgentProvider singleAgentProviderForId(String providerId) {
    final resolved = normalizeSingleAgentProviderId(providerId);
    if (resolved.isEmpty || resolved == SingleAgentProvider.auto.providerId) {
      return SingleAgentProvider.auto;
    }
    final normalizedSelection = normalizeSingleAgentProviderSelection(
      SingleAgentProvider.fromJsonValue(resolved),
    );
    final profile = externalAcpEndpointForProviderId(
      normalizedSelection.providerId,
    );
    if (profile != null) {
      return profile.toProvider();
    }
    return normalizedSelection;
  }

  List<SingleAgentProvider> get availableSingleAgentProviders =>
      normalizeSingleAgentProviderList(
        externalAcpEndpoints.map((item) => item.toProvider()),
      );

  SettingsSnapshot copyWithExternalAcpEndpointForProvider(
    SingleAgentProvider provider,
    ExternalAcpEndpointProfile profile,
  ) {
    return copyWith(
      externalAcpEndpoints: replaceExternalAcpEndpointForProvider(
        externalAcpEndpoints,
        provider,
        profile,
      ),
    );
  }
}
