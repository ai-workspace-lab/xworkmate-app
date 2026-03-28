// ignore_for_file: unused_import, unnecessary_import

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/runtime/skill_directory_access.dart';
import 'app_controller_thread_skills_suite_core.dart';
import 'app_controller_thread_skills_suite_shared_roots.dart';
import 'app_controller_thread_skills_suite_workspace_fallback.dart';
import 'app_controller_thread_skills_suite_acp.dart';
import 'app_controller_thread_skills_suite_fixtures.dart';
import 'app_controller_thread_skills_suite_fakes.dart';

void registerThreadSkillsThreadIsolationTests() {
  group('AppController thread-bound skill isolation', () {
    test(
      'AppController keeps thread-bound skills isolated and restores them after restart',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-thread-isolation-',
        );
        addTearDown(() async {
          if (await tempDirectory.exists()) {
            try {
              await tempDirectory.delete(recursive: true);
            } catch (_) {}
          }
        });
        final agentsRoot = Directory('${tempDirectory.path}/agents-skills');
        final customRootA = Directory('${tempDirectory.path}/custom-skills-a');
        final customRootB = Directory('${tempDirectory.path}/custom-skills-b');
        await writeSkillInternal(
          agentsRoot,
          'browser',
          skillName: 'Browser',
          description: 'Browser tasks',
        );
        await writeSkillInternal(
          customRootA,
          'ppt',
          skillName: 'PPT',
          description: 'Presentation tasks',
        );
        await writeSkillInternal(
          customRootB,
          'wordx',
          skillName: 'WordX',
          description: 'Document tasks',
        );
        await writeSkillInternal(
          customRootB,
          'cicd-audit',
          skillName: 'CICD Audit',
          description: 'Pipeline tasks',
        );

        Future<SecureConfigStore> createStore() {
          return createStoreInternal(tempDirectory.path);
        }

        Future<AppController> createController() async {
          return AppController(
            store: await createStore(),
            availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
              SingleAgentProvider.opencode,
              SingleAgentProvider.claude,
            ],
            singleAgentSharedSkillScanRootOverrides: <String>[
              agentsRoot.path,
              customRootA.path,
              customRootB.path,
            ],
          );
        }

        final controller = await createController();
        await waitForInternal(() => !controller.initializing);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await waitForInternal(
          () =>
              controller
                  .assistantImportedSkillsForSession(
                    controller.currentSessionKey,
                  )
                  .length ==
              4,
        );
        final taskA = controller.currentSessionKey;
        await controller.toggleAssistantSkillForSession(
          taskA,
          controller
              .assistantImportedSkillsForSession(taskA)
              .firstWhere((skill) => skill.label == 'PPT')
              .key,
        );

        controller.initializeAssistantThreadContext(
          'draft:task-b',
          title: 'Task B',
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
          singleAgentProvider: SingleAgentProvider.claude,
        );
        await controller.switchSession('draft:task-b');
        await waitForInternal(
          () =>
              controller
                  .assistantImportedSkillsForSession(
                    controller.currentSessionKey,
                  )
                  .length ==
              4,
        );
        final taskB = controller.currentSessionKey;
        await controller.toggleAssistantSkillForSession(
          taskB,
          controller
              .assistantImportedSkillsForSession(taskB)
              .firstWhere((skill) => skill.label == 'WordX')
              .key,
        );

        controller.initializeAssistantThreadContext(
          'draft:task-c',
          title: 'Task C',
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
        );
        await controller.switchSession('draft:task-c');
        await waitForInternal(
          () =>
              controller
                  .assistantImportedSkillsForSession(
                    controller.currentSessionKey,
                  )
                  .length ==
              4,
        );
        final taskC = controller.currentSessionKey;
        await controller.toggleAssistantSkillForSession(
          taskC,
          controller
              .assistantImportedSkillsForSession(taskC)
              .firstWhere((skill) => skill.label == 'Browser')
              .key,
        );

        expect(
          controller
              .assistantSelectedSkillsForSession(taskA)
              .map((skill) => skill.label),
          const <String>['PPT'],
        );
        expect(
          controller
              .assistantSelectedSkillsForSession(taskB)
              .map((skill) => skill.label),
          const <String>['WordX'],
        );
        expect(
          controller
              .assistantSelectedSkillsForSession(taskC)
              .map((skill) => skill.label),
          const <String>['Browser'],
        );

        controller.dispose();

        final restoredController = await createController();
        addTearDown(restoredController.dispose);
        await waitForInternal(() => !restoredController.initializing);
        await restoredController.switchSession(taskA);
        await waitForInternal(
          () =>
              restoredController
                  .assistantImportedSkillsForSession(taskA)
                  .length ==
              4,
        );
        expect(
          restoredController
              .assistantSelectedSkillsForSession(taskA)
              .map((skill) => skill.label),
          const <String>['PPT'],
        );
        await restoredController.switchSession(taskB);
        await waitForInternal(
          () =>
              restoredController
                  .assistantImportedSkillsForSession(taskB)
                  .length ==
              4,
        );
        expect(
          restoredController
              .assistantSelectedSkillsForSession(taskB)
              .map((skill) => skill.label),
          const <String>['WordX'],
        );
        await restoredController.switchSession(taskC);
        await waitForInternal(
          () =>
              restoredController
                  .assistantImportedSkillsForSession(taskC)
                  .length ==
              4,
        );
        expect(
          restoredController
              .assistantSelectedSkillsForSession(taskC)
              .map((skill) => skill.label),
          const <String>['Browser'],
        );
      },
    );
  });
}
