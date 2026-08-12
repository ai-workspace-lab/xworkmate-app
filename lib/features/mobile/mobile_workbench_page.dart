import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../theme/app_palette.dart';
import '../workbench/workbench_projection.dart';
import 'mobile_workbench_page_widgets.dart';

/// A touch-first view of the desktop workbench. It deliberately keeps the
/// desktop's data model, while reducing its three columns to one clear action
/// stream for a phone-sized screen.
class MobileWorkbenchPage extends StatefulWidget {
  const MobileWorkbenchPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<MobileWorkbenchPage> createState() => _MobileWorkbenchPageState();
}

class _MobileWorkbenchPageState extends State<MobileWorkbenchPage> {
  _MobileWorkbenchTab _tab = _MobileWorkbenchTab.overview;

  Future<void> _openThread(String sessionKey) async {
    await widget.controller.switchSession(sessionKey);
    widget.controller.navigateTo(WorkspaceDestination.assistant);
  }

  void _openQuickRecord() {
    widget.controller.navigateTo(WorkspaceDestination.assistant);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final projection = buildWorkbenchProjection(
          sessions: widget.controller.assistantSessions,
          threadForSession: widget.controller.taskThreadForSessionInternal,
        );
        return SafeArea(
          bottom: false,
          child: Container(
            key: const Key('mobile-workbench-page'),
            color: context.palette.canvas,
            child: CustomScrollView(
              key: const Key('mobile-workbench-scroll-view'),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      _MobileWorkbenchHeader(onQuickRecord: _openQuickRecord),
                      const SizedBox(height: 16),
                      _MobileWorkbenchTabs(
                        tab: _tab,
                        onChanged: (tab) => setState(() => _tab = tab),
                      ),
                      const SizedBox(height: 16),
                      _MobileWorkbenchContent(
                        tab: _tab,
                        projection: projection,
                        onOpenThread: _openThread,
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _MobileWorkbenchTab { overview, models, todo, projects, inbox }

extension on _MobileWorkbenchTab {
  String get label => switch (this) {
    _MobileWorkbenchTab.overview => appText('数据总览', 'Overview'),
    _MobileWorkbenchTab.models => appText('模型分析', 'Models'),
    _MobileWorkbenchTab.todo => appText('待办', 'To do'),
    _MobileWorkbenchTab.projects => appText('项目', 'Projects'),
    _MobileWorkbenchTab.inbox => appText('收件箱', 'Inbox'),
  };

  String get keyName => switch (this) {
    _MobileWorkbenchTab.overview => 'overview',
    _MobileWorkbenchTab.models => 'models',
    _MobileWorkbenchTab.todo => 'todo',
    _MobileWorkbenchTab.projects => 'projects',
    _MobileWorkbenchTab.inbox => 'inbox',
  };
}

class _MobileWorkbenchHeader extends StatelessWidget {
  const _MobileWorkbenchHeader({required this.onQuickRecord});

  final VoidCallback onQuickRecord;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 12, 17),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.strokeSoft),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appText('工作台', 'Workbench'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  appText('把进展变成下一步行动', 'Turn progress into next actions.'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('mobile-workbench-quick-record'),
            onPressed: onQuickRecord,
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Icon(Icons.edit_note_rounded),
          ),
        ],
      ),
    );
  }
}

class _MobileWorkbenchTabs extends StatelessWidget {
  const _MobileWorkbenchTabs({required this.tab, required this.onChanged});

  final _MobileWorkbenchTab tab;
  final ValueChanged<_MobileWorkbenchTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _MobileWorkbenchTab.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final candidate = _MobileWorkbenchTab.values[index];
          final selected = candidate == tab;
          return Semantics(
            selected: selected,
            button: true,
            child: InkWell(
              key: Key('mobile-workbench-tab-${candidate.keyName}'),
              onTap: () => onChanged(candidate),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 17),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? palette.accent : palette.surfacePrimary,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? palette.accent : palette.strokeSoft,
                  ),
                ),
                child: Text(
                  candidate.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? Colors.white : palette.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MobileWorkbenchContent extends StatelessWidget {
  const _MobileWorkbenchContent({
    required this.tab,
    required this.projection,
    required this.onOpenThread,
  });

  final _MobileWorkbenchTab tab;
  final WorkbenchProjection projection;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      _MobileWorkbenchTab.overview => _MobileWorkbenchOverview(
        projection: projection,
        onOpenThread: onOpenThread,
      ),
      _MobileWorkbenchTab.models => _MobileModelAnalysis(
        projection: projection,
      ),
      _MobileWorkbenchTab.todo => _MobileWorkbenchList(
        key: const Key('mobile-workbench-tab-content-todo'),
        title: appText('我的待办', 'My to do'),
        subtitle: appText('按最近进展排序', 'Sorted by latest progress'),
        child: _MobileTaskList(
          items: projection.todos,
          onOpenThread: onOpenThread,
          showProgress: true,
        ),
      ),
      _MobileWorkbenchTab.projects => _MobileWorkbenchList(
        key: const Key('mobile-workbench-tab-content-projects'),
        title: appText('项目 / 专项', 'Projects'),
        subtitle: appText('按工作目录聚合', 'Grouped by workspace'),
        child: _MobileProjectList(
          projects: projection.projects,
          onOpenThread: onOpenThread,
        ),
      ),
      _MobileWorkbenchTab.inbox => _MobileWorkbenchList(
        key: const Key('mobile-workbench-tab-content-inbox'),
        title: appText('工作收件箱', 'Work inbox'),
        subtitle: appText('最近的产物、附件与记录', 'Recent artifacts, files, and notes'),
        child: MobileWorkbenchInboxList(
          items: projection.inbox,
          onOpenThread: onOpenThread,
        ),
      ),
    };
  }
}

