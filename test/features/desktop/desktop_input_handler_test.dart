import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xworkmate/features/desktop/desktop_input_handler.dart';

void main() {
  group('desktopKeyName', () {
    test('uses xdotool-compatible names for basic terminal keys', () {
      expect(desktopKeyName(LogicalKeyboardKey.enter), 'Return');
      expect(desktopKeyName(LogicalKeyboardKey.numpadEnter), 'Return');
      expect(desktopKeyName(LogicalKeyboardKey.space), 'space');
      expect(desktopKeyName(LogicalKeyboardKey.backspace), 'BackSpace');
      expect(desktopKeyName(LogicalKeyboardKey.tab), 'Tab');
      expect(desktopKeyName(LogicalKeyboardKey.escape), 'Escape');
    });

    test('uses xdotool-compatible names for navigation keys', () {
      expect(desktopKeyName(LogicalKeyboardKey.arrowLeft), 'Left');
      expect(desktopKeyName(LogicalKeyboardKey.arrowRight), 'Right');
      expect(desktopKeyName(LogicalKeyboardKey.arrowUp), 'Up');
      expect(desktopKeyName(LogicalKeyboardKey.arrowDown), 'Down');
      expect(desktopKeyName(LogicalKeyboardKey.pageUp), 'Page_Up');
      expect(desktopKeyName(LogicalKeyboardKey.pageDown), 'Page_Down');
    });

    test('keeps printable keys available for shell and browser text input', () {
      expect(desktopKeyName(LogicalKeyboardKey.keyA), 'a');
      expect(desktopKeyName(LogicalKeyboardKey.digit1), '1');
      expect(desktopKeyName(LogicalKeyboardKey.period), 'period');
      expect(desktopKeyName(LogicalKeyboardKey.slash), 'slash');
      expect(desktopKeyName(LogicalKeyboardKey.minus), 'minus');
    });
  });

  group('desktopContentPosition', () {
    test('maps directly when viewport and content share an aspect ratio', () {
      final position = desktopContentPosition(
        const Offset(640, 360),
        const Size(1280, 720),
        contentSize: const Size(1280, 720),
      );

      expect(position, const Offset(0.5, 0.5));
    });

    test('subtracts horizontal letterbox before normalizing pointer input', () {
      final position = desktopContentPosition(
        const Offset(160, 360),
        const Size(1600, 720),
        contentSize: const Size(1280, 720),
      );

      expect(position!.dx, closeTo(0.0, 0.001));
      expect(position.dy, closeTo(0.5, 0.001));
    });

    test('subtracts vertical letterbox before normalizing pointer input', () {
      final position = desktopContentPosition(
        const Offset(640, 140),
        const Size(1280, 1000),
        contentSize: const Size(1280, 720),
      );

      expect(position!.dx, closeTo(0.5, 0.001));
      expect(position.dy, closeTo(0.0, 0.001));
    });

    test('keeps legacy full-viewport mapping when content size is unknown', () {
      final position = desktopContentPosition(
        const Offset(640, 360),
        const Size(1280, 720),
      );

      expect(position, const Offset(0.5, 0.5));
    });
  });

  group('DesktopInputHandler pointer flow control', () {
    test('throttles pointer move events before they hit the data channel', () {
      var now = 0;
      final events = <Map<String, dynamic>>[];
      final handler = DesktopInputHandler(
        onSendInput: events.add,
        nowMillis: () => now,
      );

      handler.handlePointerMove(
        const PointerHoverEvent(position: Offset(10, 10)),
        const Size(100, 100),
      );
      now = 5;
      handler.handlePointerMove(
        const PointerHoverEvent(position: Offset(20, 20)),
        const Size(100, 100),
      );
      now = 16;
      handler.handlePointerMove(
        const PointerHoverEvent(position: Offset(30, 30)),
        const Size(100, 100),
      );

      expect(events, hasLength(2));
      expect(events.first['x'], 0.1);
      expect(events.last['x'], 0.3);
    });

    test('deduplicates unchanged pointer move positions', () {
      var now = 0;
      final events = <Map<String, dynamic>>[];
      final handler = DesktopInputHandler(
        onSendInput: events.add,
        nowMillis: () => now,
      );

      handler.handlePointerMove(
        const PointerHoverEvent(position: Offset(10, 10)),
        const Size(100, 100),
      );
      now = 100;
      handler.handlePointerMove(
        const PointerHoverEvent(position: Offset(10, 10)),
        const Size(100, 100),
      );

      expect(events, hasLength(1));
    });

    test('forces latest pointer position before mouse down', () {
      var now = 0;
      final events = <Map<String, dynamic>>[];
      final handler = DesktopInputHandler(
        onSendInput: events.add,
        nowMillis: () => now,
      );

      handler.handlePointerMove(
        const PointerHoverEvent(position: Offset(10, 10)),
        const Size(100, 100),
      );
      now = 5;
      handler.handlePointerDown(
        const PointerDownEvent(
          position: Offset(80, 20),
          buttons: kPrimaryMouseButton,
        ),
        const Size(100, 100),
      );

      expect(events, hasLength(3));
      expect(events[1], containsPair('type', 'mouse_move'));
      expect(events[1]['x'], 0.8);
      expect(events[2], containsPair('type', 'mouse_down'));
    });
  });
}
