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

  /// Role names stay in English in both languages: they are the names the
  /// orchestrator policy uses.
  String get label => switch (this) {
    BotRole.auto => appText('自动选择', 'Auto'),
    BotRole.chat => 'Chat',
    BotRole.worker => 'Worker',
    BotRole.engineer => 'Engineer',
    BotRole.architect => 'Architect',
    BotRole.researcher => 'Researcher',
    BotRole.specialist => 'Specialist',
  };

  String get summary => switch (this) {
    BotRole.auto => appText(
      '由编排器按任务选择角色、执行器和模型',
      'The orchestrator picks the role, executor and model',
    ),
    BotRole.chat => appText(
      '问答、解释和简短说明',
      'Questions, explanations and short answers',
    ),
    BotRole.worker => appText(
      '按既定步骤做日常和批量操作',
      'Routine and batch work along known steps',
    ),
    BotRole.engineer => appText(
      '改代码、跑测试，交付可验证的变更',
      'Changes code and runs tests',
    ),
    BotRole.architect => appText(
      '设计方案与评审，可与研究互相协作',
      'Designs and reviews; works with Researcher',
    ),
    BotRole.researcher => appText(
      '调研资料、对比方案，整理结论',
      'Researches, compares options, summarizes',
    ),
    BotRole.specialist => appText('指定领域的专家任务', 'Work for a named specialty'),
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

/// Session title for a task: its first 40 characters.
String botTaskTitle(String text) {
  final prompt = text.trim();
  return prompt.length > 40 ? '${prompt.substring(0, 40)}…' : prompt;
}

/// Routing for a task. An empty [role] lets the orchestrator's policy pick
/// one; [workspace] is a key the orchestrator host maps to a directory.
Map<String, Object?> botRoleRouting({
  String role = '',
  String workspace = '',
}) => <String, Object?>{
  'roleMode': 'auto',
  if (role.trim().isNotEmpty) 'role': role.trim(),
  if (workspace.trim().isNotEmpty) 'workspace': workspace.trim(),
};

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
