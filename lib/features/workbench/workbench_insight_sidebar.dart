import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import '../../theme/app_palette.dart';
import 'workbench_projection.dart';

/// A compact desktop-only insight rail that keeps the workbench's primary
/// canvas intact while making operational signals available at a glance.
class WorkbenchInsightSidebar extends StatelessWidget {
  const WorkbenchInsightSidebar({
    super.key,
    required this.projection,
    required this.expanded,
    required this.onToggle,
  });

  final WorkbenchProjection projection;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedContainer(
      key: expanded ? null : const Key('workbench-insight-sidebar-collapsed'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: expanded ? 320 : 44,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: palette.chromeBackground,
        border: Border(left: BorderSide(color: palette.strokeSoft)),
      ),
      child: expanded
          ? _InsightRailContent(projection: projection, onToggle: onToggle)
          : Center(
              child: Tooltip(
                message: appText('展开工作洞察', 'Show work insights'),
                child: IconButton(
                  key: const Key('workbench-insights-expand-button'),
                  onPressed: onToggle,
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: palette.textSecondary,
                ),
              ),
            ),
    );
  }
}

class _InsightRailContent extends StatelessWidget {
  const _InsightRailContent({required this.projection, required this.onToggle});

  final WorkbenchProjection projection;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final completionRate = projection.items.isEmpty
        ? 0.0
        : projection.completedCount / projection.items.length;
    final averageProgress = projection.items.isEmpty
        ? 0.0
        : projection.items.fold<double>(0, (sum, item) => sum + item.progress) /
              projection.items.length;
    final rhythm = (averageProgress * 0.72 + completionRate * 0.28).clamp(
      0.0,
      1.0,
    );

    return Semantics(
      container: true,
      label: appText('工作洞察', 'Work insights'),
      child: Column(
        key: const Key('workbench-insight-sidebar'),
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 0, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          appText('工作洞察', 'Work insights'),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Tooltip(
                        message: appText('收起工作洞察', 'Hide work insights'),
                        child: IconButton(
                          key: const Key('workbench-insights-collapse-button'),
                          onPressed: onToggle,
                          icon: const Icon(Icons.chevron_right_rounded),
                          color: palette.textSecondary,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
                _InsightCard(
                  key: const Key('workbench-workload-trend'),
                  title: appText('7 日工作负荷趋势', '7-day workload trend'),
                  child: _WorkloadTrend(series: projection.workloadSeries),
                ),
                const SizedBox(height: 12),
                _InsightCard(
                  key: const Key('workbench-rhythm-progress'),
                  title: appText('本周节奏', 'Weekly rhythm'),
                  child: _RhythmProgress(
                    rhythm: rhythm,
                    completionRate: completionRate,
                    activeCount:
                        projection.items.length - projection.completedCount,
                  ),
                ),
                const SizedBox(height: 12),
                _InsightCard(
                  key: const Key('workbench-ai-recommendations'),
                  title: appText('AI 整理建议', 'AI recommendations'),
                  child: _Recommendations(projection: projection),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _WorkloadTrend extends StatelessWidget {
  const _WorkloadTrend({required this.series});

  final List<double> series;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final normalized = series.isEmpty ? List<double>.filled(7, 0) : series;
    final maximum = normalized.fold<double>(1, math.max);
    final labels = activeAppLanguage == AppLanguage.zh
        ? const ['一', '二', '三', '四', '五', '六', '日']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return SizedBox(
      height: 132,
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _WorkloadTrendPainter(
                values: normalized,
                maximum: maximum,
                lineColor: palette.accent,
                fillColor: palette.accent.withValues(alpha: 0.14),
                gridColor: palette.strokeSoft,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels
                .map(
                  (label) => Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.textMuted,
                      fontSize: 10,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _WorkloadTrendPainter extends CustomPainter {
  const _WorkloadTrendPainter({
    required this.values,
    required this.maximum,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  final List<double> values;
  final double maximum;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var index = 0; index < 4; index++) {
      final y = size.height * index / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.length < 2) return;

    final points = List.generate(values.length, (index) {
      final x = size.width * index / (values.length - 1);
      final y = size.height - (values[index] / maximum) * (size.height - 8) - 4;
      return Offset(x, y.clamp(4, size.height - 4));
    });
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final middleX = (previous.dx + current.dx) / 2;
      line.cubicTo(
        middleX,
        previous.dy,
        middleX,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    final fill = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = fillColor);
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 2.6, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(covariant _WorkloadTrendPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.maximum != maximum ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.gridColor != gridColor;
}

class _RhythmProgress extends StatelessWidget {
  const _RhythmProgress({
    required this.rhythm,
    required this.completionRate,
    required this.activeCount,
  });

  final double rhythm;
  final double completionRate;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final percent = (rhythm * 100).round();
    return Row(
      children: [
        SizedBox(
          width: 86,
          height: 86,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: CircularProgressIndicator(
                  value: rhythm,
                  strokeWidth: 10,
                  backgroundColor: palette.surfaceTertiary,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
                ),
              ),
              Text(
                '$percent%',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProgressDatum(
                label: appText('完成率', 'Completion'),
                value: '${(completionRate * 100).round()}%',
              ),
              const SizedBox(height: 8),
              _ProgressDatum(
                label: appText('推进中', 'In progress'),
                value: '$activeCount',
              ),
              const SizedBox(height: 8),
              Text(
                appText('节奏指数', 'Rhythm score'),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressDatum extends StatelessWidget {
  const _ProgressDatum({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _Recommendations extends StatelessWidget {
  const _Recommendations({required this.projection});

  final WorkbenchProjection projection;

  @override
  Widget build(BuildContext context) {
    final recommendations = _recommendations(projection);
    final palette = context.palette;
    return Column(
      children: [
        for (var index = 0; index < recommendations.length; index++)
          Padding(
            padding: EdgeInsets.only(
              bottom: index == recommendations.length - 1 ? 0 : 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 19,
                  height: 19,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.accentMuted,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recommendations[index],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

List<String> _recommendations(WorkbenchProjection projection) {
  final recommendations = <String>[];
  if (projection.blockedCount > 0) {
    recommendations.add(
      appText(
        '优先处理 ${projection.blockedCount} 个受阻任务，避免它们影响本周节奏。',
        'Resolve ${projection.blockedCount} blocked task(s) first to protect this week’s rhythm.',
      ),
    );
  }
  if (projection.syncingCount > 0) {
    recommendations.add(
      appText(
        '跟进 ${projection.syncingCount} 个正在同步的任务，确认产物是否可用。',
        'Check ${projection.syncingCount} syncing task(s) and confirm their artifacts are available.',
      ),
    );
  }
  final next = projection.items
      .where((item) => !item.isCompleted)
      .cast<WorkbenchItem?>()
      .firstWhere((item) => item != null, orElse: () => null);
  if (next != null) {
    recommendations.add(
      appText(
        '为「${next.title}」明确下一步，减少上下文切换。',
        'Set one clear next step for “${next.title}” to reduce context switching.',
      ),
    );
  }
  if (recommendations.isEmpty) {
    recommendations.add(
      appText(
        '暂未发现需要处理的任务，保持当前节奏即可。',
        'No task needs attention right now; keep the current rhythm.',
      ),
    );
  }
  return recommendations.take(3).toList(growable: false);
}
