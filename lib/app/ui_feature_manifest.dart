import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

import '../models/app_models.dart';
import '../runtime/runtime_models.dart';

enum UiFeaturePlatform { mobile, desktop, web }

enum UiFeatureReleaseTier { stable, beta, experimental }

enum UiFeatureBuildMode { debug, profile, release }

UiFeatureBuildMode currentUiFeatureBuildMode() {
  if (kReleaseMode) {
    return UiFeatureBuildMode.release;
  }
  if (kProfileMode) {
    return UiFeatureBuildMode.profile;
  }
  return UiFeatureBuildMode.debug;
}

UiFeaturePlatform resolveUiFeaturePlatformFromContext(BuildContext context) {
  if (kIsWeb) {
    return UiFeaturePlatform.web;
  }
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.android) {
    return UiFeaturePlatform.mobile;
  }
  return UiFeaturePlatform.desktop;
}

abstract final class UiFeatureKeys {
  static const navigationAssistant = 'navigation.assistant';
  static const navigationTasks = 'navigation.tasks';
  static const navigationWorkspace = 'navigation.workspace';
  static const navigationSkills = 'navigation.skills';
  static const navigationNodes = 'navigation.nodes';
  static const navigationAgents = 'navigation.agents';
  static const navigationMcpServer = 'navigation.mcp_server';
  static const navigationClawHub = 'navigation.claw_hub';
  static const navigationSecrets = 'navigation.secrets';
  static const navigationAiGateway = 'navigation.ai_gateway';
  static const navigationSettings = 'navigation.settings';
  static const navigationAccount = 'navigation.account';

  static const workspaceSkills = 'workspace.skills';
  static const workspaceNodes = 'workspace.nodes';
  static const workspaceAgents = 'workspace.agents';
  static const workspaceMcpServer = 'workspace.mcp_server';
  static const workspaceClawHub = 'workspace.claw_hub';
  static const workspaceAiGateway = 'workspace.ai_gateway';
  static const workspaceAccount = 'workspace.account';

  static const assistantDirectAi = 'assistant.direct_ai';
  static const assistantLocalGateway = 'assistant.local_gateway';
  static const assistantRelayGateway = 'assistant.relay_gateway';
  static const assistantFileAttachments = 'assistant.file_attachments';
  static const assistantMultiAgent = 'assistant.multi_agent';
  static const assistantLocalRuntime = 'assistant.local_runtime';

  static const settingsGeneral = 'settings.general';
  static const settingsWorkspace = 'settings.workspace';
  static const settingsGateway = 'settings.gateway';
  static const settingsVaultServer = 'settings.vault_server';
  static const settingsGatewaySetupCode = 'settings.gateway_setup_code';
  static const settingsAgents = 'settings.agents';
  static const settingsAppearance = 'settings.appearance';
  static const settingsDiagnostics = 'settings.diagnostics';
  static const settingsExperimental = 'settings.experimental';
  static const settingsAbout = 'settings.about';
  static const settingsExperimentalCanvas = 'settings.experimental_canvas';
  static const settingsExperimentalBridge = 'settings.experimental_bridge';
  static const settingsExperimentalDebug = 'settings.experimental_debug';
}

@immutable
class UiFeatureFlag {
  const UiFeatureFlag({
    required this.enabled,
    required this.releaseTier,
    required this.buildModes,
    required this.description,
    required this.uiSurface,
  });

  final bool enabled;
  final UiFeatureReleaseTier releaseTier;
  final Set<UiFeatureBuildMode> buildModes;
  final String description;
  final String uiSurface;

  UiFeatureFlag copyWith({
    bool? enabled,
    UiFeatureReleaseTier? releaseTier,
    Set<UiFeatureBuildMode>? buildModes,
    String? description,
    String? uiSurface,
  }) {
    return UiFeatureFlag(
      enabled: enabled ?? this.enabled,
      releaseTier: releaseTier ?? this.releaseTier,
      buildModes: buildModes ?? this.buildModes,
      description: description ?? this.description,
      uiSurface: uiSurface ?? this.uiSurface,
    );
  }
}

class UiFeatureManifest {
  UiFeatureManifest._({
    required this.releasePolicy,
    required Map<UiFeaturePlatform, Map<String, Map<String, UiFeatureFlag>>>
    flagsByPlatform,
  }) : _flagsByPlatform = flagsByPlatform;

