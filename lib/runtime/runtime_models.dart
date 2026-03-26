import 'dart:convert';

import '../i18n/app_language.dart';
import '../models/app_models.dart';

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

enum AssistantExecutionTarget { singleAgent, local, remote }

extension AssistantExecutionTargetCopy on AssistantExecutionTarget {
  String get label => switch (this) {
    AssistantExecutionTarget.singleAgent => appText('单机智能体', 'Single Agent'),
    AssistantExecutionTarget.local => appText(
      '本地 OpenClaw Gateway',
      'Local OpenClaw Gateway',
    ),
    AssistantExecutionTarget.remote => appText(
      '远程 OpenClaw Gateway',
      'Remote OpenClaw Gateway',
    ),
  };

  String get promptValue => switch (this) {
    AssistantExecutionTarget.singleAgent => 'single-agent',
    AssistantExecutionTarget.local => 'local',
    AssistantExecutionTarget.remote => 'remote',
  };

  static AssistantExecutionTarget fromJsonValue(String? value) {
    final normalized = value?.trim() ?? '';
    switch (normalized) {
      case 'singleAgent':
      case 'aiGatewayOnly':
      case 'single-agent':
      case 'ai-gateway-only':
        return AssistantExecutionTarget.singleAgent;
      case 'local':
        return AssistantExecutionTarget.local;
      case 'remote':
        return AssistantExecutionTarget.remote;
      default:
        return AssistantExecutionTarget.local;
    }
  }
}

String normalizeSingleAgentProviderId(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return '';
  }
  final normalizedWhitespace = trimmed.replaceAll(RegExp(r'\s+'), '-');
  final buffer = StringBuffer();
  var previousWasSeparator = false;
  var hasOutput = false;
  for (final rune in normalizedWhitespace.runes) {
    final char = String.fromCharCode(rune);
    final isAlphaNumeric =
        (rune >= 97 && rune <= 122) || (rune >= 48 && rune <= 57);
    final isSeparator = char == '-' || char == '_' || char == '.';
    if (isAlphaNumeric) {
      buffer.write(char);
      previousWasSeparator = false;
      hasOutput = true;
      continue;
    }
    if (isSeparator && !previousWasSeparator && hasOutput) {
      buffer.write('-');
      previousWasSeparator = true;
    }
  }
  return buffer.toString().replaceAll(RegExp(r'^[-_.]+|[-_.]+$'), '');
}

String _singleAgentProviderFallbackLabel(String providerId) {
  final normalized = normalizeSingleAgentProviderId(providerId);
  if (normalized.isEmpty) {
    return 'Custom Agent';
  }
  return normalized
      .split(RegExp(r'[-_.]+'))
      .where((item) => item.isNotEmpty)
      .map((item) => '${item[0].toUpperCase()}${item.substring(1)}')
      .join(' ');
}

String _singleAgentProviderFallbackBadge({
  required String providerId,
  required String label,
}) {
  final normalized = normalizeSingleAgentProviderId(providerId);
  final known = <String, String>{
    'auto': 'A',
    'codex': 'C',
    'opencode': 'O',
    'claude': 'Cl',
    'gemini': 'G',
  };
  final explicit = known[normalized];
  if (explicit != null) {
    return explicit;
  }
  final stripped = label.replaceAll(RegExp(r'\s+'), '');
  if (stripped.isEmpty) {
    return '?';
  }
  final length = stripped.length >= 2 ? 2 : 1;
  return stripped.substring(0, length).toUpperCase();
}

class SingleAgentProvider {
  const SingleAgentProvider({
    required this.providerId,
    required this.label,
    required this.badge,
    this.preset = false,
  });

  static const SingleAgentProvider auto = SingleAgentProvider(
    providerId: 'auto',
    label: 'Auto',
    badge: 'A',
  );

  static const SingleAgentProvider codex = SingleAgentProvider(
    providerId: 'codex',
    label: 'Codex',
    badge: 'C',
    preset: true,
  );

  static const SingleAgentProvider opencode = SingleAgentProvider(
    providerId: 'opencode',
    label: 'OpenCode',
    badge: 'O',
    preset: true,
  );

  static const SingleAgentProvider claude = SingleAgentProvider(
    providerId: 'claude',
    label: 'Claude',
    badge: 'Cl',
  );

  static const SingleAgentProvider gemini = SingleAgentProvider(
    providerId: 'gemini',
    label: 'Gemini',
    badge: 'G',
  );

  final String providerId;
  final String label;
  final String badge;
  final bool preset;

  bool get isAuto => providerId == auto.providerId;

  SingleAgentProvider copyWith({
    String? providerId,
    String? label,
    String? badge,
    bool? preset,
  }) {
    final resolvedProviderId = normalizeSingleAgentProviderId(
      providerId ?? this.providerId,
    );
    final resolvedLabel = (label ?? this.label).trim();
    final resolvedBadge = (badge ?? this.badge).trim();
    return SingleAgentProvider(
      providerId: resolvedProviderId,
      label: resolvedLabel.isEmpty
          ? _singleAgentProviderFallbackLabel(resolvedProviderId)
          : resolvedLabel,
      badge: resolvedBadge.isEmpty
          ? _singleAgentProviderFallbackBadge(
              providerId: resolvedProviderId,
              label: resolvedLabel,
            )
          : resolvedBadge,
      preset: preset ?? this.preset,
    );
  }

  static SingleAgentProvider fromJsonValue(
    String? value, {
    String? label,
    String? badge,
  }) {
    final normalized = normalizeSingleAgentProviderId(value ?? '');
    final base = switch (normalized) {
      'codex' => codex,
      'opencode' => opencode,
      'claude' => claude,
      'gemini' => gemini,
      'auto' || '' => auto,
      _ => SingleAgentProvider(
        providerId: normalized,
        label: _singleAgentProviderFallbackLabel(normalized),
        badge: _singleAgentProviderFallbackBadge(
          providerId: normalized,
          label: _singleAgentProviderFallbackLabel(normalized),
        ),
      ),
    };
    return base.copyWith(label: label, badge: badge);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SingleAgentProvider && other.providerId == providerId);

  @override
  int get hashCode => providerId.hashCode;
}

extension SingleAgentProviderCopy on SingleAgentProvider {
  static SingleAgentProvider fromJsonValue(
    String? value, {
    String? label,
    String? badge,
  }) => SingleAgentProvider.fromJsonValue(value, label: label, badge: badge);
}

const List<SingleAgentProvider> kBuiltinExternalAcpProviders =
    <SingleAgentProvider>[
      SingleAgentProvider.codex,
      SingleAgentProvider.opencode,
    ];

