import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../models/app_models.dart';
import '../../runtime/assistant_artifacts.dart';
import '../../runtime/runtime_models.dart' as runtime;
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/surface_card.dart';
import 'workbench_models.dart';

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({
    super.key,
    required this.controller,
    required this.onOpenDetail,
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  WorkbenchSection _section = WorkbenchSection.overview;
  final _snapshot = WorkbenchSnapshot.sample;
  List<runtime.TaskThread> _liveThreads = const <runtime.TaskThread>[];
  List<Artifact> _liveArtifacts = const <Artifact>[];
  bool _liveContextLoading = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _loadLiveContext();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!_liveContextLoading && _liveThreads.isEmpty) {
      _loadLiveContext();
    }
  }

  Future<void> _loadLiveContext() async {
    if (_liveContextLoading && _liveThreads.isNotEmpty) return;
    if (mounted) setState(() => _liveContextLoading = true);
    try {
      final threads = widget.controller.workbenchTaskThreads
          .where((thread) => !thread.archived)
          .toList(growable: false);
      final artifacts = <Artifact>[];
      for (final thread in threads.take(12)) {
        // Remote artifact synchronization is owned by the assistant artifact
        // panel. Workbench only projects already-local task artifacts so
        // opening the dashboard never starts a network sync.
        if (thread.workspaceKind != runtime.WorkspaceKind.localFs ||
            thread.lastTaskArtifactRelativePaths.isEmpty) {
          continue;
        }
        final artifactSnapshot = await widget.controller
            .loadAssistantArtifactSnapshot(sessionKey: thread.threadId);
        final entries = <String, AssistantArtifactEntry>{};
        for (final entry in [
          ...artifactSnapshot.resultEntries,
          ...artifactSnapshot.fileEntries,
        ]) {
          entries[entry.id] = entry;
        }
        for (final entry in entries.values) {
          artifacts.add(
            Artifact(
              id: entry.id,
              name: entry.label,
              kind: entry.mimeType,
              updatedAt: _formatTimestamp(entry.updatedAtMs),
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _liveThreads = threads;
        _liveArtifacts = artifacts;
        _liveContextLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _liveContextLoading = false);
    }
  }

  String _formatTimestamp(double? timestampMs) {
    if (timestampMs == null || timestampMs <= 0) return '已记录';
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs.toInt());
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return ColoredBox(
      color: palette.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1120;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              compact ? 20 : 36,
              28,
              compact ? 20 : 36,
              36,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WorkbenchHeader(onQuickRecord: _showQuickRecord),
                    const SizedBox(height: 22),
                    _WorkbenchTabs(
                      selected: _section,
                      onChanged: (section) =>
                          setState(() => _section = section),
                    ),
                    const SizedBox(height: 20),
                    if (_section == WorkbenchSection.overview)
                      _OverviewContent(
                        snapshot: _snapshot,
                        onOpenItem: _openWorkItem,
                        onOpenProject: _openProject,
                        onQuickRecord: _showQuickRecord,
                        liveThreads: _liveThreads,
                        liveArtifacts: _liveArtifacts,
                        liveContextLoading: _liveContextLoading,
                      )
                    else
                      _SectionPlaceholder(
                        section: _section,
                        snapshot: _snapshot,
                        onOpenItem: _openWorkItem,
                        onOpenProject: _openProject,
                        liveThreads: _liveThreads,
                        liveArtifacts: _liveArtifacts,
                        liveContextLoading: _liveContextLoading,
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'WorkBench · Project / WorkItem / WorkNote / TaskThread / Artifact',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openWorkItem(WorkItem item) {
    widget.onOpenDetail(
      DetailPanelData(
        title: item.title,
        subtitle: item.source,
        icon: Icons.check_box_outlined,
        status: StatusInfo(item.state.label, _toneForState(item.state)),
        description: item.meta,
        meta: [item.id, if (item.projectId != null) item.projectId!],
        sections: const [
          DetailSection(
            title: '领域对象',
            items: [
              DetailItem(label: '类型', value: 'WorkItem'),
              DetailItem(label: '来源', value: 'Connector / WorkNote'),
            ],
          ),
        ],
        actions: const ['标记完成', '转为专项'],
      ),
    );
  }

  void _openProject(Project project) {
    widget.onOpenDetail(
      DetailPanelData(
        title: project.name,
        subtitle: project.summary,
        icon: Icons.folder_open_outlined,
        status: StatusInfo(
          '${(project.progress * 100).round()}%',
          StatusTone.accent,
        ),
        description: '当前阶段：${project.currentStage}',
        meta: [project.id, 'Project'],
        sections: [
          DetailSection(
            title: '阶段',
            items: [
              for (var index = 0; index < project.stages.length; index++)
                DetailItem(label: '${index + 1}', value: project.stages[index]),
            ],
          ),
        ],
        actions: const ['查看专项', '记录投入'],
      ),
    );
  }

  StatusTone _toneForState(WorkItemState state) => switch (state) {
    WorkItemState.overdue => StatusTone.danger,
    WorkItemState.needsReview => StatusTone.warning,
    WorkItemState.todo => StatusTone.accent,
    WorkItemState.blocked => StatusTone.danger,
    WorkItemState.done => StatusTone.success,
  };

  Future<void> _showQuickRecord() async {
    final noteController = TextEditingController();
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('快速记录'),
          content: TextField(
            controller: noteController,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(hintText: '记录一个想法、进展或下一步动作…'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('保存记录'),
            ),
          ],
        );
      },
    );
    final note = noteController.text.trim();
    noteController.dispose();
    if (!mounted || shouldSave != true || note.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已记录到 WorkNote，后续可由 AI 整理。')));
  }
}

class _WorkbenchHeader extends StatelessWidget {
  const _WorkbenchHeader({required this.onQuickRecord});

  final VoidCallback onQuickRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('工作台', style: theme.textTheme.displaySmall),
              const SizedBox(height: 6),
              Text(
                '把零碎进展沉淀为清晰工作',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          key: const Key('workbench-quick-record-button'),
          onPressed: onQuickRecord,
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('快速记录'),
        ),
      ],
    );
  }
}

