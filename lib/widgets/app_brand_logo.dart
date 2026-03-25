import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

enum DoorLogoSide { left, right, doubleDoor }

class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({
    super.key,
    this.size = 32,
    this.borderRadius = 10,
    this.showShadow = true,
  });

  final double size;
  final double borderRadius;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final iconColor = palette.textPrimary;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: palette.chromeStroke),
        boxShadow: showShadow ? [palette.chromeShadowLift] : const [],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.16),
        child: CustomPaint(
          painter: _DoorLogoPainter(
            color: iconColor,
            side: DoorLogoSide.doubleDoor,
          ),
        ),
      ),
    );
  }
}

class DoorLogoIcon extends StatelessWidget {
  const DoorLogoIcon({
    super.key,
    required this.side,
    required this.color,
    this.size = 22,
  });

  final DoorLogoSide side;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DoorLogoPainter(color: color, side: side),
      ),
    );
  }
}

class _DoorLogoPainter extends CustomPainter {
  const _DoorLogoPainter({required this.color, required this.side});

  final Color color;
  final DoorLogoSide side;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final panel = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.82
      ..strokeCap = StrokeCap.round;

    final shell = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.14,
        size.height * 0.16,
        size.width * 0.72,
        size.height * 0.68,
      ),
      Radius.circular(size.width * 0.16),
    );
    canvas.drawRRect(shell, outline);

    final centerX = size.width * 0.5;
    canvas.drawLine(
      Offset(centerX, size.height * 0.2),
      Offset(centerX, size.height * 0.8),
      outline,
    );

    switch (side) {
      case DoorLogoSide.left:
        _paintLeftDoor(canvas, size, panel);
      case DoorLogoSide.right:
        _paintRightDoor(canvas, size, panel);
      case DoorLogoSide.doubleDoor:
        _paintLeftDoor(canvas, size, panel);
        _paintRightDoor(canvas, size, panel);
        _paintHandles(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _DoorLogoPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.side != side;
  }

  void _paintLeftDoor(Canvas canvas, Size size, Paint panel) {
    final insetTop = size.height * 0.25;
    final insetBottom = size.height * 0.75;
    final leftDoorInset = size.width * 0.3;
    canvas.drawLine(
      Offset(leftDoorInset, insetTop),
      Offset(leftDoorInset, insetBottom),
      panel,
    );
    _paintHandle(canvas, Offset(size.width * 0.435, size.height * 0.5), size);
  }

  void _paintRightDoor(Canvas canvas, Size size, Paint panel) {
    final insetTop = size.height * 0.25;
    final insetBottom = size.height * 0.75;
    final rightDoorInset = size.width * 0.7;
    canvas.drawLine(
      Offset(rightDoorInset, insetTop),
      Offset(rightDoorInset, insetBottom),
      panel,
    );
    _paintHandle(canvas, Offset(size.width * 0.565, size.height * 0.5), size);
  }

  void _paintHandles(Canvas canvas, Size size) {
    _paintHandle(canvas, Offset(size.width * 0.435, size.height * 0.5), size);
    _paintHandle(canvas, Offset(size.width * 0.565, size.height * 0.5), size);
  }

  void _paintHandle(Canvas canvas, Offset center, Size size) {
    final handlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final handleRadius = size.width * 0.035;
    canvas.drawCircle(center, handleRadius, handlePaint);
  }
}
