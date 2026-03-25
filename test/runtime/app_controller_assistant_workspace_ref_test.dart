@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

import '../test_support.dart';

void main() {
  test(
    'AppController keeps workspace refs aligned with assistant thread targets',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppController(
        store: createIsolatedTestStore(enableSecureStorage: false),
      );
      addTearDown(controller.dispose);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (controller.initializing) {
        if (DateTime.now().isAfter(deadline)) {
          fail('controller did not initialize in time');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(
        controller.assistantWorkspaceRefForSession(
          controller.currentSessionKey,
        ),
        controller.settings.workspacePath,
      );
      expect(
        controller.assistantWorkspaceRefKindForSession(
          controller.currentSessionKey,
        ),
        WorkspaceRefKind.localPath,
      );

      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.remote,
      );
      expect(
        controller.assistantWorkspaceRefForSession(
          controller.currentSessionKey,
        ),
        controller.settings.remoteProjectRoot,
      );
      expect(
        controller.assistantWorkspaceRefKindForSession(
          controller.currentSessionKey,
        ),
        WorkspaceRefKind.remotePath,
      );

      const draftKey = 'draft:artifact-thread';
      controller.initializeAssistantThreadContext(
        draftKey,
        title: 'Artifact Thread',
        executionTarget: AssistantExecutionTarget.singleAgent,
      );
      await controller.switchSession(draftKey);
      expect(
        controller.assistantWorkspaceRefForSession(draftKey),
        controller.settings.workspacePath,
      );
      expect(
        controller.assistantWorkspaceRefKindForSession(draftKey),
        WorkspaceRefKind.localPath,
      );
    },
  );
}