  static const String assetPath = 'config/feature_flags.yaml';

  static const String fallbackYaml = '''
release_policy:
  debug: [stable, beta, experimental]
  profile: [stable, beta]
  release: [stable]

mobile:
  navigation:
    assistant:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile assistant destination
      ui_surface: mobile_shell
    tasks:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile tasks destination
      ui_surface: mobile_shell
    workspace:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace hub destination
      ui_surface: mobile_shell
    secrets:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile secrets destination
      ui_surface: mobile_shell
    settings:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings destination
      ui_surface: mobile_shell
  workspace:
    skills:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace skills launcher
      ui_surface: mobile_workspace_hub
    nodes:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace nodes launcher
      ui_surface: mobile_workspace_hub
    agents:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace agents launcher
      ui_surface: mobile_workspace_hub
    mcp_server:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace MCP launcher
      ui_surface: mobile_workspace_hub
    claw_hub:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace ClawHub launcher
      ui_surface: mobile_workspace_hub
    ai_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace AI Gateway launcher
      ui_surface: mobile_workspace_hub
    account:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace account launcher
      ui_surface: mobile_workspace_hub
  assistant:
    direct_ai:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Mobile does not expose direct AI assistant mode
      ui_surface: assistant_page
    local_gateway:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Mobile does not expose local gateway assistant mode
      ui_surface: assistant_page
    relay_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile relay gateway assistant mode
      ui_surface: assistant_page
    file_attachments:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile file attachment action in assistant composer
      ui_surface: assistant_page
    multi_agent:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile multi-agent toggle in assistant composer
      ui_surface: assistant_page
    local_runtime:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Mobile does not expose desktop runtime controls
      ui_surface: assistant_page
  settings:
    general:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings general tab
      ui_surface: settings_page
    workspace:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings workspace tab
      ui_surface: settings_page
    gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings gateway tab
      ui_surface: settings_page
    vault_server:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile Vault server integration section
      ui_surface: settings_page
    gateway_setup_code:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile gateway setup code editor
      ui_surface: settings_page
    agents:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile settings multi-agent tab
      ui_surface: settings_page
    appearance:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings appearance tab
      ui_surface: settings_page
    diagnostics:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings diagnostics tab
      ui_surface: settings_page
    experimental:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile settings experimental tab
      ui_surface: settings_page
    about:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings about tab
      ui_surface: settings_page
    experimental_canvas:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile experimental canvas host toggle
      ui_surface: settings_page
    experimental_bridge:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile experimental bridge toggle
      ui_surface: settings_page
    experimental_debug:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile experimental debug runtime toggle
      ui_surface: settings_page

desktop:
  navigation:
    assistant:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop assistant destination
      ui_surface: sidebar_navigation
    tasks:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop tasks destination
      ui_surface: sidebar_navigation
    skills:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop skills destination
      ui_surface: sidebar_navigation
    nodes:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop nodes destination
      ui_surface: sidebar_navigation
    agents:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop agents destination
      ui_surface: sidebar_navigation
    mcp_server:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop MCP Hub destination
      ui_surface: sidebar_navigation
    claw_hub:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop ClawHub destination
      ui_surface: sidebar_navigation
    secrets:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop secrets destination
      ui_surface: sidebar_navigation
    ai_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop AI Gateway destination
      ui_surface: sidebar_navigation
    settings:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings destination
      ui_surface: sidebar_navigation
    account:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop account destination
      ui_surface: sidebar_navigation
  assistant:
    direct_ai:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop direct AI assistant mode
      ui_surface: assistant_page
    local_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop local gateway assistant mode
      ui_surface: assistant_page
    relay_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop relay gateway assistant mode
      ui_surface: assistant_page
    file_attachments:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop file attachment action in assistant composer
      ui_surface: assistant_page
    multi_agent:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop multi-agent toggle in assistant composer
      ui_surface: assistant_page
    local_runtime:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop local runtime and gateway orchestration entry
      ui_surface: assistant_page
  settings:
    general:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings general tab
      ui_surface: settings_page
    workspace:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings workspace tab
      ui_surface: settings_page
    gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings gateway tab
      ui_surface: settings_page
    vault_server:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop Vault server integration section
      ui_surface: settings_page
    gateway_setup_code:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop gateway setup code editor
      ui_surface: settings_page
    agents:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop settings multi-agent tab
      ui_surface: settings_page
    appearance:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings appearance tab
      ui_surface: settings_page
    diagnostics:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings diagnostics tab
      ui_surface: settings_page
    experimental:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop settings experimental tab
      ui_surface: settings_page
    about:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings about tab
      ui_surface: settings_page
    experimental_canvas:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop experimental canvas host toggle
      ui_surface: settings_page
    experimental_bridge:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop experimental bridge toggle
      ui_surface: settings_page
    experimental_debug:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop experimental debug runtime toggle
      ui_surface: settings_page

web:
  navigation:
    assistant:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web assistant destination
      ui_surface: web_shell
    settings:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web settings destination
      ui_surface: web_shell
  assistant:
    direct_ai:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web direct AI assistant mode
      ui_surface: web_assistant_page
    relay_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web relay gateway assistant mode
      ui_surface: web_assistant_page
    file_attachments:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Web does not expose file attachments in assistant composer
      ui_surface: web_assistant_page
    multi_agent:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Web does not expose multi-agent assistant toggle
      ui_surface: web_assistant_page
    local_gateway:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Web does not expose local gateway assistant mode
      ui_surface: web_assistant_page
    local_runtime:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Web does not expose desktop runtime controls
      ui_surface: web_assistant_page
  settings:
    general:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web settings general tab
      ui_surface: web_settings_page
    gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web settings gateway tab
      ui_surface: web_settings_page
    vault_server:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Web does not expose vault server integration
      ui_surface: web_settings_page
    gateway_setup_code:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Web does not expose gateway setup code editor
      ui_surface: web_settings_page
    appearance:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web settings appearance tab
      ui_surface: web_settings_page
    about:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web settings about tab
      ui_surface: web_settings_page
''';

