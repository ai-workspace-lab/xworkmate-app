import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class DesktopInputHandler {
  DesktopInputHandler({required this.onSendInput});

  final void Function(Map<String, dynamic> event) onSendInput;
  int _lastPressedButton = 1; // Default to left click

  void handlePointerMove(PointerEvent event, Size widgetSize) {
    if (widgetSize.width == 0 || widgetSize.height == 0) return;
    
    final x = event.localPosition.dx / widgetSize.width;
    final y = event.localPosition.dy / widgetSize.height;
    
    final cx = x.clamp(0.0, 1.0);
    final cy = y.clamp(0.0, 1.0);

    onSendInput({
      'type': 'mouse_move',
      'x': cx,
      'y': cy,
    });
  }

  void handlePointerDown(PointerDownEvent event, Size widgetSize) {
    if (widgetSize.width == 0 || widgetSize.height == 0) return;

    final x = event.localPosition.dx / widgetSize.width;
    final y = event.localPosition.dy / widgetSize.height;
    final cx = x.clamp(0.0, 1.0);
    final cy = y.clamp(0.0, 1.0);

    // Send move event first to ensure click hits the exact coordinates
    onSendInput({
      'type': 'mouse_move',
      'x': cx,
      'y': cy,
    });

    _lastPressedButton = _mapPointerButtons(event.buttons);

    onSendInput({
      'type': 'mouse_down',
      'button': _lastPressedButton,
    });
  }

  void handlePointerUp(PointerUpEvent event, Size widgetSize) {
    // Under pointer up, buttons bitmask represents STILL pressed buttons.
    // If it is 0, then the released button is the one we tracked in PointerDown.
    int releasedButton = _lastPressedButton;
    if (event.buttons != 0) {
      releasedButton = _mapPointerButtons(event.buttons);
    }

    onSendInput({
      'type': 'mouse_up',
      'button': releasedButton,
    });
  }

  void handleScroll(PointerScrollEvent event) {
    // 4 = scroll up, 5 = scroll down in X11/xdotool button maps
    final button = event.scrollDelta.dy < 0 ? 4 : 5;
    onSendInput({
      'type': 'scroll',
      'button': button,
    });
  }

  void handleKeyEvent(KeyEvent event) {
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    final keyLabel = event.logicalKey.keyLabel;

    onSendInput({
      'type': isDown ? 'key_down' : 'key_up',
      'key': keyLabel,
    });
  }

  int _mapPointerButtons(int buttons) {
    // Flutter buttons bitmask:
    // 1 = primary (left click)
    // 2 = secondary (right click)
    // 4 = middle click
    // Linux/xdotool mouse mapping: 1=left, 2=middle, 3=right
    if (buttons & 1 != 0) return 1;
    if (buttons & 4 != 0) return 2; // middle click
    if (buttons & 2 != 0) return 3; // right click
    return 1;
  }
}
