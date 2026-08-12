part of 'workbench_analytics.dart';

class WorkbenchDataOverview extends StatelessWidget {
  const WorkbenchDataOverview({
    super.key,
    required this.projection,
    required this.activityWindow,
    required this.onOpenThread,
  });

  final WorkbenchProjection projection;
  final int activityWindow;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    final items = _filterItems(projection.items, activityWindow);
    final messages = items.fold<int>(0, (sum, item) => sum + item.messageCount);
    final tokens = items.fold<int>(0, (sum, item) => sum + item.totalTokens);
    final activeDays = items
        .where((item) => item.updatedAtMs > 0)
        .map((item) {
          final date = DateTime.fromMillisecondsSinceEpoch(
            item.updatedAtMs.round(),
          );
          return '${date.year}-${date.month}-${date.day}';
        })
        .toSet()
        .length;
    final favoriteModel = _modelSummaries(items).firstOrNull?.model ?? '—';
    return ListView(
      key: const Key('workbench-data-overview'),
      children: [
        _MetricGrid(
          metrics: [
            ('TaskThreads', _formatInteger(items.length)),
            (appText('消息', 'Messages'), _formatInteger(messages)),
            (appText('总 Tokens', 'Total tokens'), _formatTokens(tokens)),
            (appText('活跃天数', 'Active days'), '$activeDays'),
            (
              appText('待处理', 'Needs attention'),
              _formatInteger(items.where((item) => !item.isCompleted).length),
            ),
            (
              appText('推进中专项', 'Active projects'),
              _formatInteger(
                items.map((item) => item.projectLabel).toSet().length,
              ),
            ),
            (
              appText('已归档产物', 'Artifacts'),
              _formatInteger(
                items.fold<int>(
                  0,
                  (sum, item) => sum + item.artifactPaths.length,
                ),
              ),
            ),
            (appText('最常用模型', 'Favorite model'), favoriteModel),
          ],
          columns: 4,
        ),
        const SizedBox(height: 16),
        _AnnualHeatmap(
          key: const Key('workbench-activity-heatmap'),
          items: items,
        ),
        const SizedBox(height: 16),
        _AnalyticsTable(
          key: const Key('workbench-overview-table'),
          title: appText('最近 TaskThreads', 'Recent TaskThreads'),
          items: items.take(8).toList(growable: false),
          onOpenThread: onOpenThread,
          showInputOutput: false,
        ),
      ],
    );
  }
}

class WorkbenchModelAnalysis extends StatelessWidget {
  const WorkbenchModelAnalysis({
    super.key,
    required this.projection,
    required this.activityWindow,
    required this.onOpenThread,
  });

  final WorkbenchProjection projection;
  final int activityWindow;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    final items = _filterItems(projection.items, activityWindow);
    final messages = items.fold<int>(0, (sum, item) => sum + item.messageCount);
    final input = items.fold<int>(0, (sum, item) => sum + item.inputTokens);
    final output = items.fold<int>(0, (sum, item) => sum + item.outputTokens);
    return ListView(
      key: const Key('workbench-model-analysis'),
      children: [
        _MetricGrid(
          metrics: [
            ('TaskThreads', _formatInteger(items.length)),
            (
              appText('待处理', 'Needs attention'),
              _formatInteger(items.where((item) => !item.isCompleted).length),
            ),
            (
              appText('推进中专项', 'Active projects'),
              _formatInteger(
                items.map((item) => item.projectLabel).toSet().length,
              ),
            ),
            (appText('消息', 'Messages'), _formatInteger(messages)),
            ('Tokens', _formatTokens(input + output)),
            (
              'Artifact',
              _formatInteger(
                items.fold<int>(
                  0,
                  (sum, item) => sum + item.artifactPaths.length,
                ),
              ),
            ),
          ],
          columns: 6,
          compact: true,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            final chart = _TokenTrendCard(items: items);
            final models = _ModelShareCard(items: items);
            if (compact) {
              return Column(
                children: [chart, const SizedBox(height: 14), models],
              );
            }
            return SizedBox(
              height: 340,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 7, child: chart),
                  const SizedBox(width: 14),
                  Expanded(flex: 5, child: models),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _AnalyticsTable(
          title: appText('最近活动', 'Recent activity'),
          items: items.take(8).toList(growable: false),
          onOpenThread: onOpenThread,
          showInputOutput: true,
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.metrics,
    required this.columns,
    this.compact = false,
  });

  final List<(String, String)> metrics;
  final int columns;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actualColumns = constraints.maxWidth < 700 ? 2 : columns;
        const gap = 12.0;
        final width =
            (constraints.maxWidth - gap * (actualColumns - 1)) / actualColumns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _MetricCard(
                  label: metric.$1,
                  value: metric.$2,
                  compact: compact,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.compact,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      key: Key('workbench-metric-$label'),
      height: compact ? 86 : 96,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnualHeatmap extends StatelessWidget {
  const _AnnualHeatmap({super.key, required this.items});

  final List<WorkbenchItem> items;
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final counts = <String, int>{};
    for (final item in items) {
      if (item.updatedAtMs <= 0) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(
        item.updatedAtMs.round(),
      );
      final key = '${date.year}-${date.month}-${date.day}';
      counts[key] = (counts[key] ?? 0) + math.max(1, item.messageCount);
    }
    final maximum = counts.values.fold<int>(1, math.max);
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 363));
    final months = List.generate(12, (index) {
      final month = DateTime(start.year, start.month + index);
      return appText('${month.month}月', _englishMonth(month.month));
    });
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: months
                  .map(
                    (month) => Text(
                      month,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 42,
                height: 128,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [Text('Mon'), Text('Wed'), Text('Fri')],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const columns = 52;
                    const gap = 3.0;
                    final size = math.max(
                      3.0,
                      (constraints.maxWidth - gap * (columns - 1)) / columns,
                    );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(columns, (column) {
                        return Padding(
                          padding: EdgeInsets.only(
                            right: column == columns - 1 ? 0 : gap,
                          ),
                          child: Column(
                            children: List.generate(7, (row) {
                              final date = start.add(
                                Duration(days: column * 7 + row),
                              );
                              final count =
                                  counts['${date.year}-${date.month}-${date.day}'] ??
                                  0;
                              final level = count == 0
                                  ? 0.0
                                  : (count / maximum).clamp(0.18, 1.0);
                              final color = count == 0
                                  ? palette.surfaceTertiary
                                  : Color.lerp(
                                      palette.accentMuted,
                                      palette.accent,
                                      level,
                                    )!;
                              return Container(
                                width: size,
                                height: 14,
                                margin: EdgeInsets.only(
                                  bottom: row == 6 ? 0 : 3,
                                ),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(2.5),
                                ),
                              );
                            }),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                appText('了解我们如何统计贡献', 'How activity is counted'),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: palette.accent),
              ),
              const Spacer(),
              Text(
                'Less',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(width: 6),
              for (var index = 0; index < 5; index++)
                Container(
                  width: 13,
                  height: 13,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: index == 0
                        ? palette.surfaceTertiary
                        : Color.lerp(
                            palette.accentMuted,
                            palette.accent,
                            index / 4,
                          ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              Text(
                'More',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
