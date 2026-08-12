import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// A quiet, edge-aligned entry point used when a workspace pane is hidden.
///
/// Keeping the two reveal affordances visually identical lets the canvas stay
/// focused while still making the hidden navigation and artifact panes easy to
/// rediscover.
class CollapsedPaneRevealButton extends StatefulWidget {
  const CollapsedPaneRevealButton({
    super.key,
    required this.onTap,
    required this.tooltip,
    required this.icon,
    this.buttonKey,
  });

  final VoidCallback onTap;
  final String tooltip;
  final IconData icon;
  final Key? buttonKey;

  @override
  State<CollapsedPaneRevealButton> createState() =>
      _CollapsedPaneRevealButtonState();
}

class _CollapsedPaneRevealButtonState extends State<CollapsedPaneRevealButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final active = _hovered || _pressed;

    return Semantics(
      button: true,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: active ? 36 : 32,
            height: 36,
            decoration: BoxDecoration(
              color: active ? palette.surfacePrimary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? palette.strokeSoft : Colors.transparent,
              ),
              boxShadow: active
                  ? <BoxShadow>[
                      BoxShadow(
                        color: palette.shadow.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: widget.buttonKey,
                borderRadius: BorderRadius.circular(10),
                onTap: widget.onTap,
                onHighlightChanged: (pressed) =>
                    setState(() => _pressed = pressed),
                child: Center(
                  child: Icon(
                    widget.icon,
                    size: 20,
                    color: active ? palette.textPrimary : palette.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
