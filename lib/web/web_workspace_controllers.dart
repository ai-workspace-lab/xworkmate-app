import '../runtime/runtime_models.dart';

class WebTasksController {
  List<DerivedTaskItem> queueInternal = const <DerivedTaskItem>[];
  List<DerivedTaskItem> runningInternal = const <DerivedTaskItem>[];
  List<DerivedTaskItem> historyInternal = const <DerivedTaskItem>[];
  List<DerivedTaskItem> failedInternal = const <DerivedTaskItem>[];
  List<DerivedTaskItem> scheduledInternal = const <DerivedTaskItem>[];

  List<DerivedTaskItem> get queue => queueInternal;
  List<DerivedTaskItem> get running => runningInternal;
  List<DerivedTaskItem> get history => historyInternal;
  List<DerivedTaskItem> get failed => failedInternal;
  List<DerivedTaskItem> get scheduled => scheduledInternal;

  int get totalCount =>
      queueInternal.length +
      runningInternal.length +
      historyInternal.length +
      failedInternal.length;

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
        status: statusForThreadInternal(
          thread: thread,
          currentSessionKey: currentSessionKey,
          pendingSessionKeys: pendingSessionKeys,
        ),
        surface: surfaceForTargetInternal(thread.executionTarget),
        startedAtLabel: timeLabelInternal(thread.updatedAtMs),
        durationLabel: durationLabelInternal(thread.updatedAtMs),
        summary: summaryForThreadInternal(thread),
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
    queueInternal = queue;
    runningInternal = running;
    historyInternal = history;
    failedInternal = failed;
    scheduledInternal = cronJobs
        .map(
          (job) => DerivedTaskItem(
            id: job.id,
            title: job.name,
            owner: job.agentId?.trim().isNotEmpty == true
                ? job.agentId!
                : 'Cron',
            status: job.enabled ? 'Scheduled' : 'Disabled',
            surface: 'Cron',
            startedAtLabel: timeLabelInternal(job.nextRunAtMs?.toDouble()),
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

  String statusForThreadInternal({
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

  String surfaceForTargetInternal(AssistantExecutionTarget? target) {
    return switch (target) {
      AssistantExecutionTarget.local => 'Local Gateway',
      AssistantExecutionTarget.remote => 'Remote Gateway',
      _ => 'Single Agent',
    };
  }

  String summaryForThreadInternal(AssistantThreadRecord thread) {
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

  String timeLabelInternal(double? timestampMs) {
    if (timestampMs == null) {
      return 'Unknown';
    }
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs.toInt());
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String durationLabelInternal(double? timestampMs) {
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
  WebSkillsController(this.onRefreshInternal);

  final Future<void> Function(String? agentId) onRefreshInternal;

  Future<void> refresh({String? agentId}) {
    return onRefreshInternal(agentId);
  }
}
