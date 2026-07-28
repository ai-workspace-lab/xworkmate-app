import '../../runtime/runtime_models.dart';

enum WorkbenchItemState { blocked, syncing, running, ready, completed }

class WorkbenchItem {
  const WorkbenchItem({
    required this.sessionKey,
    required this.title,
    required this.preview,
    required this.projectLabel,
    required this.updatedAtMs,
    required this.state,
    required this.progress,
    required this.artifactPaths,
    required this.attachmentNames,
    required this.messageCount,
    required this.thread,
  });

  final String sessionKey;
  final String title;
  final String preview;
  final String projectLabel;
  final double updatedAtMs;
  final WorkbenchItemState state;
  final double progress;
  final List<String> artifactPaths;
  final List<String> attachmentNames;
  final int messageCount;
  final TaskThread? thread;

  bool get isCompleted => state == WorkbenchItemState.completed;

  bool get needsAttention =>
      state == WorkbenchItemState.blocked ||
      state == WorkbenchItemState.syncing ||
      state == WorkbenchItemState.running ||
      state == WorkbenchItemState.ready;
}

class WorkbenchProject {
  const WorkbenchProject({
    required this.label,
    required this.items,
    required this.progress,
    required this.artifactCount,
  });

  final String label;
  final List<WorkbenchItem> items;
  final double progress;
  final int artifactCount;
}

enum WorkbenchInboxKind { artifact, attachment, note }

class WorkbenchInboxItem {
  const WorkbenchInboxItem({
    required this.sessionKey,
    required this.title,
    required this.subtitle,
    required this.sourceTitle,
    required this.updatedAtMs,
    required this.kind,
  });

  final String sessionKey;
  final String title;
  final String subtitle;
  final String sourceTitle;
  final double updatedAtMs;
  final WorkbenchInboxKind kind;
}

class WorkbenchProjection {
  const WorkbenchProjection({
    required this.items,
    required this.projects,
    required this.inbox,
    required this.workloadSeries,
  });

  final List<WorkbenchItem> items;
  final List<WorkbenchProject> projects;
  final List<WorkbenchInboxItem> inbox;
  final List<double> workloadSeries;

  int get artifactCount =>
      items.fold(0, (sum, item) => sum + item.artifactPaths.length);

  int get syncingCount =>
      items.where((item) => item.state == WorkbenchItemState.syncing).length;

  int get blockedCount =>
      items.where((item) => item.state == WorkbenchItemState.blocked).length;

  int get completedCount =>
      items.where((item) => item.state == WorkbenchItemState.completed).length;

  List<WorkbenchItem> get todos {
    final pending = items
        .where((item) => !item.isCompleted)
        .toList(growable: false);
    return pending.isEmpty ? items : pending;
  }
}

