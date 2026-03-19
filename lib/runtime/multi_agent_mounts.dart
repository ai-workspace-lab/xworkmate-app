import 'dart:convert';
import 'dart:io';

import 'codex_config_bridge.dart';
import 'opencode_config_bridge.dart';
import 'runtime_models.dart';

class MultiAgentMountManager {
  MultiAgentMountManager({
    CodexConfigBridge? codexConfigBridge,
    OpencodeConfigBridge? opencodeConfigBridge,
  }) : _adapters = <CliMountAdapter>[
         CodexMountAdapter(codexConfigBridge ?? CodexConfigBridge()),
         ClaudeMountAdapter(),
         GeminiMountAdapter(),
         OpencodeMountAdapter(opencodeConfigBridge ?? OpencodeConfigBridge()),
         OpenClawMountAdapter(),
       ];

  final List<CliMountAdapter> _adapters;

  Future<MultiAgentConfig> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    final states = <ManagedMountTargetState>[];
    for (final adapter in _adapters) {
      try {
        states.add(
          await adapter.reconcile(config: config, aiGatewayUrl: aiGatewayUrl),
        );
      } catch (error) {
        states.add(
          ManagedMountTargetState.placeholder(
            targetId: adapter.targetId,
            label: adapter.label,
            supportsSkills: adapter.supportsSkills,
            supportsMcp: adapter.supportsMcp,
            supportsAiGatewayInjection: adapter.supportsAiGatewayInjection,
          ).copyWith(
            available: await adapter.isInstalled(),
            discoveryState: 'error',
            syncState: 'error',
            detail: error.toString(),
          ),
        );
      }
    }
    return config.copyWith(mountTargets: states);
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

  Future<String> _runCommand(List<String> command) async {
    final result = await Process.run(
      command.first,
      command.sublist(1),
      runInShell: true,
    );
    final stdout = '${result.stdout}'.trim();
    final stderr = '${result.stderr}'.trim();
    return stdout.isNotEmpty ? stdout : stderr;
  }

  Future<int> _countListedEntries(List<String> command) async {
    final output = await _runCommand(command);
    if (output.isEmpty ||
        output.contains('No MCP servers configured') ||
        output.contains('No MCP servers configured yet') ||
        output.contains('No MCP servers configured.')) {
      return 0;
    }
    return output
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .where((item) => !item.startsWith('Usage:'))
        .where((item) => !item.startsWith('┌'))
        .where((item) => !item.startsWith('│'))
        .where((item) => !item.startsWith('└'))
        .length;
  }

  Future<bool> _binaryExists(String command) async {
    final check = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      <String>[command],
      runInShell: true,
    );
    return check.exitCode == 0 && '${check.stdout}'.trim().isNotEmpty;
  }

  int countMcpTomlSections(String content) {
    return RegExp(
      r'^\[mcp_servers\.[^\]]+\]',
      multiLine: true,
    ).allMatches(content).length;
  }
}

class CodexMountAdapter extends CliMountAdapter {
  CodexMountAdapter(this._bridge);

  final CodexConfigBridge _bridge;

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
  Future<bool> isInstalled() => _binaryExists('codex');

  @override
  Future<ManagedMountTargetState> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    final available = await isInstalled();
    final configFile = File('${_bridge.codexHome}/config.toml');
    final content = await configFile.exists()
        ? await configFile.readAsString()
        : '';
    final discoveredMcpCount = countMcpTomlSections(content);
    final managedMcpServers = config.managedMcpServers
        .where((item) => item.enabled && item.command.trim().isNotEmpty)
        .toList(growable: false);
    if (available && config.autoSync && managedMcpServers.isNotEmpty) {
      await _bridge.configureManagedMcpServers(
        servers: managedMcpServers
            .map(
              (item) => CodexMcpServer(
                name: item.id,
                command: item.command,
                args: item.args,
              ),
            )
            .toList(growable: false),
      );
    }
    return ManagedMountTargetState.placeholder(
      targetId: targetId,
      label: label,
      supportsSkills: supportsSkills,
      supportsMcp: supportsMcp,
      supportsAiGatewayInjection: supportsAiGatewayInjection,
    ).copyWith(
      available: available,
      discoveryState: available ? 'ready' : 'missing',
      syncState: !available
          ? 'missing'
          : config.autoSync
          ? 'ready'
          : 'disabled',
      discoveredMcpCount: discoveredMcpCount,
      managedMcpCount: managedMcpServers.length,
      detail: aiGatewayUrl.isNotEmpty
          ? 'AI Gateway uses launch-scoped defaults for collaboration runs.'
          : 'AI Gateway not configured.',
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
  Future<bool> isInstalled() => _binaryExists('claude');

  @override
  Future<ManagedMountTargetState> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    final available = await isInstalled();
    final discoveredMcpCount = available
        ? await _countListedEntries(<String>['claude', 'mcp', 'list'])
        : 0;
    return ManagedMountTargetState.placeholder(
      targetId: targetId,
      label: label,
      supportsSkills: supportsSkills,
      supportsMcp: supportsMcp,
      supportsAiGatewayInjection: supportsAiGatewayInjection,
    ).copyWith(
      available: available,
      discoveryState: available ? 'ready' : 'missing',
      syncState: available && config.autoSync ? 'launch-only' : 'disabled',
      discoveredMcpCount: discoveredMcpCount,
      managedMcpCount: config.managedMcpServers
          .where((item) => item.enabled)
          .length,
      detail:
          'MCP discovery uses `claude mcp list`; AI Gateway stays launch-scoped.',
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
  Future<bool> isInstalled() => _binaryExists('gemini');

  @override
  Future<ManagedMountTargetState> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    final available = await isInstalled();
    final discoveredMcpCount = available
        ? await _countListedEntries(<String>['gemini', 'mcp', 'list'])
        : 0;
    return ManagedMountTargetState.placeholder(
      targetId: targetId,
      label: label,
      supportsSkills: supportsSkills,
      supportsMcp: supportsMcp,
      supportsAiGatewayInjection: supportsAiGatewayInjection,
    ).copyWith(
      available: available,
      discoveryState: available ? 'ready' : 'missing',
      syncState: available && config.autoSync ? 'launch-only' : 'disabled',
      discoveredMcpCount: discoveredMcpCount,
      managedMcpCount: config.managedMcpServers
          .where((item) => item.enabled)
          .length,
      detail:
          'MCP discovery uses `gemini mcp list`; AI Gateway stays launch-scoped.',
    );
  }
}

class OpencodeMountAdapter extends CliMountAdapter {
  OpencodeMountAdapter(this._bridge);

