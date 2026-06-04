import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class DesktopInputHandler {
  DesktopInputHandler({required this.onSendInput});

  final void Function(Map<String, dynamic> event) onSendInput;
  int _lastPressedButton = 1; // Default to left click

  void handlePointerMove(
    PointerEvent event,
    Size widgetSize, {
    Size? contentSize,
  }) {
    final position = desktopContentPosition(
      event.localPosition,
      widgetSize,
      contentSize: contentSize,
    );
    if (position == null) return;

    onSendInput({'type': 'mouse_move', 'x': position.dx, 'y': position.dy});
  }

  void handlePointerDown(
    PointerDownEvent event,
    Size widgetSize, {
    Size? contentSize,
  }) {
    final position = desktopContentPosition(
      event.localPosition,
      widgetSize,
      contentSize: contentSize,
    );
    if (position == null) return;

    // Send move event first to ensure click hits the exact coordinates
    onSendInput({'type': 'mouse_move', 'x': position.dx, 'y': position.dy});

    _lastPressedButton = _mapPointerButtons(event.buttons);

    onSendInput({'type': 'mouse_down', 'button': _lastPressedButton});
  }

  void handlePointerUp(PointerUpEvent event, Size widgetSize) {
    // Under pointer up, buttons bitmask represents STILL pressed buttons.
    // If it is 0, then the released button is the one we tracked in PointerDown.
    int releasedButton = _lastPressedButton;
    if (event.buttons != 0) {
      releasedButton = _mapPointerButtons(event.buttons);
    }

    onSendInput({'type': 'mouse_up', 'button': releasedButton});
  }

  void handleScroll(PointerScrollEvent event) {
    // 4 = scroll up, 5 = scroll down in X11/xdotool button maps
    final button = event.scrollDelta.dy < 0 ? 4 : 5;
    onSendInput({'type': 'scroll', 'button': button});
  }

  void handleKeyEvent(KeyEvent event) {
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    final keyLabel = desktopKeyName(event.logicalKey);
    if (keyLabel == null) return;

    onSendInput({'type': isDown ? 'key_down' : 'key_up', 'key': keyLabel});
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

String? desktopKeyName(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.enter) return 'Return';
  if (key == LogicalKeyboardKey.numpadEnter) return 'Return';
  if (key == LogicalKeyboardKey.space) return 'space';
  if (key == LogicalKeyboardKey.backspace) return 'BackSpace';
  if (key == LogicalKeyboardKey.tab) return 'Tab';
  if (key == LogicalKeyboardKey.escape) return 'Escape';
  if (key == LogicalKeyboardKey.delete) return 'Delete';
  if (key == LogicalKeyboardKey.arrowLeft) return 'Left';
  if (key == LogicalKeyboardKey.arrowRight) return 'Right';
  if (key == LogicalKeyboardKey.arrowUp) return 'Up';
  if (key == LogicalKeyboardKey.arrowDown) return 'Down';
  if (key == LogicalKeyboardKey.home) return 'Home';
  if (key == LogicalKeyboardKey.end) return 'End';
  if (key == LogicalKeyboardKey.pageUp) return 'Page_Up';
  if (key == LogicalKeyboardKey.pageDown) return 'Page_Down';
  
  if (key == LogicalKeyboardKey.shiftLeft) return 'Shift_L';
  if (key == LogicalKeyboardKey.shiftRight) return 'Shift_R';
  if (key == LogicalKeyboardKey.controlLeft) return 'Control_L';
  if (key == LogicalKeyboardKey.controlRight) return 'Control_R';
  if (key == LogicalKeyboardKey.altLeft) return 'Alt_L';
  if (key == LogicalKeyboardKey.altRight) return 'Alt_R';
  if (key == LogicalKeyboardKey.metaLeft) return 'Super_L';
  if (key == LogicalKeyboardKey.metaRight) return 'Super_R';
  if (key == LogicalKeyboardKey.capsLock) return 'Caps_Lock';

  final label = key.keyLabel;
  if (label.isEmpty) return null;
  if (label.length == 1) {
    final punctuation = _xdotoolPunctuationNames[label];
    if (punctuation != null) return punctuation;
    if (RegExp(r'^[A-Z]$').hasMatch(label)) {
      return label.toLowerCase();
    }
  }
  return label;
}

const Map<String, String> _xdotoolPunctuationNames = <String, String>{
  '/': 'slash',
  '.': 'period',
  ',': 'comma',
  '-': 'minus',
  '_': 'underscore',
  '=': 'equal',
  ';': 'semicolon',
  "'": 'apostrophe',
  '`': 'grave',
  '[': 'bracketleft',
  ']': 'bracketright',
  '\\': 'backslash',
  '!': 'exclam',
  '@': 'at',
  '#': 'numbersign',
  '\$': 'dollar',
  '%': 'percent',
  '^': 'asciicircum',
  '&': 'ampersand',
  '*': 'asterisk',
  '(': 'parenleft',
  ')': 'parenright',
  '+': 'plus',
  '{': 'braceleft',
  '}': 'braceright',
  '|': 'bar',
  ':': 'colon',
  '"': 'quotedbl',
  '<': 'less',
  '>': 'greater',
  '?': 'question',
  '~': 'asciitilde',
};

Offset? desktopContentPosition(
  Offset localPosition,
  Size viewportSize, {
  Size? contentSize,
}) {
  if (viewportSize.width <= 0 || viewportSize.height <= 0) return null;

  if (contentSize == null || contentSize.width <= 0 || contentSize.height <= 0) {
    return Offset(
      (localPosition.dx / viewportSize.width).clamp(0.0, 1.0),
      (localPosition.dy / viewportSize.height).clamp(0.0, 1.0),
    );
  }

  final double viewportRatio = viewportSize.width / viewportSize.height;
  final double contentRatio = contentSize.width / contentSize.height;

  double renderedWidth;
  double renderedHeight;

  if (viewportRatio > contentRatio) {
    // Viewport is wider, so height is the constraint
    renderedHeight = viewportSize.height;
    renderedWidth = renderedHeight * contentRatio;
  } else {
    // Viewport is taller, so width is the constraint
    renderedWidth = viewportSize.width;
    renderedHeight = renderedWidth / contentRatio;
  }

  final double dxOffset = (viewportSize.width - renderedWidth) / 2;
  final double dyOffset = (viewportSize.height - renderedHeight) / 2;

  return Offset(
    ((localPosition.dx - dxOffset) / renderedWidth).clamp(0.0, 1.0),
    ((localPosition.dy - dyOffset) / renderedHeight).clamp(0.0, 1.0),
  );
}
