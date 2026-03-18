import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

enum SectionTabsSize { small, medium }

class SectionTabs extends StatelessWidget {
  const SectionTabs({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.size = SectionTabsSize.medium,
  });

  final List<String> items;
  final String value;
  final ValueChanged<String> onChanged;
  final SectionTabsSize size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final padding = switch (size) {
      SectionTabsSize.small => const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.compact,
      ),
      SectionTabsSize.medium => const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.compact,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items.map((item) {
            final selected = item == value;
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xxs),
              child: _SectionTabChip(
                label: item,
                selected: selected,
                padding: padding,
                onTap: () => onChanged(item),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SectionTabChip extends StatefulWidget {
  const _SectionTabChip({
    required this.label,
    required this.selected,
    required this.padding,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final VoidCallback onTap;

  @override
  State<_SectionTabChip> createState() => _SectionTabChipState();
}

class _SectionTabChipState extends State<_SectionTabChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: widget.selected
              ? palette.surfacePrimary
              : _hovered
              ? palette.surfaceTertiary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(
            color: widget.selected ? palette.stroke : Colors.transparent,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.button),
            onTap: widget.onTap,
            child: Padding(
              padding: widget.padding,
              child: Text(
                widget.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: widget.selected
                      ? palette.textPrimary
                      : palette.textSecondary,
                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
