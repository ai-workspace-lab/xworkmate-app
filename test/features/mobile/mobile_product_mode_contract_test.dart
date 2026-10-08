// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/mobile/mobile_assistant_page_composer.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  testWidgets(
    'mobile AutoBot manages schedules without clearing or sending the draft',
    (tester) async {
      final controller = AppController(environmentOverride: const {});
      final input = TextEditingController(text: 'scheduled mobile draft');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(input.dispose);
      addTearDown(focus.dispose);
      controller.sessionsControllerInternal.currentSessionKeyInternal =
          'unit-mobile-modes';
      controller.upsertTaskThreadInternal(
        'unit-mobile-modes',
        productMode: AssistantMode.autoBot,
      );
      var sends = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: Align(
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
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mobile-assistant-send-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assistant-bot-dialog')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('assistant-bot-prompt')))
            .controller
            ?.text,
        'scheduled mobile draft',
      );
      expect(input.text, 'scheduled mobile draft');
      expect(sends, 0);
    },
  );
}