const List<SingleAgentProvider> kKnownSingleAgentProviders =
    <SingleAgentProvider>[
      SingleAgentProvider.codex,
      SingleAgentProvider.opencode,
      SingleAgentProvider.claude,
      SingleAgentProvider.gemini,
    ];

const Set<String> kLegacyExternalAcpProviderIds = <String>{'claude', 'gemini'};

class ExternalAcpEndpointProfile {
  const ExternalAcpEndpointProfile({
    required this.providerKey,
    required this.label,
    required this.badge,
    required this.endpoint,
    required this.enabled,
  });

  final String providerKey;
  final String label;
  final String badge;
  final String endpoint;
  final bool enabled;

  factory ExternalAcpEndpointProfile.defaultsForProvider(
    SingleAgentProvider provider,
  ) {
    return ExternalAcpEndpointProfile(
      providerKey: provider.providerId,
      label: provider.label,
      badge: provider.badge,
      endpoint: '',
      enabled: true,
    );
  }

  ExternalAcpEndpointProfile copyWith({
    String? providerKey,
    String? label,
    String? badge,
    String? endpoint,
    bool? enabled,
  }) {
    return ExternalAcpEndpointProfile(
      providerKey: normalizeSingleAgentProviderId(
        providerKey ?? this.providerKey,
      ),
      label: (label ?? this.label).trim(),
      badge: (badge ?? this.badge).trim(),
      endpoint: (endpoint ?? this.endpoint).trim(),
      enabled: enabled ?? this.enabled,
    );
  }

  SingleAgentProvider? get builtinProvider {
    final normalized = providerKey.trim().toLowerCase();
    for (final provider in kKnownSingleAgentProviders) {
      if (provider.providerId == normalized) {
        return provider;
      }
    }
    return null;
  }

  bool get isPreset => kBuiltinExternalAcpProviders.any(
    (item) => item.providerId == providerKey,
  );

  SingleAgentProvider toProvider() {
    return SingleAgentProvider.fromJsonValue(
      providerKey,
      label: label,
      badge: badge,
    ).copyWith(preset: isPreset);
  }

  Map<String, dynamic> toJson() {
    return {
      'providerKey': providerKey,
      'label': label,
      'badge': badge,
      'endpoint': endpoint,
      'enabled': enabled,
    };
  }

