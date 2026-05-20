import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('assistant archived tasks', () {
    test(
      'lists archived tasks separately and restores them to active sessions',
      () async {
        final home = await Directory.systemTemp.createTemp(
          'xworkmate-archived-task-home-',
        );
        addTearDown(() async {
          if (await home.exists()) {
            await home.delete(recursive: true);
          }
        });
        final controller = AppController(
          environmentOverride: <String, String>{'HOME': home.path},
        );
        addTearDown(controller.dispose);

        const sessionKey = 'draft:archived-task';
        controller.initializeAssistantThreadContext(
          sessionKey,
          title: '导出 PDF',
          executionTarget: AssistantExecutionTarget.gateway,
          messageViewMode: AssistantMessageViewMode.rendered,
        );
        controller.appendAssistantThreadMessageInternal(
          sessionKey,
          const GatewayChatMessage(
            id: 'm-1',
            role: 'user',
            text: '输出为PDF文件',
            timestampMs: 1779178980000,
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: false,
          ),
        );

        await controller.saveAssistantTaskArchived(sessionKey, true);

        expect(
          controller.assistantSessions.map((item) => item.key),
          isNot(contains(sessionKey)),
        );
        expect(
          controller.archivedAssistantSessions.map((item) => item.key),
          <String>[sessionKey],
        );
        expect(controller.archivedAssistantSessions.single.label, '导出 PDF');

        await controller.saveAssistantTaskArchived(sessionKey, false);

        expect(controller.archivedAssistantSessions, isEmpty);
        expect(
          controller.assistantSessions.map((item) => item.key),
          contains(sessionKey),
        );
      },
    );

    test('deletes archived task records and local task directory', () async {
      final home = await Directory.systemTemp.createTemp(
        'xworkmate-delete-archived-task-home-',
      );
      addTearDown(() async {
        if (await home.exists()) {
          await home.delete(recursive: true);
        }
      });
      final controller = AppController(
        environmentOverride: <String, String>{'HOME': home.path},
      );
      addTearDown(controller.dispose);

      const sessionKey = 'draft:delete-archived-task';
      controller.initializeAssistantThreadContext(
        sessionKey,
        title: '待删除任务',
        executionTarget: AssistantExecutionTarget.gateway,
        messageViewMode: AssistantMessageViewMode.rendered,
      );
      final workspacePath = controller.assistantWorkspacePathForSession(
        sessionKey,
      );
      expect(workspacePath, isNotEmpty);
      final workspaceDirectory = Directory(workspacePath);
      await workspaceDirectory.create(recursive: true);
      await File(
        '${workspaceDirectory.path}/artifact.md',
      ).writeAsString('archived task artifact');
      await controller.saveAssistantTaskArchived(sessionKey, true);

      expect(
        controller.archivedAssistantSessions.map((item) => item.key),
        <String>[sessionKey],
      );

      await controller.deleteArchivedAssistantTask(sessionKey);

      expect(controller.archivedAssistantSessions, isEmpty);
      expect(
        controller.assistantSessions.map((item) => item.key),
        isNot(contains(sessionKey)),
      );
      expect(controller.hasAssistantTaskStateInternal(sessionKey), isFalse);
      expect(await workspaceDirectory.exists(), isFalse);
    });
  });
}
