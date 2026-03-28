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
import 'app_controller_thread_skills_suite_thread_isolation.dart';
import 'app_controller_thread_skills_suite_workspace_fallback.dart';
import 'app_controller_thread_skills_suite_acp.dart';
import 'app_controller_thread_skills_suite_fixtures.dart';
import 'app_controller_thread_skills_suite_fakes.dart';

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
        await writeSkillInternal(
          systemRoot,
          'analysis',
          skillName: 'Analysis',
          description: 'System version should be overridden',
        );
        await writeSkillInternal(
          agentsRoot,
          'browser',
          skillName: 'Browser Automation',
          description: 'Shared browser skill',
        );
        await writeSkillInternal(
          customRootA,
          'ppt',
          skillName: 'PPT',
          description: 'Presentation skill',
        );
        await writeSkillInternal(
          customRootB,
          'analysis',
          skillName: 'Analysis',
          description: 'Custom version wins',
        );
        await writeSkillInternal(
          customRootB,
          'cicd-audit',
          skillName: 'CICD Audit',
          description: 'Pipeline audit skill',
        );

        final controller = AppController(
          store: await createStoreInternal(tempDirectory.path),
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
        await waitForInternal(() => !controller.initializing);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.opencode);
        await waitForInternal(
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
        await waitForInternal(
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
        await writeSkillInternal(
          agentsRoot,
          'browser',
          skillName: 'Browser',
          description: 'Browser tasks',
        );

        final store = await createStoreInternal(tempDirectory.path);
        final controller = AppController(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          singleAgentSharedSkillScanRootOverrides: const <String>[],
        );
        addTearDown(controller.dispose);
        await waitForInternal(() => !controller.initializing);
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
            singleAgentTestSettingsInternal(
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

        await waitForInternal(
          () => controller.authorizedSkillDirectories
              .map((item) => item.path)
              .contains(agentsRoot.path),
        );
        await waitForInternal(
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
        await writeSkillInternal(
          actualSkillRoot,
          'linked-browser',
          skillName: 'Linked Browser',
          description: 'Loaded through a symlinked directory',
        );
        await Link(
          '${sharedRoot.path}/linked-pack',
        ).create(actualSkillRoot.path);

        final controller = AppController(
          store: await createStoreInternal(tempDirectory.path),
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          singleAgentSharedSkillScanRootOverrides: <String>[sharedRoot.path],
        );
        addTearDown(controller.dispose);
        await waitForInternal(() => !controller.initializing);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await waitForInternal(
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
        await writeSkillInternal(
          agentsRoot,
          'browser',
          skillName: 'Browser',
          description: 'Browser tasks',
        );

        final controller = AppController(
          store: await createStoreInternal(tempDirectory.path),
          skillDirectoryAccessService: FakeSkillDirectoryAccessServiceInternal(
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
        await waitForInternal(() => !controller.initializing);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await waitForInternal(
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
        await writeSkillInternal(
          fixedRoot,
          'docx',
          skillName: 'docx',
          description: 'Fixed root version',
        );
        await writeSkillInternal(
          externalRepoSkill.parent,
          'docx',
          skillName: 'docx',
          description: 'Imported package version',
        );

        final store = await createStoreInternal(tempDirectory.path);
        await store.saveSettingsSnapshot(
          singleAgentTestSettingsInternal(
            workspacePath: tempDirectory.path,
          ).copyWith(
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
        await waitForInternal(() => !controller.initializing);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await waitForInternal(
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