class _WorkbenchTabs extends StatelessWidget {
  const _WorkbenchTabs({required this.selected, required this.onChanged});

  final WorkbenchSection selected;
  final ValueChanged<WorkbenchSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final section in WorkbenchSection.values)
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: InkWell(
                key: ValueKey<String>('workbench-tab-${section.name}'),
                onTap: () => onChanged(section),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                  child: Text(
                    _labelForSection(section),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: selected == section
                          ? palette.accent
                          : palette.textSecondary,
                      fontWeight: selected == section
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _labelForSection(WorkbenchSection section) => switch (section) {
    WorkbenchSection.overview => '总览',
    WorkbenchSection.myWork => '我的待办',
    WorkbenchSection.projects => '项目 / 专项',
    WorkbenchSection.inbox => '收件箱',
  };
}

class _OverviewContent extends StatelessWidget {
  const _OverviewContent({
    required this.snapshot,
    required this.onOpenItem,
    required this.onOpenProject,
    required this.onQuickRecord,
    required this.liveThreads,
    required this.liveArtifacts,
    required this.liveContextLoading,
  });

  final WorkbenchSnapshot snapshot;
  final ValueChanged<WorkItem> onOpenItem;
  final ValueChanged<Project> onOpenProject;
  final VoidCallback onQuickRecord;
  final List<runtime.TaskThread> liveThreads;
  final List<Artifact> liveArtifacts;
  final bool liveContextLoading;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showInsightRail = constraints.maxWidth >= 980;
        final main = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NeedsAttentionCard(items: snapshot.workItems, onOpen: onOpenItem),
            const SizedBox(height: 16),
            _ProjectsCard(projects: snapshot.projects, onOpen: onOpenProject),
          ],
        );
        if (!showInsightRail) {
          return Column(
            children: [
              main,
              const SizedBox(height: 16),
              _InsightRail(
                snapshot: snapshot,
                onQuickRecord: onQuickRecord,
                liveThreads: liveThreads,
                liveArtifacts: liveArtifacts,
                liveContextLoading: liveContextLoading,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: main),
            const SizedBox(width: 18),
            SizedBox(
              width: 340,
              child: _InsightRail(
                snapshot: snapshot,
                onQuickRecord: onQuickRecord,
                liveThreads: liveThreads,
                liveArtifacts: liveArtifacts,
                liveContextLoading: liveContextLoading,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NeedsAttentionCard extends StatelessWidget {
  const _NeedsAttentionCard({required this.items, required this.onOpen});

  final List<WorkItem> items;
  final ValueChanged<WorkItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      key: const Key('workbench-needs-attention-card'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardHeading(title: '需要你处理', icon: Icons.inbox_outlined),
          for (final item in items)
            _WorkItemRow(item: item, onOpen: () => onOpen(item)),
        ],
      ),
    );
  }
}

class _ProjectsCard extends StatelessWidget {
  const _ProjectsCard({required this.projects, required this.onOpen});

  final List<Project> projects;
  final ValueChanged<Project> onOpen;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      key: const Key('workbench-projects-card'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardHeading(title: '正在推进的专项', icon: Icons.timeline_rounded),
          for (final project in projects)
            _ProjectRow(project: project, onOpen: () => onOpen(project)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            child: TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.arrow_forward_rounded, size: 17),
              label: const Text('查看全部专项'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightRail extends StatelessWidget {
  const _InsightRail({
    required this.snapshot,
    required this.onQuickRecord,
    required this.liveThreads,
    required this.liveArtifacts,
    required this.liveContextLoading,
  });

  final WorkbenchSnapshot snapshot;
  final VoidCallback onQuickRecord;
  final List<runtime.TaskThread> liveThreads;
  final List<Artifact> liveArtifacts;
  final bool liveContextLoading;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _WorkloadCard(values: snapshot.dailyLoad),
        const SizedBox(height: 16),
        _CadenceCard(snapshot: snapshot),
        const SizedBox(height: 16),
        _AiSuggestionCard(onQuickRecord: onQuickRecord),
        const SizedBox(height: 16),
        _LiveContextCard(
          threads: liveThreads,
          artifacts: liveArtifacts,
          loading: liveContextLoading,
        ),
      ],
    );
  }
}

class _CardHeading extends StatelessWidget {
  const _CardHeading({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        children: [
          Icon(icon, size: 19, color: palette.accent),
          const SizedBox(width: 9),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _WorkItemRow extends StatelessWidget {
  const _WorkItemRow({required this.item, required this.onOpen});

  final WorkItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      key: ValueKey<String>('workbench-work-item-${item.id}'),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.strokeSoft)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 74,
              child: Text(
                item.state.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: item.state.color(Theme.of(context).colorScheme),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.check_box_outlined, color: palette.accent, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.source} · ${item.meta}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.project, required this.onOpen});

  final Project project;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final activeIndex = project.stages.indexOf(project.currentStage);
    return InkWell(
      key: ValueKey<String>('workbench-project-${project.id}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: palette.accentMuted,
              child: Text(
                project.name.substring(0, 1),
                style: TextStyle(color: palette.accent),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 170,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    project.summary,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      for (
                        var index = 0;
                        index < project.stages.length;
                        index++
                      ) ...[
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: index <= activeIndex
                                  ? palette.accent
                                  : palette.surfaceTertiary,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        if (index != project.stages.length - 1)
                          const SizedBox(width: 4),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      project.currentStage,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${(project.progress * 100).round()}%',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: palette.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _WorkloadCard extends StatelessWidget {
  const _WorkloadCard({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('工作洞察', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '工作负载趋势（近 7 天）',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 150,
            child: CustomPaint(
              painter: _WorkloadChartPainter(values, context.palette),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Expanded(child: Text('5/10')),
              Expanded(child: Text('5/11')),
              Expanded(child: Text('5/12')),
              Expanded(child: Text('5/13')),
              Expanded(child: Text('5/14')),
              Expanded(child: Text('5/15')),
              Expanded(child: Text('5/16')),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkloadChartPainter extends CustomPainter {
  _WorkloadChartPainter(this.values, this.palette);

  final List<double> values;
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final chart = Rect.fromLTWH(4, 8, size.width - 8, size.height - 16);
    final minValue = 0.0;
    final maxValue = 20.0;
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x = chart.left + chart.width * index / (values.length - 1);
      final y =
          chart.bottom -
          (values[index] - minValue) / (maxValue - minValue) * chart.height;
      points.add(Offset(x, y));
    }
    final gridPaint = Paint()
      ..color = palette.strokeSoft
      ..strokeWidth = 1;
    for (var line = 0; line <= 4; line++) {
      final y = chart.top + chart.height * line / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }
    final linePaint = Paint()
      ..color = palette.accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(line, linePaint);
    final pointPaint = Paint()..color = palette.accent;
    for (final point in points) {
      canvas.drawCircle(point, 4.5, pointPaint);
      canvas.drawCircle(point, 2, Paint()..color = palette.surfacePrimary);
    }
  }

  @override
  bool shouldRepaint(covariant _WorkloadChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.palette != palette;
  }
}

class _CadenceCard extends StatelessWidget {
  const _CadenceCard({required this.snapshot});

  final WorkbenchSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = (snapshot.weeklyActualHours / snapshot.weeklyPlanHours)
        .clamp(0, 1)
        .toDouble();
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '本周节奏',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: Text(
                  '5月5日 – 5月11日',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MetricBar(
            label: '计划投入',
            value: '${snapshot.weeklyPlanHours} 小时',
            progress: 1,
            color: palette.accent,
          ),
          const SizedBox(height: 14),
          _MetricBar(
            label: '实际投入',
            value: '${snapshot.weeklyActualHours} 小时',
            progress: progress,
            color: palette.success,
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('进度', style: Theme.of(context).textTheme.bodyMedium),
              Text(
                '${(progress * 100).round()}%',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: palette.accent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricBar extends StatelessWidget {
  const _MetricBar({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
  });

  final String label;
  final String value;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            color: color,
            backgroundColor: palette.surfaceTertiary,
          ),
        ),
      ],
    );
  }
}

class _AiSuggestionCard extends StatelessWidget {
  const _AiSuggestionCard({required this.onQuickRecord});

  final VoidCallback onQuickRecord;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: palette.warning),
              const SizedBox(width: 8),
              Text('AI 整理建议', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 14),
          _SuggestionRow(
            icon: Icons.description_outlined,
            title: '建议归类为会议纪要',
            subtitle: 'XStream 连接层设计评审',
            action: '确认',
            onTap: () {},
          ),
          const SizedBox(height: 8),
          _SuggestionRow(
            icon: Icons.add_task_rounded,
            title: '建议创建待办任务',
            subtitle: '跟进统一鉴权服务上线进度',
            action: '创建',
            onTap: onQuickRecord,
          ),
          const SizedBox(height: 12),
          Text(
            '基于当前上下文智能建议',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }
}

class _LiveContextCard extends StatelessWidget {
  const _LiveContextCard({
    required this.threads,
    required this.artifacts,
    required this.loading,
  });

  final List<runtime.TaskThread> threads;
  final List<Artifact> artifacts;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SurfaceCard(
      key: const Key('workbench-live-context-card'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.link_rounded, color: palette.accent),
              const SizedBox(width: 8),
              Text('真实工作上下文', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          if (loading)
            const LinearProgressIndicator(minHeight: 3)
          else ...[
            Text(
              '${threads.length} 个 TaskThread · ${artifacts.length} 个 Artifact',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 10),
            for (final thread in threads.take(3))
              _LiveContextRow(
                icon: Icons.forum_outlined,
                title: thread.title.trim().isEmpty
                    ? thread.threadId
                    : thread.title,
                subtitle: 'TaskThread · ${thread.lifecycleState.status}',
              ),
            for (final artifact in artifacts.take(2))
              _LiveContextRow(
                icon: Icons.description_outlined,
                title: artifact.name,
                subtitle: 'Artifact · ${artifact.kind}',
              ),
            if (threads.isEmpty && artifacts.isEmpty)
              Text(
                '完成一次助手任务后，真实线程和产物会显示在这里。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
          ],
        ],
      ),
    );
  }
}

class _LiveInboxBody extends StatelessWidget {
  const _LiveInboxBody({
    required this.threads,
    required this.artifacts,
    required this.loading,
  });

  final List<runtime.TaskThread> threads;
  final List<Artifact> artifacts;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('正在读取 TaskThread 与 Artifact…'),
          SizedBox(height: 12),
          LinearProgressIndicator(),
        ],
      );
    }
    if (threads.isEmpty && artifacts.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('工作收件箱暂时为空', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'WorkNote、TaskThread 与 Artifact 会在确认后归入对应的 Project 或 WorkItem。',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('真实工作上下文', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final thread in threads)
          _LiveContextRow(
            icon: Icons.forum_outlined,
            title: thread.title.trim().isEmpty ? thread.threadId : thread.title,
            subtitle: 'TaskThread · ${thread.lifecycleState.status}',
          ),
        for (final artifact in artifacts)
          _LiveContextRow(
            icon: Icons.description_outlined,
            title: artifact.name,
            subtitle: 'Artifact · ${artifact.kind} · ${artifact.updatedAt}',
          ),
      ],
    );
  }
}

class _LiveContextRow extends StatelessWidget {
  const _LiveContextRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: palette.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionPlaceholder extends StatelessWidget {
  const _SectionPlaceholder({
    required this.section,
    required this.snapshot,
    required this.onOpenItem,
    required this.onOpenProject,
    required this.liveThreads,
    required this.liveArtifacts,
    required this.liveContextLoading,
  });

  final WorkbenchSection section;
  final WorkbenchSnapshot snapshot;
  final ValueChanged<WorkItem> onOpenItem;
  final ValueChanged<Project> onOpenProject;
  final List<runtime.TaskThread> liveThreads;
  final List<Artifact> liveArtifacts;
  final bool liveContextLoading;

  @override
  Widget build(BuildContext context) {
    final title = switch (section) {
      WorkbenchSection.myWork => '我的待办',
      WorkbenchSection.projects => '项目 / 专项',
      WorkbenchSection.inbox => '工作收件箱',
      WorkbenchSection.overview => '总览',
    };
    final body = switch (section) {
      WorkbenchSection.myWork => _NeedsAttentionCard(
        items: snapshot.workItems,
        onOpen: onOpenItem,
      ),
      WorkbenchSection.projects => _ProjectsCard(
        projects: snapshot.projects,
        onOpen: onOpenProject,
      ),
      WorkbenchSection.inbox => SurfaceCard(
        child: _LiveInboxBody(
          threads: liveThreads,
          artifacts: liveArtifacts,
          loading: liveContextLoading,
        ),
      ),
      WorkbenchSection.overview => const SizedBox.shrink(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        body,
      ],
    );
  }
}
