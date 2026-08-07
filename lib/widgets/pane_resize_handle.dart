import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// A pane boundary: a hairline divider that can optionally be dragged.
///
/// The visible part is always a 1px line running the full length of the
/// boundary (2px while hovered or dragged). When [onDelta] is set the widget
/// also claims a wider *invisible* grab area centred on that line, so the seam
/// reads as zero-gap while staying comfortably draggable.
///
/// Overlay this on the boundary with a [Positioned] inside the [Stack] that
/// holds the panes — do not insert it into the pane [Row]/[Column] as a child.
/// A child would occupy layout space and reintroduce the visible gutter that
/// this widget exists to remove.
class PaneResizeHandle extends StatefulWidget {
  const PaneResizeHandle({
    super.key,
    required this.axis,
    this.onDelta,
    this.extent,
  });

  final Axis axis;

  /// Drag callback. When null the boundary renders as a static divider and
  /// lets pointer events through to the panes underneath.
  final ValueChanged<double>? onDelta;

  /// Thickness of the grab area — not of the visible line.
  final double? extent;

  /// Grab-area thickness. Also the width/height to give the [Positioned] that
  /// overlays the boundary, so the line lands exactly on the seam.
  static const double defaultHitExtent = 8;

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
    final hitExtent = widget.extent ?? PaneResizeHandle.defaultHitExtent;
    final onDelta = widget.onDelta;
    final thickness = highlight ? 2.0 : 1.0;

    final boundary = SizedBox(
      width: isHorizontalDrag ? hitExtent : double.infinity,
      height: isHorizontalDrag ? double.infinity : hitExtent,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          width: isHorizontalDrag ? thickness : double.infinity,
          height: isHorizontalDrag ? double.infinity : thickness,
          color: highlight ? palette.accent : palette.strokeSoft,
        ),
      ),
    );

    if (onDelta == null) {
      return IgnorePointer(child: boundary);
    }

    return MouseRegion(
      cursor: isHorizontalDrag
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _dragging = true),
        onPanEnd: (_) => setState(() => _dragging = false),
        onPanCancel: () => setState(() => _dragging = false),
        onPanUpdate: (details) =>
            onDelta(isHorizontalDrag ? details.delta.dx : details.delta.dy),
        child: boundary,
      ),
    );
  }
}
