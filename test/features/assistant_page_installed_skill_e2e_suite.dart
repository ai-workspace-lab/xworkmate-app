// ignore_for_file: unused_import, unnecessary_import

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_sessions.dart';
import 'package:xworkmate/app/app_controller_desktop_workspace_execution.dart';
import 'package:xworkmate/runtime/desktop_thread_artifact_service.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

import 'assistant_page_suite_support.dart';

void main() {
  group('AssistantPage installed skill E2E harness', () {
    for (final testCase in installedSkillE2ECasesInternal) {
      test('discovers, binds, and handoffs ${testCase.skillKey}', () async {
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-installed-skill-${testCase.skillKey}-',
        );
        addTearDown(() async {
          if (await tempDirectory.exists()) {
            try {
              await tempDirectory.delete(recursive: true);
            } catch (_) {}
          }
        });

        final skillsRoot = Directory('${tempDirectory.path}/installed-skills');
        final workspaceRoot = Directory('${tempDirectory.path}/workspace');
        await workspaceRoot.create(recursive: true);

        await writeSkillInternal(
          skillsRoot,
          'pptx',
          skillName: 'pptx',
          description: 'Presentation creation, editing, and QA.',
        );
        await writeSkillInternal(
          skillsRoot,
          'docx',
          skillName: 'docx',
          description: 'Word document authoring and editing.',
        );
        await writeSkillInternal(
          skillsRoot,
          'xlsx',
          skillName: 'xlsx',
          description: 'Spreadsheet authoring and formula validation.',
        );
        await writeSkillInternal(
          skillsRoot,
          'pdf',
          skillName: 'pdf',
          description: 'PDF extraction, creation, and form workflows.',
        );

        final controller = await createInstalledSkillE2EControllerSimpleInternal(
          tempDirectory: tempDirectory,
          skillsRoot: skillsRoot,
          workspaceRoot: workspaceRoot,
          testCase: testCase,
        );

        final sendFuture = controller.sendChatMessage(
          testCase.prompt,
          selectedSkillLabels: <String>[testCase.skillKey],
        );
        await waitForConditionInternal(() => controller.sendCallCount == 1);

        expect(controller.lastSentMessage, contains(testCase.prompt));
        expect(controller.lastPromptInternal, contains(testCase.prompt));
        expect(
          controller.lastSelectedSkillLabelsInternal,
          equals(<String>[testCase.skillKey]),
        );
        expect(controller.lastWorkspacePathInternal, isNotEmpty);

        controller.sendGate.complete();
        await sendFuture;

        final artifactService = DesktopThreadArtifactService();
        final snapshot = await artifactService.loadSnapshot(
          workspacePath: controller.lastWorkspacePathInternal,
          workspaceKind: WorkspaceRefKind.localPath,
        );

        expect(
          snapshot.fileEntries.map((item) => item.relativePath),
          contains(testCase.outputRelativePath),
        );
        expect(
          snapshot.resultEntries.map((item) => item.relativePath),
          contains(testCase.outputRelativePath),
        );
      });
    }

    test('records deferred media skill coverage explicitly', () {
      expect(
        installedSkillE2EDeferredCoverageInternal,
        equals(const <String>[
          'image-cog',
          'wan-image-video-generation-editting',
          'video-translator',
          'image-resizer',
        ]),
      );
    }, skip: 'Deferred until the media skill packs are installed.');
  });
}
