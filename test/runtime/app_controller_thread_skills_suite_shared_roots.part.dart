part of 'app_controller_thread_skills_suite.dart';

void registerThreadSkillsSharedRootTests() {
  group('AppController shared skill roots and directory authorization', () {
    test(
      'AppController scans shared single-agent public roots on startup and shares them across providers',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-single-agent-shared-skills-',
        );
        addTearDown(() async {
          if (await tempDirectory.exists()) {
            try {
              await tempDirectory.delete(recursive: true);
            } catch (_) {}
          }
        });
        final systemRoot = Directory('${tempDirectory.path}/etc-skills');
        final agentsRoot = Directory('${tempDirectory.path}/agents-skills');
        final customRootA = Directory('${tempDirectory.path}/custom-skills-a');
        final customRootB = Directory('${tempDirectory.path}/custom-skills-b');
        await _writeSkill(
          systemRoot,
          'analysis',
          skillName: 'Analysis',
          description: 'System version should be overridden',
        );
        await _writeSkill(
          agentsRoot,
          'browser',
          skillName: 'Browser Automation',
          description: 'Shared browser skill',
        );
        await _writeSkill(
          customRootA,
          'ppt',
          skillName: 'PPT',
          description: 'Presentation skill',
        );
        await _writeSkill(
          customRootB,
          'analysis',
          skillName: 'Analysis',
          description: 'Custom version wins',
        );
        await _writeSkill(
          customRootB,
          'cicd-audit',
          skillName: 'CICD Audit',
          description: 'Pipeline audit skill',
        );

        final controller = AppController(
          store: await _createStore(tempDirectory.path),
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
            SingleAgentProvider.claude,
          ],
          singleAgentSharedSkillScanRootOverrides: <String>[
            systemRoot.path,
            agentsRoot.path,
            customRootA.path,
            customRootB.path,
          ],
        );
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.initializing);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.opencode);
        await _waitFor(
          () =>
              controller
                  .assistantImportedSkillsForSession(
                    controller.currentSessionKey,
                  )
                  .length ==
              4,
        );

        final firstSessionKey = controller.currentSessionKey;
        expect(
          controller
              .assistantImportedSkillsForSession(firstSessionKey)
              .map((skill) => skill.label),
          containsAll(const <String>[
            'Analysis',
            'Browser Automation',
            'PPT',
            'CICD Audit',
          ]),
        );
        final analysisSkill = controller
            .assistantImportedSkillsForSession(firstSessionKey)
            .firstWhere((skill) => skill.label == 'Analysis');
        expect(analysisSkill.description, 'Custom version wins');
        expect(analysisSkill.source, 'custom');
        expect(analysisSkill.scope, 'user');

        await controller.toggleAssistantSkillForSession(
          firstSessionKey,
          controller
              .assistantImportedSkillsForSession(firstSessionKey)
              .firstWhere((skill) => skill.label == 'PPT')
              .key,
        );
        expect(
          controller
              .assistantSelectedSkillsForSession(firstSessionKey)
              .map((skill) => skill.label),
          const <String>['PPT'],
        );

        await controller.setSingleAgentProvider(SingleAgentProvider.claude);
        await _waitFor(
          () =>
              controller
                  .assistantImportedSkillsForSession(firstSessionKey)
                  .length ==
              4,
        );
        expect(
          controller
              .assistantSelectedSkillsForSession(firstSessionKey)
              .map((skill) => skill.label),
          const <String>['PPT'],
        );
      },
    );

    test(
      'AppController hot reloads authorized custom skill directories from settings.yaml',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-skill-directory-hot-reload-',
        );
        addTearDown(() async {
          if (await tempDirectory.exists()) {
            try {
              await tempDirectory.delete(recursive: true);
            } catch (_) {}
          }
        });
        final agentsRoot = Directory('${tempDirectory.path}/agents-skills');
        await _writeSkill(
          agentsRoot,
          'browser',
          skillName: 'Browser',
          description: 'Browser tasks',
        );

        final store = await _createStore(tempDirectory.path);
        final controller = AppController(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          singleAgentSharedSkillScanRootOverrides: const <String>[],
        );
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.initializing);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        expect(
          controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .where((skill) => skill.label == 'Browser'),
          isEmpty,
        );

        final updatedSnapshot =
            _singleAgentTestSettings(
              workspacePath: tempDirectory.path,
            ).copyWith(
              authorizedSkillDirectories: <AuthorizedSkillDirectory>[
                AuthorizedSkillDirectory(path: agentsRoot.path),
              ],
            );
        final settingsFile = File('${tempDirectory.path}/config/settings.yaml');
        await settingsFile.writeAsString(
          encodeYamlDocument(updatedSnapshot.toJson()),
          flush: true,
        );

        await _waitFor(
          () => controller.authorizedSkillDirectories
              .map((item) => item.path)
              .contains(agentsRoot.path),
        );
        await _waitFor(
          () => controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .any((skill) => skill.label == 'Browser'),
        );
        expect(
          controller.authorizedSkillDirectories.map((item) => item.path),
          <String>[agentsRoot.path],
        );
      },
    );

    test(
      'AppController scans skills inside symlinked directories under shared roots',
      () async {
        if (Platform.isWindows) {
          return;
        }
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-skill-directory-symlink-',
        );
        addTearDown(() async {
          if (await tempDirectory.exists()) {
            try {
              await tempDirectory.delete(recursive: true);
            } catch (_) {}
          }
        });
        final sharedRoot = Directory('${tempDirectory.path}/shared-root');
        final actualSkillRoot = Directory(
          '${tempDirectory.path}/actual-skills',
        );
        await sharedRoot.create(recursive: true);
        await _writeSkill(
          actualSkillRoot,
          'linked-browser',
          skillName: 'Linked Browser',
          description: 'Loaded through a symlinked directory',
        );
        await Link(
          '${sharedRoot.path}/linked-pack',
        ).create(actualSkillRoot.path);

        final controller = AppController(
          store: await _createStore(tempDirectory.path),
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          singleAgentSharedSkillScanRootOverrides: <String>[sharedRoot.path],
        );
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.initializing);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await _waitFor(
          () => controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .any((skill) => skill.label == 'Linked Browser'),
        );

        final linkedSkill = controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .firstWhere((skill) => skill.label == 'Linked Browser');
        expect(linkedSkill.description, 'Loaded through a symlinked directory');
        expect(linkedSkill.source, 'custom');
        expect(linkedSkill.sourceLabel, contains('linked-pack/linked-browser'));
      },
    );

    test(
      'AppController resolves preset shared roots against the access service home directory',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-skill-directory-home-',
        );
        addTearDown(() async {
          if (await tempDirectory.exists()) {
            try {
              await tempDirectory.delete(recursive: true);
            } catch (_) {}
          }
        });
        final userHome = Directory('${tempDirectory.path}/real-home');
        final agentsRoot = Directory('${userHome.path}/.agents/skills');
        await _writeSkill(
          agentsRoot,
          'browser',
          skillName: 'Browser',
          description: 'Browser tasks',
        );

        final controller = AppController(
          store: await _createStore(tempDirectory.path),
          skillDirectoryAccessService: _FakeSkillDirectoryAccessService(
            userHomeDirectory: userHome.path,
          ),
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          singleAgentSharedSkillScanRootOverrides: const <String>[
            '~/.agents/skills',
          ],
        );
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.initializing);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await _waitFor(
          () => controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .any((item) => item.label == 'Browser'),
        );

        expect(controller.userHomeDirectory, userHome.path);
        expect(
          controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .map((item) => item.label),
          contains('Browser'),
        );
      },
    );

    test(
      'AppController accepts authorized single skill package paths and keeps fixed-root scanning intact',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-single-skill-package-path-',
        );
        addTearDown(() async {
          if (await tempDirectory.exists()) {
            try {
              await tempDirectory.delete(recursive: true);
            } catch (_) {}
          }
        });
        final fixedRoot = Directory('${tempDirectory.path}/fixed-root');
        final externalRepoSkill = Directory(
          '${tempDirectory.path}/ai-workflow-craft/skills/docx',
        );
        await _writeSkill(
          fixedRoot,
          'docx',
          skillName: 'docx',
          description: 'Fixed root version',
        );
        await _writeSkill(
          externalRepoSkill.parent,
          'docx',
          skillName: 'docx',
          description: 'Imported package version',
        );

        final store = await _createStore(tempDirectory.path);
        await store.saveSettingsSnapshot(
          _singleAgentTestSettings(workspacePath: tempDirectory.path).copyWith(
            authorizedSkillDirectories: <AuthorizedSkillDirectory>[
              AuthorizedSkillDirectory(
                path: '${externalRepoSkill.path}/SKILL.md',
              ),
            ],
          ),
        );

        final controller = AppController(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          singleAgentSharedSkillScanRootOverrides: <String>[fixedRoot.path],
        );
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.initializing);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await _waitFor(
          () => controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .any((item) => item.label == 'docx'),
        );

        final docxSkill = controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .firstWhere((item) => item.label == 'docx');
        expect(docxSkill.description, 'Imported package version');
        expect(docxSkill.source, 'custom');
        expect(
          controller.authorizedSkillDirectories.map((item) => item.path),
          <String>['${tempDirectory.path}/ai-workflow-craft/skills/docx'],
        );
      },
    );
  });
}