  final Map<UiFeatureBuildMode, Set<UiFeatureReleaseTier>> releasePolicy;
  final Map<UiFeaturePlatform, Map<String, Map<String, UiFeatureFlag>>>
  _flagsByPlatform;

  factory UiFeatureManifest.fromYamlString(String raw) {
    final root = loadYaml(raw);
    if (root is! YamlMap) {
      throw const FormatException('Feature manifest root must be a YAML map.');
    }
    final releasePolicy = _parseReleasePolicy(root['release_policy']);
    final flagsByPlatform =
        <UiFeaturePlatform, Map<String, Map<String, UiFeatureFlag>>>{};
    for (final platform in UiFeaturePlatform.values) {
      flagsByPlatform[platform] = _parsePlatformModules(
        platform: platform,
        raw: root[platform.name],
      );
    }
    return UiFeatureManifest._(
      releasePolicy: releasePolicy,
      flagsByPlatform: flagsByPlatform,
    );
  }

  factory UiFeatureManifest.fallback() {
    return UiFeatureManifest.fromYamlString(fallbackYaml);
  }

  UiFeatureAccess forPlatform(
    UiFeaturePlatform platform, {
    UiFeatureBuildMode? buildMode,
  }) {
    return UiFeatureAccess._(
      manifest: this,
      platform: platform,
      buildMode: buildMode ?? currentUiFeatureBuildMode(),
    );
  }

  UiFeatureFlag? lookup(
    UiFeaturePlatform platform,
    String module,
    String feature,
  ) {
    return _flagsByPlatform[platform]?[module]?[feature];
  }

  UiFeatureManifest copyWithFeature({
    required UiFeaturePlatform platform,
    required String module,
    required String feature,
    bool? enabled,
    UiFeatureReleaseTier? releaseTier,
    Set<UiFeatureBuildMode>? buildModes,
    String? description,
    String? uiSurface,
  }) {
    final current = lookup(platform, module, feature);
    if (current == null) {
      throw StateError('Unknown feature: ${platform.name}.$module.$feature');
    }
    final updated = current.copyWith(
      enabled: enabled,
      releaseTier: releaseTier,
      buildModes: buildModes,
      description: description,
      uiSurface: uiSurface,
    );
    final nextPlatforms =
        <UiFeaturePlatform, Map<String, Map<String, UiFeatureFlag>>>{};
    for (final entry in _flagsByPlatform.entries) {
      nextPlatforms[entry.key] = entry.value.map(
        (moduleName, features) => MapEntry(
          moduleName,
          features.map((featureName, flag) => MapEntry(featureName, flag)),
        ),
      );
    }
    nextPlatforms[platform]![module]![feature] = updated;
    return UiFeatureManifest._(
      releasePolicy: releasePolicy,
      flagsByPlatform: nextPlatforms,
    );
  }