class _MobileWorkbenchOverview extends StatelessWidget {
  const _MobileWorkbenchOverview({
    required this.projection,
    required this.onOpenThread,
  });

  final WorkbenchProjection projection;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('mobile-workbench-tab-content-overview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MobileSnapshot(projection: projection),
        const SizedBox(height: 20),
        _MobileSection(
          title: appText('需要你处理', 'Needs your attention'),
          subtitle: appText('优先处理正在推进的任务', 'Focus on what is moving now'),
          child: _MobileTaskList(
            items: projection.todos.take(3).toList(growable: false),
            onOpenThread: onOpenThread,
          ),
        ),
        const SizedBox(height: 20),
        _MobileSection(
          title: appText('正在推进的专项', 'Projects in progress'),
          subtitle: appText('工作目录中的连续进展', 'Ongoing progress in your workspace'),
          child: _MobileProjectList(
            projects: projection.projects.take(3).toList(growable: false),
            onOpenThread: onOpenThread,
          ),
        ),
        if (projection.inbox.isNotEmpty) ...[
          const SizedBox(height: 20),
          _MobileSection(
            title: appText('最近收件', 'Recent inbox'),
            child: MobileWorkbenchInboxList(
              items: projection.inbox.take(2).toList(growable: false),
              onOpenThread: onOpenThread,
            ),
          ),
        ],
      ],
    );
  }
}

class _MobileModelAnalysis extends StatelessWidget {
  const _MobileModelAnalysis({required this.projection});

  final WorkbenchProjection projection;