WorkbenchProjection buildWorkbenchProjection({
  required List<GatewaySessionSummary> sessions,
  required TaskThread? Function(String sessionKey) threadForSession,
  DateTime? now,
}) {
  final items =
      sessions
          .map((session) {
            final thread = threadForSession(session.key);
            final title = _firstNonEmpty([
              thread?.title,
              session.label,
              session.key,
            ]);
            final latestMessage = _latestMeaningfulMessage(thread);
            final preview = _firstNonEmpty([
              session.lastMessagePreview,
              latestMessage?.text,
              thread?.lifecycleState.lastResultCode,
            ]);
            final updatedAtMs = _latestTimestamp([
              session.updatedAtMs,
              thread?.updatedAtMs,
              thread?.lifecycleState.lastRunAtMs,
              thread?.lastArtifactSyncAtMs,
              latestMessage?.timestampMs,
            ]);
            return WorkbenchItem(
              sessionKey: session.key,
              title: title,
              preview: preview,
              projectLabel: _projectLabel(thread, title),
              updatedAtMs: updatedAtMs,
              state: _resolveState(thread),
              progress: _resolveProgress(thread),
              artifactPaths:
                  thread?.lastTaskArtifactRelativePaths ?? const <String>[],
              attachmentNames:
                  thread?.taskInputAttachments
                      .map((attachment) => attachment.name.trim())
                      .where((name) => name.isNotEmpty)
                      .toList(growable: false) ??
                  const <String>[],
              messageCount: thread?.messages.length ?? 0,
              thread: thread,
            );
          })
          .toList(growable: false)
        ..sort((left, right) => right.updatedAtMs.compareTo(left.updatedAtMs));

  final projectsByLabel = <String, List<WorkbenchItem>>{};
  for (final item in items) {
    projectsByLabel.putIfAbsent(item.projectLabel, () => []).add(item);
  }
  final projects =
      projectsByLabel.entries
          .map((entry) {
            final projectItems = entry.value;
            return WorkbenchProject(
              label: entry.key,
              items: List.unmodifiable(projectItems),
              progress: projectItems.isEmpty
                  ? 0
                  : projectItems.fold<double>(
                          0,
                          (sum, item) => sum + item.progress,
                        ) /
                        projectItems.length,
              artifactCount: projectItems.fold(
                0,
                (sum, item) => sum + item.artifactPaths.length,
              ),
            );
          })
          .toList(growable: false)
        ..sort((left, right) {
          final leftUpdated = left.items.isEmpty
              ? 0
              : left.items.first.updatedAtMs;
          final rightUpdated = right.items.isEmpty
              ? 0
              : right.items.first.updatedAtMs;
          return rightUpdated.compareTo(leftUpdated);
        });

  final inbox = <WorkbenchInboxItem>[];
  for (final item in items) {
    final thread = item.thread;
    for (final path in item.artifactPaths) {
      inbox.add(
        WorkbenchInboxItem(
          sessionKey: item.sessionKey,
          title: _fileName(path),
          subtitle: path,
          sourceTitle: item.title,
          updatedAtMs: thread?.lastArtifactSyncAtMs ?? item.updatedAtMs,
          kind: WorkbenchInboxKind.artifact,
        ),
      );
    }
    for (final attachment
        in thread?.taskInputAttachments ??
            const <TaskInputAttachmentRecord>[]) {
      inbox.add(
        WorkbenchInboxItem(
          sessionKey: item.sessionKey,
          title: attachment.name,
          subtitle: attachment.mimeType,
          sourceTitle: item.title,
          updatedAtMs: attachment.uploadedAtMs,
          kind: WorkbenchInboxKind.attachment,
        ),
      );
    }
    final latestUserMessage = _latestUserMessage(thread);
    if (latestUserMessage != null &&
        item.artifactPaths.isEmpty &&
        item.attachmentNames.isEmpty) {
      inbox.add(
        WorkbenchInboxItem(
          sessionKey: item.sessionKey,
          title: _truncate(latestUserMessage.text.trim(), 56),
          subtitle: 'TaskThread note',
          sourceTitle: item.title,
          updatedAtMs: latestUserMessage.timestampMs ?? item.updatedAtMs,
          kind: WorkbenchInboxKind.note,
        ),
      );
    }
  }
  inbox.sort((left, right) => right.updatedAtMs.compareTo(left.updatedAtMs));

  return WorkbenchProjection(
    items: List.unmodifiable(items),
    projects: List.unmodifiable(projects),
    inbox: List.unmodifiable(inbox),
    workloadSeries: List.unmodifiable(
      _buildWorkloadSeries(items, now ?? DateTime.now()),
    ),
  );
}

