import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import '../../runtime/task_session_client.dart';

/// Roles the DSH orchestrator routes by. The orchestrator's reviewed policy
/// decides which are enabled and which executor and model serve them; a role
/// it has not enabled comes back as a rejected task with its reason.
enum BotRole { auto, chat, worker, engineer, architect, researcher, specialist }

extension BotRoleCopy on BotRole {
  /// The routing value; auto sends no role and lets the policy decide.
  String get routingValue => this == BotRole.auto ? '' : name;

  String get label => switch (this) {
    BotRole.auto => appText('自动', 'Auto'),
    BotRole.chat => appText('对话', 'Chat'),
    BotRole.worker => appText('执行', 'Worker'),
    BotRole.engineer => appText('工程', 'Engineer'),
    BotRole.architect => appText('架构', 'Architect'),
    BotRole.researcher => appText('研究', 'Researcher'),
    BotRole.specialist => appText('专家', 'Specialist'),
  };

  String get summary => switch (this) {
    BotRole.auto => appText('由编排策略选择角色', 'The policy picks the role'),
    BotRole.chat => appText('问答与说明', 'Questions and explanations'),
    BotRole.worker => appText('批量与日常操作', 'Routine and batch work'),
    BotRole.engineer => appText('改代码、跑测试', 'Change code and run tests'),
    BotRole.architect => appText('方案与评审', 'Design and review'),
    BotRole.researcher => appText('调研与资料整理', 'Research and synthesis'),
    BotRole.specialist => appText('指定领域专家', 'A named specialty'),
  };

  IconData get icon => switch (this) {
    BotRole.auto => Icons.auto_awesome_outlined,
    BotRole.chat => Icons.chat_bubble_outline_rounded,
    BotRole.worker => Icons.handyman_outlined,
    BotRole.engineer => Icons.code_rounded,
    BotRole.architect => Icons.architecture_rounded,
    BotRole.researcher => Icons.travel_explore_rounded,
    BotRole.specialist => Icons.workspace_premium_outlined,
  };
}

enum BotTaskPhase {
  queued,
  claimed,
  selected,
  executing,
  completed,
  failed,
  rejected,
  cancelled,
}

extension BotTaskPhaseCopy on BotTaskPhase {
  bool get terminal =>
      this == BotTaskPhase.completed ||
      this == BotTaskPhase.failed ||
      this == BotTaskPhase.rejected ||
      this == BotTaskPhase.cancelled;

  String get label => switch (this) {
    BotTaskPhase.queued => appText('排队中', 'Queued'),
    BotTaskPhase.claimed => appText('已领取', 'Claimed'),
    BotTaskPhase.selected => appText('已选定执行器', 'Executor selected'),
    BotTaskPhase.executing => appText('执行中', 'Running'),
    BotTaskPhase.completed => appText('已完成', 'Completed'),
    BotTaskPhase.failed => appText('失败', 'Failed'),
    BotTaskPhase.rejected => appText('被策略拒绝', 'Rejected by policy'),
    BotTaskPhase.cancelled => appText('已取消', 'Cancelled'),
  };
}

/// One task run folded from the session's ordered events.
class BotTaskView {
  BotTaskView({required this.runId});

  final String runId;
  String prompt = '';
  BotTaskPhase phase = BotTaskPhase.queued;
  String role = '';
  String executor = '';
  String modelId = '';
  String answer = '';
  String error = '';
  bool cancelRequested = false;
  bool memoryUsed = false;
  bool memoryUnavailable = false;
  int lastSeq = 0;

  bool get active => !phase.terminal;
}

String _string(Object? value) => value?.toString().trim() ?? '';

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

/// Folds events in sequence order into one view per run, oldest first.
List<BotTaskView> foldBotTasks(Iterable<TaskSessionEvent> events) {
  final runs = <String, BotTaskView>{};
  final ordered = events.toList()..sort((a, b) => a.seq.compareTo(b.seq));
  for (final event in ordered) {
    final runId = event.taskRunId;
    if (runId.isEmpty) {
      continue;
    }
    final view = runs.putIfAbsent(runId, () => BotTaskView(runId: runId));
    view.lastSeq = event.seq;
    final payload = event.payload;
    final selection = _map(payload['roleSelection']);
    if (selection.isNotEmpty) {
      view.role = _string(selection['role']);
      view.executor = _string(selection['executor']);
      view.modelId = _string(selection['modelId']);
    }
    switch (event.type) {
      case 'message.created':
        view.prompt = _string(payload['text']);
      case 'run.queued':
        view.phase = BotTaskPhase.queued;
      case 'run.running':
        view.phase = BotTaskPhase.claimed;
      case 'run.progressed':
        switch (_string(payload['phase'])) {
          case 'selected':
            view.phase = BotTaskPhase.selected;
          case 'started':
            view.phase = BotTaskPhase.executing;
          case 'memory':
            view.memoryUsed = true;
          case 'memory_unavailable':
            view.memoryUnavailable = true;
        }
      case 'run.cancel_requested':
        view.cancelRequested = true;
      case 'assistant.message.created':
        view.answer = _string(payload['text']);
      case 'run.completed':
        view.phase = BotTaskPhase.completed;
        _applyResolved(view, payload);
      case 'run.failed':
        final rejected = _string(payload['phase']) == 'rejected';
        view.phase = rejected ? BotTaskPhase.rejected : BotTaskPhase.failed;
        _applyResolved(view, payload);
        view.error = rejected
            ? _string(selection['message'])
            : [
                _string(payload['code']),
                _string(payload['stopReason']),
                _string(payload['error']),
                _string(payload['diagnostic']),
              ].where((part) => part.isNotEmpty).join(' · ');
      case 'run.cancelled':
        view.phase = BotTaskPhase.cancelled;
    }
  }
  return runs.values.toList(growable: false);
}

void _applyResolved(BotTaskView view, Map<String, dynamic> payload) {
  if (_string(payload['resolvedRole']).isNotEmpty) {
    view.role = _string(payload['resolvedRole']);
  }
  if (_string(payload['executor']).isNotEmpty) {
    view.executor = _string(payload['executor']);
  }
  if (_string(payload['resolvedModelId']).isNotEmpty) {
    view.modelId = _string(payload['resolvedModelId']);
  }
}
