// ignore_for_file: unused_import, unnecessary_import

import 'dart:convert';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import 'runtime_models_connection.dart';
import 'runtime_models_configs.dart';
import 'runtime_models_settings_snapshot.dart';
import 'runtime_models_runtime_payloads.dart';
import 'runtime_models_gateway_entities.dart';
import 'runtime_models_multi_agent.dart';

class ExternalAcpEndpointProfile {
  const ExternalAcpEndpointProfile({
    required this.providerKey,
    required this.label,
    required this.badge,
    required this.endpoint,
    required this.authRef,
    required this.enabled,
  });

  final String providerKey;
  final String label;
  final String badge;
  final String endpoint;
  final String authRef;
  final bool enabled;

  factory ExternalAcpEndpointProfile.defaultsForProvider(
    SingleAgentProvider provider,
  ) {
    return ExternalAcpEndpointProfile(
      providerKey: provider.providerId,
      label: provider.label,
      badge: provider.badge,
      endpoint: '',
      authRef: '',
      enabled: true,
    );
  }

  ExternalAcpEndpointProfile copyWith({
    String? providerKey,
    String? label,
    String? badge,
    String? endpoint,
    String? authRef,
    bool? enabled,
  }) {
    return ExternalAcpEndpointProfile(
      providerKey: normalizeSingleAgentProviderId(
        providerKey ?? this.providerKey,
      ),
      label: (label ?? this.label).trim(),
      badge: (badge ?? this.badge).trim(),
      endpoint: (endpoint ?? this.endpoint).trim(),
      authRef: (authRef ?? this.authRef).trim(),
      enabled: enabled ?? this.enabled,
    );
  }

  SingleAgentProvider? get builtinProvider {
    final normalized = providerKey.trim().toLowerCase();
    for (final provider in kPresetExternalAcpProviders) {
      if (provider.providerId == normalized) {
        return provider;
      }
    }
    return null;
  }

  bool get isPreset =>
      kPresetExternalAcpProviders.any((item) => item.providerId == providerKey);

  SingleAgentProvider toProvider() {
    final builtin = builtinProvider;
    return SingleAgentProvider.fromJsonValue(
      providerKey,
      label: label,
      badge: badge,
    ).copyWith(
      source: builtin?.source ?? SingleAgentProviderSource.externalExtension,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'providerKey': providerKey,
      'label': label,
      'badge': badge,
      'endpoint': endpoint,
      'authRef': authRef,
      'enabled': enabled,
    };
  }

