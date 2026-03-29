@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/aris_bundle.dart';
import 'package:xworkmate/runtime/go_core.dart';
import 'package:xworkmate/runtime/codex_config_bridge.dart';
import 'package:xworkmate/runtime/multi_agent_mount_resolver.dart';
import 'package:xworkmate/runtime/multi_agent_mounts.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test('ArisMountAdapter reports error when bundle is unavailable', () async {
    final adapter = ArisMountAdapter(
      _ThrowingArisBundleRepository(),
      GoCoreLocator(binaryExistsResolver: (_) async => false),
    );

    final state = await adapter.reconcile(
      config: MultiAgentConfig.defaults().copyWith(
        framework: MultiAgentFramework.aris,
        arisEnabled: true,
      ),
      aiGatewayUrl: '',
    );

    expect(state.available, isFalse);
    expect(state.discoveryState, 'error');
    expect(state.syncState, 'error');
  });

  test(
    'ArisMountAdapter reports embedded state when bundle exists but bridge is unavailable',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'aris-mount-embedded-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final bundle = await _writeFakeBundle(tempDir);
      final adapter = ArisMountAdapter(
        _FixedArisBundleRepository(bundle),
        GoCoreLocator(
          workspaceRoot: tempDir.path,
          binaryExistsResolver: (_) async => false,
        ),
      );

      final state = await adapter.reconcile(
        config: MultiAgentConfig.defaults().copyWith(
          framework: MultiAgentFramework.aris,
          arisEnabled: true,
        ),
        aiGatewayUrl: '',
      );

      expect(state.available, isTrue);
      expect(state.discoveryState, 'ready');
      expect(state.syncState, 'embedded');
      expect(state.discoveredMcpCount, 1);
      expect(state.managedMcpCount, 0);
      expect(state.detail, contains('Go core is not available'));
    },
  );

  test(
    'ArisMountAdapter reports ready when bundle and bundled helper are both available',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'aris-mount-ready-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final bundle = await _writeFakeBundle(tempDir);
      final helperDir = Directory(
        '${tempDir.path}/XWorkmate.app/Contents/Helpers',
      );
      await helperDir.create(recursive: true);
      final helper = File('${helperDir.path}/xworkmate-go-core');
      await helper.writeAsString('#!/bin/sh\nexit 0\n');
      await Process.run('chmod', <String>['+x', helper.path]);
      final locator = GoCoreLocator(
        workspaceRoot: tempDir.path,
        binaryExistsResolver: (_) async => false,
        resolvedExecutableResolver: () =>
            '${tempDir.path}/XWorkmate.app/Contents/MacOS/XWorkmate',
      );
      final adapter = ArisMountAdapter(
        _FixedArisBundleRepository(bundle),
        locator,
      );

      final state = await adapter.reconcile(
        config: MultiAgentConfig.defaults().copyWith(
          framework: MultiAgentFramework.aris,
          arisEnabled: true,
        ),
        aiGatewayUrl: '',
      );

      expect(state.available, isTrue);
      expect(state.discoveryState, 'ready');
      expect(state.syncState, 'ready');
      expect(state.managedMcpCount, 1);
      expect(state.detail, contains('manages llm-chat and claude-review'));
    },
  );

  test('CodexMountAdapter marks configured codex path as available', () async {
    final tempDir = await Directory.systemTemp.createTemp('codex-mount-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final configuredBinary = File('${tempDir.path}/custom-codex');
    await configuredBinary.writeAsString('#!/bin/sh\nexit 0\n');
    await Process.run('chmod', <String>['+x', configuredBinary.path]);
    final adapter = CodexMountAdapter(
      CodexConfigBridge(codexHome: '${tempDir.path}/codex-home'),
    );

    final state = await adapter.reconcile(
      config: MultiAgentConfig.defaults().copyWith(autoSync: false),
      aiGatewayUrl: '',
      configuredCodexCliPath: configuredBinary.path,
    );

    expect(state.available, isTrue);
    expect(state.discoveryState, 'ready');
    expect(state.syncState, 'disabled');
  });

  test('MultiAgentMountManager uses resolver result when attached', () async {
    final manager = MultiAgentMountManager(
      resolver: _FakeMountResolver(
        config: MultiAgentConfig.defaults().copyWith(
          arisBundleVersion: 'bundle-v1',
          arisCompatStatus: 'ready',
          mountTargets: const <ManagedMountTargetState>[
            ManagedMountTargetState(
              targetId: 'codex',
              label: 'Codex',
              available: true,
              supportsSkills: true,
              supportsMcp: true,
              supportsAiGatewayInjection: true,
              discoveryState: 'ready',
              syncState: 'ready',
              discoveredSkillCount: 0,
              discoveredMcpCount: 2,
              managedMcpCount: 1,
              detail: 'resolver-backed',
            ),
          ],
        ),
      ),
    );
    addTearDown(manager.dispose);

    final resolved = await manager.reconcile(
      config: MultiAgentConfig.defaults(),
      aiGatewayUrl: 'https://gateway.example.com',
    );

    expect(resolved.arisBundleVersion, 'bundle-v1');
    expect(resolved.arisCompatStatus, 'ready');
    expect(resolved.mountTargets, hasLength(1));
    expect(resolved.mountTargets.single.detail, 'resolver-backed');
  });
}

Future<ResolvedArisBundle> _writeFakeBundle(Directory root) async {
  final skillsDir = Directory('${root.path}/skills/idea-discovery');
  await skillsDir.create(recursive: true);
  await File('${skillsDir.path}/SKILL.md').writeAsString('# idea\n');
  await File('${root.path}/mcp-server.py').writeAsString('print("ok")\n');
  await File('${root.path}/requirements.txt').writeAsString('httpx\n');
  return ResolvedArisBundle(
    rootPath: root.path,
    manifest: ArisBundleManifest(
      schemaVersion: 1,
      name: 'ARIS',
      bundleVersion: 'test',
      upstreamRepository: 'https://example.com/aris',
      upstreamCommit: 'abc123',
      llmChatServerPath: 'mcp-server.py',
      llmChatRequirementsPath: 'requirements.txt',
      roleSkills: const <MultiAgentRole, List<String>>{
        MultiAgentRole.architect: <String>['skills/idea-discovery/SKILL.md'],
        MultiAgentRole.engineer: <String>[],
        MultiAgentRole.testerDoc: <String>[],
      },
      codexRoleSkills: const <MultiAgentRole, List<String>>{
        MultiAgentRole.architect: <String>[],
        MultiAgentRole.engineer: <String>[],
        MultiAgentRole.testerDoc: <String>[],
      },
    ),
  );
}

class _FixedArisBundleRepository extends ArisBundleRepository {
  _FixedArisBundleRepository(this._bundle);

  final ResolvedArisBundle _bundle;

  @override
  Future<ResolvedArisBundle> ensureReady() async => _bundle;

  @override
  Future<int> countSkillFiles() async => 1;
}

class _ThrowingArisBundleRepository extends ArisBundleRepository {
  @override
  Future<ResolvedArisBundle> ensureReady() async {
    throw StateError('missing bundle');
  }
}

class _FakeMountResolver implements MultiAgentMountResolver {
  _FakeMountResolver({required this.config});

  final MultiAgentConfig config;

  @override
  Future<MultiAgentConfig?> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
    String configuredCodexCliPath = '',
    required String codexHome,
    required String opencodeHome,
    required ArisMountProbe arisProbe,
  }) async => this.config;

  @override
  Future<void> dispose() async {}
}
