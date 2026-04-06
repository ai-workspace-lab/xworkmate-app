@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Desktop ACP guard', () {
    test(
      'critical runtime client files must not execute external CLI directly',
      () {
        final blockedStartPattern = RegExp(r'\bProcess\.start\s*\(');
        final blockedRunPattern = RegExp(r'\bProcess\.run\s*\(');
        final allowedRunPatterns = <RegExp>[
          RegExp(r"Process\.run\(\s*'open'"),
          RegExp(r"Process\.run\(\s*'cmd'"),
          RegExp(r"Process\.run\(\s*'xdg-open'"),
        ];
        const guardedFiles = <String>[
          'lib/app/app_controller_desktop.dart',
          'lib/runtime/go_task_service_client.dart',
          'lib/runtime/runtime_coordinator.dart',
          'lib/runtime/gateway_acp_client.dart',
        ];

        for (final relativePath in guardedFiles) {
          final file = File(relativePath);
          expect(
            file.existsSync(),
            isTrue,
            reason: '$relativePath should exist',
          );
          final content = file.readAsStringSync();
          expect(
            blockedStartPattern.hasMatch(content),
            isFalse,
            reason:
                '$relativePath contains forbidden local CLI execution: ${blockedStartPattern.pattern}',
          );

          for (final match in blockedRunPattern.allMatches(content)) {
            final start = (match.start - 48).clamp(0, content.length);
            final end = (match.end + 72).clamp(0, content.length);
            final snippet = content.substring(start, end);
            expect(
              allowedRunPatterns.any((pattern) => pattern.hasMatch(snippet)),
              isTrue,
              reason:
                  '$relativePath contains non-whitelisted Process.run at offset ${match.start}',
            );
          }
        }
      },
    );

    test('legacy direct single-agent runtime implementation stays removed', () {
      const removedFiles = <String>[
        'lib/runtime/direct_single_agent_app_server_client_core.dart',
        'lib/runtime/direct_single_agent_app_server_client_helpers.dart',
        'lib/runtime/direct_single_agent_app_server_client_transport.dart',
      ];

      for (final relativePath in removedFiles) {
        expect(
          File(relativePath).existsSync(),
          isFalse,
          reason: '$relativePath should stay removed after GoTaskService cutover',
        );
      }

      final runnerShim = File('lib/runtime/single_agent_runner.dart');
      expect(runnerShim.existsSync(), isTrue);
      final shimContent = runnerShim.readAsStringSync();
      expect(shimContent.contains('DefaultSingleAgentRunner'), isFalse);
      expect(shimContent.contains('DirectSingleAgentAppServerClient'), isFalse);
    });
  });
}
