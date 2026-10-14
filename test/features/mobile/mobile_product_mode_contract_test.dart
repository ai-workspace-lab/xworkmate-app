// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/mobile/mobile_assistant_page_composer.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  testWidgets(
    'mobile roles run now through the page and offer a Bot team hand-off',
    (tester) async {
      final controller = AppController(environmentOverride: const {});
      final input = TextEditingController(text: 'refactor on mobile');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(input.dispose);
      addTearDown(focus.dispose);
      controller.sessionsControllerInternal.currentSessionKeyInternal =
          'unit-mobile-modes';
      controller.upsertTaskThreadInternal(
        'unit-mobile-modes',
        productMode: AssistantMode.engineer,
      );
      var sends = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(platform: TargetPlatform.iOS),
          home: Scaffold(
            // The page rebuilds the composer when the controller changes.
            body: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Align(
                alignment: Alignment.bottomCenter,
                child: MobileAssistantComposer(
                  controller: controller,
                  inputController: input,
                  focusNode: focus,
                  thinking: 'off',
                  bottomPadding: 0,
                  attachments: const [],
                  onPickAttachments: () {},
                  onRemoveAttachment: (_) {},
                  onThinkingChanged: (_) {},
                  onComposerStateChanged: () {},
                  onSend: () => sends++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mobile-assistant-send-button')));
      await tester.pumpAndSettle();
      expect(sends, 1);

      // No Bridge or account here: the hand-off is noted in the
      // conversation instead of being dropped.
      await tester.tap(
        find.byKey(const Key('mobile-assistant-hand-off-button')),
      );
      await tester.pumpAndSettle();
      expect(input.text, isEmpty);
      final messages =
          controller.assistantThreadMessagesInternal['unit-mobile-modes']!;
      expect(messages[messages.length - 2].text, 'refactor on mobile');
      expect(messages.last.error, isTrue);

      controller.upsertTaskThreadInternal(
        'unit-mobile-modes',
        productMode: AssistantMode.chat,
      );
      controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('mobile-assistant-hand-off-button')),
        findsNothing,
      );
    },
  );
}
