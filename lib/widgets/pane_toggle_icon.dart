import 'package:flutter/material.dart';

/// Which edge of the window the pane sits on.
enum PaneSide { left, right }

/// The panel glyph used by every control that shows or hides a side pane: a
/// rounded frame with a divider on the pane's side. One glyph for both panes,
/// mirrored, instead of chevrons that point in whichever way the pane moves.
///
/// Size and colour come from the surrounding [IconTheme], so it drops into an
/// [IconButton] like an [Icon].
class PaneToggleIcon extends StatelessWidget {
  const PaneToggleIcon({super.key, required this.side, this.size, this.color});

  final PaneSide side;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final extent = size ?? iconTheme.size ?? 24;
    return SizedBox.square(
      dimension: extent,
      child: CustomPaint(
        painter: _PaneTogglePainter(
          side: side,
          color: color ?? iconTheme.color ?? const Color(0xFF000000),
        ),
      ),
    );
  }
}

class _PaneTogglePainter extends CustomPainter {
  const _PaneTogglePainter({required this.side, required this.color});

  final PaneSide side;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 24;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * unit
      ..strokeCap = StrokeCap.round;
    final frame = Rect.fromLTWH(3 * unit, 4 * unit, 18 * unit, 16 * unit);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, Radius.circular(3 * unit)),
      stroke,
    );
    final x = side == PaneSide.left ? 9.5 * unit : 14.5 * unit;
    canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), stroke);
  }

  @override
  bool shouldRepaint(_PaneTogglePainter oldDelegate) =>
      oldDelegate.side != side || oldDelegate.color != color;
}
