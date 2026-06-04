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
