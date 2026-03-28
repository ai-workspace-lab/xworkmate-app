part of 'runtime_controllers.dart';

class DerivedTasksController extends ChangeNotifier {
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
    required List<GatewaySessionSummary> sessions,
    required List<GatewayCronJobSummary> cronJobs,
    required String currentSessionKey,
    required bool hasPendingRun,
    required String activeAgentName,
  }) {
    final sorted = sessions.toList(growable: false)
      ..sort(
        (left, right) =>
            (right.updatedAtMs ?? 0).compareTo(left.updatedAtMs ?? 0),
      );
    final queue = <DerivedTaskItem>[];
    final running = <DerivedTaskItem>[];
    final history = <DerivedTaskItem>[];
    final failed = <DerivedTaskItem>[];
    for (final session in sorted) {
      final item = DerivedTaskItem(
        id: session.key,
        title: session.label,
        owner: activeAgentName,
        status: _statusForSession(
          session: session,
          currentSessionKey: currentSessionKey,
          hasPendingRun: hasPendingRun,
        ),
        surface: session.surface ?? session.kind ?? 'Assistant',
        startedAtLabel: _timeLabel(session.updatedAtMs),
        durationLabel: _durationLabel(session.updatedAtMs),
        summary:
            session.lastMessagePreview ?? session.subject ?? 'Session activity',
        sessionKey: session.key,
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
            owner: job.agentId?.trim().isNotEmpty == true
                ? job.agentId!
                : activeAgentName,
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
    notifyListeners();
  }

  String _statusForSession({
    required GatewaySessionSummary session,
    required String currentSessionKey,
    required bool hasPendingRun,
  }) {
    if (session.abortedLastRun == true) {
      return 'Failed';
    }
    if (hasPendingRun && matchesSessionKey(session.key, currentSessionKey)) {
      return 'Running';
    }
    if ((session.lastMessagePreview ?? '').isEmpty) {
      return 'Queued';
    }
    return 'Open';
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

String normalizeMainSessionKey(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? 'main' : trimmed;
}

String makeAgentSessionKey({required String agentId, required String baseKey}) {
  final trimmedAgent = agentId.trim();
  final trimmedBase = baseKey.trim();
  if (trimmedAgent.isEmpty) {
    return normalizeMainSessionKey(trimmedBase);
  }
  return 'agent:$trimmedAgent:${normalizeMainSessionKey(trimmedBase)}';
}

bool matchesSessionKey(String incoming, String current) {
  final left = incoming.trim().toLowerCase();
  final right = current.trim().toLowerCase();
  if (left == right) {
    return true;
  }
  return (left == 'agent:main:main' && right == 'main') ||
      (left == 'main' && right == 'agent:main:main');
}

String encodePrettyJson(Object value) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(value);
}

String _ephemeralId() => DateTime.now().microsecondsSinceEpoch.toString();
