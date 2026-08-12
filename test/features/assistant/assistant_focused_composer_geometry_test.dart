import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_clipboard.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_skill_picker.dart';
import 'package:xworkmate/features/assistant/assistant_page_main.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  testWidgets('keeps the composer in its expanded-pane work column', (
    tester,
  ) async {
    final controller = AppController();
    final inputController = TextEditingController();
    tester.view.physicalSize = const Size(1600, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Material(
          child: SizedBox(
            width: 1600,
            height: 240,
            child: AssistantLowerPaneInternal(
              bottomContentInset: 0,
              horizontalContentInsets: const EdgeInsets.only(
                left: assistantFocusedComposerLeftInsetInternal,
                right: assistantFocusedComposerRightInsetInternal,
              ),
              controller: controller,
              inputController: inputController,
              focusNode: FocusNode(),
              thinkingLabel: 'medium',
              showModelControl: false,
              modelLabel: 'gpt-5.4',
              modelOptions: const <String>[],
              attachments: const <ComposerAttachmentInternal>[],
              availableSkills: const <ComposerSkillOptionInternal>[],
              selectedSkillKeys: const <String>[],
              onRemoveAttachment: (_) {},
              onToggleSkill: (_) {},
              onThinkingChanged: (_) {},
              onModelChanged: (_) async {},
              onPickAttachments: () {},
              onAddAttachment: (_) {},
              onPasteImageAttachment: () async => null,
              onSend: () async {},
            ),
          ),
        ),
      ),
    );

    final composer = tester.getRect(
      find.byKey(const Key('assistant-composer-input-area')),
    );
    expect(
      composer.left,
      greaterThanOrEqualTo(assistantFocusedComposerLeftInsetInternal),
    );
    expect(
      composer.right,
      lessThanOrEqualTo(1600 - assistantFocusedComposerRightInsetInternal),
    );
  });
}
