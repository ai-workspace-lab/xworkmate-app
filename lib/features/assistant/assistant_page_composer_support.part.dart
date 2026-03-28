part of 'assistant_page.dart';

class _ComposerIconButton extends StatefulWidget {
  const _ComposerIconButton({required this.icon});

  final IconData icon;

  @override
  State<_ComposerIconButton> createState() => _ComposerIconButtonState();
}

class _ComposerResizeHandle extends StatefulWidget {
  const _ComposerResizeHandle({super.key, required this.onDelta});

  final ValueChanged<double> onDelta;

  @override
  State<_ComposerResizeHandle> createState() => _ComposerResizeHandleState();
}

class _ComposerResizeHandleState extends State<_ComposerResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final highlight = _hovered || _dragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => setState(() => _dragging = true),
        onVerticalDragEnd: (_) => setState(() => _dragging = false),
        onVerticalDragCancel: () => setState(() => _dragging = false),
        onVerticalDragUpdate: (details) => widget.onDelta(details.delta.dy),
        child: SizedBox(
          height: 12,
          width: double.infinity,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 42,
              height: 2,
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

class _ComposerIconButtonState extends State<_ComposerIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _hovered ? palette.surfaceSecondary : palette.surfacePrimary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.strokeSoft),
        ),
        child: Icon(widget.icon, size: 18, color: palette.textMuted),
      ),
    );
  }
}

class _ComposerToolbarChip extends StatefulWidget {
  const _ComposerToolbarChip({
    super.key,
    this.icon,
    this.leading,
    required this.tooltip,
    required this.showChevron,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: 6,
    ),
  });

  final IconData? icon;
  final Widget? leading;
  final String tooltip;
  final bool showChevron;
  final EdgeInsetsGeometry padding;

  @override
  State<_ComposerToolbarChip> createState() => _ComposerToolbarChipState();
}

class _ComposerToolbarChipState extends State<_ComposerToolbarChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hovered ? palette.surfaceSecondary : palette.surfacePrimary,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.leading ??
                  Icon(widget.icon, size: 16, color: palette.textMuted),
              if (widget.showChevron) ...[
                const SizedBox(width: 1),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: palette.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

extension on AssistantExecutionTarget {
  IconData get icon => switch (this) {
    AssistantExecutionTarget.singleAgent => Icons.hub_outlined,
    AssistantExecutionTarget.local => Icons.computer_outlined,
    AssistantExecutionTarget.remote => Icons.cloud_outlined,
  };
}

extension on AssistantPermissionLevel {
  IconData get icon => switch (this) {
    AssistantPermissionLevel.defaultAccess => Icons.verified_user_outlined,
    AssistantPermissionLevel.fullAccess => Icons.error_outline_rounded,
  };
}

class _SingleAgentProviderBadge extends StatelessWidget {
  const _SingleAgentProviderBadge({required this.provider});

  final SingleAgentProvider provider;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final candidate = provider.badge.trim().isEmpty
        ? provider.label
        : provider.badge;
    final display = candidate.length <= 2
        ? candidate
        : candidate.substring(0, 2);
    final isAuto = provider == SingleAgentProvider.auto;
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isAuto
            ? palette.accent.withValues(alpha: 0.16)
            : palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isAuto
              ? palette.accent.withValues(alpha: 0.4)
              : palette.strokeSoft,
        ),
      ),
      child: Text(
        display,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.textMuted,
          fontWeight: FontWeight.w700,
          fontSize: 9,
          height: 1,
        ),
      ),
    );
  }
}