WorkbenchItemState _resolveState(TaskThread? thread) {
  if (thread == null) {
    return WorkbenchItemState.ready;
  }
  final lifecycle = thread.lifecycleState.status.trim().toLowerCase();
  final sync = thread.lastArtifactSyncStatus?.trim().toLowerCase() ?? '';
  final result =
      thread.lifecycleState.lastResultCode?.trim().toLowerCase() ?? '';
  final resultFailed =
      result.isNotEmpty &&
      result != 'success' &&
      result != 'ok' &&
      result != 'completed' &&
      result != '0';
  if (lifecycle == 'failed' ||
      lifecycle == 'interrupted' ||
      sync == 'failed' ||
      sync == 'interrupted' ||
      sync == 'partial' ||
      resultFailed) {
    return WorkbenchItemState.blocked;
  }
  if (lifecycle == 'syncing-artifacts' ||
      sync == 'syncing' ||
      sync == 'queued') {
    return WorkbenchItemState.syncing;
  }
  if (lifecycle == 'running') {
    return WorkbenchItemState.running;
  }
  if (lifecycle == 'completed') {
    return WorkbenchItemState.completed;
  }
  return WorkbenchItemState.ready;
}

double _resolveProgress(TaskThread? thread) {
  return switch (_resolveState(thread)) {
    WorkbenchItemState.blocked => 0.42,
    WorkbenchItemState.syncing => 0.84,
    WorkbenchItemState.running => 0.64,
    WorkbenchItemState.ready =>
      thread?.messages.isNotEmpty == true ? 0.28 : 0.12,
    WorkbenchItemState.completed => 1,
  };
}

String _projectLabel(TaskThread? thread, String fallback) {
  final candidates = [
    thread?.workspaceBinding.displayPath,
    thread?.workspaceBinding.workspacePath,
  ];
  for (final candidate in candidates) {
    final normalized = candidate?.trim().replaceAll('\\', '/') ?? '';
    if (normalized.isEmpty) {
      continue;
    }
    final segments = normalized
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    if (segments.isNotEmpty) {
      return segments.last;
    }
  }
  return fallback;
}

List<double> _buildWorkloadSeries(List<WorkbenchItem> items, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final start = today.subtract(const Duration(days: 6));
  final series = List<double>.filled(7, 0);
  for (final item in items) {
    final thread = item.thread;
    final events = <double>[
      if (item.updatedAtMs > 0) item.updatedAtMs,
      if ((thread?.lifecycleState.lastRunAtMs ?? 0) > 0)
        thread!.lifecycleState.lastRunAtMs!,
      if ((thread?.lastArtifactSyncAtMs ?? 0) > 0)
        thread!.lastArtifactSyncAtMs!,
      ...?thread?.messages
          .map((message) => message.timestampMs)
          .whereType<double>(),
    ];
    for (final eventMs in events) {
      final event = DateTime.fromMillisecondsSinceEpoch(eventMs.round());
      final eventDay = DateTime(event.year, event.month, event.day);
      final index = eventDay.difference(start).inDays;
      if (index >= 0 && index < series.length) {
        series[index] += 1;
      }
    }
  }
  return series;
}

GatewayChatMessage? _latestMeaningfulMessage(TaskThread? thread) {
  if (thread == null) {
    return null;
  }
  for (final message in thread.messages.reversed) {
    if (message.text.trim().isNotEmpty) {
      return message;
    }
  }
  return null;
}

GatewayChatMessage? _latestUserMessage(TaskThread? thread) {
  if (thread == null) {
    return null;
  }
  for (final message in thread.messages.reversed) {
    if (message.role.trim().toLowerCase() == 'user' &&
        message.text.trim().isNotEmpty) {
      return message;
    }
  }
  return null;
}

double _latestTimestamp(Iterable<double?> values) {
  var latest = 0.0;
  for (final value in values) {
    if (value != null && value > latest) {
      latest = value;
    }
  }
  return latest;
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final normalized = value?.trim() ?? '';
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return '';
}

String _fileName(String path) {
  final normalized = path.trim().replaceAll('\\', '/');
  final parts = normalized.split('/');
  return parts.isEmpty ? normalized : parts.last;
}

String _truncate(String value, int maxCharacters) {
  if (value.length <= maxCharacters) {
    return value;
  }
  return '${value.substring(0, maxCharacters - 1)}…';
}
