// Lightweight cloud-session transport models.
//
// This file deliberately contains no widget or presentation concerns. The
// existing TaskThread/UI remains the app-facing model while this contract
// supplies its durable session cursor and scheduler state.

class CloudSessionSnapshot {
  const CloudSessionSnapshot({
    required this.sessionId,
    required this.namespaceId,
    required this.title,
    required this.lastEventSeq,
    required this.lifecycleState,
    required this.context,
    this.taskRun,
  });

  final String sessionId;
  final String namespaceId;
  final String title;
  final int lastEventSeq;
  final String lifecycleState;
  final Map<String, dynamic> context;
  final CloudTaskRun? taskRun;

  factory CloudSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final rawContext = json['context'];
    return CloudSessionSnapshot(
      sessionId: json['sessionId']?.toString() ?? '',
      namespaceId: json['namespaceId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      lastEventSeq: _intValue(json['lastEventSeq']),
      lifecycleState: json['lifecycleState']?.toString() ?? 'ready',
      context: rawContext is Map
          ? rawContext.map((key, value) => MapEntry(key.toString(), value))
          : const <String, dynamic>{},
      taskRun: json['taskRun'] is Map
          ? CloudTaskRun.fromJson(
              (json['taskRun'] as Map).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'sessionId': sessionId,
    'namespaceId': namespaceId,
    'title': title,
    'lastEventSeq': lastEventSeq,
    'lifecycleState': lifecycleState,
    'context': Map<String, dynamic>.from(context),
    if (taskRun != null) 'taskRun': taskRun!.toJson(),
  };
}

class CloudTaskRun {
  const CloudTaskRun({
    required this.id,
    required this.state,
    required this.bridgeTaskRef,
  });

  final String id;
  final String state;
  final String bridgeTaskRef;

  factory CloudTaskRun.fromJson(Map<String, dynamic> json) => CloudTaskRun(
    id: json['id']?.toString() ?? '',
    state: json['state']?.toString() ?? 'queued',
    bridgeTaskRef: json['bridgeTaskRef']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'state': state,
    'bridgeTaskRef': bridgeTaskRef,
  };
}

class SessionEvent {
  const SessionEvent({required this.seq, required this.type, this.payload});

  final int seq;
  final String type;
  final Map<String, dynamic>? payload;
}

class SessionSyncGap implements Exception {
  const SessionSyncGap(this.expected, this.received);

  final int expected;
  final int received;

  @override
  String toString() =>
      'SessionSyncGap(expected: $expected, received: $received)';
}

class SessionSyncCursor {
  SessionSyncCursor({this.lastSeq = 0});

  int lastSeq;

  bool accept(SessionEvent event) {
    if (event.seq <= lastSeq) {
      return false;
    }
    final expected = lastSeq + 1;
    if (event.seq != expected) {
      throw SessionSyncGap(expected, event.seq);
    }
    lastSeq = event.seq;
    return true;
  }
}

class SessionSyncCoordinator {
  CloudSessionSnapshot? snapshot;
  SessionSyncCursor _cursor = SessionSyncCursor();
  bool needsReplay = false;

  void attach(CloudSessionSnapshot next) {
    snapshot = next;
    _cursor = SessionSyncCursor(lastSeq: next.lastEventSeq);
    needsReplay = false;
  }

  bool accept(SessionEvent event) {
    if (snapshot == null) {
      needsReplay = true;
      return false;
    }
    try {
      final accepted = _cursor.accept(event);
      if (accepted) {
        snapshot = CloudSessionSnapshot(
          sessionId: snapshot!.sessionId,
          namespaceId: snapshot!.namespaceId,
          title: snapshot!.title,
          lastEventSeq: _cursor.lastSeq,
          lifecycleState: snapshot!.lifecycleState,
          context: snapshot!.context,
          taskRun: snapshot!.taskRun,
        );
      }
      return accepted;
    } on SessionSyncGap {
      needsReplay = true;
      return false;
    }
  }

  int get replayFromSeq => _cursor.lastSeq + 1;
}

class NamespaceBinding {
  const NamespaceBinding({
    required this.workspaceId,
    required this.namespaceId,
  });

  final String workspaceId;
  final String namespaceId;

  factory NamespaceBinding.fromWorkspace({
    required String workspaceId,
    required String namespaceId,
  }) {
    final normalizedWorkspaceId = workspaceId.trim();
    final normalizedNamespaceId = namespaceId.trim();
    if (normalizedWorkspaceId.isEmpty || normalizedNamespaceId.isEmpty) {
      throw ArgumentError('workspaceId and namespaceId are required');
    }
    return NamespaceBinding(
      workspaceId: normalizedWorkspaceId,
      namespaceId: normalizedNamespaceId,
    );
  }
}

int _intValue(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
