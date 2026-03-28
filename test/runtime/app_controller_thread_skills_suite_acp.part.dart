part of 'app_controller_thread_skills_suite.dart';

void registerThreadSkillsAcpTests() {
  group('AppController ACP skill refresh and empty-root handling', () {
    test(
      'AppController merges ACP skills after shared roots and workspace skills',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-acp-skill-merge-',
        );
        final acpServer = await _AcpSkillsStatusServer.start(
          skills: const <Map<String, dynamic>>[
            <String, dynamic>{
              'skillKey': 'acp-shared',
              'name': 'Shared Skill',
              'description': 'ACP should not override shared',
              'source': 'acp',
            },
            <String, dynamic>{
              'skillKey': 'acp-workspace',
              'name': 'Workspace Skill',
              'description': 'ACP should not override workspace',
              'source': 'acp',
            },
            <String, dynamic>{
              'skillKey': 'acp-only',
              'name': 'ACP Only',
              'description': 'Only from ACP',
              'source': 'acp',
            },
          ],
        );
        addTearDown(acpServer.close);
        addTearDown(() async {
          if (await tempDirectory.exists()) {
            try {
              await tempDirectory.delete(recursive: true);
            } catch (_) {}
          }
        });

        final customRoot = Directory(
          '${tempDirectory.path}/custom-shared-skills',
        );
        final workspaceRoot = Directory('${tempDirectory.path}/workspace');
        await _writeSkill(
          customRoot,
          'shared-skill',
          skillName: 'Shared Skill',
          description: 'Shared root wins',
        );
        await _writeSkill(
          Directory('${workspaceRoot.path}/skills'),
          'workspace-skill',
          skillName: 'Workspace Skill',
          description: 'Workspace wins',
        );

        final store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async =>
              '${tempDirectory.path}/settings.sqlite3',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
          defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
        );
        await store.initialize();
        await store.saveSettingsSnapshot(
          _singleAgentTestSettings(
            workspacePath: tempDirectory.path,
            gatewayPort: acpServer.port,
          ),
        );
        await store.saveAssistantThreadRecords(<AssistantThreadRecord>[
          AssistantThreadRecord(
            sessionKey: 'main',
            messages: const <GatewayChatMessage>[],
            updatedAtMs: 1,
            title: '',
            archived: false,
            executionTarget: AssistantExecutionTarget.singleAgent,
            messageViewMode: AssistantMessageViewMode.rendered,
            workspaceRef: workspaceRoot.path,
            workspaceRefKind: WorkspaceRefKind.localPath,
          ),
        ]);

        final controller = AppController(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          singleAgentSharedSkillScanRootOverrides: <String>[customRoot.path],
        );
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.initializing);
        await _waitFor(
          () => controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .any((item) => item.label == 'ACP Only'),
        );

        final importedSkills = controller.assistantImportedSkillsForSession(
          controller.currentSessionKey,
        );
        expect(
          importedSkills.map((item) => item.label),
          containsAll(const <String>[
            'Shared Skill',
            'Workspace Skill',
            'ACP Only',
          ]),
        );
        expect(
          importedSkills.firstWhere((item) => item.label == 'Shared Skill'),
          isA<AssistantThreadSkillEntry>()
              .having(
                (item) => item.description,
                'description',
                'Shared root wins',
              )
              .having((item) => item.source, 'source', 'custom'),
        );
        expect(
          importedSkills.firstWhere((item) => item.label == 'Workspace Skill'),
          isA<AssistantThreadSkillEntry>()
              .having(
                (item) => item.description,
                'description',
                'Workspace wins',
              )
              .having((item) => item.source, 'source', 'workspace'),
        );
        expect(
          importedSkills.firstWhere((item) => item.label == 'ACP Only'),
          isA<AssistantThreadSkillEntry>()
              .having(
                (item) => item.description,
                'description',
                'Only from ACP',
              )
              .having((item) => item.source, 'source', 'acp'),
        );
      },
    );

    test(
      'AppController clears stale ACP-only skills when ACP refresh fails',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-acp-skill-error-',
        );
        final acpServer = await _AcpSkillsStatusServer.start(
          skills: const <Map<String, dynamic>>[
            <String, dynamic>{
              'skillKey': 'acp-only',
              'name': 'ACP Only',
              'description': 'Only from ACP',
              'source': 'acp',
            },
          ],
        );
        addTearDown(acpServer.close);
        addTearDown(() async {
          if (await tempDirectory.exists()) {
            try {
              await tempDirectory.delete(recursive: true);
            } catch (_) {}
          }
        });

        final customRoot = Directory(
          '${tempDirectory.path}/custom-shared-skills',
        );
        await _writeSkill(
          customRoot,
          'local-only',
          skillName: 'Local Only',
          description: 'Only from local scan',
        );

        final store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async =>
              '${tempDirectory.path}/settings.sqlite3',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
          defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
        );
        await store.initialize();
        await store.saveSettingsSnapshot(
          _singleAgentTestSettings(
            workspacePath: tempDirectory.path,
            gatewayPort: acpServer.port,
          ),
        );

        final controller = AppController(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          singleAgentSharedSkillScanRootOverrides: <String>[customRoot.path],
        );
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.initializing);
        await _waitFor(
          () => controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .any((item) => item.label == 'ACP Only'),
        );

        acpServer.skillsError = <String, dynamic>{
          'code': -32001,
          'message': 'skills refresh failed',
        };
      await controller.refreshSingleAgentSkillsForSession(
        controller.currentSessionKey,
      );

      await _waitFor(() {
        final labels = controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((item) => item.label)
            .toList(growable: false);
        return labels.length == 1 && labels.first == 'Local Only';
      });

      final importedSkills = controller.assistantImportedSkillsForSession(
        controller.currentSessionKey,
      );
        expect(importedSkills.map((item) => item.label), const <String>[
          'Local Only',
        ]);
      },
    );

    test(
      'AppController can return empty skills when neither public nor repo-local roots exist',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-empty-relative-skills-',
        );
        addTearDown(() async {
          if (await tempDirectory.exists()) {
            try {
              await tempDirectory.delete(recursive: true);
            } catch (_) {}
          }
        });

        final store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async =>
              '${tempDirectory.path}/settings.sqlite3',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
          defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
        );
        await store.initialize();
        await store.saveSettingsSnapshot(
          _singleAgentTestSettings(
            workspacePath: '${tempDirectory.path}/missing-workspace',
          ),
        );
        await store.saveAssistantThreadRecords(<AssistantThreadRecord>[
          AssistantThreadRecord(
            sessionKey: 'main',
            messages: const <GatewayChatMessage>[],
            updatedAtMs: 1,
            title: '',
            archived: false,
            executionTarget: AssistantExecutionTarget.singleAgent,
            messageViewMode: AssistantMessageViewMode.rendered,
            workspaceRef: '${tempDirectory.path}/missing-workspace',
            workspaceRefKind: WorkspaceRefKind.localPath,
          ),
        ]);

        final controller = AppController(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          singleAgentSharedSkillScanRootOverrides: const <String>[],
        );
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.initializing);
        await _waitFor(
          () => controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .isEmpty,
        );

        expect(
          controller.assistantImportedSkillsForSession(
            controller.currentSessionKey,
          ),
          isEmpty,
        );
      },
    );
  });
}