  static Map<UiFeatureBuildMode, Set<UiFeatureReleaseTier>> _parseReleasePolicy(
    Object? raw,
  ) {
    if (raw is! YamlMap) {
      throw const FormatException(
        'release_policy must define debug/profile/release tiers.',
      );
    }
    final policy = <UiFeatureBuildMode, Set<UiFeatureReleaseTier>>{};
    for (final mode in UiFeatureBuildMode.values) {
      final rawValue = raw[mode.name];
      if (rawValue is! YamlList) {
        throw FormatException(
          'release_policy.${mode.name} must be a list of tiers.',
        );
      }
      policy[mode] = rawValue
          .map((value) => _parseReleaseTier(value, context: mode.name))
          .toSet();
    }
    return policy;
  }

  static Map<String, Map<String, UiFeatureFlag>> _parsePlatformModules({
    required UiFeaturePlatform platform,
    required Object? raw,
  }) {
    if (raw is! YamlMap) {
      throw FormatException('${platform.name} must be a YAML map.');
    }
    final modules = <String, Map<String, UiFeatureFlag>>{};
    for (final entry in raw.entries) {
      final moduleName = '${entry.key}'.trim();
      if (moduleName.isEmpty) {
        throw FormatException('${platform.name} contains an empty module key.');
      }
      final rawModule = entry.value;
      if (rawModule is! YamlMap) {
        throw FormatException('${platform.name}.$moduleName must be a map.');
      }
      final features = <String, UiFeatureFlag>{};
      for (final featureEntry in rawModule.entries) {
        final featureName = '${featureEntry.key}'.trim();
        if (featureName.isEmpty) {
          throw FormatException(
            '${platform.name}.$moduleName contains an empty feature key.',
          );
        }
        features[featureName] = _parseFeatureFlag(
          platform: platform,
          moduleName: moduleName,
          featureName: featureName,
          raw: featureEntry.value,
        );
      }
      modules[moduleName] = features;
    }
    return modules;
  }

  static UiFeatureFlag _parseFeatureFlag({
    required UiFeaturePlatform platform,
    required String moduleName,
    required String featureName,
    required Object? raw,
  }) {
    if (raw is! YamlMap) {
      throw FormatException(
        '${platform.name}.$moduleName.$featureName must be a map.',
      );
    }
    const allowedKeys = <String>{
      'enabled',
      'release_tier',
      'build_modes',
      'description',
      'ui_surface',
    };
    for (final key in raw.keys) {
      final name = '$key';
      if (!allowedKeys.contains(name)) {
        throw FormatException(
          'Unsupported key "$name" in '
          '${platform.name}.$moduleName.$featureName.',
        );
      }
    }
    final enabled = raw['enabled'];
    final releaseTier = raw['release_tier'];
    final buildModes = raw['build_modes'];
    final description = raw['description'];
    final uiSurface = raw['ui_surface'];
    if (enabled is! bool) {
      throw FormatException(
        '${platform.name}.$moduleName.$featureName.enabled must be bool.',
      );
    }
    if (buildModes is! YamlList) {
      throw FormatException(
        '${platform.name}.$moduleName.$featureName.build_modes must be a list.',
      );
    }
    if (description is! String || description.trim().isEmpty) {
      throw FormatException(
        '${platform.name}.$moduleName.$featureName.description is required.',
      );
    }
    if (uiSurface is! String || uiSurface.trim().isEmpty) {
      throw FormatException(
        '${platform.name}.$moduleName.$featureName.ui_surface is required.',
      );
    }
    return UiFeatureFlag(
      enabled: enabled,
      releaseTier: _parseReleaseTier(
        releaseTier,
        context: '${platform.name}.$moduleName.$featureName',
      ),
      buildModes: buildModes
          .map(
            (value) => _parseBuildMode(
              value,
              context: '${platform.name}.$moduleName.$featureName',
            ),
          )
          .toSet(),
      description: description.trim(),
      uiSurface: uiSurface.trim(),
    );
  }

