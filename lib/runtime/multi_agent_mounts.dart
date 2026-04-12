import 'dart:convert';
import 'dart:io';

import 'aris_bundle.dart';
import 'go_core.dart';
import 'codex_config_bridge.dart';
import 'multi_agent_mount_resolver.dart';
import 'opencode_config_bridge.dart';
import 'runtime_models.dart';

class MultiAgentMountManager {
  MultiAgentMountManager({
    CodexConfigBridge? codexConfigBridge,
    OpencodeConfigBridge? opencodeConfigBridge,
    ArisBundleRepository? arisBundleRepository,
    GoCoreLocator? goCoreLocator,
    MultiAgentMountResolver? resolver,
  }) : this._(
         arisAdapter: ArisMountAdapter(
           arisBundleRepository ?? ArisBundleRepository(),
           goCoreLocator ?? GoCoreLocator(),
         ),
         codexConfigBridge: codexConfigBridge ?? CodexConfigBridge(),
         opencodeConfigBridge: opencodeConfigBridge ?? OpencodeConfigBridge(),
         resolver: resolver,
       );

  MultiAgentMountManager._({
    required ArisMountAdapter arisAdapter,
    required CodexConfigBridge codexConfigBridge,
    required OpencodeConfigBridge opencodeConfigBridge,
    MultiAgentMountResolver? resolver,
  }) : _arisAdapter = arisAdapter,
       _codexConfigBridge = codexConfigBridge,
       _opencodeConfigBridge = opencodeConfigBridge,
       _resolver = resolver,
       _adapters = <CliMountAdapter>[
         arisAdapter,
         CodexMountAdapter(codexConfigBridge),
         ClaudeMountAdapter(),
         GeminiMountAdapter(),
         OpencodeMountAdapter(opencodeConfigBridge),
         OpenClawMountAdapter(),
       ];

  final ArisMountAdapter _arisAdapter;
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
    return _reconcileLocally(
      config: config,
      aiGatewayUrl: aiGatewayUrl,
    );
  }

  Future<void> dispose() async {
    await _resolver?.dispose();
  }

  Future<ArisMountProbe> _buildArisProbe() async {
    try {
      final bundle = await _arisAdapter._bundleRepository.ensureReady();
      return ArisMountProbe(
        available: true,
        bundleVersion: bundle.manifest.bundleVersion,
        llmChatServerPath: bundle.manifest.llmChatServerPath.trim(),
        skillCount: await _arisAdapter._bundleRepository.countSkillFiles(),
        bridgeAvailable: await _arisAdapter._goCoreLocator.isAvailable(),
      );
    } catch (error) {
      return ArisMountProbe.unavailable(error: error.toString());
    }
  }

  Future<MultiAgentConfig> _reconcileLocally({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    final states = <ManagedMountTargetState>[];
    for (final adapter in _adapters) {
      try {
        states.add(
          await adapter.reconcile(
            config: config,
            aiGatewayUrl: aiGatewayUrl,
          ),
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
    final arisState = states.firstWhere(
      (item) => item.targetId == _arisAdapter.targetId,
      orElse: () => ManagedMountTargetState.placeholder(
        targetId: _arisAdapter.targetId,
        label: _arisAdapter.label,
        supportsSkills: _arisAdapter.supportsSkills,
        supportsMcp: _arisAdapter.supportsMcp,
        supportsAiGatewayInjection: _arisAdapter.supportsAiGatewayInjection,
      ),
    );
    return config.copyWith(
      mountTargets: states,
      arisBundleVersion: _arisAdapter.lastBundleVersion,
      arisCompatStatus: arisState.syncState,
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

  int countMcpTomlSections(String content) {
    return RegExp(
      r'^\[mcp_servers\.[^\]]+\]',
      multiLine: true,
    ).allMatches(content).length;
  }
}

class ArisMountAdapter extends CliMountAdapter {
  ArisMountAdapter(this._bundleRepository, this._goCoreLocator);

  final ArisBundleRepository _bundleRepository;
  final GoCoreLocator _goCoreLocator;
  String _lastBundleVersion = '';

  String get lastBundleVersion => _lastBundleVersion;

  @override
  String get targetId => 'aris';

  @override
  String get label => 'ARIS';

  @override
  bool get supportsSkills => true;

  @override
  bool get supportsMcp => true;

  @override
  bool get supportsAiGatewayInjection => false;

  @override
  Future<bool> isInstalled() async {
    try {
      await _bundleRepository.loadManifest();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ManagedMountTargetState> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
  }) async {
    try {
      final bundle = await _bundleRepository.ensureReady();
      _lastBundleVersion = bundle.manifest.bundleVersion;
      final skillCount = await _bundleRepository.countSkillFiles();
      final bridgeAvailable = await _goCoreLocator.isAvailable();
      final llmChatEntry = bundle.manifest.llmChatServerPath.trim();
      final llmChatReady = llmChatEntry.isNotEmpty;
      return ManagedMountTargetState.placeholder(
        targetId: targetId,
        label: label,
        supportsSkills: supportsSkills,
        supportsMcp: supportsMcp,
        supportsAiGatewayInjection: supportsAiGatewayInjection,
      ).copyWith(
        available: true,
        discoveryState: 'ready',
        syncState: config.usesAris && llmChatReady && bridgeAvailable
            ? 'ready'
            : 'embedded',
        discoveredSkillCount: skillCount,
        discoveredMcpCount: llmChatReady ? 1 : 0,
        managedMcpCount: config.usesAris && llmChatReady && bridgeAvailable
            ? 1
            : 0,
        detail: llmChatReady
            ? bridgeAvailable
                  ? 'Embedded bundle ${bundle.manifest.bundleVersion} ready; XWorkmate Go core manages llm-chat and claude-review.'
                  : 'Embedded bundle is ready, but the XWorkmate Go core is not available yet.'
            : 'Embedded bundle extracted, but llm-chat metadata is missing.',
      );
    } catch (error) {
      return ManagedMountTargetState.placeholder(
        targetId: targetId,
        label: label,
        supportsSkills: supportsSkills,
        supportsMcp: supportsMcp,
        supportsAiGatewayInjection: supportsAiGatewayInjection,
      ).copyWith(
        available: false,
        discoveryState: 'error',
        syncState: 'error',
        detail: error.toString(),
      );
    }
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
  Future<bool> isInstalled() async => false;

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
          ? 'LLM API uses launch-scoped defaults for collaboration runs.'
          : 'LLM API not configured.',
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
          'MCP discovery uses `claude mcp list`; LLM API stays launch-scoped.',
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
          'MCP discovery uses `gemini mcp list`; LLM API stays launch-scoped.',
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
  Future<bool> isInstalled() async => false;

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
  Future<bool> isInstalled() async => false;

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
