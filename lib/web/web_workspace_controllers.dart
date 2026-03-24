import '../runtime/runtime_models.dart';

class WebTasksController {
  List<DerivedTaskItem> _queue = const <DerivedTaskItem>[];
  List<DerivedTaskItem> _running = const <DerivedTaskItem>[];
  List<DerivedTaskItem> _history = const <DerivedTaskItem>[];
  List<DerivedTaskItem> _failed = const <DerivedTaskItem>[];
  List<DerivedTaskItem> _scheduled = const <DerivedTaskItem>[];

  List<DerivedTaskItem> get queue => _queue;
  List<DerivedTaskItem> get running => _running;
  List<DerivedTaskItem> get history => _history;
  List<DerivedTaskItem> get failed => _failed;
  List<DerivedTaskItem> get scheduled => _scheduled;

  int get totalCount =>
      _queue.length + _running.length + _history.length + _failed.length;

  void recompute({
    required List<AssistantThreadRecord> threads,
    required List<GatewayCronJobSummary> cronJobs,
    required String currentSessionKey,
    required Set<String> pendingSessionKeys,
  }) {
    final sorted = threads.toList(growable: false)
      ..sort(
        (left, right) =>
            (right.updatedAtMs ?? 0).compareTo(left.updatedAtMs ?? 0),
      );
    final queue = <DerivedTaskItem>[];
    final running = <DerivedTaskItem>[];
    final history = <DerivedTaskItem>[];
    final failed = <DerivedTaskItem>[];
    for (final thread in sorted) {
      final item = DerivedTaskItem(
        id: thread.sessionKey,
        title: thread.title.trim().isEmpty ? 'Untitled task' : thread.title,
        owner: 'Assistant',
        status: _statusForThread(
          thread: thread,
          currentSessionKey: currentSessionKey,
          pendingSessionKeys: pendingSessionKeys,
        ),
        surface: _surfaceForTarget(thread.executionTarget),
        startedAtLabel: _timeLabel(thread.updatedAtMs),
        durationLabel: _durationLabel(thread.updatedAtMs),
        summary: _summaryForThread(thread),
        sessionKey: thread.sessionKey,
      );
      switch (item.status) {
        case 'Running':
          running.add(item);
        case 'Failed':
          failed.add(item);
        case 'Queued':
          queue.add(item);
        default:
          history.add(item);
      }
    }
    _queue = queue;
    _running = running;
    _history = history;
    _failed = failed;
    _scheduled = cronJobs
        .map(
          (job) => DerivedTaskItem(
            id: job.id,
            title: job.name,
            owner:
                job.agentId?.trim().isNotEmpty == true ? job.agentId! : 'Cron',
            status: job.enabled ? 'Scheduled' : 'Disabled',
            surface: 'Cron',
            startedAtLabel: _timeLabel(job.nextRunAtMs?.toDouble()),
            durationLabel: job.scheduleLabel,
            summary:
                job.description ??
                job.lastError ??
                job.lastStatus ??
                'Scheduled automation',
            sessionKey: 'cron:${job.id}',
          ),
        )
        .toList(growable: false);
  }

  String _statusForThread({
    required AssistantThreadRecord thread,
    required String currentSessionKey,
    required Set<String> pendingSessionKeys,
  }) {
    final messages = thread.messages;
    if (pendingSessionKeys.contains(thread.sessionKey) ||
        thread.sessionKey == currentSessionKey &&
            messages.any((item) => item.pending)) {
      return 'Running';
    }
    if (messages.any((item) => item.error)) {
      return 'Failed';
    }
    if (messages.isEmpty) {
      return 'Queued';
    }
    return 'Open';
  }

  String _surfaceForTarget(AssistantExecutionTarget? target) {
    return switch (target) {
      AssistantExecutionTarget.local => 'Local Gateway',
      AssistantExecutionTarget.remote => 'Remote Gateway',
      _ => 'Single Agent',
    };
  }

  String _summaryForThread(AssistantThreadRecord thread) {
    final latest = thread.messages.isEmpty ? null : thread.messages.last;
    final text = latest?.text.trim() ?? '';
    if (text.isNotEmpty) {
      return text;
    }
    if (thread.importedSkills.isNotEmpty) {
      return 'Skills: ${thread.importedSkills.length}';
    }
    return 'No activity yet';
  }

  String _timeLabel(double? timestampMs) {
    if (timestampMs == null) {
      return 'Unknown';
    }
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs.toInt());
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _durationLabel(double? timestampMs) {
    if (timestampMs == null) {
      return 'n/a';
    }
    final delta = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestampMs.toInt()),
    );
    if (delta.inMinutes < 1) {
      return 'just now';
    }
    if (delta.inHours < 1) {
      return '${delta.inMinutes}m ago';
    }
    if (delta.inDays < 1) {
      return '${delta.inHours}h ago';
    }
    return '${delta.inDays}d ago';
  }
}

class WebSkillsController {
  WebSkillsController(this._onRefresh);

  final Future<void> Function(String? agentId) _onRefresh;

  Future<void> refresh({String? agentId}) {
    return _onRefresh(agentId);
  }
}
