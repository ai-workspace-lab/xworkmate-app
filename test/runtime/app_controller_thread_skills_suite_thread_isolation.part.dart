part of 'app_controller_thread_skills_suite.dart';

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
        await _writeSkill(
          agentsRoot,
          'browser',
          skillName: 'Browser',
          description: 'Browser tasks',
        );
        await _writeSkill(
          customRootA,
          'ppt',
          skillName: 'PPT',
          description: 'Presentation tasks',
        );
        await _writeSkill(
          customRootB,
          'wordx',
          skillName: 'WordX',
          description: 'Document tasks',
        );
        await _writeSkill(
          customRootB,
          'cicd-audit',
          skillName: 'CICD Audit',
          description: 'Pipeline tasks',
        );

        Future<SecureConfigStore> createStore() {
          return _createStore(tempDirectory.path);
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
        await _waitFor(() => !controller.initializing);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await _waitFor(
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
        await _waitFor(
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
        await _waitFor(
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
        await _waitFor(() => !restoredController.initializing);
        await restoredController.switchSession(taskA);
        await _waitFor(
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
        await _waitFor(
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
        await _waitFor(
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
