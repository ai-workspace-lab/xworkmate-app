import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
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
}
