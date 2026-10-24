import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import '../../runtime/task_session_client.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import 'bot_team_controller.dart';
import 'bot_team_models.dart';

/// The Bot team: send a task to a role, follow its run, cancel it. Tasks are
/// queued in Accounts and run by the DSH orchestrator, which picks executor
/// and model under its policy; this page only shows what it reports.
class BotTeamPage extends StatefulWidget {
  const BotTeamPage({
    super.key,
    required this.clientFactory,
    this.controller,
    this.leading,
  });

  final FutureOr<TaskSessionClient?> Function() clientFactory;

  /// Injected by tests; the page owns and disposes one it creates itself.
  final BotTeamController? controller;

  /// Placed before the title (the hidden sidebar's way back).
  final Widget? leading;

  @override
  State<BotTeamPage> createState() => _BotTeamPageState();
}

class _BotTeamPageState extends State<BotTeamPage> {
  late final BotTeamController _controller;
  late final bool _ownsController;
  final TextEditingController _composer = TextEditingController();
  final TextEditingController _workspace = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        BotTeamController(clientFactory: widget.clientFactory);
    _controller.load();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    _composer.dispose();
    _workspace.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text;
    if (text.trim().isEmpty) {
      return;
    }
    await _controller.send(text, workspaceKey: _workspace.text);
    if (_controller.error.isEmpty) {
      _composer.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final palette = context.palette;
        final theme = Theme.of(context);
        return Padding(
          key: const Key('bot-team-page'),
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ?widget.leading,
                  Icon(Icons.groups_2_outlined, color: palette.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    appText('Bot 团队', 'Bot team'),
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('bot-team-refresh-button'),
                    tooltip: appText('刷新', 'Refresh'),
                    onPressed: _controller.loading ? null : _controller.load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              Text(
                appText(
                  '按角色下发任务，由编排器选择执行器与模型。',
                  'Send a task to a role; the orchestrator picks the executor and model.',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              if (_controller.error.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _Banner(text: _controller.error),
              ],
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 220,
                      child: _SessionList(controller: _controller),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _TaskTimeline(controller: _controller),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _Composer(
                            controller: _controller,
                            composer: _composer,
                            workspace: _workspace,
                            enabled:
                                _controller.connected && !_controller.sending,
                            onSend: _send,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      key: const Key('bot-team-error'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: palette.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.controller});

  final BotTeamController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              appText('会话', 'Sessions').toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: palette.textMuted,
                letterSpacing: 1.1,
              ),
            ),
            const Spacer(),
            IconButton(
              key: const Key('bot-team-new-session-button'),
              tooltip: appText('新会话', 'New session'),
              visualDensity: VisualDensity.compact,
              onPressed: controller.connected
                  ? controller.startNewSession
                  : null,
              icon: const Icon(Icons.add_rounded, size: 18),
            ),
          ],
        ),
        Expanded(
          child: controller.sessions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    appText('还没有会话', 'No sessions yet'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              : ListView(
                  children: [
                    for (final session in controller.sessions)
                      ListTile(
                        key: Key('bot-team-session-${session.sessionId}'),
                        dense: true,
                        selected:
                            session.sessionId == controller.selectedSessionId,
                        selectedTileColor: palette.chromeSurfacePressed,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                        title: Text(
                          session.title.isEmpty
                              ? appText('未命名任务', 'Untitled task')
                              : session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () =>
                            controller.selectSession(session.sessionId),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// The role menu in the composer: the button shows the current role, the
/// menu lists the escalation ladder Chat → Worker → Engineer → Architect ⟷
/// Researcher → Specialist, with "auto" above it to let the orchestrator's
/// policy choose.
class _RoleMenu extends StatelessWidget {
  const _RoleMenu({required this.controller, required this.enabled});

  final BotTeamController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final current = controller.role;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.surfacePrimary),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: palette.strokeSoft)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.dialog),
          ),
        ),
      ),
      menuChildren: [
        _item(context, BotRole.auto),
        const Divider(height: 9),
        for (final role in BotRole.values)
          if (role != BotRole.auto) _item(context, role),
      ],
      builder: (context, menu, _) => TextButton.icon(
        key: const Key('bot-team-role-button'),
        onPressed: enabled
            ? () => menu.isOpen ? menu.close() : menu.open()
            : null,
        style: TextButton.styleFrom(
          foregroundColor: palette.textPrimary,
          backgroundColor: palette.chromeSurfacePressed,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
        icon: Icon(current.icon, size: 18),
        label: Text(current.label),
      ),
    );
  }

  Widget _item(BuildContext context, BotRole role) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final selected = controller.role == role;
    return MenuItemButton(
      key: Key('bot-team-role-${role.name}'),
      onPressed: () => controller.setRole(role),
      style: MenuItemButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: selected ? palette.chromeSurfacePressed : null,
      ),
      leadingIcon: Icon(role.icon, size: 20, color: palette.textSecondary),
      trailingIcon: selected
          ? Icon(Icons.check_rounded, size: 18, color: palette.accent)
          : const SizedBox(width: 18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              role.label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              role.summary,
              softWrap: true,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskTimeline extends StatelessWidget {
  const _TaskTimeline({required this.controller});

  final BotTeamController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final tasks = controller.tasks;
    if (tasks.isEmpty) {
      return Center(
        child: Text(
          controller.loading
              ? appText('加载中…', 'Loading…')
              : appText('选择角色，写下任务即可开始。', 'Pick a role and describe a task.'),
          style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
        ),
      );
    }
    return ListView.separated(
      key: const Key('bot-team-timeline'),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) => _TaskCard(
        task: tasks[index],
        onCancel: () => controller.cancel(tasks[index].runId),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onCancel});

  final BotTaskView task;
  final VoidCallback onCancel;

  Color _phaseColor(AppPalette palette) => switch (task.phase) {
    BotTaskPhase.completed => palette.success,
    BotTaskPhase.failed || BotTaskPhase.rejected => palette.danger,
    BotTaskPhase.cancelled => palette.textMuted,
    _ => palette.accent,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final route = [
      if (task.role.isNotEmpty) task.role,
      if (task.executor.isNotEmpty) task.executor,
      if (task.modelId.isNotEmpty) task.modelId,
    ].join(' · ');
    return Container(
      key: Key('bot-team-task-${task.runId}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.prompt, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(Icons.circle, size: 8, color: _phaseColor(palette)),
              const SizedBox(width: AppSpacing.xs),
              Text(
                task.cancelRequested && task.active
                    ? appText('正在取消…', 'Cancelling…')
                    : task.phase.label,
                key: Key('bot-team-task-phase-${task.runId}'),
                style: theme.textTheme.labelMedium,
              ),
              if (route.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    route,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (task.active && !task.cancelRequested)
                TextButton.icon(
                  key: Key('bot-team-cancel-${task.runId}'),
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: Text(appText('取消', 'Cancel')),
                ),
            ],
          ),
          if (task.memoryUnavailable)
            Text(
              appText(
                '共享记忆暂不可用，本次未带入记忆。',
                'Shared memory was unavailable for this run.',
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: palette.warning,
              ),
            ),
          if (task.answer.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              task.answer,
              key: Key('bot-team-answer-${task.runId}'),
            ),
          ],
          if (task.error.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              task.error,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.danger),
            ),
          ],
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.composer,
    required this.workspace,
    required this.enabled,
    required this.onSend,
  });

  final BotTeamController controller;
  final TextEditingController composer;
  final TextEditingController workspace;
  final bool enabled;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 160,
          child: TextField(
            key: const Key('bot-team-workspace-field'),
            controller: workspace,
            enabled: enabled,
            decoration: InputDecoration(
              isDense: true,
              labelText: appText('工作区', 'Workspace'),
              hintText: appText('已授权的工作区键', 'Authorized workspace key'),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: TextField(
            key: const Key('bot-team-composer'),
            controller: composer,
            enabled: enabled,
            minLines: 1,
            maxLines: 5,
            decoration: InputDecoration(
              isDense: true,
              hintText: appText('描述任务…', 'Describe the task…'),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _RoleMenu(controller: controller, enabled: enabled),
        const SizedBox(width: AppSpacing.sm),
        FilledButton.icon(
          key: const Key('bot-team-send-button'),
          onPressed: enabled ? onSend : null,
          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          label: Text(appText('发送', 'Send')),
        ),
      ],
    );
  }
}
