import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.compact = false});

  final StatusInfo status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tone = switch (status.tone) {
      StatusTone.neutral => (palette.surfaceTertiary, palette.textSecondary),
      StatusTone.accent => (palette.accentMuted, palette.accent),
      StatusTone.success => (
        palette.success.withValues(alpha: 0.14),
        palette.success,
      ),
      StatusTone.warning => (
        palette.warning.withValues(alpha: 0.14),
        palette.warning,
      ),
      StatusTone.danger => (
        palette.danger.withValues(alpha: 0.14),
        palette.danger,
      ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.xs : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: tone.$1,
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: tone.$2,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
