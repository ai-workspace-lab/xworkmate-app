import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'status_badge.dart';
import 'surface_card.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.metric});

  final MetricSummary metric;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.surfaceSecondary,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Icon(metric.icon, color: palette.textPrimary, size: 20),
              ),
              const Spacer(),
              if (metric.status != null)
                StatusBadge(status: metric.status!, compact: true),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(metric.label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(metric.value, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(metric.caption, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
