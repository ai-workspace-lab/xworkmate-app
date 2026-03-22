@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_bootstrap.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'RuntimeBootstrapConfig loads gateway prefill targets from .env',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'xworkmate-bootstrap-',
      );
      addTearDown(() async {
        Directory.current = tempDir.parent;
        await tempDir.delete(recursive: true);
      });

      await File(
        '${tempDir.path}/pubspec.yaml',
      ).writeAsString('name: xworkmate_test\n');
      await Directory('${tempDir.path}/lib').create(recursive: true);
      await File(
        '${tempDir.path}/lib/main.dart',
      ).writeAsString('void main() {}\n');
      await File('${tempDir.path}/.env').writeAsString('''
local: http://127.0.0.1:18789/
local-token: local-test-token
remote: wss://openclaw.example.com:443
remote-token: remote-test-token
''');

      Directory.current = tempDir;

      final config = await RuntimeBootstrapConfig.load();

      expect(config.localGateway, isNotNull);
      expect(config.remoteGateway, isNotNull);
      expect(config.localGateway!.mode, RuntimeConnectionMode.local);
      expect(config.localGateway!.host, '127.0.0.1');
      expect(config.localGateway!.token, 'local-test-token');
      expect(config.remoteGateway!.mode, RuntimeConnectionMode.remote);
      expect(config.remoteGateway!.host, 'openclaw.example.com');
      expect(config.remoteGateway!.token, 'remote-test-token');
      expect(
        config.preferredGatewayFor(RuntimeConnectionMode.remote)?.host,
        'openclaw.example.com',
      );
    },
  );

  test(
    'RuntimeBootstrapConfig resolves .env from workspace path hints outside the repo cwd',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'xworkmate-bootstrap-hint-',
      );
      final outsideDir = await Directory.systemTemp.createTemp(
        'xworkmate-bootstrap-outside-',
      );
      addTearDown(() async {
        Directory.current = outsideDir.parent;
        await tempDir.delete(recursive: true);
        await outsideDir.delete(recursive: true);
      });

      await File(
        '${tempDir.path}/pubspec.yaml',
      ).writeAsString('name: xworkmate_test\n');
      await Directory('${tempDir.path}/lib').create(recursive: true);
      await File(
        '${tempDir.path}/lib/main.dart',
      ).writeAsString('void main() {}\n');
      await File('${tempDir.path}/.env').writeAsString('''
remote: wss://openclaw.example.com:443
remote-token: remote-test-token
''');

      Directory.current = outsideDir;

      final config = await RuntimeBootstrapConfig.load(
        workspacePathHint: tempDir.path,
      );

      expect(config.remoteGateway, isNotNull);
      expect(config.remoteGateway!.host, 'openclaw.example.com');
      expect(config.remoteGateway!.token, 'remote-test-token');
      expect(config.workspacePath, tempDir.path);
    },
  );
}
