import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bridge-only UI copy does not regress to legacy gateway connection wording', () {
    final targets = <String>[
      'lib/features/assistant/assistant_page_components.dart',
      'lib/widgets/assistant_focus_panel_previews.dart',
      'lib/features/mcp_server/mcp_server_page.dart',
      'lib/features/modules/modules_page.dart',
      'lib/features/mobile/mobile_shell_sheet.dart',
      'lib/features/mobile/mobile_shell_core.dart',
      'lib/features/mobile/mobile_shell_workspace.dart',
    ];

    const forbiddenSnippets = <String>[
      '连接 Gateway 后',
      'Connect a gateway',
      'Connect Gateway',
      '编辑连接',
      '当前线程目标网关尚未连接',
      'Gateway connection failed',
      'Connect gateway',
    ];

    for (final path in targets) {
      final source = File(path).readAsStringSync();
      for (final snippet in forbiddenSnippets) {
        expect(
          source.contains(snippet),
          isFalse,
          reason: '$path should not contain legacy gateway-only copy: $snippet',
        );
      }
    }
  });
}
