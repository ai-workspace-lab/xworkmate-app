import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

class PaneResizeHandle extends StatefulWidget {
  const PaneResizeHandle({
    super.key,
    required this.axis,
    required this.onDelta,
    this.extent,
  });

  final Axis axis;
  final ValueChanged<double> onDelta;
  final double? extent;

  @override
  State<PaneResizeHandle> createState() => _PaneResizeHandleState();
}

class _PaneResizeHandleState extends State<PaneResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isHorizontalDrag = widget.axis == Axis.horizontal;
    final highlight = _dragging || _hovered;
    final extent = widget.extent ?? 12;

    return MouseRegion(
      cursor: isHorizontalDrag
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => setState(() => _dragging = true),
        onPanEnd: (_) => setState(() => _dragging = false),
        onPanCancel: () => setState(() => _dragging = false),
        onPanUpdate: (details) => widget.onDelta(
          isHorizontalDrag ? details.delta.dx : details.delta.dy,
        ),
        child: SizedBox(
          width: isHorizontalDrag ? extent : double.infinity,
          height: isHorizontalDrag ? double.infinity : extent,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: isHorizontalDrag ? 2 : 42,
              height: isHorizontalDrag ? 42 : 2,
              decoration: BoxDecoration(
                color: highlight
                    ? palette.accent.withValues(alpha: 0.72)
                    : palette.strokeSoft,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