  @override
  Widget build(BuildContext context) {
    final byModel = <String, ({int input, int output, int sessions})>{};
    for (final item in projection.items) {
      final model = item.model.trim();
      if (model.isEmpty) continue;
      final current = byModel[model] ?? (input: 0, output: 0, sessions: 0);
      byModel[model] = (
        input: current.input + item.inputTokens,
        output: current.output + item.outputTokens,
        sessions: current.sessions + 1,
      );
    }
    final models = byModel.entries.toList()
      ..sort(
        (left, right) => (right.value.input + right.value.output).compareTo(
          left.value.input + left.value.output,
        ),
      );
    final totalTokens = projection.items.fold<int>(
      0,
      (sum, item) => sum + item.totalTokens,
    );
    return Column(
      key: const Key('mobile-workbench-tab-content-models'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SnapshotMetric(
              label: 'Tokens',
              value: _mobileFormatTokens(totalTokens),
            ),
            const SizedBox(width: 7),
            _SnapshotMetric(
              label: appText('模型', 'Models'),
              value: '${models.length}',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _MobileSection(
          title: appText('模型使用份额', 'Model usage share'),
          subtitle: appText('服务端会话用量', 'Server session usage'),
          child: MobileWorkbenchSurface(
            child: models.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        appText('暂无模型用量数据', 'No model usage data'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.palette.textMuted,
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (var index = 0; index < models.length; index++) ...[
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Color.lerp(
                                    context.palette.accent,
                                    context.palette.accentMuted,
                                    index / models.length,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  models[index].key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                '${_mobileFormatTokens(models[index].value.input)} / ${_mobileFormatTokens(models[index].value.output)}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: context.palette.textSecondary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (index < models.length - 1)
                          Divider(height: 1, color: context.palette.strokeSoft),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

String _mobileFormatTokens(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '$value';
}

class _MobileSnapshot extends StatelessWidget {
  const _MobileSnapshot({required this.projection});

  final WorkbenchProjection projection;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final activityMaximum = projection.workloadSeries.fold<double>(
      1,
      (maximum, value) => value > maximum ? value : maximum,
    );
    return Container(
      key: const Key('mobile-workbench-overview-summary'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _SnapshotMetric(
                label: appText('TaskThreads', 'TaskThreads'),
                value: '${projection.items.length}',
              ),
              const SizedBox(width: 7),
              _SnapshotMetric(
                label: appText('待处理', 'To do'),
                value: '${projection.todos.length}',
              ),
              const SizedBox(width: 7),
              _SnapshotMetric(
                label: appText('专项', 'Projects'),
                value: '${projection.projects.length}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              color: palette.surfacePrimary.withValues(alpha: 0.56),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appText('工作活跃度 · 过去 7 天', 'Work activity · past 7 days'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: List.generate(7, (index) {
                    final value = index < projection.workloadSeries.length
                        ? projection.workloadSeries[index]
                        : 0.0;
                    final color = value == 0
                        ? palette.surfaceTertiary
                        : Color.lerp(
                            palette.accentMuted,
                            palette.accent,
                            0.36 + (value / activityMaximum) * 0.64,
                          )!;
                    return Expanded(
                      child: Container(
                        key: Key('mobile-workbench-activity-$index'),
                        height: 20,
                        margin: EdgeInsets.only(right: index == 6 ? 0 : 5),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapshotMetric extends StatelessWidget {
  const _SnapshotMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        height: 65,
        padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
        decoration: BoxDecoration(
          color: palette.surfacePrimary.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: palette.textSecondary),
            ),
            const Spacer(),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileWorkbenchList extends StatelessWidget {
  const _MobileWorkbenchList({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _MobileSection(title: title, subtitle: subtitle, child: child);
  }
}

class _MobileSection extends StatelessWidget {
  const _MobileSection({
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _MobileTaskList extends StatelessWidget {
  const _MobileTaskList({
    required this.items,
    required this.onOpenThread,
    this.showProgress = false,
  });

  final List<WorkbenchItem> items;
  final ValueChanged<String> onOpenThread;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return MobileWorkbenchEmptyCard(
        icon: Icons.task_alt_rounded,
        title: appText('目前没有待处理事项', 'Nothing needs attention'),
        subtitle: appText('新的工作会自动出现在这里。', 'New work will appear here.'),
      );
    }
    return MobileWorkbenchSurface(
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _MobileTaskTile(
              item: items[index],
              showProgress: showProgress,
              onTap: () => onOpenThread(items[index].sessionKey),
            ),
            if (index < items.length - 1)
              Divider(height: 1, color: context.palette.strokeSoft),
          ],
        ],
      ),
    );
  }
}

class _MobileTaskTile extends StatelessWidget {
  const _MobileTaskTile({
    required this.item,
    required this.showProgress,
    required this.onTap,
  });

  final WorkbenchItem item;
  final bool showProgress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final visual = mobileWorkbenchTaskVisual(context, item.state);
    return InkWell(
      key: Key('mobile-workbench-task-${item.sessionKey}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: visual.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(visual.icon, color: visual.color, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: palette.textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.projectLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: visual.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.preview.isEmpty ? visual.label : item.preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  if (showProgress) ...[
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 5,
                        backgroundColor: palette.surfaceTertiary,
                        valueColor: AlwaysStoppedAnimation<Color>(visual.color),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileProjectList extends StatelessWidget {
  const _MobileProjectList({
    required this.projects,
    required this.onOpenThread,
  });

  final List<WorkbenchProject> projects;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return MobileWorkbenchEmptyCard(
        icon: Icons.folder_open_rounded,
        title: appText('暂无项目进展', 'No projects yet'),
        subtitle: appText('绑定工作目录后会自动聚合。', 'Workspace work groups here.'),
      );
    }
    return MobileWorkbenchSurface(
      child: Column(
        children: [
          for (var index = 0; index < projects.length; index++) ...[
            _MobileProjectTile(
              project: projects[index],
              onTap: () => onOpenThread(projects[index].items.first.sessionKey),
            ),
            if (index < projects.length - 1)
              Divider(height: 1, color: context.palette.strokeSoft),
          ],
        ],
      ),
    );
  }
}

class _MobileProjectTile extends StatelessWidget {
  const _MobileProjectTile({required this.project, required this.onTap});

  final WorkbenchProject project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = project.progress.clamp(0.0, 1.0);
    return InkWell(
      key: Key('mobile-workbench-project-${project.label}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: palette.accentMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.folder_special_rounded,
                    color: palette.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        appText(
                          '${project.items.length} 个工作项 · ${project.artifactCount} 个产物',
                          '${project.items.length} items · ${project.artifactCount} artifacts',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: palette.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: palette.surfaceTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
