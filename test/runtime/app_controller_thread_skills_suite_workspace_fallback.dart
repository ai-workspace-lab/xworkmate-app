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
import 'app_controller_thread_skills_suite_thread_isolation.dart';
import 'app_controller_thread_skills_suite_acp.dart';
import 'app_controller_thread_skills_suite_fixtures.dart';
import 'app_controller_thread_skills_suite_fakes.dart';

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
        await writeSkillInternal(
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
          singleAgentTestSettingsInternal(
            workspacePath: '${tempDirectory.path}/unused-default-workspace',
          ),
        );
        await store.saveTaskThreads(<TaskThread>[
          TaskThread(
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
        await waitForInternal(() => !controller.initializing);
        await waitForInternal(
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
        await writeSkillInternal(
          customRoot,
          'shared-skill',
          skillName: 'Shared Skill',
          description: 'Global wins',
        );
        await writeSkillInternal(
          customRoot,
          'global-only',
          skillName: 'Global Only',
          description: 'Only from global',
        );
        await writeSkillInternal(
          Directory('${workspaceRoot.path}/skills'),
          'shared-skill',
          skillName: 'Shared Skill',
          description: 'Repo-local should not override',
        );
        await writeSkillInternal(
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
          singleAgentTestSettingsInternal(workspacePath: tempDirectory.path),
        );
        await store.saveTaskThreads(<TaskThread>[
          TaskThread(
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
        await waitForInternal(() => !controller.initializing);
        await waitForInternal(
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
        await writeSkillInternal(
          Directory('${workspaceRoot.path}/skills'),
          'shared-skill',
          skillName: 'Shared Skill',
          description: 'Workspace version wins',
        );
        await writeSkillInternal(
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
          singleAgentTestSettingsInternal(workspacePath: tempDirectory.path),
        );
        await store.saveTaskThreads(<TaskThread>[
          TaskThread(
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
        await waitForInternal(() => !controller.initializing);
        await waitForInternal(
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
