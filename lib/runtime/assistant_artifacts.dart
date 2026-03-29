import 'runtime_models.dart';

enum AssistantArtifactEntryKind { file, object }

extension AssistantArtifactEntryKindCopy on AssistantArtifactEntryKind {
  static AssistantArtifactEntryKind fromJsonValue(String? value) {
    return AssistantArtifactEntryKind.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AssistantArtifactEntryKind.file,
    );
  }
}

enum AssistantArtifactPreviewKind { markdown, html, text, unsupported, empty }

extension AssistantArtifactPreviewKindCopy on AssistantArtifactPreviewKind {
  static AssistantArtifactPreviewKind fromJsonValue(String? value) {
    return AssistantArtifactPreviewKind.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AssistantArtifactPreviewKind.empty,
    );
  }
}

class AssistantArtifactEntry {
  const AssistantArtifactEntry({
    required this.id,
    required this.label,
    required this.relativePath,
    required this.kind,
    required this.mimeType,
    required this.previewable,
    required this.workspacePath,
    this.sizeBytes,
    this.updatedAtMs,
  });

  final String id;
  final String label;
  final String relativePath;
  final AssistantArtifactEntryKind kind;
  final String mimeType;
  final int? sizeBytes;
  final double? updatedAtMs;
  final bool previewable;
  final String workspacePath;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'relativePath': relativePath,
      'kind': kind.name,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
      'updatedAtMs': updatedAtMs,
      'previewable': previewable,
      'workspacePath': workspacePath,
      'workspaceRef': workspacePath,
    };
  }

  factory AssistantArtifactEntry.fromJson(Map<String, dynamic> json) {
    return AssistantArtifactEntry(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      relativePath: json['relativePath']?.toString() ?? '',
      kind: AssistantArtifactEntryKindCopy.fromJsonValue(
        json['kind']?.toString(),
      ),
      mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
      sizeBytes: switch (json['sizeBytes']) {
        final num value => value.toInt(),
        _ => null,
      },
      updatedAtMs: switch (json['updatedAtMs']) {
        final num value => value.toDouble(),
        _ => null,
      },
      previewable: json['previewable'] as bool? ?? false,
      workspacePath:
          json['workspacePath']?.toString() ??
          json['workspaceRef']?.toString() ??
          '',
    );
  }
}

class AssistantArtifactChangeEntry {
  const AssistantArtifactChangeEntry({
    required this.path,
    required this.changeType,
    required this.displayLabel,
  });

  final String path;
  final String changeType;
  final String displayLabel;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'path': path,
      'changeType': changeType,
      'displayLabel': displayLabel,
    };
  }

  factory AssistantArtifactChangeEntry.fromJson(Map<String, dynamic> json) {
    return AssistantArtifactChangeEntry(
      path: json['path']?.toString() ?? '',
      changeType: json['changeType']?.toString() ?? '',
      displayLabel: json['displayLabel']?.toString() ?? '',
    );
  }
}

class AssistantArtifactPreview {
  const AssistantArtifactPreview({
    required this.kind,
    this.title = '',
    this.content = '',
    this.message = '',
  });

  const AssistantArtifactPreview.empty({String message = ''})
    : this(kind: AssistantArtifactPreviewKind.empty, message: message);

  const AssistantArtifactPreview.unsupported({
    String title = '',
    String message = '',
  }) : this(
         kind: AssistantArtifactPreviewKind.unsupported,
         title: title,
         message: message,
       );

  final AssistantArtifactPreviewKind kind;
  final String title;
  final String content;
  final String message;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'kind': kind.name,
      'title': title,
      'content': content,
      'message': message,
    };
  }

  factory AssistantArtifactPreview.fromJson(Map<String, dynamic> json) {
    return AssistantArtifactPreview(
      kind: AssistantArtifactPreviewKindCopy.fromJsonValue(
        json['kind']?.toString(),
      ),
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
    );
  }
}

class AssistantArtifactSnapshot {
  const AssistantArtifactSnapshot({
    required this.workspacePath,
    required this.workspaceKind,
    this.resultEntries = const <AssistantArtifactEntry>[],
    this.fileEntries = const <AssistantArtifactEntry>[],
    this.changes = const <AssistantArtifactChangeEntry>[],
    this.resultMessage = '',
    this.filesMessage = '',
    this.changesMessage = '',
  });

  final String workspacePath;
  final WorkspaceRefKind workspaceKind;
  final List<AssistantArtifactEntry> resultEntries;
  final List<AssistantArtifactEntry> fileEntries;
  final List<AssistantArtifactChangeEntry> changes;
  final String resultMessage;
  final String filesMessage;
  final String changesMessage;

  bool get hasAnyContent =>
      resultEntries.isNotEmpty || fileEntries.isNotEmpty || changes.isNotEmpty;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'workspacePath': workspacePath,
      'workspaceRef': workspacePath,
      'workspaceKind': workspaceKind.name,
      'workspaceRefKind': workspaceKind.name,
      'resultEntries': resultEntries.map((item) => item.toJson()).toList(),
      'fileEntries': fileEntries.map((item) => item.toJson()).toList(),
      'changes': changes.map((item) => item.toJson()).toList(),
      'resultMessage': resultMessage,
      'filesMessage': filesMessage,
      'changesMessage': changesMessage,
    };
  }

  factory AssistantArtifactSnapshot.fromJson(Map<String, dynamic> json) {
    List<T> decodeList<T>(
      Object? value,
      T Function(Map<String, dynamic>) mapper,
    ) {
      if (value is! List) {
        return <T>[];
      }
      return value
          .whereType<Map>()
          .map((item) => mapper(item.cast<String, dynamic>()))
          .toList(growable: false);
    }

    return AssistantArtifactSnapshot(
      workspacePath:
          json['workspacePath']?.toString() ??
          json['workspaceRef']?.toString() ??
          '',
      workspaceKind: WorkspaceRefKindCopy.fromJsonValue(
        json['workspaceKind']?.toString() ??
            json['workspaceRefKind']?.toString(),
      ),
      resultEntries: decodeList(
        json['resultEntries'],
        AssistantArtifactEntry.fromJson,
      ),
      fileEntries: decodeList(
        json['fileEntries'],
        AssistantArtifactEntry.fromJson,
      ),
      changes: decodeList(
        json['changes'],
        AssistantArtifactChangeEntry.fromJson,
      ),
      resultMessage: json['resultMessage']?.toString() ?? '',
      filesMessage: json['filesMessage']?.toString() ?? '',
      changesMessage: json['changesMessage']?.toString() ?? '',
    );
  }
}
