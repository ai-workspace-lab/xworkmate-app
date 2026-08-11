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
    required this.snapshotVersion,
    required this.lastEventSeq,
    required this.lifecycleState,
    required this.context,
    this.taskRun,
  });

  final String sessionId;
  final String namespaceId;
  final String title;
  final int snapshotVersion;
  final int lastEventSeq;
  final String lifecycleState;
  final Map<String, dynamic> context;
  final CloudTaskRun? taskRun;

  factory CloudSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final rawContext = json['context'];
    return CloudSessionSnapshot(
      sessionId: _requiredString(json, 'sessionId'),
      namespaceId: _requiredString(json, 'namespaceId'),
      title: json['title']?.toString() ?? '',
      snapshotVersion: _requiredNonNegativeInt(json, 'snapshotVersion'),
      lastEventSeq: _requiredNonNegativeInt(json, 'lastEventSeq'),
      lifecycleState: _requiredString(json, 'lifecycleState'),
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
    'snapshotVersion': snapshotVersion,
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
    id: _requiredString(json, 'id'),
    state: _requiredString(json, 'state'),
    bridgeTaskRef: json['bridgeTaskRef']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'state': state,
    'bridgeTaskRef': bridgeTaskRef,
  };
}

class SessionEvent {
  const SessionEvent({
    required this.seq,
    required this.type,
    this.payload,
    this.createdAt,
  });

  final int seq;
  final String type;
  final Map<String, dynamic>? payload;
  final DateTime? createdAt;

  factory SessionEvent.fromJson(Map<String, dynamic> json) {
    final seq = _requiredPositiveInt(json, 'seq');
    final type = _requiredString(json, 'type');
    final rawPayload = json['payload'];
    if (rawPayload is! Map) {
      throw const FormatException('SessionEvent.payload must be an object.');
    }
    final rawCreatedAt = _requiredString(json, 'createdAt');
    final createdAt = DateTime.tryParse(rawCreatedAt);
    if (createdAt == null) {
      throw const FormatException('SessionEvent.createdAt must be RFC3339.');
    }
    return SessionEvent(
      seq: seq,
      type: type,
      payload: rawPayload.map((key, value) => MapEntry(key.toString(), value)),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'seq': seq,
    'type': type,
    'payload': Map<String, dynamic>.from(payload ?? const <String, dynamic>{}),
    if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
  };
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
          snapshotVersion: snapshot!.snapshotVersion,
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

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw FormatException('$key is required.');
  }
  return value;
}

int _requiredPositiveInt(Map<String, dynamic> json, String key) {
  final value = _requiredNonNegativeInt(json, key);
  if (value == 0) {
    throw FormatException('$key must be a positive integer.');
  }
  return value;
}

int _requiredNonNegativeInt(Map<String, dynamic> json, String key) {
  final raw = json[key];
  final value = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  if (value == null || value < 0) {
    throw FormatException('$key must be a non-negative integer.');
  }
  return value;
}
