// ignore_for_file: unused_import, unnecessary_import

import 'dart:convert';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import 'runtime_models_connection.dart';
import 'runtime_models_profiles.dart';
import 'runtime_models_configs.dart';
import 'runtime_models_settings_snapshot.dart';
import 'runtime_models_runtime_payloads.dart';
import 'runtime_models_gateway_entities.dart';

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
