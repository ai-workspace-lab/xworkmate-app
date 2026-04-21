import 'codex_config_bridge.dart';
import 'multi_agent_mount_resolver.dart';
import 'opencode_config_bridge.dart';
import 'runtime_models.dart';

/// 协作模式挂载管理器
///
/// 在云中性设计下，挂载目标的发现与状态调和应通过桥接同步到远程端点。
class MultiAgentMountManager {
  MultiAgentMountManager({
    CodexConfigBridge? codexConfigBridge,
    OpencodeConfigBridge? opencodeConfigBridge,
    MultiAgentMountResolver? resolver,
  }) : this._(
         codexConfigBridge: codexConfigBridge ?? CodexConfigBridge(),
         opencodeConfigBridge: opencodeConfigBridge ?? OpencodeConfigBridge(),
         resolver: resolver,
       );

  MultiAgentMountManager._({
    required CodexConfigBridge codexConfigBridge,
    required OpencodeConfigBridge opencodeConfigBridge,
    MultiAgentMountResolver? resolver,
  }) : _codexConfigBridge = codexConfigBridge,
       _opencodeConfigBridge = opencodeConfigBridge,
       _resolver = resolver,
       _adapters = <CliMountAdapter>[
         CodexMountAdapter(codexConfigBridge),
         ClaudeMountAdapter(),
         GeminiMountAdapter(),
         OpencodeMountAdapter(opencodeConfigBridge),
         OpenClawMountAdapter(),
       ];

  final CodexConfigBridge _codexConfigBridge;
  final OpencodeConfigBridge _opencodeConfigBridge;
  final MultiAgentMountResolver? _resolver;
  final List<CliMountAdapter> _adapters;

  Future<MultiAgentConfig> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    final resolved = await _resolver?.reconcile(
      config: config,
      aiGatewayUrl: aiGatewayUrl,
      codexHome: _codexConfigBridge.codexHome,
      opencodeHome: _opencodeConfigBridge.opencodeHome,
      arisProbe: await _buildArisProbe(),
    );
    if (resolved != null) {
      return resolved;
    }
    return _reconcileLocally(config: config, aiGatewayUrl: aiGatewayUrl);
  }

  Future<void> dispose() async {
    await _resolver?.dispose();
  }

  Future<ArisMountProbe> _buildArisProbe() async {
    return const ArisMountProbe(
      available: false,
      bundleVersion: '',
      llmChatServerPath: '',
      skillCount: 0,
      bridgeAvailable: false,
      error: 'Legacy local agent execution is disabled.',
    );
  }

  Future<MultiAgentConfig> _reconcileLocally({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    final states = <ManagedMountTargetState>[];
    for (final adapter in _adapters) {
      states.add(
        await adapter.reconcile(config: config, aiGatewayUrl: aiGatewayUrl),
      );
    }
    return config.copyWith(
      mountTargets: states,
      arisBundleVersion: '',
      arisCompatStatus: 'missing',
    );
  }
}

abstract class CliMountAdapter {
  String get targetId;
  String get label;
  bool get supportsSkills;
  bool get supportsMcp;
  bool get supportsAiGatewayInjection;

  Future<bool> isInstalled();

  Future<ManagedMountTargetState> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  });

  int countMcpTomlSections(String content) {
    return RegExp(
      r'^\[mcp_servers\.[^\]]+\]',
      multiLine: true,
    ).allMatches(content).length;
  }
}

class CodexMountAdapter extends CliMountAdapter {
  CodexMountAdapter(CodexConfigBridge bridge);

  @override
  String get targetId => 'codex';

  @override
  String get label => 'Codex';

  @override
  bool get supportsSkills => true;

  @override
  bool get supportsMcp => true;

  @override
  bool get supportsAiGatewayInjection => true;

  @override
  Future<bool> isInstalled() async => false;

  @override
  Future<ManagedMountTargetState> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    return ManagedMountTargetState.placeholder(
      targetId: targetId,
      label: label,
      supportsSkills: supportsSkills,
      supportsMcp: supportsMcp,
      supportsAiGatewayInjection: supportsAiGatewayInjection,
    ).copyWith(
      available: false,
      discoveryState: 'missing',
      syncState: 'missing',
      detail:
          'Local CLI interaction is disabled. Use bridge for orchestration.',
    );
  }
}

class ClaudeMountAdapter extends CliMountAdapter {
  @override
  String get targetId => 'claude';

  @override
  String get label => 'Claude';

  @override
  bool get supportsSkills => true;

  @override
  bool get supportsMcp => true;

  @override
  bool get supportsAiGatewayInjection => true;

  @override
  Future<bool> isInstalled() async => false;

  @override
  Future<ManagedMountTargetState> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    return ManagedMountTargetState.placeholder(
      targetId: targetId,
      label: label,
      supportsSkills: supportsSkills,
      supportsMcp: supportsMcp,
      supportsAiGatewayInjection: supportsAiGatewayInjection,
    ).copyWith(
      available: false,
      discoveryState: 'missing',
      syncState: 'disabled',
      detail: 'Local CLI interaction is disabled.',
    );
  }
}

class GeminiMountAdapter extends CliMountAdapter {
  @override
  String get targetId => 'gemini';

  @override
  String get label => 'Gemini';

  @override
  bool get supportsSkills => true;

  @override
  bool get supportsMcp => true;

  @override
  bool get supportsAiGatewayInjection => true;

  @override
  Future<bool> isInstalled() async => false;

  @override
  Future<ManagedMountTargetState> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    return ManagedMountTargetState.placeholder(
      targetId: targetId,
      label: label,
      supportsSkills: supportsSkills,
      supportsMcp: supportsMcp,
      supportsAiGatewayInjection: supportsAiGatewayInjection,
    ).copyWith(
      available: false,
      discoveryState: 'missing',
      syncState: 'disabled',
      detail: 'Local CLI interaction is disabled.',
    );
  }
}

class OpencodeMountAdapter extends CliMountAdapter {
  OpencodeMountAdapter(OpencodeConfigBridge bridge);

  @override
  String get targetId => 'opencode';

  @override
  String get label => 'OpenCode';

  @override
  bool get supportsSkills => true;

  @override
  bool get supportsMcp => true;

  @override
  bool get supportsAiGatewayInjection => true;

  @override
  Future<bool> isInstalled() async => false;

  @override
  Future<ManagedMountTargetState> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    return ManagedMountTargetState.placeholder(
      targetId: targetId,
      label: label,
      supportsSkills: supportsSkills,
      supportsMcp: supportsMcp,
      supportsAiGatewayInjection: supportsAiGatewayInjection,
    ).copyWith(
      available: false,
      discoveryState: 'missing',
      syncState: 'missing',
      detail: 'Local CLI interaction is disabled.',
    );
  }
}

class OpenClawMountAdapter extends CliMountAdapter {
  @override
  String get targetId => 'openclaw';

  @override
  String get label => 'OpenClaw';

  @override
  bool get supportsSkills => true;

  @override
  bool get supportsMcp => false;

  @override
  bool get supportsAiGatewayInjection => true;

  @override
  Future<bool> isInstalled() async => false;

  @override
  Future<ManagedMountTargetState> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    return ManagedMountTargetState.placeholder(
      targetId: targetId,
      label: label,
      supportsSkills: supportsSkills,
      supportsMcp: supportsMcp,
      supportsAiGatewayInjection: supportsAiGatewayInjection,
    ).copyWith(
      available: false,
      discoveryState: 'missing',
      syncState: 'disabled',
      detail: 'Local CLI interaction is disabled.',
    );
  }
}