  factory ExternalAcpEndpointProfile.fromJson(Map<String, dynamic> json) {
    final providerKey = normalizeSingleAgentProviderId(
      json['providerKey']?.toString() ?? '',
    );
    final builtin = SingleAgentProviderCopy.fromJsonValue(providerKey);
    final fallbackLabel = builtin.isUnspecified ? providerKey : builtin.label;
    final label = json['label']?.toString().trim().isNotEmpty == true
        ? json['label'].toString().trim()
        : fallbackLabel;
    return ExternalAcpEndpointProfile(
      providerKey: providerKey,
      label: label,
      badge: json['badge']?.toString().trim().isNotEmpty == true
          ? json['badge'].toString().trim()
          : singleAgentProviderFallbackBadgeInternal(
              providerId: providerKey,
              label: label,
            ),
      endpoint: json['endpoint']?.toString().trim() ?? '',
      authRef: json['authRef']?.toString().trim() ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

List<ExternalAcpEndpointProfile> normalizeExternalAcpEndpoints({
  Iterable<ExternalAcpEndpointProfile>? profiles,
}) {
  final incoming =
      profiles?.toList(growable: false) ?? const <ExternalAcpEndpointProfile>[];
  final byKey = <String, ExternalAcpEndpointProfile>{};

  SingleAgentProvider? canonicalProviderForProfile(
    ExternalAcpEndpointProfile profile,
  ) {
    final key = profile.providerKey.trim().toLowerCase();
    for (final provider in kPresetExternalAcpProviders) {
      if (provider.providerId == key) {
        return provider;
      }
    }
    final label = profile.label.trim();
    final badge = profile.badge.trim();
    for (final provider in kPresetExternalAcpProviders) {
      if (provider.label == label && provider.badge == badge) {
        return provider;
      }
    }
    return null;
  }

  for (final item in incoming) {
    final originalKey = item.providerKey.trim().toLowerCase();
    final canonicalProvider = canonicalProviderForProfile(item);
    final key = canonicalProvider?.providerId ?? originalKey;
    if (key.isEmpty) {
      continue;
    }
    if (!isBridgeOwnedSingleAgentProviderId(originalKey) &&
        item.endpoint.trim().isEmpty) {
      continue;
    }
    final normalizedItem = item.copyWith(
      providerKey: key,
      label: canonicalProvider?.label ?? item.label,
      badge: canonicalProvider?.badge ?? item.badge,
    );
    final existing = byKey[key];
    if (existing == null ||
        (existing.endpoint.trim().isEmpty &&
            normalizedItem.endpoint.trim().isNotEmpty)) {
      byKey[key] = normalizedItem;
    }
  }

  final normalized = <ExternalAcpEndpointProfile>[
    for (final provider in kPresetExternalAcpProviders)
      byKey.remove(provider.providerId) ??
          ExternalAcpEndpointProfile.defaultsForProvider(provider),
    ...byKey.values,
  ];
  return List<ExternalAcpEndpointProfile>.unmodifiable(normalized);
}

List<ExternalAcpEndpointProfile> replaceExternalAcpEndpointForProvider(
  List<ExternalAcpEndpointProfile> profiles,
  SingleAgentProvider provider,
  ExternalAcpEndpointProfile profile,
) {
  final normalized = normalizeExternalAcpEndpoints(profiles: profiles);
  final next = List<ExternalAcpEndpointProfile>.from(normalized);
  final index = next.indexWhere(
    (item) => item.providerKey.trim().toLowerCase() == provider.providerId,
  );
  final resolved = profile.copyWith(
    providerKey: provider.providerId,
    label: profile.label.trim().isEmpty ? provider.label : profile.label,
    badge: profile.badge.trim().isEmpty ? provider.badge : profile.badge,
  );
  if (index == -1) {
    next.add(resolved);
  } else {
    next[index] = resolved;
  }
  return normalizeExternalAcpEndpoints(profiles: next);
}

ExternalAcpEndpointProfile buildCustomExternalAcpEndpointProfile(
  Iterable<ExternalAcpEndpointProfile> profiles, {
  required String label,
  required String endpoint,
}) {
  final normalizedProfiles = normalizeExternalAcpEndpoints(profiles: profiles);
  var suffix = normalizedProfiles.length + 1;

  String providerKey() => 'custom-agent-$suffix';

  final existingKeys = normalizedProfiles
      .map((item) => item.providerKey)
      .toSet();
  while (existingKeys.contains(providerKey())) {
    suffix += 1;
  }

  final normalizedLabel = label.trim().isEmpty
      ? 'Custom ACP Endpoint $suffix'
      : label.trim();
  return ExternalAcpEndpointProfile(
    providerKey: providerKey(),
    label: normalizedLabel,
    badge: singleAgentProviderFallbackBadgeInternal(
      providerId: providerKey(),
      label: normalizedLabel,
    ),
    endpoint: endpoint.trim(),
    authRef: '',
    enabled: true,
  );
}

String normalizeAuthorizedSkillDirectoryPath(String path) {
  var trimmed = path.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  trimmed = trimmed.replaceFirst(RegExp(r'[\\/]+$'), '');
  trimmed = trimmed.replaceFirst(
    RegExp(r'([\\/])SKILL\.md$', caseSensitive: false),
    '',
  );
  if (trimmed.length <= 1) {
    return trimmed;
  }
  return trimmed.replaceFirst(RegExp(r'[\\/]+$'), '');
}

class AuthorizedSkillDirectory {
  const AuthorizedSkillDirectory({required this.path, this.bookmark = ''});

  final String path;
  final String bookmark;

  AuthorizedSkillDirectory copyWith({String? path, String? bookmark}) {
    return AuthorizedSkillDirectory(
      path: normalizeAuthorizedSkillDirectoryPath(path ?? this.path),
      bookmark: bookmark ?? this.bookmark,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'path': path,
      if (bookmark.trim().isNotEmpty) 'bookmark': bookmark,
    };
  }

  factory AuthorizedSkillDirectory.fromJson(Map<String, dynamic> json) {
    return AuthorizedSkillDirectory(
      path: normalizeAuthorizedSkillDirectoryPath(
        json['path']?.toString() ?? '',
      ),
      bookmark: json['bookmark']?.toString().trim() ?? '',
    );
  }
}

List<AuthorizedSkillDirectory> normalizeAuthorizedSkillDirectories({
  Iterable<AuthorizedSkillDirectory>? directories,
}) {
  final incoming =
      directories?.toList(growable: false) ??
      const <AuthorizedSkillDirectory>[];
  final normalized = <AuthorizedSkillDirectory>[];
  final seen = <String>{};
  for (final item in incoming) {
    final path = normalizeAuthorizedSkillDirectoryPath(item.path);
    if (path.isEmpty || !seen.add(path)) {
      continue;
    }
    normalized.add(
      AuthorizedSkillDirectory(path: path, bookmark: item.bookmark.trim()),
    );
  }
  normalized.sort((left, right) => left.path.compareTo(right.path));
  return List<AuthorizedSkillDirectory>.unmodifiable(normalized);
}

class AssistantThreadConnectionState {
  const AssistantThreadConnectionState({
    required this.executionTarget,
    required this.status,
    required this.primaryLabel,
    required this.detailLabel,
    required this.ready,
    required this.pairingRequired,
    required this.gatewayTokenMissing,
    required this.lastError,
  });

  final AssistantExecutionTarget executionTarget;
  final RuntimeConnectionStatus status;
  final String primaryLabel;
  final String detailLabel;
  final bool ready;
  final bool pairingRequired;
  final bool gatewayTokenMissing;
  final String? lastError;

  bool get isSingleAgent => false;

  bool get connected => ready;

  bool get connecting =>
      !isSingleAgent && status == RuntimeConnectionStatus.connecting;
}

enum AssistantMessageViewMode { rendered, raw }

extension AssistantMessageViewModeCopy on AssistantMessageViewMode {
  String get label => switch (this) {
    AssistantMessageViewMode.rendered => appText('渲染', 'Rendered'),
    AssistantMessageViewMode.raw => 'RAW',
  };

  static AssistantMessageViewMode fromJsonValue(String? value) {
    return AssistantMessageViewMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AssistantMessageViewMode.rendered,
    );
  }
}

enum WorkspaceRefKind { localPath, remotePath, objectStore }

extension WorkspaceRefKindCopy on WorkspaceRefKind {
  static WorkspaceRefKind fromJsonValue(String? value) {
    return WorkspaceRefKind.values.firstWhere(
      (item) => item.name == value,
      orElse: () => WorkspaceRefKind.localPath,
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

enum CodeAgentRuntimeMode { builtIn, externalCli }

extension CodeAgentRuntimeModeCopy on CodeAgentRuntimeMode {
  String get label => switch (this) {
    CodeAgentRuntimeMode.externalCli => appText(
      '外部 Codex CLI',
      'External Codex CLI',
    ),
    CodeAgentRuntimeMode.builtIn => appText('内置 Codex', 'Built-in Codex'),
  };

  static CodeAgentRuntimeMode fromJsonValue(String? value) {
    return CodeAgentRuntimeMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => CodeAgentRuntimeMode.externalCli,
    );
  }
}

enum VpnMode { tunnel, proxy }

extension VpnModeCopy on VpnMode {
  String get label => switch (this) {
    VpnMode.tunnel => appText('隧道', 'Tunnel'),
    VpnMode.proxy => appText('代理', 'Proxy'),
  };

  static VpnMode fromJsonValue(String? value) {
    return VpnMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => VpnMode.proxy,
    );
  }
}

enum DesktopEnvironment { unknown, gnome, kde }

extension DesktopEnvironmentCopy on DesktopEnvironment {
  String get label => switch (this) {
    DesktopEnvironment.unknown => appText('未知桌面', 'Unknown Desktop'),
    DesktopEnvironment.gnome => 'GNOME',
    DesktopEnvironment.kde => 'KDE Plasma',
  };

  static DesktopEnvironment fromJsonValue(String? value) {
    return DesktopEnvironment.values.firstWhere(
      (item) => item.name == value,
      orElse: () => DesktopEnvironment.unknown,
    );
  }
}

class LinuxDesktopConfig {
  const LinuxDesktopConfig({
    required this.preferredMode,
    required this.vpnConnectionName,
    required this.proxyHost,
    required this.proxyPort,
    required this.trayEnabled,
  });

  final VpnMode preferredMode;
  final String vpnConnectionName;
  final String proxyHost;
  final int proxyPort;
  final bool trayEnabled;

  factory LinuxDesktopConfig.defaults() {
    return const LinuxDesktopConfig(
      preferredMode: VpnMode.proxy,
      vpnConnectionName: 'XWorkmate Tunnel',
      proxyHost: '127.0.0.1',
      proxyPort: 7890,
      trayEnabled: true,
    );
  }

  LinuxDesktopConfig copyWith({
    VpnMode? preferredMode,
    String? vpnConnectionName,
    String? proxyHost,
    int? proxyPort,
    bool? trayEnabled,
  }) {
    return LinuxDesktopConfig(
      preferredMode: preferredMode ?? this.preferredMode,
      vpnConnectionName: vpnConnectionName ?? this.vpnConnectionName,
      proxyHost: proxyHost ?? this.proxyHost,
      proxyPort: proxyPort ?? this.proxyPort,
      trayEnabled: trayEnabled ?? this.trayEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'preferredMode': preferredMode.name,
      'vpnConnectionName': vpnConnectionName,
      'proxyHost': proxyHost,
      'proxyPort': proxyPort,
      'trayEnabled': trayEnabled,
    };
  }

  factory LinuxDesktopConfig.fromJson(Map<String, dynamic> json) {
    final defaults = LinuxDesktopConfig.defaults();
    return LinuxDesktopConfig(
      preferredMode: VpnModeCopy.fromJsonValue(
        json['preferredMode'] as String?,
      ),
      vpnConnectionName:
          json['vpnConnectionName'] as String? ?? defaults.vpnConnectionName,
      proxyHost: json['proxyHost'] as String? ?? defaults.proxyHost,
      proxyPort: json['proxyPort'] as int? ?? defaults.proxyPort,
      trayEnabled: json['trayEnabled'] as bool? ?? defaults.trayEnabled,
    );
  }
}

class SystemProxyState {
  const SystemProxyState({
    required this.enabled,
    required this.host,
    required this.port,
    required this.backend,
    required this.lastAppliedMode,
  });

  final bool enabled;
  final String host;
  final int port;
  final String backend;
  final VpnMode lastAppliedMode;

  factory SystemProxyState.defaults({LinuxDesktopConfig? config}) {
    final resolvedConfig = config ?? LinuxDesktopConfig.defaults();
    return SystemProxyState(
      enabled: resolvedConfig.preferredMode == VpnMode.proxy,
      host: resolvedConfig.proxyHost,
      port: resolvedConfig.proxyPort,
      backend: '',
      lastAppliedMode: resolvedConfig.preferredMode,
    );
  }

  SystemProxyState copyWith({
    bool? enabled,
    String? host,
    int? port,
    String? backend,
    VpnMode? lastAppliedMode,
  }) {
    return SystemProxyState(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      port: port ?? this.port,
      backend: backend ?? this.backend,
      lastAppliedMode: lastAppliedMode ?? this.lastAppliedMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'host': host,
      'port': port,
      'backend': backend,
      'lastAppliedMode': lastAppliedMode.name,
    };
  }

  factory SystemProxyState.fromJson(
    Map<String, dynamic> json, {
    LinuxDesktopConfig? config,
  }) {
    final defaults = SystemProxyState.defaults(config: config);
    return SystemProxyState(
      enabled: json['enabled'] as bool? ?? defaults.enabled,
      host: json['host'] as String? ?? defaults.host,
      port: json['port'] as int? ?? defaults.port,
      backend: json['backend'] as String? ?? defaults.backend,
      lastAppliedMode: VpnModeCopy.fromJsonValue(
        json['lastAppliedMode'] as String?,
      ),
    );
  }
}

class TunnelSessionState {
  const TunnelSessionState({
    required this.available,
    required this.connected,
    required this.connectionName,
    required this.backend,
    required this.lastError,
  });

  final bool available;
  final bool connected;
  final String connectionName;
  final String backend;
  final String lastError;

  factory TunnelSessionState.defaults({LinuxDesktopConfig? config}) {
    final resolvedConfig = config ?? LinuxDesktopConfig.defaults();
    return TunnelSessionState(
      available: false,
      connected: false,
      connectionName: resolvedConfig.vpnConnectionName,
      backend: '',
      lastError: '',
    );
  }

  TunnelSessionState copyWith({
    bool? available,
    bool? connected,
    String? connectionName,
    String? backend,
    String? lastError,
  }) {
    return TunnelSessionState(
      available: available ?? this.available,
      connected: connected ?? this.connected,
      connectionName: connectionName ?? this.connectionName,
      backend: backend ?? this.backend,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'available': available,
      'connected': connected,
      'connectionName': connectionName,
      'backend': backend,
      'lastError': lastError,
    };
  }

  factory TunnelSessionState.fromJson(
    Map<String, dynamic> json, {
    LinuxDesktopConfig? config,
  }) {
    final defaults = TunnelSessionState.defaults(config: config);
    return TunnelSessionState(
      available: json['available'] as bool? ?? defaults.available,
      connected: json['connected'] as bool? ?? defaults.connected,
      connectionName:
          json['connectionName'] as String? ?? defaults.connectionName,
      backend: json['backend'] as String? ?? defaults.backend,
      lastError: json['lastError'] as String? ?? defaults.lastError,
    );
  }
}

class DesktopIntegrationState {
  const DesktopIntegrationState({
    required this.isSupported,
    required this.environment,
    required this.mode,
    required this.trayAvailable,
    required this.trayEnabled,
    required this.autostartEnabled,
    required this.networkManagerAvailable,
    required this.systemProxy,
    required this.tunnel,
    required this.statusMessage,
  });

  final bool isSupported;
  final DesktopEnvironment environment;
  final VpnMode mode;
  final bool trayAvailable;
  final bool trayEnabled;
  final bool autostartEnabled;
  final bool networkManagerAvailable;
  final SystemProxyState systemProxy;
  final TunnelSessionState tunnel;
  final String statusMessage;

  factory DesktopIntegrationState.loading() {
    final config = LinuxDesktopConfig.defaults();
    return DesktopIntegrationState(
      isSupported: true,
      environment: DesktopEnvironment.unknown,
      mode: config.preferredMode,
      trayAvailable: false,
      trayEnabled: config.trayEnabled,
      autostartEnabled: false,
      networkManagerAvailable: false,
      systemProxy: SystemProxyState.defaults(config: config),
      tunnel: TunnelSessionState.defaults(config: config),
      statusMessage: '',
    );
  }

  factory DesktopIntegrationState.unsupported({
    LinuxDesktopConfig? config,
    String message = '',
  }) {
    final resolvedConfig = config ?? LinuxDesktopConfig.defaults();
    return DesktopIntegrationState(
      isSupported: false,
      environment: DesktopEnvironment.unknown,
      mode: resolvedConfig.preferredMode,
      trayAvailable: false,
      trayEnabled: false,
      autostartEnabled: false,
      networkManagerAvailable: false,
      systemProxy: SystemProxyState.defaults(config: resolvedConfig),
      tunnel: TunnelSessionState.defaults(config: resolvedConfig),
      statusMessage: message,
    );
  }

  DesktopIntegrationState copyWith({
    bool? isSupported,
    DesktopEnvironment? environment,
    VpnMode? mode,
    bool? trayAvailable,
    bool? trayEnabled,
    bool? autostartEnabled,
    bool? networkManagerAvailable,
    SystemProxyState? systemProxy,
    TunnelSessionState? tunnel,
    String? statusMessage,
  }) {
    return DesktopIntegrationState(
      isSupported: isSupported ?? this.isSupported,
      environment: environment ?? this.environment,
      mode: mode ?? this.mode,
      trayAvailable: trayAvailable ?? this.trayAvailable,
      trayEnabled: trayEnabled ?? this.trayEnabled,
      autostartEnabled: autostartEnabled ?? this.autostartEnabled,
      networkManagerAvailable:
          networkManagerAvailable ?? this.networkManagerAvailable,
      systemProxy: systemProxy ?? this.systemProxy,
      tunnel: tunnel ?? this.tunnel,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isSupported': isSupported,
      'environment': environment.name,
      'mode': mode.name,
      'trayAvailable': trayAvailable,
      'trayEnabled': trayEnabled,
      'autostartEnabled': autostartEnabled,
      'networkManagerAvailable': networkManagerAvailable,
      'systemProxy': systemProxy.toJson(),
      'tunnel': tunnel.toJson(),
      'statusMessage': statusMessage,
    };
  }

  factory DesktopIntegrationState.fromJson(
    Map<String, dynamic> json, {
    LinuxDesktopConfig? fallbackConfig,
  }) {
    final config = fallbackConfig ?? LinuxDesktopConfig.defaults();
    return DesktopIntegrationState(
      isSupported: json['isSupported'] as bool? ?? true,
      environment: DesktopEnvironmentCopy.fromJsonValue(
        json['environment'] as String?,
      ),
      mode: VpnModeCopy.fromJsonValue(json['mode'] as String?),
      trayAvailable: json['trayAvailable'] as bool? ?? false,
      trayEnabled: json['trayEnabled'] as bool? ?? config.trayEnabled,
      autostartEnabled: json['autostartEnabled'] as bool? ?? false,
      networkManagerAvailable:
          json['networkManagerAvailable'] as bool? ?? false,
      systemProxy: SystemProxyState.fromJson(
        (json['systemProxy'] as Map?)?.cast<String, dynamic>() ?? const {},
        config: config,
      ),
      tunnel: TunnelSessionState.fromJson(
        (json['tunnel'] as Map?)?.cast<String, dynamic>() ?? const {},
        config: config,
      ),
      statusMessage: json['statusMessage'] as String? ?? '',
    );
  }
}
