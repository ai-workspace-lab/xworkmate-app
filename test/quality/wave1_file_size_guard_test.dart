import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wave1 oversized files should stay within 800 lines', () {
    const maxLines = 800;
    const targets = <String>[
      // Wave 1
      'lib/runtime/runtime_models.dart',
      'lib/runtime/runtime_controllers.dart',
      'lib/app/app_controller_desktop.dart',
      'lib/app/app_controller_web.dart',
      'lib/runtime/gateway_runtime.dart',
      'lib/runtime/multi_agent_orchestrator.dart',
      'test/features/assistant_page_suite.dart',
      // Wave 2
      'lib/features/settings/settings_page.dart',
      'lib/features/assistant/assistant_page.dart',
      'lib/features/assistant/assistant_page_components.part.dart',
      'lib/web/web_workspace_pages.dart',
      'lib/web/web_assistant_page.dart',
      'lib/web/web_settings_page.dart',
      'lib/features/mobile/mobile_shell.dart',
      // Wave 3
      'lib/runtime/direct_single_agent_app_server_client.dart',
      'test/runtime/app_controller_thread_skills_suite.dart',
      'go/go_core/main.go',
      'test/runtime/app_controller_ai_gateway_chat_suite.dart',
      'test/runtime/secure_config_store_suite.dart',
      'lib/app/ui_feature_manifest.dart',
      'test/runtime/app_controller_execution_target_switch_suite.dart',
      'lib/widgets/assistant_focus_panel.dart',
      'lib/web/web_focus_panel.dart',
    ];

    final violations = <String>[];
    for (final path in targets) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'missing file: $path');
      final lines = file.readAsLinesSync().length;
      if (lines > maxLines) {
        violations.add('$path has $lines lines (limit: $maxLines)');
      }
    }

    expect(
      violations,
      isEmpty,
      reason: violations.isEmpty ? null : violations.join('\n'),
    );
  });
}
