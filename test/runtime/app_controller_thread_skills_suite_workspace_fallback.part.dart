part of 'app_controller_thread_skills_suite.dart';

void registerThreadSkillsWorkspaceFallbackTests() {
  group('AppController workspace fallback and repo-local precedence', () {
    test(
      'AppController uses thread workspaceRef for repo-local fallback',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-workspace-ref-skills-',
        );
        addTearDown(() async {
          if (await tempDirectory.exists()) {
            try {
              await tempDirectory.delete(recursive: true);
            } catch (_) {}
          }
        });
        final workspaceRoot = Directory('${tempDirectory.path}/workspace');
        await _writeSkill(
          Directory('${workspaceRoot.path}/skills'),
          'workspace-only',
          skillName: 'Workspace Only Skill',
          description: 'Repo-local fallback',
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
            workspacePath: '${tempDirectory.path}/unused-default-workspace',
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
          singleAgentSharedSkillScanRootOverrides: const <String>[],
        );
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.initializing);
        await _waitFor(
          () => controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .any((item) => item.label == 'Workspace Only Skill'),
        );

        expect(
          controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .map((item) => item.label),
          contains('Workspace Only Skill'),
        );
      },
    );

    test(
      'AppController keeps public roots ahead of repo-local fallback and only fills missing skills',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-global-overrides-repo-local-',
        );
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
          description: 'Global wins',
        );
        await _writeSkill(
          customRoot,
          'global-only',
          skillName: 'Global Only',
          description: 'Only from global',
        );
        await _writeSkill(
          Directory('${workspaceRoot.path}/skills'),
          'shared-skill',
          skillName: 'Shared Skill',
          description: 'Repo-local should not override',
        );
        await _writeSkill(
          Directory('${workspaceRoot.path}/skills'),
          'workspace-only',
          skillName: 'Workspace Only',
          description: 'Only from workspace',
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
          _singleAgentTestSettings(workspacePath: tempDirectory.path),
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
          () =>
              controller
                  .assistantImportedSkillsForSession(
                    controller.currentSessionKey,
                  )
                  .length ==
              3,
        );

        final sharedSkill = controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .firstWhere((item) => item.label == 'Shared Skill');
        expect(sharedSkill.description, 'Global wins');
        expect(
          controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .map((item) => item.label),
          containsAll(const <String>[
            'Shared Skill',
            'Global Only',
            'Workspace Only',
          ]),
        );
      },
    );

    test(
      'AppController scans repo-local skills from workspace skills directory only',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-repo-local-order-',
        );
        addTearDown(() async {
          if (await tempDirectory.exists()) {
            try {
              await tempDirectory.delete(recursive: true);
            } catch (_) {}
          }
        });
        final workspaceRoot = Directory('${tempDirectory.path}/workspace');
        await _writeSkill(
          Directory('${workspaceRoot.path}/skills'),
          'shared-skill',
          skillName: 'Shared Skill',
          description: 'Workspace version wins',
        );
        await _writeSkill(
          Directory('${workspaceRoot.path}/.codex/skills'),
          'legacy-only',
          skillName: 'Legacy Only',
          description: 'Deprecated workspace root should be ignored',
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
          _singleAgentTestSettings(workspacePath: tempDirectory.path),
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
          singleAgentSharedSkillScanRootOverrides: const <String>[],
        );
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.initializing);
        await _waitFor(
          () => controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .isNotEmpty,
        );

        final sharedSkill = controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .firstWhere((item) => item.label == 'Shared Skill');
        expect(sharedSkill.description, 'Workspace version wins');
        expect(sharedSkill.source, 'workspace');
        expect(
          controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .where((item) => item.label == 'Legacy Only'),
          isEmpty,
        );
      },
    );
  });
}
