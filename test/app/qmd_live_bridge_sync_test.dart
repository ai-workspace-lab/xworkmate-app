// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_core.dart';
import 'package:xworkmate/app/app_controller_desktop_qmd_sync.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_actions.dart';
import 'package:xworkmate/runtime/agent_context_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Live Bridge E2E: AppController fetches real tasks from local Bridge/QMD and merges into assistantSessions', () async {
    // 覆盖 Flutter test 对 HttpClient 的拦截，恢复真实网络调用
    HttpOverrides.global = null;

    const bridgeUrl = 'http://127.0.0.1:8787';
    const bridgeToken = 'fe9c2b2a096b9ff569fdbe5296a9602ae25d6694dba0c22d';

    final controller = AppController(
      environmentOverride: const <String, String>{},
    );

    // 绑定真实的 HTTP 客户端，直连正在运行的本地 Bridge 与 QMD
    controller.agentContextClientOverride = HttpAgentContextClient(
      bridgeBase: Uri.parse(bridgeUrl),
      authToken: bridgeToken,
    );

    // Act: 调度拉取真实 Bridge / QMD 任务
    await controller.refreshQmdRemoteTasksInternal();

    // Assert: 验证成功从 QMD 拉取到远端任务并在侧栏生成 sessions
    expect(controller.qmdRemoteSessionSummariesInternal.isNotEmpty, isTrue,
        reason: 'Should have fetched remote threads from QMD');

    final sessions = controller.assistantSessions;
    print('\n==========================================================================');
    print('  🎉 [E2E 测试成功] XWorkmate App 成功从 QMD 记忆系统聚合历史任务！');
    print('==========================================================================');
    print('  • 聚合历史任务总数: ${controller.qmdRemoteSessionSummariesInternal.length}');

    for (final summary in controller.qmdRemoteSessionSummariesInternal.values) {
      final session = sessions.firstWhere((s) => s.key == summary.key);
      print('   ------------------------------------------------------------');
      print('   • 会话 Key    : ${session.key}');
      print('   • 侧栏显示标题 : ${session.displayName}');
      print('   • 任务状态预览 : ${session.lastMessagePreview}');
    }
    print('==========================================================================\n');

    // 验证特定任务的来源标签和 PR 编号
    final hasCodexOrAppTask = sessions.any((s) => (s.displayName?.contains('Fix bridge reconnect') ?? false));
    final hasDshTask = sessions.any((s) => (s.displayName?.contains('DSH') ?? false) || (s.displayName?.contains('OpenClaw') ?? false));

    expect(hasCodexOrAppTask, isTrue, reason: 'Should contain the ingested bridge reconnect task');
    expect(hasDshTask, isTrue, reason: 'Should contain the ingested DSH migration task');

    // 验证会话切换与只读任务简报加载
    const testSessionKey = 'qmd:thread:68773372-8961-4a86-8ff6-df875cbfcb15';
    await controller.switchSession(testSessionKey);

    final messages = controller.localSessionMessagesInternal[testSessionKey];
    expect(messages, isNotNull);
    expect(messages!.isNotEmpty, isTrue);
    print('  • 选中的历史任务会话简报第一行:\n    ${messages.first.text.split("\n").take(4).join("\n    ")}');
  });
}
