import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import '../../theme/app_palette.dart';
import 'workbench_projection.dart';

class WorkbenchTodoPage extends StatelessWidget {
  const WorkbenchTodoPage({
    super.key,
    required this.items,
    required this.onOpenThread,
  });
  final List<WorkbenchItem> items;
  final ValueChanged<String> onOpenThread;
  @override
  Widget build(BuildContext context) => _DetailPage(
    key: const Key('workbench-todo-page'),
    title: appText('我的待办', 'My todo'),
    subtitle: appText(
      '按运行状态和最近进展汇总 TaskThread',
      'TaskThreads grouped by runtime state.',
    ),
    child: _TaskList(items: items, onOpenThread: onOpenThread),
  );
}

class WorkbenchProjectsPage extends StatelessWidget {
  const WorkbenchProjectsPage({
    super.key,
    required this.projects,
    required this.onOpenThread,
  });
  final List<WorkbenchProject> projects;
  final ValueChanged<String> onOpenThread;
  @override
  Widget build(BuildContext context) => _DetailPage(
    key: const Key('workbench-projects-page'),
    title: appText('项目 / 专项', 'Projects / topics'),
    subtitle: appText('按工作目录聚合 TaskThread 与 Artifact', 'Grouped by workspace.'),
    child: projects.isEmpty
        ? _Empty(message: appText('暂无专项', 'No projects'))
        : Column(
            children: [
              for (final project in projects)
                _ProjectRow(
                  project: project,
                  onTap: () => onOpenThread(project.items.first.sessionKey),
                ),
            ],
          ),
  );
}

class WorkbenchInboxPage extends StatelessWidget {
  const WorkbenchInboxPage({
    super.key,
    required this.items,
    required this.onOpenThread,
  });
  final List<WorkbenchInboxItem> items;
  final ValueChanged<String> onOpenThread;
  @override
  Widget build(BuildContext context) => _DetailPage(
    key: const Key('workbench-inbox-page'),
    title: appText('工作收件箱', 'Work inbox'),
    subtitle: appText(
      '集中查看 Artifact、输入附件和工作记录',
      'Artifacts, attachments, and notes.',
    ),
    child: items.isEmpty
        ? _Empty(message: appText('暂无收件记录', 'No inbox records'))
        : Column(
            children: [
              for (final item in items)
                _InboxRow(
                  item: item,
                  onTap: () => onOpenThread(item.sessionKey),
                ),
            ],
          ),
  );
}

class _DetailPage extends StatelessWidget {
  const _DetailPage({
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
    final palette = context.palette;
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: palette.surfacePrimary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: palette.strokeSoft),
              child,
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.items, required this.onOpenThread});
  final List<WorkbenchItem> items;
  final ValueChanged<String> onOpenThread;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _Empty(message: appText('当前没有待处理事项', 'Nothing needs attention'));
    }
    return Column(
      children: [
        for (final item in items)
          _TaskRow(item: item, onTap: () => onOpenThread(item.sessionKey)),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.item, required this.onTap});
  final WorkbenchItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.palette.strokeSoft)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.radio_button_checked,
            size: 12,
            color: context.palette.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.projectLabel} · ${item.preview}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(item.progress * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.project, required this.onTap});
  final WorkbenchProject project;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.palette.strokeSoft)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, color: context.palette.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              project.label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            appText(
              '${project.items.length} 个工作项 · ${project.artifactCount} 个产物',
              '${project.items.length} items · ${project.artifactCount} artifacts',
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({required this.item, required this.onTap});
  final WorkbenchInboxItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.palette.strokeSoft)),
      ),
      child: Row(
        children: [
          Icon(
            item.kind == WorkbenchInboxKind.artifact
                ? Icons.description_outlined
                : Icons.attach_file_rounded,
            color: context.palette.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.sourceTitle} · ${item.subtitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.palette.textSecondary,
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

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 180,
    child: Center(
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.palette.textMuted),
      ),
    ),
  );
}
