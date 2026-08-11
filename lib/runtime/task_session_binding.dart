import 'dart:convert';
import 'dart:io';

import 'file_store_support.dart';

/// Durable local identity link between the existing TaskThread key and the
/// Bridge-hosted cloud session. No message, artifact, credential, or endpoint
/// data belongs in this record.
class TaskSessionBinding {
  TaskSessionBinding({
    required String taskThreadKey,
    required String cloudSessionId,
    required String namespaceId,
    required this.lastEventSeq,
    required this.snapshotVersion,
  }) : taskThreadKey = _required(taskThreadKey, 'taskThreadKey'),
       cloudSessionId = _required(cloudSessionId, 'cloudSessionId'),
       namespaceId = _required(namespaceId, 'namespaceId') {
    if (lastEventSeq < 0) {
      throw ArgumentError.value(
        lastEventSeq,
        'lastEventSeq',
        'must be non-negative',
      );
    }
    if (snapshotVersion < 0) {
      throw ArgumentError.value(
        snapshotVersion,
        'snapshotVersion',
        'must be non-negative',
      );
    }
  }

  final String taskThreadKey;
  final String cloudSessionId;
  final String namespaceId;
  final int lastEventSeq;
  final int snapshotVersion;

  TaskSessionBinding copyWith({int? lastEventSeq, int? snapshotVersion}) =>
      TaskSessionBinding(
        taskThreadKey: taskThreadKey,
        cloudSessionId: cloudSessionId,
        namespaceId: namespaceId,
        lastEventSeq: lastEventSeq ?? this.lastEventSeq,
        snapshotVersion: snapshotVersion ?? this.snapshotVersion,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'taskThreadKey': taskThreadKey,
    'cloudSessionId': cloudSessionId,
    'namespaceId': namespaceId,
    'lastEventSeq': lastEventSeq,
    'snapshotVersion': snapshotVersion,
  };

  factory TaskSessionBinding.fromJson(Map<String, dynamic> json) {
    return TaskSessionBinding(
      taskThreadKey: _requiredJsonString(json, 'taskThreadKey'),
      cloudSessionId: _requiredJsonString(json, 'cloudSessionId'),
      namespaceId: _requiredJsonString(json, 'namespaceId'),
      lastEventSeq: _requiredJsonInt(json, 'lastEventSeq'),
      snapshotVersion: _requiredJsonInt(json, 'snapshotVersion'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TaskSessionBinding &&
      other.taskThreadKey == taskThreadKey &&
      other.cloudSessionId == cloudSessionId &&
      other.namespaceId == namespaceId &&
      other.lastEventSeq == lastEventSeq &&
      other.snapshotVersion == snapshotVersion;

  @override
  int get hashCode => Object.hash(
    taskThreadKey,
    cloudSessionId,
    namespaceId,
    lastEventSeq,
    snapshotVersion,
  );
}

abstract interface class TaskSessionBindingStore {
  Future<TaskSessionBinding?> load(String taskThreadKey);

  Future<void> save(TaskSessionBinding binding);

  Future<void> remove(String taskThreadKey);
}

class MemoryTaskSessionBindingStore implements TaskSessionBindingStore {
  final Map<String, TaskSessionBinding> _bindings =
      <String, TaskSessionBinding>{};

  @override
  Future<TaskSessionBinding?> load(String taskThreadKey) async {
    return _bindings[_required(taskThreadKey, 'taskThreadKey')];
  }

  @override
  Future<void> save(TaskSessionBinding binding) async {
    _bindings[binding.taskThreadKey] = binding;
  }

  @override
  Future<void> remove(String taskThreadKey) async {
    _bindings.remove(_required(taskThreadKey, 'taskThreadKey'));
  }
}

/// Desktop persistence for cloud bindings, kept separate from TaskThread JSON
/// so the existing UI model and thread store schema remain unchanged.
class FileTaskSessionBindingStore implements TaskSessionBindingStore {
  FileTaskSessionBindingStore({required StoreLayoutResolver layoutResolver})
    : _layoutResolver = layoutResolver;

  final StoreLayoutResolver _layoutResolver;

  @override
  Future<TaskSessionBinding?> load(String taskThreadKey) async {
    final normalizedKey = _required(taskThreadKey, 'taskThreadKey');
    final file = await _fileFor(normalizedKey);
    if (!await file.exists()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException(
        'Task session binding must be a JSON object.',
      );
    }
    final binding = TaskSessionBinding.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
    if (binding.taskThreadKey != normalizedKey) {
      throw const FormatException(
        'Task session binding key does not match its local file key.',
      );
    }
    return binding;
  }

  @override
  Future<void> save(TaskSessionBinding binding) async {
    await atomicWriteString(
      await _fileFor(binding.taskThreadKey),
      jsonEncode(binding.toJson()),
    );
  }

  @override
  Future<void> remove(String taskThreadKey) async {
    await deleteIfExists(
      await _fileFor(_required(taskThreadKey, 'taskThreadKey')),
    );
  }

  Future<File> _fileFor(String taskThreadKey) async {
    final layout = await _layoutResolver.resolve();
    return File(
      '${layout.tasksDirectory.path}/session-bindings/'
      '${encodeStableFileKey(taskThreadKey)}.json',
    );
  }
}

String _required(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'is required');
  }
  return normalized;
}

String _requiredJsonString(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw FormatException('$key is required.');
  }
  return value;
}

int _requiredJsonInt(Map<String, dynamic> json, String key) {
  final raw = json[key];
  final value = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  if (value == null || value < 0) {
    throw FormatException('$key must be a non-negative integer.');
  }
  return value;
}