  final OpencodeConfigBridge _bridge;

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
  Future<bool> isInstalled() => _binaryExists('opencode');

  @override
  Future<ManagedMountTargetState> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    final available = await isInstalled();
    final content = await _bridge.readConfig();
    final discoveredMcpCount = countMcpTomlSections(content);
    final managedMcpServers = config.managedMcpServers
        .where((item) => item.enabled)
        .toList(growable: false);
    if (available && config.autoSync && managedMcpServers.isNotEmpty) {
      await _bridge.configureManagedMcpServers(
        servers: managedMcpServers
            .map(
              (item) => OpencodeMcpServer(
                name: item.id,
                command: item.command,
                url: item.url,
                args: item.args,
              ),
            )
            .toList(growable: false),
      );
    }
    return ManagedMountTargetState.placeholder(
      targetId: targetId,
      label: label,
      supportsSkills: supportsSkills,
      supportsMcp: supportsMcp,
      supportsAiGatewayInjection: supportsAiGatewayInjection,
    ).copyWith(
      available: available,
      discoveryState: available ? 'ready' : 'missing',
      syncState: !available
          ? 'missing'
          : config.autoSync
          ? 'ready'
          : 'disabled',
      discoveredMcpCount: discoveredMcpCount,
      managedMcpCount: managedMcpServers.length,
      detail: 'Managed MCP config is preserved in ~/.opencode/config.toml.',
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
  Future<bool> isInstalled() => _binaryExists('openclaw');

  @override
  Future<ManagedMountTargetState> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    final available = await isInstalled();
    final configFile = File(
      '${Platform.environment['HOME'] ?? ''}/.openclaw/openclaw.json',
    );
    var discoveredSkillCount = 0;
    var detail = 'OpenClaw acts as the host/control plane mount.';
    if (await configFile.exists()) {
      try {
        final decoded = jsonDecode(await configFile.readAsString());
        final agents =
            (decoded is Map<String, dynamic> &&
                decoded['agents'] is Map<String, dynamic> &&
                (decoded['agents'] as Map<String, dynamic>)['list'] is List)
            ? ((decoded['agents'] as Map<String, dynamic>)['list'] as List)
                  .length
            : 0;
        final skillsDir = Directory(
          '${Platform.environment['HOME'] ?? ''}/.openclaw/skills',
        );
        if (await skillsDir.exists()) {
          discoveredSkillCount = await skillsDir
              .list()
              .where((entity) => entity is File || entity is Directory)
              .length;
        }
        detail = 'agents: $agents · skills: $discoveredSkillCount';
      } catch (_) {
        detail = 'OpenClaw config detected but could not be fully parsed.';
      }
    }
    return ManagedMountTargetState.placeholder(
      targetId: targetId,
      label: label,
      supportsSkills: supportsSkills,
      supportsMcp: supportsMcp,
      supportsAiGatewayInjection: supportsAiGatewayInjection,
    ).copyWith(
      available: available,
      discoveryState: available ? 'ready' : 'missing',
      syncState: available && config.autoSync ? 'launch-only' : 'disabled',
      discoveredSkillCount: discoveredSkillCount,
      detail: detail,
    );
  }
}
