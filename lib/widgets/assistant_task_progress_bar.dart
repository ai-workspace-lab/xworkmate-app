import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

enum AssistantTaskProgressPhase {
  idle,
  running,
  retrying,
  continuing,
  syncingArtifacts,
  interrupted,
}

class AssistantTaskProgressState {
  const AssistantTaskProgressState({
    required this.phase,
    required this.label,
    this.value,
    this.runtimeBudgetMinutes,
  });

  const AssistantTaskProgressState.idle()
    : phase = AssistantTaskProgressPhase.idle,
      label = '',
      value = null,
      runtimeBudgetMinutes = null;

  final AssistantTaskProgressPhase phase;
  final String label;
  final double? value;
  final int? runtimeBudgetMinutes;

  bool get visible => phase != AssistantTaskProgressPhase.idle;
  bool get interrupted => phase == AssistantTaskProgressPhase.interrupted;
  bool get running =>
      phase == AssistantTaskProgressPhase.running ||
      phase == AssistantTaskProgressPhase.retrying ||
      phase == AssistantTaskProgressPhase.continuing ||
      phase == AssistantTaskProgressPhase.syncingArtifacts;
}

class AssistantTaskProgressBar extends StatelessWidget {
  const AssistantTaskProgressBar({
    super.key,
    required this.state,
    this.onStop,
    this.onContinue,
  });

  final AssistantTaskProgressState state;
  final VoidCallback? onStop;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    if (!state.visible) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final color = state.interrupted
        ? theme.colorScheme.error
        : state.phase == AssistantTaskProgressPhase.retrying
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    return Container(
      key: const Key('assistant-task-progress-bar'),
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: state.interrupted
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.18)
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.18),
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.42)),
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.42)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  state.label,
                  key: const Key('assistant-task-progress-label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                LinearProgressIndicator(
                  key: const Key('assistant-task-progress-indicator'),
                  value: state.value,
                  minHeight: 3,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
              ],
            ),
          ),
          if (state.running && onStop != null) ...[
            const SizedBox(width: 8),
            _AssistantTaskProgressActionButton(
              key: const Key('assistant-task-progress-stop-button'),
              icon: Icons.stop_rounded,
              label: appText('停止', 'Stop'),
              color: color,
              onPressed: onStop,
            ),
          ] else if (state.interrupted && onContinue != null) ...[
            const SizedBox(width: 8),
            _AssistantTaskProgressActionButton(
              key: const Key('assistant-task-progress-continue-button'),
              icon: Icons.play_arrow_rounded,
              label: appText('继续', 'Continue'),
              color: color,
              onPressed: onContinue,
            ),
          ],
        ],
      ),
    );
  }
}

class _AssistantTaskProgressActionButton extends StatelessWidget {
  const _AssistantTaskProgressActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

AssistantTaskProgressState assistantTaskProgressState({
  required bool pending,
  required String lifecycleStatus,
  required String lastResultCode,
  required String artifactSyncStatus,
  int? runtimeBudgetMinutes,
}) {
  final syncStatus = artifactSyncStatus.trim().toLowerCase();
  final status = lifecycleStatus.trim().toLowerCase();
  final budget = runtimeBudgetMinutes == null || runtimeBudgetMinutes <= 0
      ? null
      : runtimeBudgetMinutes;
  if (pending && syncStatus == 'syncing') {
    return AssistantTaskProgressState(
      phase: AssistantTaskProgressPhase.syncingArtifacts,
      label: appText('正在同步生成文件...', 'Syncing generated files...'),
      value: 0.82,
      runtimeBudgetMinutes: budget,
    );
  }
  if (pending && status == 'continuing') {
    return AssistantTaskProgressState(
      phase: AssistantTaskProgressPhase.continuing,
      label: _budgetedProgressLabel(
        appText('任务继续中', 'Continuing task'),
        budget,
      ),
      value: 0.62,
      runtimeBudgetMinutes: budget,
    );
  }
  if (pending && status == 'retrying') {
    return AssistantTaskProgressState(
      phase: AssistantTaskProgressPhase.retrying,
      label: _budgetedProgressLabel(appText('任务重试中', 'Retrying task'), budget),
      value: 0.38,
      runtimeBudgetMinutes: budget,
    );
  }
  if (pending) {
    return AssistantTaskProgressState(
      phase: AssistantTaskProgressPhase.running,
      label: _budgetedProgressLabel(appText('任务运行中', 'Task running'), budget),
      runtimeBudgetMinutes: budget,
    );
  }
  final result = lastResultCode.trim().toUpperCase();
  if (status == 'interrupted' || syncStatus == 'interrupted') {
    return AssistantTaskProgressState(
      phase: AssistantTaskProgressPhase.interrupted,
      label: _interruptedTaskProgressLabel(result),
      value: 0.48,
    );
  }
  return const AssistantTaskProgressState.idle();
}

String _budgetedProgressLabel(String base, int? minutes) {
  if (minutes == null || minutes <= 0) {
    return '$base...';
  }
  return appText('$base，预计最长 $minutes 分钟...', '$base, up to $minutes min...');
}

String _interruptedTaskProgressLabel(String result) {
  if (result == 'ACP_HTTP_HANDSHAKE_INTERRUPTED') {
    return appText(
      'Bridge 握手中断，等待下一次发送续写同一会话。',
      'Bridge handshake interrupted; the next send will continue this session.',
    );
  }
  return appText(
    'Bridge 响应中断，等待下一次发送续写同一会话。',
    'Bridge response interrupted; the next send will continue this session.',
  );
}
