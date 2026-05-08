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
  });

  const AssistantTaskProgressState.idle()
    : phase = AssistantTaskProgressPhase.idle,
      label = '',
      value = null;

  final AssistantTaskProgressPhase phase;
  final String label;
  final double? value;

  bool get visible => phase != AssistantTaskProgressPhase.idle;
  bool get interrupted => phase == AssistantTaskProgressPhase.interrupted;
}

class AssistantTaskProgressBar extends StatelessWidget {
  const AssistantTaskProgressBar({super.key, required this.state});

  final AssistantTaskProgressState state;

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
    );
  }
}

AssistantTaskProgressState assistantTaskProgressState({
  required bool pending,
  required String lifecycleStatus,
  required String lastResultCode,
  required String artifactSyncStatus,
}) {
  final syncStatus = artifactSyncStatus.trim().toLowerCase();
  final status = lifecycleStatus.trim().toLowerCase();
  if (pending && syncStatus == 'syncing') {
    return AssistantTaskProgressState(
      phase: AssistantTaskProgressPhase.syncingArtifacts,
      label: appText('正在同步生成文件...', 'Syncing generated files...'),
      value: 0.82,
    );
  }
  if (pending && status == 'continuing') {
    return AssistantTaskProgressState(
      phase: AssistantTaskProgressPhase.continuing,
      label: appText('任务继续中...', 'Continuing task...'),
      value: 0.62,
    );
  }
  if (pending && status == 'retrying') {
    return AssistantTaskProgressState(
      phase: AssistantTaskProgressPhase.retrying,
      label: appText('任务重试中...', 'Retrying task...'),
      value: 0.38,
    );
  }
  if (pending) {
    return AssistantTaskProgressState(
      phase: AssistantTaskProgressPhase.running,
      label: appText('任务运行中...', 'Task running...'),
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
