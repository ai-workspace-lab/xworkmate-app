import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_clipboard.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_skill_picker.dart';
import 'package:xworkmate/features/assistant/assistant_page_main.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/pane_resize_handle.dart';
import 'package:xworkmate/widgets/surface_card.dart';

/// The desktop composer's key contract. Before this, the field was multiline
/// (`maxLines: null`), so its `onSubmitted` never fired and Enter did nothing —
/// clicking Submit was the only way to send.
void main() {
  group('composer input contract', () {
    testWidgets('Enter sends the draft', (tester) async {
      final controller = _controller(tester);
      final input = TextEditingController(text: 'ship it');
      var sends = 0;

      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 320,
            child: _lowerPane(
              controller: controller,
              inputController: input,
              onSend: () async => sends++,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('assistant-input-field')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sends, 1);
    });

    testWidgets('Shift+Enter inserts a newline instead of sending', (
      tester,
    ) async {
      final controller = _controller(tester);
      final input = TextEditingController(text: 'line one');
      var sends = 0;

      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 320,
            child: _lowerPane(
              controller: controller,
              inputController: input,
              onSend: () async => sends++,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('assistant-input-field')));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(sends, 0, reason: 'Shift+Enter must not send');
    });

    testWidgets('Cmd+Enter also sends', (tester) async {
      final controller = _controller(tester);
      final input = TextEditingController(text: 'ship it');
      var sends = 0;

      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 320,
            child: _lowerPane(
              controller: controller,
              inputController: input,
              onSend: () async => sends++,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('assistant-input-field')));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(sends, 1);
    });

    testWidgets('an empty draft cannot be sent, by key or by button', (
      tester,
    ) async {
      final controller = _controller(tester);
      final input = TextEditingController(text: '   ');
      var sends = 0;

      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 320,
            child: _lowerPane(
              controller: controller,
              inputController: input,
              onSend: () async => sends++,
            ),
          ),
        ),
      );
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('assistant-send-button')),
      );
      expect(button.onPressed, isNull, reason: 'whitespace is not a draft');

      await tester.tap(find.byKey(const Key('assistant-input-field')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sends, 0);
    });

    // The card fills the pane it is given, so dragging the lower pane taller
    // grows the writing area instead of stranding the card at the bottom of an
    // empty gap. Regression guard for the height-linkage report.
    for (final paneHeight in <double>[240, 360, 520]) {
      testWidgets('the composer fills a ${paneHeight.toInt()}px pane', (
        tester,
      ) async {
        final controller = _controller(tester);
        final input = TextEditingController();

        await tester.pumpWidget(
          _app(
            SizedBox(
              height: paneHeight,
              child: _lowerPane(controller: controller, inputController: input),
            ),
          ),
        );
        await tester.pump();

        // No leftover gap: the card reaches the bottom of its pane.
        final pane = tester.getRect(find.byType(SurfaceCard));
        final card = tester.getRect(
          find.byKey(const Key('assistant-composer-input-area')),
        );
        expect(
          card.height,
          greaterThan(0),
          reason: 'the writing area must absorb the pane slack',
        );
        expect(pane.height, closeTo(paneHeight, 0.5));
        expect(tester.takeException(), isNull);
      });
    }

    // Every pane boundary in the app uses the same grammar: a 1px line
    // overlaid on the seam with a wider grab area, costing no layout space.
    // The transcript/composer divider used to be the odd one out — a colored
    // strip that ate 8px of the workspace.
    testWidgets('the composer boundary reserves no layout height', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      children: const [
                        Expanded(child: SizedBox()),
                        SizedBox(height: 160),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 160 - PaneResizeHandle.defaultHitExtent / 2,
                    height: PaneResizeHandle.defaultHitExtent,
                    child: PaneResizeHandle(
                      axis: Axis.vertical,
                      onDelta: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The visible line is a hairline; the grab area is wider and overlaid.
      final line = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(line.constraints?.maxHeight, 1);
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byType(PaneResizeHandle),
                matching: find.byType(SizedBox),
              ),
            )
            .height,
        PaneResizeHandle.defaultHitExtent,
      );
    });

    testWidgets('the second, redundant resize handle is gone', (tester) async {
      final controller = _controller(tester);
      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 320,
            child: _lowerPane(
              controller: controller,
              inputController: TextEditingController(),
            ),
          ),
        ),
      );
      await tester.pump();

      // Height is owned by the lower pane's handle alone.
      expect(
        find.byKey(const Key('assistant-composer-resize-handle')),
        findsNothing,
      );
    });

    testWidgets('a non-empty draft enables the send button', (tester) async {
      final controller = _controller(tester);
      final input = TextEditingController(text: 'ship it');

      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 320,
            child: _lowerPane(controller: controller, inputController: input),
          ),
        ),
      );
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('assistant-send-button')),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}

AppController _controller(WidgetTester tester) {
  final controller = AppController(
    environmentOverride: const <String, String>{},
  );
  addTearDown(controller.dispose);
  return controller;
}

// The composer always receives a bounded height in the app (the lower pane is
// a SizedBox of the computed pane height), so the harness gives it one too.
Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

Widget _lowerPane({
  required AppController controller,
  required TextEditingController inputController,
  Future<void> Function()? onSend,
}) {
  return SurfaceCard(
    child: AssistantLowerPaneInternal(
      bottomContentInset: 0,
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
      onSend: onSend ?? () async {},
    ),
  );
}