  static UiFeatureReleaseTier _parseReleaseTier(
    Object? raw, {
    required String context,
  }) {
    final value = '$raw'.trim();
    return UiFeatureReleaseTier.values.firstWhere(
      (item) => item.name == value,
      orElse: () {
        throw FormatException('Unknown release tier "$value" at $context.');
      },
    );
  }

  static UiFeatureBuildMode _parseBuildMode(
    Object? raw, {
    required String context,
  }) {
    final value = '$raw'.trim();
    return UiFeatureBuildMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () {
        throw FormatException('Unknown build mode "$value" at $context.');
      },
    );
  }
}

class UiFeatureAccess {
  UiFeatureAccess._({
    required UiFeatureManifest manifest,
    required this.platform,
    required this.buildMode,
  }) : _manifest = manifest;

  final UiFeatureManifest _manifest;
  final UiFeaturePlatform platform;
  final UiFeatureBuildMode buildMode;

  static const Map<UiFeaturePlatform, Map<String, WorkspaceDestination>>
  _destinationMappings = <UiFeaturePlatform, Map<String, WorkspaceDestination>>{
    UiFeaturePlatform.mobile: <String, WorkspaceDestination>{
      UiFeatureKeys.navigationAssistant: WorkspaceDestination.assistant,
      UiFeatureKeys.navigationTasks: WorkspaceDestination.tasks,
      UiFeatureKeys.navigationSecrets: WorkspaceDestination.secrets,
      UiFeatureKeys.navigationSettings: WorkspaceDestination.settings,
      UiFeatureKeys.workspaceSkills: WorkspaceDestination.skills,
      UiFeatureKeys.workspaceNodes: WorkspaceDestination.nodes,
      UiFeatureKeys.workspaceAgents: WorkspaceDestination.agents,
      UiFeatureKeys.workspaceMcpServer: WorkspaceDestination.mcpServer,
      UiFeatureKeys.workspaceClawHub: WorkspaceDestination.clawHub,
      UiFeatureKeys.workspaceAiGateway: WorkspaceDestination.aiGateway,
      UiFeatureKeys.workspaceAccount: WorkspaceDestination.account,
    },
    UiFeaturePlatform.desktop: <String, WorkspaceDestination>{
      UiFeatureKeys.navigationAssistant: WorkspaceDestination.assistant,
      UiFeatureKeys.navigationTasks: WorkspaceDestination.tasks,
      UiFeatureKeys.navigationSkills: WorkspaceDestination.skills,
      UiFeatureKeys.navigationNodes: WorkspaceDestination.nodes,
      UiFeatureKeys.navigationAgents: WorkspaceDestination.agents,
      UiFeatureKeys.navigationMcpServer: WorkspaceDestination.mcpServer,
      UiFeatureKeys.navigationClawHub: WorkspaceDestination.clawHub,
      UiFeatureKeys.navigationSecrets: WorkspaceDestination.secrets,
      UiFeatureKeys.navigationAiGateway: WorkspaceDestination.aiGateway,
      UiFeatureKeys.navigationSettings: WorkspaceDestination.settings,
      UiFeatureKeys.navigationAccount: WorkspaceDestination.account,
    },
    UiFeaturePlatform.web: <String, WorkspaceDestination>{
      UiFeatureKeys.navigationAssistant: WorkspaceDestination.assistant,
      UiFeatureKeys.navigationSettings: WorkspaceDestination.settings,
    },
  };

  static const Map<String, SettingsTab> _settingsTabMappings =
      <String, SettingsTab>{
        UiFeatureKeys.settingsGeneral: SettingsTab.general,
        UiFeatureKeys.settingsWorkspace: SettingsTab.workspace,
        UiFeatureKeys.settingsGateway: SettingsTab.gateway,
        UiFeatureKeys.settingsAgents: SettingsTab.agents,
        UiFeatureKeys.settingsAppearance: SettingsTab.appearance,
        UiFeatureKeys.settingsDiagnostics: SettingsTab.diagnostics,
        UiFeatureKeys.settingsExperimental: SettingsTab.experimental,
        UiFeatureKeys.settingsAbout: SettingsTab.about,
      };

  bool isEnabledPath(String path) {
    final parts = path.split('.');
    if (parts.length != 2) {
      throw ArgumentError.value(path, 'path', 'Expected module.feature');
    }
    return isEnabled(parts[0], parts[1]);
  }

