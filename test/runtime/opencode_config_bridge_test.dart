import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/opencode_config_bridge.dart';

void main() {
  group('OpencodeConfigBridge', () {
    late Directory tempDir;
    late OpencodeConfigBridge bridge;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'opencode-config-bridge-',
      );
      bridge = OpencodeConfigBridge(opencodeHome: tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('configureManagedMcpServers preserves user config', () async {
      final configFile = File('${tempDir.path}/config.toml');
      await configFile.writeAsString('''
[model]
name = "user-default"

[mcp_servers.user_server]
type = "stdio"
command = "user-mcp"
''');

      await bridge.configureManagedMcpServers(
        servers: const <OpencodeMcpServer>[
          OpencodeMcpServer(
            name: 'xworkmate_server',
            command: 'xworkmate-mcp',
            args: <String>['--stdio'],
          ),
        ],
      );

      final content = await configFile.readAsString();
      expect(content, contains('[model]'));
      expect(content, contains('name = "user-default"'));
      expect(content, contains('[mcp_servers.user_server]'));
      expect(content, contains('[mcp_servers.xworkmate_server]'));
      expect(content, contains('# BEGIN XWORKMATE MANAGED MCP BLOCK'));
    });

    test(
      'configureManagedMcpServers updates managed block without duplication',
      () async {
        await bridge.configureManagedMcpServers(
          servers: const <OpencodeMcpServer>[
            OpencodeMcpServer(
              name: 'xworkmate_server',
              command: 'xworkmate-mcp',
              args: <String>['--port', '3000'],
            ),
          ],
        );
        await bridge.configureManagedMcpServers(
          servers: const <OpencodeMcpServer>[
            OpencodeMcpServer(
              name: 'xworkmate_server',
              command: 'xworkmate-mcp',
              args: <String>['--port', '3001'],
            ),
          ],
        );

        final content = await bridge.readConfig();
        expect(
          '# BEGIN XWORKMATE MANAGED MCP BLOCK'.allMatches(content).length,
          1,
        );
        expect(content, contains('"3001"'));
        expect(content, isNot(contains('"3000"')));
      },
    );
  });
}
