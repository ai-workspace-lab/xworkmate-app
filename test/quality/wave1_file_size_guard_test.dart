import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wave1 implementation-bearing files stay under closure size caps', () {
    // NOTE:
    // - This guard now tracks implementation-bearing files instead of thin export
    //   entry files.
    // - For oversized legacy closures, we use baseline caps to prevent further
    //   growth before T2/T3 shrink work lands.
    const targets = <String, int>{
      // Enforced closure targets (300-800 expected by workflow).
      'lib/app/app_controller_desktop_core.dart': 800,
      'lib/runtime/multi_agent_orchestrator_core.dart': 800,
      'lib/runtime/multi_agent_orchestrator_workflow.dart': 800,
      // Baseline cap for legacy oversized closure; tighten after T3.
      'lib/runtime/gateway_runtime_core.dart': 950,
      'lib/runtime/gateway_runtime_helpers.dart': 800,
      // Tightened after T3 closure convergence.
      'lib/runtime/runtime_controllers_settings.dart': 800,
      'lib/features/settings/settings_page_gateway.dart': 800,
      'test/runtime/app_controller_assistant_flow_suite.dart': 800,
      'test/runtime/app_controller_thread_skills_suite.dart': 800,

      // Tightened in T2/T3 after assistant + app/runtime closure split.
      'lib/features/assistant/assistant_page_main.dart': 1000,
      'lib/app/app_controller_desktop_runtime_helpers.dart': 800,
      'lib/app/app_controller_desktop_single_agent.dart': 200,
      'lib/app/app_controller_desktop_single_agent_ai_gateway.dart': 800,
      'lib/app/app_controller_desktop_single_agent_go_task_flow.dart': 800,
      'lib/app/app_controller_desktop_single_agent_status_messages.dart': 400,
      'lib/app/app_controller_desktop_external_acp_routing.dart': 400,
      'lib/app/app_controller_desktop_thread_sessions.dart': 800,
      'lib/app/app_controller_desktop_runtime_coordination_impl.dart': 800,
      'lib/app/app_controller_desktop_thread_sessions_collaboration_impl.dart':
          800,
      'lib/runtime/runtime_controllers_settings_connectivity_impl.dart': 800,
    };
    final violations = <String>[];
    for (final entry in targets.entries) {
      final path = entry.key;
      final maxLines = entry.value;
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
