import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/aris_bundle.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'ArisBundleRepository extracts embedded bundle into app support path',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-aris-bundle-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final manifest = jsonEncode(<String, dynamic>{
        'schemaVersion': 1,
        'name': 'ARIS',
        'bundleVersion': 'test-bundle',
        'upstreamRepository': 'https://example.com/aris',
        'upstreamCommit': 'abc123',
        'llmChatServerPath': 'mcp-servers/llm-chat/server.py',
        'llmChatRequirementsPath': 'mcp-servers/llm-chat/requirements.txt',
        'roleSkills': <String, Object>{
          'architect': <String>['skills/idea-discovery/SKILL.md'],
        },
        'codexRoleSkills': <String, Object>{
          'architect': <String>['skills/skills-codex/idea-discovery/SKILL.md'],
        },
      });
      final bundle = _MapAssetBundle(<String, String>{
        'assets/aris/manifest.json': manifest,
        'assets/aris/mcp-servers/llm-chat/server.py': 'print("ok")\n',
        'assets/aris/mcp-servers/llm-chat/requirements.txt': 'httpx\n',
        'assets/aris/skills/idea-discovery/SKILL.md': '# idea\n',
        'assets/aris/skills/skills-codex/idea-discovery/SKILL.md': '# codex\n',
        'assets/aris/skills/research-pipeline/SKILL.md': '# unrelated\n',
      });
      final repository = ArisBundleRepository(
        assetBundle: bundle,
        rootPathResolver: () async => '${tempDirectory.path}/bundle',
        assetKeysResolver: () async => bundle.keys.toList(growable: false),
      );

      final resolved = await repository.ensureReady();

      expect(resolved.manifest.name, 'ARIS');
      expect(resolved.manifest.upstreamCommit, 'abc123');
      expect(await File(resolved.llmChatServerPath).exists(), isTrue);
      expect(resolved.skillPathsForRole(MultiAgentRole.architect), isNotEmpty);
      expect(await repository.countSkillFiles(), 2);
      expect(
        await File(
          '${resolved.rootPath}/skills/research-pipeline/SKILL.md',
        ).exists(),
        isFalse,
      );
    },
  );
}

class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(this._assets);

  final Map<String, String> _assets;

  Iterable<String> get keys => _assets.keys;

  @override
  Future<ByteData> load(String key) async {
    final content = _assets[key];
    if (content == null) {
      throw StateError('Missing asset: $key');
    }
    final bytes = Uint8List.fromList(utf8.encode(content));
    return ByteData.sublistView(bytes);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final content = _assets[key];
    if (content == null) {
      throw StateError('Missing asset: $key');
    }
    return content;
  }
}
