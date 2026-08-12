part of 'workbench_analytics.dart';

class _TokenTrendCard extends StatelessWidget {
  const _TokenTrendCard({required this.items});

  final List<WorkbenchItem> items;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final now = DateTime.now();
    final buckets = List.generate(12, (_) => [0, 0]);
    for (final item in items) {
      if (item.updatedAtMs <= 0) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(
        item.updatedAtMs.round(),
      );
      final distance = (now.year - date.year) * 12 + now.month - date.month;
      if (distance >= 0 && distance < 12) {
        final index = 11 - distance;
        buckets[index][0] += item.inputTokens;
        buckets[index][1] += item.outputTokens;
      }
    }
    final maximum = buckets.expand((item) => item).fold<int>(1, math.max);
    return _AnalyticsCard(
      title: appText('Tokens 使用趋势（按月）', 'Token usage by month'),
      child: SizedBox(
        height: 270,
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(12, (index) {
                  final month = DateTime(now.year, now.month - 11 + index);
                  final inputHeight = buckets[index][0] / maximum * 190;
                  final outputHeight = buckets[index][1] / maximum * 190;
                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 18,
                          height: math.max(1, outputHeight),
                          color: palette.accentMuted,
                        ),
                        Container(
                          width: 18,
                          height: math.max(1, inputHeight),
                          color: palette.accent,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          appText('${month.month}月', '${month.month}'),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Legend(
                  color: palette.accent,
                  label: appText('输入 Tokens', 'Input tokens'),
                ),
                const SizedBox(width: 22),
                _Legend(
                  color: palette.accentMuted,
                  label: appText('输出 Tokens', 'Output tokens'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelShareCard extends StatelessWidget {
  const _ModelShareCard({required this.items});

  final List<WorkbenchItem> items;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final models = _modelSummaries(items).take(6).toList(growable: false);
    return _AnalyticsCard(
      title: appText('模型使用份额', 'Model usage share'),
      child: SizedBox(
        height: 270,
        child: models.isEmpty
            ? _EmptyAnalytics(
                message: appText('暂无模型用量数据', 'No model usage data'),
              )
            : Column(
                children: [
                  _ModelHeader(),
                  for (var index = 0; index < models.length; index++)
                    Expanded(
                      child: _ModelRow(
                        summary: models[index],
                        color: Color.lerp(
                          palette.accent,
                          palette.accentMuted,
                          index / math.max(1, models.length - 1),
                        )!,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ModelHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: context.palette.textSecondary,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(appText('模型', 'Model'), style: style)),
          Expanded(flex: 2, child: Text(appText('输入', 'Input'), style: style)),
          Expanded(flex: 2, child: Text(appText('输出', 'Output'), style: style)),
          Expanded(
            child: Text(
              appText('占比', 'Share'),
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.summary, required this.color});
  final _ModelSummary summary;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  summary.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(_formatTokens(summary.input), style: style),
        ),
        Expanded(
          flex: 2,
          child: Text(_formatTokens(summary.output), style: style),
        ),
        Expanded(
          child: Text(
            '${(summary.share * 100).toStringAsFixed(1)}%',
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
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
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _AnalyticsTable extends StatelessWidget {
  const _AnalyticsTable({
    super.key,
    required this.title,
    required this.items,
    required this.onOpenThread,
    required this.showInputOutput,
  });
  final String title;
  final List<WorkbenchItem> items;
  final ValueChanged<String> onOpenThread;
  final bool showInputOutput;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Divider(height: 1, color: palette.strokeSoft),
          if (items.isEmpty)
            SizedBox(
              height: 150,
              child: _EmptyAnalytics(
                message: appText('暂无服务端会话', 'No server sessions'),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(980, MediaQuery.sizeOf(context).width - 52),
                child: Column(
                  children: [
                    _TableHeader(showInputOutput: showInputOutput),
                    for (final item in items)
                      _TableRow(
                        item: item,
                        onTap: () => onOpenThread(item.sessionKey),
                        showInputOutput: showInputOutput,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.showInputOutput});
  final bool showInputOutput;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: context.palette.textSecondary,
      fontWeight: FontWeight.w700,
    );
    return Container(
      color: context.palette.surfaceSecondary.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(appText('状态', 'Status'), style: style),
          ),
          Expanded(flex: 4, child: Text('TaskThread', style: style)),
          Expanded(
            flex: 2,
            child: Text(appText('专项', 'Project'), style: style),
          ),
          Expanded(flex: 2, child: Text(appText('模型', 'Model'), style: style)),
          Expanded(
            flex: 2,
            child: Text(
              showInputOutput
                  ? appText('Tokens（输入 / 输出）', 'Tokens (in / out)')
                  : 'Tokens',
              style: style,
            ),
          ),
          Expanded(child: Text('Artifact', style: style)),
          SizedBox(
            width: 150,
            child: Text(appText('最近更新', 'Updated'), style: style),
          ),
          const SizedBox(width: 72),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.item,
    required this.onTap,
    required this.showInputOutput,
  });
  final WorkbenchItem item;
  final VoidCallback onTap;
  final bool showInputOutput;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final state = _stateText(item.state);
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: palette.textSecondary);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.strokeSoft)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: state.$2,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    state.$1,
                    style: style?.copyWith(
                      color: state.$2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.sessionKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                item.projectLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                item.model.isEmpty ? '—' : item.model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                showInputOutput
                    ? '${_formatTokens(item.inputTokens)} / ${_formatTokens(item.outputTokens)}'
                    : _formatTokens(item.totalTokens),
                style: style,
              ),
            ),
            Expanded(child: Text('${item.artifactPaths.length}', style: style)),
            SizedBox(
              width: 150,
              child: Text(_formatDate(item.updatedAtMs), style: style),
            ),
            SizedBox(
              width: 72,
              child: OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text(appText('查看', 'View')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.palette.textSecondary),
      ),
    ],
  );
}

class _EmptyAnalytics extends StatelessWidget {
  const _EmptyAnalytics({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      message,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.palette.textMuted),
    ),
  );
}

typedef _ModelSummary = ({String model, int input, int output, double share});

List<_ModelSummary> _modelSummaries(List<WorkbenchItem> items) {
  final totals = <String, List<int>>{};
  for (final item in items) {
    final model = item.model.trim();
    if (model.isEmpty) continue;
    final values = totals.putIfAbsent(model, () => [0, 0]);
    values[0] += item.inputTokens;
    values[1] += item.outputTokens;
  }
  final grandTotal = totals.values.fold<int>(
    0,
    (sum, value) => sum + value[0] + value[1],
  );
  final result = totals.entries.map((entry) {
    final total = entry.value[0] + entry.value[1];
    return (
      model: entry.key,
      input: entry.value[0],
      output: entry.value[1],
      share: grandTotal == 0 ? 0.0 : total / grandTotal,
    );
  }).toList();
  result.sort(
    (left, right) =>
        (right.input + right.output).compareTo(left.input + left.output),
  );
  return result;
}

(String, Color) _stateText(WorkbenchItemState state) => switch (state) {
  WorkbenchItemState.blocked => (
    appText('被阻塞', 'Blocked'),
    const Color(0xffcf625b),
  ),
  WorkbenchItemState.syncing => (
    appText('等待中', 'Waiting'),
    const Color(0xffe8a61b),
  ),
  WorkbenchItemState.running => (
    appText('进行中', 'Running'),
    const Color(0xff1769d2),
  ),
  WorkbenchItemState.ready => (appText('待处理', 'Todo'), const Color(0xff1769d2)),
  WorkbenchItemState.completed => (
    appText('已完成', 'Done'),
    const Color(0xff2da44e),
  ),
};

String _formatInteger(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);
String _formatTokens(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '$value';
}

String _formatDate(double value) {
  if (value <= 0) return '—';
  final date = DateTime.fromMillisecondsSinceEpoch(value.round());
  String two(int number) => number.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}

String _englishMonth(int month) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][month - 1];

List<WorkbenchItem> _filterItems(List<WorkbenchItem> items, int window) {
  if (window == 0) return items;
  final days = window == 1 ? 30 : 7;
  final boundary = DateTime.now()
      .subtract(Duration(days: days))
      .millisecondsSinceEpoch;
  return items
      .where((item) => item.updatedAtMs >= boundary)
      .toList(growable: false);
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
