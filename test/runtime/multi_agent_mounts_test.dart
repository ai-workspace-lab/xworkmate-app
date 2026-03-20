import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/aris_bundle.dart';
import 'package:xworkmate/runtime/aris_bridge.dart';
import 'package:xworkmate/runtime/multi_agent_mounts.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test('ArisMountAdapter reports error when bundle is unavailable', () async {
    final adapter = ArisMountAdapter(
      _ThrowingArisBundleRepository(),
      ArisBridgeLocator(binaryExistsResolver: (_) async => false),
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
        ArisBridgeLocator(
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
      expect(state.detail, contains('bridge is not available'));
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
      final helper = File('${helperDir.path}/xworkmate-aris-bridge');
      await helper.writeAsString('#!/bin/sh\nexit 0\n');
      await Process.run('chmod', <String>['+x', helper.path]);
      final locator = ArisBridgeLocator(
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
