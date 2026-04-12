import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_clipboard.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_skill_models.dart';
import 'package:xworkmate/features/assistant/assistant_page_main.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/surface_card.dart';

void main() {
  testWidgets('assistant lower pane matches desktop baseline', (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);

    await controller.sessionsController.switchSession('session-1');
    await tester.binding.setSurfaceSize(const Size(1400, 360));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: 1400,
              height: 360,
              child: SurfaceCard(
                child: AssistantLowerPaneInternal(
                  bottomContentInset: 0,
                  controller: controller,
                  inputController: TextEditingController(text: '修复智能体模式'),
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
                  onComposerContentHeightChanged: (_) {},
                  onComposerInputHeightChanged: (_) {},
                  onSend: () async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/assistant_lower_pane.png'),
    );
  });
}