  factory ExternalAcpEndpointProfile.fromJson(Map<String, dynamic> json) {
    final providerKey = normalizeSingleAgentProviderId(
      json['providerKey']?.toString() ?? '',
    );
    final builtin = SingleAgentProviderCopy.fromJsonValue(providerKey);
    final fallbackLabel = builtin.isAuto ? providerKey : builtin.label;
    final label = json['label']?.toString().trim().isNotEmpty == true
        ? json['label'].toString().trim()
        : fallbackLabel;
    return ExternalAcpEndpointProfile(
      providerKey: providerKey,
      label: label,
      badge: json['badge']?.toString().trim().isNotEmpty == true
          ? json['badge'].toString().trim()
          : _singleAgentProviderFallbackBadge(
              providerId: providerKey,
              label: label,
            ),
      endpoint: json['endpoint']?.toString().trim() ?? '',
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
  final migratedCustomProfiles = <ExternalAcpEndpointProfile>[];
  var customSuffix = 1;

  String nextCustomKey() {
    while (true) {
      final key = 'custom-agent-$customSuffix';
      customSuffix += 1;
      if (!byKey.containsKey(key) &&
          !migratedCustomProfiles.any((item) => item.providerKey == key)) {
        return key;
      }
    }
  }

  for (final item in incoming) {
    final key = item.providerKey.trim().toLowerCase();
    if (key.isEmpty || byKey.containsKey(key)) {
      continue;
    }
    if (kLegacyExternalAcpProviderIds.contains(key)) {
      migratedCustomProfiles.add(item.copyWith(providerKey: nextCustomKey()));
      continue;
    }
    byKey[key] = item.copyWith(providerKey: key);
  }

  final normalized = <ExternalAcpEndpointProfile>[
    for (final provider in kBuiltinExternalAcpProviders)
      byKey.remove(provider.providerId) ??
          ExternalAcpEndpointProfile.defaultsForProvider(provider),
    ...migratedCustomProfiles,
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

String normalizeAuthorizedSkillDirectoryPath(String path) {
  final trimmed = path.trim();
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

  bool get isSingleAgent =>
      executionTarget == AssistantExecutionTarget.singleAgent;

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
    return GatewayConnectionProfile.defaultsRemote();
  }

  factory GatewayConnectionProfile.defaultsLocal() {
    return const GatewayConnectionProfile(
      mode: RuntimeConnectionMode.local,
      useSetupCode: false,
      setupCode: '',
      host: '127.0.0.1',
      port: 18789,
      tls: false,
      selectedAgentId: '',
    );
  }

  factory GatewayConnectionProfile.defaultsRemote() {
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

  factory GatewayConnectionProfile.emptySlot({required int index}) {
    return const GatewayConnectionProfile(
      mode: RuntimeConnectionMode.unconfigured,
      useSetupCode: false,
      setupCode: '',
      host: '',
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

const int kGatewayProfileListLength = 5;
const int kGatewayLocalProfileIndex = 0;
const int kGatewayRemoteProfileIndex = 1;
const int kGatewayCustomProfileStartIndex = 2;

List<GatewayConnectionProfile> normalizeGatewayProfiles({
  Iterable<GatewayConnectionProfile>? profiles,
}) {
  final defaults = List<GatewayConnectionProfile>.generate(
    kGatewayProfileListLength,
    (index) => switch (index) {
      kGatewayLocalProfileIndex => GatewayConnectionProfile.defaultsLocal(),
      kGatewayRemoteProfileIndex => GatewayConnectionProfile.defaultsRemote(),
      _ => GatewayConnectionProfile.emptySlot(index: index),
    },
    growable: false,
  );
  final incoming =
      profiles?.toList(growable: false) ?? const <GatewayConnectionProfile>[];
  final normalized = <GatewayConnectionProfile>[];
  for (var index = 0; index < kGatewayProfileListLength; index += 1) {
    final fallback = defaults[index];
    final current = index < incoming.length ? incoming[index] : fallback;
    if (index == kGatewayLocalProfileIndex) {
      normalized.add(
        current.copyWith(
          mode: RuntimeConnectionMode.local,
          useSetupCode: false,
          setupCode: '',
          host: current.host.trim().isEmpty ? fallback.host : current.host,
          port: current.port > 0 ? current.port : fallback.port,
          tls: false,
        ),
      );
      continue;
    }
    if (index == kGatewayRemoteProfileIndex) {
      final useDefaultRemoteEndpoint =
          current.host.trim().isEmpty || current.port <= 0;
      normalized.add(
        current.copyWith(
          mode: RuntimeConnectionMode.remote,
          host: useDefaultRemoteEndpoint ? fallback.host : current.host,
          port: useDefaultRemoteEndpoint ? fallback.port : current.port,
          tls: useDefaultRemoteEndpoint ? fallback.tls : current.tls,
        ),
      );
      continue;
    }
    final slotMode = switch (current.mode) {
      RuntimeConnectionMode.local => RuntimeConnectionMode.local,
      RuntimeConnectionMode.remote => RuntimeConnectionMode.remote,
      RuntimeConnectionMode.unconfigured =>
        current.host.trim().isNotEmpty
            ? RuntimeConnectionMode.remote
            : RuntimeConnectionMode.unconfigured,
    };
    normalized.add(
      current.copyWith(
        mode: slotMode,
        useSetupCode: slotMode == RuntimeConnectionMode.local
            ? false
            : current.useSetupCode,
        setupCode: slotMode == RuntimeConnectionMode.local
            ? ''
            : current.setupCode,
        port: current.port > 0
            ? current.port
            : slotMode == RuntimeConnectionMode.local
            ? 18789
            : 443,
        tls: slotMode == RuntimeConnectionMode.local ? false : current.tls,
      ),
    );
  }
  return List<GatewayConnectionProfile>.unmodifiable(normalized);
}

List<GatewayConnectionProfile> replaceGatewayProfileAt(
  List<GatewayConnectionProfile> profiles,
  int index,
  GatewayConnectionProfile profile,
) {
  final normalizedProfiles = normalizeGatewayProfiles(profiles: profiles);
  final next = List<GatewayConnectionProfile>.from(normalizedProfiles);
  final clampedIndex = index.clamp(0, kGatewayProfileListLength - 1);
  next[clampedIndex] = profile;
  return normalizeGatewayProfiles(profiles: next);
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
      baseUrl: 'https://ollama.com',
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
      name: 'LLM API',
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

enum WebSessionPersistenceMode { browser, remote }

extension WebSessionPersistenceModeCopy on WebSessionPersistenceMode {
  String get label => switch (this) {
    WebSessionPersistenceMode.browser => appText('浏览器本地缓存', 'Browser cache'),
    WebSessionPersistenceMode.remote => appText(
      '远端 Session API',
      'Remote session API',
    ),
  };

  static WebSessionPersistenceMode fromJsonValue(String? value) {
    return WebSessionPersistenceMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => WebSessionPersistenceMode.browser,
    );
  }
}

class WebSessionPersistenceConfig {
  const WebSessionPersistenceConfig({
    required this.mode,
    required this.remoteBaseUrl,
  });

  final WebSessionPersistenceMode mode;
  final String remoteBaseUrl;

  factory WebSessionPersistenceConfig.defaults() {
    return const WebSessionPersistenceConfig(
      mode: WebSessionPersistenceMode.browser,
      remoteBaseUrl: '',
    );
  }

  bool get usesRemoteApi =>
      mode == WebSessionPersistenceMode.remote &&
      remoteBaseUrl.trim().isNotEmpty;

  WebSessionPersistenceConfig copyWith({
    WebSessionPersistenceMode? mode,
    String? remoteBaseUrl,
  }) {
    return WebSessionPersistenceConfig(
      mode: mode ?? this.mode,
      remoteBaseUrl: remoteBaseUrl ?? this.remoteBaseUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {'mode': mode.name, 'remoteBaseUrl': remoteBaseUrl};
  }

  factory WebSessionPersistenceConfig.fromJson(Map<String, dynamic> json) {
    final defaults = WebSessionPersistenceConfig.defaults();
    return WebSessionPersistenceConfig(
      mode: WebSessionPersistenceModeCopy.fromJsonValue(
        json['mode'] as String?,
      ),
      remoteBaseUrl: json['remoteBaseUrl'] as String? ?? defaults.remoteBaseUrl,
    );
  }
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
                  (item) => AssistantFocusEntryCopy.fromJsonValue(
                    item?.toString(),
                  ),
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
    return externalAcpEndpoints.firstWhere(
      (item) => item.providerKey.trim().toLowerCase() == provider.providerId,
      orElse: () => ExternalAcpEndpointProfile.defaultsForProvider(provider),
    );
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
    return null;
  }

  SingleAgentProvider resolveSingleAgentProvider(SingleAgentProvider provider) {
    if (provider.isAuto) {
      return SingleAgentProvider.auto;
    }
    final profile = externalAcpEndpointForProviderId(provider.providerId);
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
    final profile = externalAcpEndpointForProviderId(resolved);
    if (profile != null) {
      return profile.toProvider();
    }
    return SingleAgentProvider.fromJsonValue(resolved);
  }

  List<SingleAgentProvider> get availableSingleAgentProviders =>
      externalAcpEndpoints
          .map((item) => item.toProvider())
          .toList(growable: false);

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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'text': text,
      'timestampMs': timestampMs,
      'toolCallId': toolCallId,
      'toolName': toolName,
      'stopReason': stopReason,
      'pending': pending,
      'error': error,
    };
  }

  factory GatewayChatMessage.fromJson(Map<String, dynamic> json) {
    double? asDouble(Object? value) {
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value?.toString() ?? '');
    }

    return GatewayChatMessage(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'assistant',
      text: json['text']?.toString() ?? '',
      timestampMs: asDouble(json['timestampMs']),
      toolCallId: json['toolCallId']?.toString(),
      toolName: json['toolName']?.toString(),
      stopReason: json['stopReason']?.toString(),
      pending: json['pending'] as bool? ?? false,
      error: json['error'] as bool? ?? false,
    );
  }

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

class AssistantThreadSkillEntry {
  const AssistantThreadSkillEntry({
    required this.key,
    required this.label,
    required this.description,
    this.source = '',
    required this.sourcePath,
    this.scope = '',
    required this.sourceLabel,
  });

  final String key;
  final String label;
  final String description;
  final String source;
  final String sourcePath;
  final String scope;
  final String sourceLabel;

  AssistantThreadSkillEntry copyWith({
    String? key,
    String? label,
    String? description,
    String? source,
    String? sourcePath,
    String? scope,
    String? sourceLabel,
  }) {
    return AssistantThreadSkillEntry(
      key: key ?? this.key,
      label: label ?? this.label,
      description: description ?? this.description,
      source: source ?? this.source,
      sourcePath: sourcePath ?? this.sourcePath,
      scope: scope ?? this.scope,
      sourceLabel: sourceLabel ?? this.sourceLabel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'description': description,
      'source': source,
      'sourcePath': sourcePath,
      'scope': scope,
      'sourceLabel': sourceLabel,
    };
  }

  factory AssistantThreadSkillEntry.fromJson(Map<String, dynamic> json) {
    return AssistantThreadSkillEntry(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      sourcePath: json['sourcePath']?.toString() ?? '',
      scope: json['scope']?.toString() ?? '',
      sourceLabel: json['sourceLabel']?.toString() ?? '',
    );
  }
}

class AssistantThreadRecord {
  const AssistantThreadRecord({
    required this.sessionKey,
    required this.messages,
    required this.updatedAtMs,
    required this.title,
    required this.archived,
    required this.executionTarget,
    required this.messageViewMode,
    this.importedSkills = const <AssistantThreadSkillEntry>[],
    this.selectedSkillKeys = const <String>[],
    this.assistantModelId = '',
    this.singleAgentProvider = SingleAgentProvider.auto,
    this.gatewayEntryState,
    this.workspaceRef = '',
    this.workspaceRefKind = WorkspaceRefKind.localPath,
  });

  final String sessionKey;
  final List<GatewayChatMessage> messages;
  final double? updatedAtMs;
  final String title;
  final bool archived;
  final AssistantExecutionTarget? executionTarget;
  final AssistantMessageViewMode messageViewMode;
  final List<AssistantThreadSkillEntry> importedSkills;
  final List<String> selectedSkillKeys;
  final String assistantModelId;
  final SingleAgentProvider singleAgentProvider;
  final String? gatewayEntryState;
  final String workspaceRef;
  final WorkspaceRefKind workspaceRefKind;

  AssistantThreadRecord copyWith({
    String? sessionKey,
    List<GatewayChatMessage>? messages,
    double? updatedAtMs,
    String? title,
    bool? archived,
    AssistantExecutionTarget? executionTarget,
    bool clearExecutionTarget = false,
    AssistantMessageViewMode? messageViewMode,
    List<AssistantThreadSkillEntry>? importedSkills,
    List<String>? selectedSkillKeys,
    String? assistantModelId,
    SingleAgentProvider? singleAgentProvider,
    String? gatewayEntryState,
    bool clearGatewayEntryState = false,
    String? workspaceRef,
    WorkspaceRefKind? workspaceRefKind,
  }) {
    return AssistantThreadRecord(
      sessionKey: sessionKey ?? this.sessionKey,
      messages: messages ?? this.messages,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      title: title ?? this.title,
      archived: archived ?? this.archived,
      executionTarget: clearExecutionTarget
          ? null
          : (executionTarget ?? this.executionTarget),
      messageViewMode: messageViewMode ?? this.messageViewMode,
      importedSkills: importedSkills ?? this.importedSkills,
      selectedSkillKeys: selectedSkillKeys ?? this.selectedSkillKeys,
      assistantModelId: assistantModelId ?? this.assistantModelId,
      singleAgentProvider: singleAgentProvider ?? this.singleAgentProvider,
      gatewayEntryState: clearGatewayEntryState
          ? null
          : (gatewayEntryState ?? this.gatewayEntryState),
      workspaceRef: workspaceRef ?? this.workspaceRef,
      workspaceRefKind: workspaceRefKind ?? this.workspaceRefKind,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionKey': sessionKey,
      'messages': messages.map((item) => item.toJson()).toList(growable: false),
      'updatedAtMs': updatedAtMs,
      'title': title,
      'archived': archived,
      'executionTarget': executionTarget?.name,
      'messageViewMode': messageViewMode.name,
      'importedSkills': importedSkills
          .map((item) => item.toJson())
          .toList(growable: false),
      'selectedSkillKeys': selectedSkillKeys,
      'assistantModelId': assistantModelId,
      'singleAgentProvider': singleAgentProvider.providerId,
      'gatewayEntryState': gatewayEntryState,
      'workspaceRef': workspaceRef,
      'workspaceRefKind': workspaceRefKind.name,
    };
  }

  factory AssistantThreadRecord.fromJson(Map<String, dynamic> json) {
    double? asDouble(Object? value) {
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value?.toString() ?? '');
    }

    final rawMessages = json['messages'];
    final messages = rawMessages is List
        ? rawMessages
              .whereType<Map>()
              .map(
                (item) =>
                    GatewayChatMessage.fromJson(item.cast<String, dynamic>()),
              )
              .toList(growable: false)
        : const <GatewayChatMessage>[];
    List<AssistantThreadSkillEntry> normalizeSkillEntries(Object? value) {
      if (value is! List) {
        return const <AssistantThreadSkillEntry>[];
      }
      final entries = <AssistantThreadSkillEntry>[];
      final seen = <String>{};
      for (final item in value.whereType<Map>()) {
        final entry = AssistantThreadSkillEntry.fromJson(
          item.cast<String, dynamic>(),
        );
        final normalizedKey = entry.key.trim();
        if (normalizedKey.isEmpty || !seen.add(normalizedKey)) {
          continue;
        }
        entries.add(entry);
      }
      return entries;
    }

    List<String> normalizeSkillKeys(Object? value) {
      if (value is! List) {
        return const <String>[];
      }
      final keys = <String>[];
      final seen = <String>{};
      for (final item in value) {
        final normalized = item?.toString().trim() ?? '';
        if (normalized.isEmpty || !seen.add(normalized)) {
          continue;
        }
        keys.add(normalized);
      }
      return keys;
    }

    String? normalizeGatewayEntryState(Object? value) {
      final normalized = value?.toString().trim() ?? '';
      if (normalized.isEmpty) {
        return null;
      }
      if (normalized == 'ai-gateway-only') {
        return 'single-agent';
      }
      return normalized;
    }

    WorkspaceRefKind normalizeWorkspaceRefKind(
      Object? value, {
      required AssistantExecutionTarget? executionTarget,
      required String workspaceRef,
    }) {
      final raw = value?.toString().trim();
      if (raw != null && raw.isNotEmpty) {
        return WorkspaceRefKindCopy.fromJsonValue(raw);
      }
      if (workspaceRef.startsWith('object://')) {
        return WorkspaceRefKind.objectStore;
      }
      if (executionTarget == AssistantExecutionTarget.remote) {
        return WorkspaceRefKind.remotePath;
      }
      return WorkspaceRefKind.localPath;
    }

    // Keep tolerating legacy payloads that still contain discoveredSkills,
    // but do not map the retired field back into the runtime model.
    normalizeSkillEntries(json['discoveredSkills']);

    final executionTarget = json['executionTarget'] == null
        ? null
        : AssistantExecutionTargetCopy.fromJsonValue(
            json['executionTarget']?.toString(),
          );
    final workspaceRef = json['workspaceRef']?.toString() ?? '';

    return AssistantThreadRecord(
      sessionKey: json['sessionKey']?.toString() ?? '',
      messages: messages,
      updatedAtMs: asDouble(json['updatedAtMs']),
      title: json['title']?.toString() ?? '',
      archived: json['archived'] as bool? ?? false,
      executionTarget: executionTarget,
      messageViewMode: AssistantMessageViewModeCopy.fromJsonValue(
        json['messageViewMode']?.toString(),
      ),
      importedSkills: normalizeSkillEntries(json['importedSkills']),
      selectedSkillKeys: normalizeSkillKeys(json['selectedSkillKeys']),
      assistantModelId: json['assistantModelId']?.toString() ?? '',
      singleAgentProvider: SingleAgentProviderCopy.fromJsonValue(
        json['singleAgentProvider']?.toString(),
      ),
      gatewayEntryState: normalizeGatewayEntryState(json['gatewayEntryState']),
      workspaceRef: workspaceRef,
      workspaceRefKind: normalizeWorkspaceRefKind(
        json['workspaceRefKind'],
        executionTarget: executionTarget,
        workspaceRef: workspaceRef,
      ),
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

/// 多 Agent 协作角色
enum MultiAgentRole {
  architect, // 调度/文档：需求收口、接受标准、工作流设计
  engineer, // 主程：关键实现、重构、集成
  testerDoc, // worker/review：并行切片、复审、回归建议
}

enum MultiAgentFramework { native, aris }

extension MultiAgentFrameworkCopy on MultiAgentFramework {
  String get label => switch (this) {
    MultiAgentFramework.native => appText('原生多 Agent', 'Native Multi-Agent'),
    MultiAgentFramework.aris => appText('ARIS 框架', 'ARIS Framework'),
  };

  static MultiAgentFramework fromJsonValue(String? value) {
    return MultiAgentFramework.values.firstWhere(
      (item) => item.name == value,
      orElse: () => MultiAgentFramework.native,
    );
  }
}

extension MultiAgentRoleCopy on MultiAgentRole {
  String get label => switch (this) {
    MultiAgentRole.architect => 'Architect（调度/文档）',
    MultiAgentRole.engineer => 'Lead Engineer（主程）',
    MultiAgentRole.testerDoc => 'Worker/Review（Worker 池）',
  };

  String get description => switch (this) {
    MultiAgentRole.architect => '负责需求收口、接受标准、文档与协作调度',
    MultiAgentRole.engineer => '负责主实现、关键改动、集成收口',
    MultiAgentRole.testerDoc => '负责并行 worker、复审、回归和补充说明',
  };
}

enum AiGatewayInjectionPolicy { disabled, launchScoped, appManagedDefault }

extension AiGatewayInjectionPolicyCopy on AiGatewayInjectionPolicy {
  String get label => switch (this) {
    AiGatewayInjectionPolicy.disabled => appText('禁用', 'Disabled'),
    AiGatewayInjectionPolicy.launchScoped => appText(
      '仅当前协作运行',
      'Launch scoped',
    ),
    AiGatewayInjectionPolicy.appManagedDefault => appText(
      'XWorkmate 默认',
      'XWorkmate default',
    ),
  };

  static AiGatewayInjectionPolicy fromJsonValue(String? value) {
    return AiGatewayInjectionPolicy.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AiGatewayInjectionPolicy.appManagedDefault,
    );
  }
}

/// 单个 Agent Worker 配置
class AgentWorkerConfig {
  const AgentWorkerConfig({
    required this.role,
    required this.cliTool,
    required this.model,
    required this.enabled,
    this.maxRetries = 2,
  });

  final MultiAgentRole role;
  final String cliTool; // e.g. 'claude' | 'codex' | 'opencode' | 'gemini'
  final String model;
  final bool enabled;
  final int maxRetries;

  AgentWorkerConfig copyWith({
    MultiAgentRole? role,
    String? cliTool,
    String? model,
    bool? enabled,
    int? maxRetries,
  }) {
    return AgentWorkerConfig(
      role: role ?? this.role,
      cliTool: cliTool ?? this.cliTool,
      model: model ?? this.model,
      enabled: enabled ?? this.enabled,
      maxRetries: maxRetries ?? this.maxRetries,
    );
  }
}

class ManagedSkillEntry {
  const ManagedSkillEntry({
    required this.key,
    required this.label,
    required this.source,
    required this.selected,
  });

  final String key;
  final String label;
  final String source;
  final bool selected;

  ManagedSkillEntry copyWith({
    String? key,
    String? label,
    String? source,
    bool? selected,
  }) {
    return ManagedSkillEntry(
      key: key ?? this.key,
      label: label ?? this.label,
      source: source ?? this.source,
      selected: selected ?? this.selected,
    );
  }

  Map<String, dynamic> toJson() {
    return {'key': key, 'label': label, 'source': source, 'selected': selected};
  }

  factory ManagedSkillEntry.fromJson(Map<String, dynamic> json) {
    return ManagedSkillEntry(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      source: json['source'] as String? ?? '',
      selected: json['selected'] as bool? ?? false,
    );
  }
}

class ManagedMcpServerEntry {
  const ManagedMcpServerEntry({
    required this.id,
    required this.name,
    required this.transport,
    required this.command,
    required this.url,
    required this.args,
    required this.envKeys,
    required this.enabled,
  });

  final String id;
  final String name;
  final String transport;
  final String command;
  final String url;
  final List<String> args;
  final List<String> envKeys;
  final bool enabled;

  ManagedMcpServerEntry copyWith({
    String? id,
    String? name,
    String? transport,
    String? command,
    String? url,
    List<String>? args,
    List<String>? envKeys,
    bool? enabled,
  }) {
    return ManagedMcpServerEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      transport: transport ?? this.transport,
      command: command ?? this.command,
      url: url ?? this.url,
      args: args ?? this.args,
      envKeys: envKeys ?? this.envKeys,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'transport': transport,
      'command': command,
      'url': url,
      'args': args,
      'envKeys': envKeys,
      'enabled': enabled,
    };
  }

  factory ManagedMcpServerEntry.fromJson(Map<String, dynamic> json) {
    final rawArgs = json['args'];
    final rawEnvKeys = json['envKeys'];
    return ManagedMcpServerEntry(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      transport: json['transport'] as String? ?? 'stdio',
      command: json['command'] as String? ?? '',
      url: json['url'] as String? ?? '',
      args: rawArgs is List
          ? rawArgs.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
      envKeys: rawEnvKeys is List
          ? rawEnvKeys.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class ManagedMountTargetState {
  const ManagedMountTargetState({
    required this.targetId,
    required this.label,
    required this.available,
    required this.supportsSkills,
    required this.supportsMcp,
    required this.supportsAiGatewayInjection,
    required this.discoveryState,
    required this.syncState,
    required this.discoveredSkillCount,
    required this.discoveredMcpCount,
    required this.managedMcpCount,
    required this.detail,
  });

  final String targetId;
  final String label;
  final bool available;
  final bool supportsSkills;
  final bool supportsMcp;
  final bool supportsAiGatewayInjection;
  final String discoveryState;
  final String syncState;
  final int discoveredSkillCount;
  final int discoveredMcpCount;
  final int managedMcpCount;
  final String detail;

  ManagedMountTargetState copyWith({
    String? targetId,
    String? label,
    bool? available,
    bool? supportsSkills,
    bool? supportsMcp,
    bool? supportsAiGatewayInjection,
    String? discoveryState,
    String? syncState,
    int? discoveredSkillCount,
    int? discoveredMcpCount,
    int? managedMcpCount,
    String? detail,
  }) {
    return ManagedMountTargetState(
      targetId: targetId ?? this.targetId,
      label: label ?? this.label,
      available: available ?? this.available,
      supportsSkills: supportsSkills ?? this.supportsSkills,
      supportsMcp: supportsMcp ?? this.supportsMcp,
      supportsAiGatewayInjection:
          supportsAiGatewayInjection ?? this.supportsAiGatewayInjection,
      discoveryState: discoveryState ?? this.discoveryState,
      syncState: syncState ?? this.syncState,
      discoveredSkillCount: discoveredSkillCount ?? this.discoveredSkillCount,
      discoveredMcpCount: discoveredMcpCount ?? this.discoveredMcpCount,
      managedMcpCount: managedMcpCount ?? this.managedMcpCount,
      detail: detail ?? this.detail,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'targetId': targetId,
      'label': label,
      'available': available,
      'supportsSkills': supportsSkills,
      'supportsMcp': supportsMcp,
      'supportsAiGatewayInjection': supportsAiGatewayInjection,
      'discoveryState': discoveryState,
      'syncState': syncState,
      'discoveredSkillCount': discoveredSkillCount,
      'discoveredMcpCount': discoveredMcpCount,
      'managedMcpCount': managedMcpCount,
      'detail': detail,
    };
  }

  factory ManagedMountTargetState.fromJson(Map<String, dynamic> json) {
    return ManagedMountTargetState(
      targetId: json['targetId'] as String? ?? '',
      label: json['label'] as String? ?? '',
      available: json['available'] as bool? ?? false,
      supportsSkills: json['supportsSkills'] as bool? ?? false,
      supportsMcp: json['supportsMcp'] as bool? ?? false,
      supportsAiGatewayInjection:
          json['supportsAiGatewayInjection'] as bool? ?? false,
      discoveryState: json['discoveryState'] as String? ?? 'idle',
      syncState: json['syncState'] as String? ?? 'idle',
      discoveredSkillCount: json['discoveredSkillCount'] as int? ?? 0,
      discoveredMcpCount: json['discoveredMcpCount'] as int? ?? 0,
      managedMcpCount: json['managedMcpCount'] as int? ?? 0,
      detail: json['detail'] as String? ?? '',
    );
  }

  factory ManagedMountTargetState.placeholder({
    required String targetId,
    required String label,
    required bool supportsSkills,
    required bool supportsMcp,
    required bool supportsAiGatewayInjection,
  }) {
    return ManagedMountTargetState(
      targetId: targetId,
      label: label,
      available: false,
      supportsSkills: supportsSkills,
      supportsMcp: supportsMcp,
      supportsAiGatewayInjection: supportsAiGatewayInjection,
      discoveryState: 'idle',
      syncState: 'idle',
      discoveredSkillCount: 0,
      discoveredMcpCount: 0,
      managedMcpCount: 0,
      detail: '',
    );
  }

  static List<ManagedMountTargetState> defaults() {
    return const <ManagedMountTargetState>[
      ManagedMountTargetState(
        targetId: 'aris',
        label: 'ARIS',
        available: false,
        supportsSkills: true,
        supportsMcp: true,
        supportsAiGatewayInjection: false,
        discoveryState: 'idle',
        syncState: 'idle',
        discoveredSkillCount: 0,
        discoveredMcpCount: 0,
        managedMcpCount: 0,
        detail: '',
      ),
      ManagedMountTargetState(
        targetId: 'codex',
        label: 'Codex',
        available: false,
        supportsSkills: true,
        supportsMcp: true,
        supportsAiGatewayInjection: true,
        discoveryState: 'idle',
        syncState: 'idle',
        discoveredSkillCount: 0,
        discoveredMcpCount: 0,
        managedMcpCount: 0,
        detail: '',
      ),
      ManagedMountTargetState(
        targetId: 'claude',
        label: 'Claude',
        available: false,
        supportsSkills: true,
        supportsMcp: true,
        supportsAiGatewayInjection: true,
        discoveryState: 'idle',
        syncState: 'idle',
        discoveredSkillCount: 0,
        discoveredMcpCount: 0,
        managedMcpCount: 0,
        detail: '',
      ),
      ManagedMountTargetState(
        targetId: 'gemini',
        label: 'Gemini',
        available: false,
        supportsSkills: true,
        supportsMcp: true,
        supportsAiGatewayInjection: true,
        discoveryState: 'idle',
        syncState: 'idle',
        discoveredSkillCount: 0,
        discoveredMcpCount: 0,
        managedMcpCount: 0,
        detail: '',
      ),
      ManagedMountTargetState(
        targetId: 'opencode',
        label: 'OpenCode',
        available: false,
        supportsSkills: true,
        supportsMcp: true,
        supportsAiGatewayInjection: true,
        discoveryState: 'idle',
        syncState: 'idle',
        discoveredSkillCount: 0,
        discoveredMcpCount: 0,
        managedMcpCount: 0,
        detail: '',
      ),
      ManagedMountTargetState(
        targetId: 'openclaw',
        label: 'OpenClaw',
        available: false,
        supportsSkills: true,
        supportsMcp: false,
        supportsAiGatewayInjection: true,
        discoveryState: 'idle',
        syncState: 'idle',
        discoveredSkillCount: 0,
        discoveredMcpCount: 0,
        managedMcpCount: 0,
        detail: '',
      ),
    ];
  }
}

/// 多 Agent 协作配置
class MultiAgentConfig {
  const MultiAgentConfig({
    required this.enabled,
    required this.autoSync,
    required this.framework,
    required this.arisEnabled,
    required this.arisMode,
    required this.arisBundleVersion,
    required this.arisCompatStatus,
    required this.architect,
    required this.engineer,
    required this.tester,
    required this.ollamaEndpoint,
    required this.maxIterations,
    required this.minAcceptableScore,
    required this.timeoutSeconds,
    required this.aiGatewayInjectionPolicy,
    required this.managedSkills,
    required this.managedMcpServers,
    required this.mountTargets,
  });

  final bool enabled;
  final bool autoSync;
  final MultiAgentFramework framework;
  final bool arisEnabled;
  final String arisMode;
  final String arisBundleVersion;
  final String arisCompatStatus;
  final AgentWorkerConfig architect;
  final AgentWorkerConfig engineer;
  final AgentWorkerConfig tester;
  final String ollamaEndpoint;
  final int maxIterations;
  final int minAcceptableScore;
  final int timeoutSeconds;
  final AiGatewayInjectionPolicy aiGatewayInjectionPolicy;
  final List<ManagedSkillEntry> managedSkills;
  final List<ManagedMcpServerEntry> managedMcpServers;
  final List<ManagedMountTargetState> mountTargets;

  /// Architect 配置的便捷访问
  bool get architectEnabled => architect.enabled;
  String get architectTool => architect.cliTool;
  String get architectModel => architect.model;

  /// Engineer 配置的便捷访问
  String get engineerTool => engineer.cliTool;
  String get engineerModel => engineer.model;

  /// Tester 配置的便捷访问
  String get testerTool => tester.cliTool;
  String get testerModel => tester.model;

  bool get usesAris => arisEnabled || framework == MultiAgentFramework.aris;

  factory MultiAgentConfig.defaults() {
    return MultiAgentConfig(
      enabled: false,
      autoSync: true,
      framework: MultiAgentFramework.native,
      arisEnabled: false,
      arisMode: 'full',
      arisBundleVersion: '',
      arisCompatStatus: 'idle',
      architect: const AgentWorkerConfig(
        role: MultiAgentRole.architect,
        cliTool: 'claude',
        model: 'kimi-k2.5:cloud',
        enabled: true,
      ),
      engineer: const AgentWorkerConfig(
        role: MultiAgentRole.engineer,
        cliTool: 'codex',
        model: 'minimax-m2.7:cloud',
        enabled: true,
      ),
      tester: const AgentWorkerConfig(
        role: MultiAgentRole.testerDoc,
        cliTool: 'opencode',
        model: 'glm-5:cloud',
        enabled: true,
      ),
      ollamaEndpoint: 'http://127.0.0.1:11434',
      maxIterations: 3,
      minAcceptableScore: 7,
      timeoutSeconds: 120,
      aiGatewayInjectionPolicy: AiGatewayInjectionPolicy.appManagedDefault,
      managedSkills: const <ManagedSkillEntry>[],
      managedMcpServers: const <ManagedMcpServerEntry>[],
      mountTargets: const <ManagedMountTargetState>[
        ManagedMountTargetState(
          targetId: 'aris',
          label: 'ARIS',
          available: false,
          supportsSkills: true,
          supportsMcp: true,
          supportsAiGatewayInjection: false,
          discoveryState: 'idle',
          syncState: 'idle',
          discoveredSkillCount: 0,
          discoveredMcpCount: 0,
          managedMcpCount: 0,
          detail: '',
        ),
        ManagedMountTargetState(
          targetId: 'codex',
          label: 'Codex',
          available: false,
          supportsSkills: true,
          supportsMcp: true,
          supportsAiGatewayInjection: true,
          discoveryState: 'idle',
          syncState: 'idle',
          discoveredSkillCount: 0,
          discoveredMcpCount: 0,
          managedMcpCount: 0,
          detail: '',
        ),
        ManagedMountTargetState(
          targetId: 'claude',
          label: 'Claude',
          available: false,
          supportsSkills: true,
          supportsMcp: true,
          supportsAiGatewayInjection: true,
          discoveryState: 'idle',
          syncState: 'idle',
          discoveredSkillCount: 0,
          discoveredMcpCount: 0,
          managedMcpCount: 0,
          detail: '',
        ),
        ManagedMountTargetState(
          targetId: 'gemini',
          label: 'Gemini',
          available: false,
          supportsSkills: true,
          supportsMcp: true,
          supportsAiGatewayInjection: true,
          discoveryState: 'idle',
          syncState: 'idle',
          discoveredSkillCount: 0,
          discoveredMcpCount: 0,
          managedMcpCount: 0,
          detail: '',
        ),
        ManagedMountTargetState(
          targetId: 'opencode',
          label: 'OpenCode',
          available: false,
          supportsSkills: true,
          supportsMcp: true,
          supportsAiGatewayInjection: true,
          discoveryState: 'idle',
          syncState: 'idle',
          discoveredSkillCount: 0,
          discoveredMcpCount: 0,
          managedMcpCount: 0,
          detail: '',
        ),
        ManagedMountTargetState(
          targetId: 'openclaw',
          label: 'OpenClaw',
          available: false,
          supportsSkills: true,
          supportsMcp: false,
          supportsAiGatewayInjection: true,
          discoveryState: 'idle',
          syncState: 'idle',
          discoveredSkillCount: 0,
          discoveredMcpCount: 0,
          managedMcpCount: 0,
          detail: '',
        ),
      ],
    );
  }

  MultiAgentConfig copyWith({
    bool? enabled,
    bool? autoSync,
    MultiAgentFramework? framework,
    bool? arisEnabled,
    String? arisMode,
    String? arisBundleVersion,
    String? arisCompatStatus,
    AgentWorkerConfig? architect,
    AgentWorkerConfig? engineer,
    AgentWorkerConfig? tester,
    String? ollamaEndpoint,
    int? maxIterations,
    int? minAcceptableScore,
    int? timeoutSeconds,
    AiGatewayInjectionPolicy? aiGatewayInjectionPolicy,
    List<ManagedSkillEntry>? managedSkills,
    List<ManagedMcpServerEntry>? managedMcpServers,
    List<ManagedMountTargetState>? mountTargets,
  }) {
    return MultiAgentConfig(
      enabled: enabled ?? this.enabled,
      autoSync: autoSync ?? this.autoSync,
      framework: framework ?? this.framework,
      arisEnabled: arisEnabled ?? this.arisEnabled,
      arisMode: arisMode ?? this.arisMode,
      arisBundleVersion: arisBundleVersion ?? this.arisBundleVersion,
      arisCompatStatus: arisCompatStatus ?? this.arisCompatStatus,
      architect: architect ?? this.architect,
      engineer: engineer ?? this.engineer,
      tester: tester ?? this.tester,
      ollamaEndpoint: ollamaEndpoint ?? this.ollamaEndpoint,
      maxIterations: maxIterations ?? this.maxIterations,
      minAcceptableScore: minAcceptableScore ?? this.minAcceptableScore,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      aiGatewayInjectionPolicy:
          aiGatewayInjectionPolicy ?? this.aiGatewayInjectionPolicy,
      managedSkills: managedSkills ?? this.managedSkills,
      managedMcpServers: managedMcpServers ?? this.managedMcpServers,
      mountTargets: mountTargets ?? this.mountTargets,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'autoSync': autoSync,
      'framework': framework.name,
      'arisEnabled': arisEnabled,
      'arisMode': arisMode,
      'arisBundleVersion': arisBundleVersion,
      'arisCompatStatus': arisCompatStatus,
      'architect': {
        'role': architect.role.name,
        'cliTool': architect.cliTool,
        'model': architect.model,
        'enabled': architect.enabled,
        'maxRetries': architect.maxRetries,
      },
      'engineer': {
        'role': engineer.role.name,
        'cliTool': engineer.cliTool,
        'model': engineer.model,
        'enabled': engineer.enabled,
        'maxRetries': engineer.maxRetries,
      },
      'tester': {
        'role': tester.role.name,
        'cliTool': tester.cliTool,
        'model': tester.model,
        'enabled': tester.enabled,
        'maxRetries': tester.maxRetries,
      },
      'ollamaEndpoint': ollamaEndpoint,
      'maxIterations': maxIterations,
      'minAcceptableScore': minAcceptableScore,
      'timeoutSeconds': timeoutSeconds,
      'aiGatewayInjectionPolicy': aiGatewayInjectionPolicy.name,
      'managedSkills': managedSkills.map((item) => item.toJson()).toList(),
      'managedMcpServers': managedMcpServers
          .map((item) => item.toJson())
          .toList(),
      'mountTargets': mountTargets.map((item) => item.toJson()).toList(),
    };
  }

  factory MultiAgentConfig.fromJson(Map<String, dynamic> json) {
    final defaults = MultiAgentConfig.defaults();
    final architectJson = json['architect'] as Map<String, dynamic>? ?? {};
    final engineerJson = json['engineer'] as Map<String, dynamic>? ?? {};
    final testerJson = json['tester'] as Map<String, dynamic>? ?? {};
    final rawManagedSkills = json['managedSkills'];
    final rawManagedMcpServers = json['managedMcpServers'];
    final rawMountTargets = json['mountTargets'];

    AgentWorkerConfig parseWorker(
      Map<String, dynamic> m,
      MultiAgentRole role,
      String defaultTool,
    ) {
      return AgentWorkerConfig(
        role: role,
        cliTool: m['cliTool'] as String? ?? defaultTool,
        model: m['model'] as String? ?? '',
        enabled: m['enabled'] as bool? ?? true,
        maxRetries: m['maxRetries'] as int? ?? 2,
      );
    }

    return MultiAgentConfig(
      enabled: json['enabled'] as bool? ?? false,
      autoSync: json['autoSync'] as bool? ?? defaults.autoSync,
      framework: MultiAgentFrameworkCopy.fromJsonValue(
        json['framework'] as String?,
      ),
      arisEnabled: json['arisEnabled'] as bool? ?? defaults.arisEnabled,
      arisMode: json['arisMode'] as String? ?? defaults.arisMode,
      arisBundleVersion:
          json['arisBundleVersion'] as String? ?? defaults.arisBundleVersion,
      arisCompatStatus:
          json['arisCompatStatus'] as String? ?? defaults.arisCompatStatus,
      architect: parseWorker(
        architectJson,
        MultiAgentRole.architect,
        defaults.architect.cliTool,
      ),
      engineer: parseWorker(
        engineerJson,
        MultiAgentRole.engineer,
        defaults.engineer.cliTool,
      ),
      tester: parseWorker(
        testerJson,
        MultiAgentRole.testerDoc,
        defaults.tester.cliTool,
      ),
      ollamaEndpoint:
          json['ollamaEndpoint'] as String? ?? defaults.ollamaEndpoint,
      maxIterations: json['maxIterations'] as int? ?? defaults.maxIterations,
      minAcceptableScore:
          json['minAcceptableScore'] as int? ?? defaults.minAcceptableScore,
      timeoutSeconds: json['timeoutSeconds'] as int? ?? defaults.timeoutSeconds,
      aiGatewayInjectionPolicy: AiGatewayInjectionPolicyCopy.fromJsonValue(
        json['aiGatewayInjectionPolicy'] as String?,
      ),
      managedSkills: rawManagedSkills is List
          ? rawManagedSkills
                .whereType<Map>()
                .map(
                  (item) =>
                      ManagedSkillEntry.fromJson(item.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : defaults.managedSkills,
      managedMcpServers: rawManagedMcpServers is List
          ? rawManagedMcpServers
                .whereType<Map>()
                .map(
                  (item) => ManagedMcpServerEntry.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : defaults.managedMcpServers,
      mountTargets: rawMountTargets is List
          ? rawMountTargets
                .whereType<Map>()
                .map(
                  (item) => ManagedMountTargetState.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : defaults.mountTargets,
    );
  }
}

class MultiAgentRunEvent {
  const MultiAgentRunEvent({
    required this.type,
    required this.title,
    required this.message,
    required this.pending,
    required this.error,
    this.role,
    this.iteration,
    this.score,
    this.data = const <String, dynamic>{},
  });

  final String type;
  final String title;
  final String message;
  final bool pending;
  final bool error;
  final String? role;
  final int? iteration;
  final int? score;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'title': title,
      'message': message,
      'pending': pending,
      'error': error,
      if (role != null) 'role': role,
      if (iteration != null) 'iteration': iteration,
      if (score != null) 'score': score,
      'data': data,
    };
  }

  factory MultiAgentRunEvent.fromJson(Map<String, dynamic> json) {
    return MultiAgentRunEvent(
      type: json['type'] as String? ?? 'status',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      pending: json['pending'] as bool? ?? false,
      error: json['error'] as bool? ?? false,
      role: json['role'] as String?,
      iteration: (json['iteration'] as num?)?.toInt(),
      score: (json['score'] as num?)?.toInt(),
      data:
          (json['data'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }
}