  bool isEnabled(String module, String feature) {
    final flag = _manifest.lookup(platform, module, feature);
    if (flag == null || !flag.enabled) {
      return false;
    }
    if (!flag.buildModes.contains(buildMode)) {
      return false;
    }
    final allowedTiers = _manifest.releasePolicy[buildMode] ?? const {};
    return allowedTiers.contains(flag.releaseTier);
  }

  Set<WorkspaceDestination> get allowedDestinations {
    final mappings = _destinationMappings[platform] ?? const {};
    final allowed = <WorkspaceDestination>{};
    for (final entry in mappings.entries) {
      if (isEnabledPath(entry.key)) {
        allowed.add(entry.value);
      }
    }
    return allowed;
  }

  bool get showsWorkspaceHub =>
      platform == UiFeaturePlatform.mobile &&
      isEnabledPath(UiFeatureKeys.navigationWorkspace);

  bool get supportsDirectAi => isEnabledPath(UiFeatureKeys.assistantDirectAi);

  bool get supportsLocalGateway =>
      isEnabledPath(UiFeatureKeys.assistantLocalGateway);

  bool get supportsRelayGateway =>
      isEnabledPath(UiFeatureKeys.assistantRelayGateway);

  bool get supportsFileAttachments =>
      isEnabledPath(UiFeatureKeys.assistantFileAttachments);

  bool get supportsMultiAgent =>
      isEnabledPath(UiFeatureKeys.assistantMultiAgent);

  bool get supportsDesktopRuntime =>
      platform == UiFeaturePlatform.desktop &&
      isEnabledPath(UiFeatureKeys.assistantLocalRuntime);

  bool get supportsDiagnostics =>
      isEnabledPath(UiFeatureKeys.settingsDiagnostics);

  bool get supportsGatewaySetupCode =>
      isEnabledPath(UiFeatureKeys.settingsGatewaySetupCode);

  bool get supportsVaultServer =>
      isEnabledPath(UiFeatureKeys.settingsVaultServer);

  List<SettingsTab> get availableSettingsTabs {
    return SettingsTab.values
        .where(
          (tab) => _settingsTabMappings.entries.any(
            (entry) => entry.value == tab && isEnabledPath(entry.key),
          ),
        )
        .toList(growable: false);
  }

  SettingsTab sanitizeSettingsTab(SettingsTab tab) {
    final available = availableSettingsTabs;
    if (available.contains(tab)) {
      return tab;
    }
    if (available.isNotEmpty) {
      return available.first;
    }
    return SettingsTab.general;
  }

  bool allowsExperimentalSetting(String keyPath) {
    return isEnabledPath(keyPath);
  }

  List<AssistantExecutionTarget> get availableExecutionTargets {
    final targets = <AssistantExecutionTarget>[];
    if (supportsDirectAi) {
      targets.add(AssistantExecutionTarget.singleAgent);
    }
    if (supportsLocalGateway) {
      targets.add(AssistantExecutionTarget.local);
    }
    if (supportsRelayGateway) {
      targets.add(AssistantExecutionTarget.remote);
    }
    return targets;
  }

  AssistantExecutionTarget sanitizeExecutionTarget(
    AssistantExecutionTarget? target,
  ) {
    final available = availableExecutionTargets;
    if (target != null && available.contains(target)) {
      return target;
    }
    final preferredOrder = platform == UiFeaturePlatform.web
        ? const <AssistantExecutionTarget>[
            AssistantExecutionTarget.singleAgent,
            AssistantExecutionTarget.remote,
          ]
        : const <AssistantExecutionTarget>[
            AssistantExecutionTarget.local,
            AssistantExecutionTarget.singleAgent,
            AssistantExecutionTarget.remote,
          ];
    for (final candidate in preferredOrder) {
      if (available.contains(candidate)) {
        return candidate;
      }
    }
    return platform == UiFeaturePlatform.web
        ? AssistantExecutionTarget.singleAgent
        : AssistantExecutionTarget.local;
  }
}

class UiFeatureManifestLoader {
  const UiFeatureManifestLoader._();

  static Future<UiFeatureManifest> load({
    AssetBundle? assetBundle,
    String assetPath = UiFeatureManifest.assetPath,
  }) async {
    final bundle = assetBundle ?? rootBundle;
    try {
      final raw = await bundle.loadString(assetPath);
      return UiFeatureManifest.fromYamlString(raw);
    } catch (_) {
      return UiFeatureManifest.fallback();
    }
  }
}
