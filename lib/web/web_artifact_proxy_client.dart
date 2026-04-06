import '../runtime/assistant_artifacts.dart';
import '../runtime/runtime_models.dart';
import 'web_relay_gateway_client.dart';

class WebArtifactProxyClient {
  const WebArtifactProxyClient(this._relayClient);

  final WebRelayGatewayClient _relayClient;

  Future<AssistantArtifactSnapshot> loadSnapshot({
    required String sessionKey,
    required String workspacePath,
    required WorkspaceRefKind workspaceKind,
  }) async {
    if (workspacePath.trim().isEmpty) {
      return AssistantArtifactSnapshot(
        workspacePath: workspacePath,
        workspaceKind: workspaceKind,
        resultMessage: 'No recorded workspace for this thread.',
        filesMessage: 'No recorded workspace for this thread.',
        changesMessage: 'No recorded workspace for this thread.',
      );
    }
    try {
      final responses = await Future.wait<Map<String, dynamic>>(
        <Future<Map<String, dynamic>>>[
          _requestPayload(
            'artifacts.list',
            params: <String, dynamic>{
              'sessionKey': sessionKey,
              'workspacePath': workspacePath,
            },
          ),
          _requestPayload(
            'artifacts.files',
            params: <String, dynamic>{
              'sessionKey': sessionKey,
              'workspacePath': workspacePath,
            },
          ),
          _requestPayload(
            'artifacts.changes',
            params: <String, dynamic>{
              'sessionKey': sessionKey,
              'workspacePath': workspacePath,
            },
          ),
        ],
      );
      final resultPayload = responses[0];
      final filesPayload = responses[1];
      final changesPayload = responses[2];
      return AssistantArtifactSnapshot(
        workspacePath: workspacePath,
        workspaceKind: workspaceKind,
        resultEntries: _decodeEntries(
          resultPayload['entries'] ??
              resultPayload['items'] ??
              resultPayload['files'],
          workspacePath: workspacePath,
        ),
        fileEntries: _decodeEntries(
          filesPayload['entries'] ??
              filesPayload['items'] ??
              filesPayload['files'],
          workspacePath: workspacePath,
        ),
        changes: _decodeChanges(
          changesPayload['changes'] ?? changesPayload['items'],
        ),
        resultMessage:
            resultPayload['message']?.toString() ??
            'No artifacts returned by the relay for this thread.',
        filesMessage:
            filesPayload['message']?.toString() ??
            'No file index returned by the relay for this thread.',
        changesMessage:
            changesPayload['message']?.toString() ??
            'No change index returned by the relay for this thread.',
      );
    } on WebRelayGatewayException catch (error) {
      return AssistantArtifactSnapshot(
        workspacePath: workspacePath,
        workspaceKind: workspaceKind,
        resultMessage: _messageFor(error),
        filesMessage: _messageFor(error),
        changesMessage: _messageFor(error),
      );
    }
  }

  Future<AssistantArtifactPreview> loadPreview({
    required String sessionKey,
    required AssistantArtifactEntry entry,
  }) async {
    try {
      final previewPayload = await _requestPayload(
        'artifacts.preview',
        params: <String, dynamic>{
          'sessionKey': sessionKey,
          'workspacePath': entry.workspacePath,
          'path': entry.relativePath,
        },
      );
      if (previewPayload.isNotEmpty) {
        return AssistantArtifactPreview.fromJson(<String, dynamic>{
          'kind': previewPayload['kind'],
          'title': previewPayload['title']?.toString().trim().isNotEmpty == true
              ? previewPayload['title']
              : entry.label,
          'content': previewPayload['content'],
          'message': previewPayload['message'],
        });
      }
    } on WebRelayGatewayException catch (_) {
      // Fall through to read-based fallback.
    }

    try {
      final readPayload = await _requestPayload(
        'artifacts.read',
        params: <String, dynamic>{
          'sessionKey': sessionKey,
          'workspacePath': entry.workspacePath,
          'path': entry.relativePath,
        },
      );
      final content = readPayload['content']?.toString() ?? '';
      if (content.isEmpty) {
        return AssistantArtifactPreview.empty(
          message:
              readPayload['message']?.toString() ??
              'The relay returned an empty artifact payload.',
        );
      }
      final extension = _extensionFor(entry.relativePath);
      if (extension == 'md' || extension == 'markdown') {
        return AssistantArtifactPreview(
          kind: AssistantArtifactPreviewKind.markdown,
          title: entry.label,
          content: content,
        );
      }
      if (extension == 'html' || extension == 'htm') {
        return AssistantArtifactPreview(
          kind: AssistantArtifactPreviewKind.html,
          title: entry.label,
          content: content,
        );
      }
      if (_isPlainTextExtension(extension)) {
        return AssistantArtifactPreview(
          kind: AssistantArtifactPreviewKind.text,
          title: entry.label,
          content: content,
        );
      }
    } on WebRelayGatewayException catch (error) {
      return AssistantArtifactPreview.empty(message: _messageFor(error));
    }

    return AssistantArtifactPreview.unsupported(
      title: entry.label,
      message: 'Preview is not available for this artifact type.',
    );
  }

  Future<Map<String, dynamic>> _requestPayload(
    String method, {
    required Map<String, dynamic> params,
  }) async {
    final payload = await _relayClient.request(method, params: params);
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    if (payload is Map) {
      return payload.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  static List<AssistantArtifactEntry> _decodeEntries(
    Object? value, {
    required String workspacePath,
  }) {
    if (value is! List) {
      return const <AssistantArtifactEntry>[];
    }
    return value
        .whereType<Map>()
        .map((item) {
          final json = item.cast<String, dynamic>();
          final relativePath =
              json['relativePath']?.toString() ??
              json['path']?.toString() ??
              '';
          return AssistantArtifactEntry.fromJson(<String, dynamic>{
            'id': json['id']?.toString().trim().isNotEmpty == true
                ? json['id']
                : '$workspacePath::$relativePath',
            'label': json['label']?.toString().trim().isNotEmpty == true
                ? json['label']
                : _baseName(relativePath),
            'relativePath': relativePath,
            'kind': json['kind']?.toString() ?? 'object',
            'mimeType':
                json['mimeType']?.toString() ?? 'application/octet-stream',
            'sizeBytes': json['sizeBytes'] ?? json['size'],
            'updatedAtMs':
                json['updatedAtMs'] ?? json['updatedAt'] ?? json['modifiedAt'],
            'previewable':
                json['previewable'] as bool? ??
                _isPreviewableExtension(_extensionFor(relativePath)),
            'workspacePath':
                json['workspacePath']?.toString().trim().isNotEmpty == true
                ? json['workspacePath']
                : (json['workspaceRef']?.toString().trim().isNotEmpty == true
                      ? json['workspaceRef']
                      : workspacePath),
          });
        })
        .where((item) => item.relativePath.trim().isNotEmpty)
        .toList(growable: false);
  }

  static List<AssistantArtifactChangeEntry> _decodeChanges(Object? value) {
    if (value is! List) {
      return const <AssistantArtifactChangeEntry>[];
    }
    return value
        .whereType<Map>()
        .map((item) {
          final json = item.cast<String, dynamic>();
          final path =
              json['path']?.toString() ??
              json['relativePath']?.toString() ??
              '';
          final changeType =
              json['changeType']?.toString() ??
              json['status']?.toString() ??
              '';
          return AssistantArtifactChangeEntry.fromJson(<String, dynamic>{
            'path': path,
            'changeType': changeType,
            'displayLabel':
                json['displayLabel']?.toString() ??
                json['label']?.toString() ??
                changeType,
          });
        })
        .where((item) => item.path.trim().isNotEmpty)
        .toList(growable: false);
  }

  static String _messageFor(WebRelayGatewayException error) {
    final lower = error.message.toLowerCase();
    if (lower.contains('not connected')) {
      return 'Connect the relay to browse thread artifacts.';
    }
    return 'Artifact browsing is not available from the current relay: ${error.message}';
  }

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? normalized : parts.last;
  }

  static String _extensionFor(String path) {
    final baseName = _baseName(path);
    final index = baseName.lastIndexOf('.');
    if (index <= 0 || index >= baseName.length - 1) {
      return '';
    }
    return baseName.substring(index + 1).toLowerCase();
  }

  static bool _isPreviewableExtension(String extension) {
    return extension == 'md' ||
        extension == 'markdown' ||
        extension == 'html' ||
        extension == 'htm' ||
        _isPlainTextExtension(extension);
  }

  static bool _isPlainTextExtension(String extension) {
    return <String>{
      'txt',
      'log',
      'json',
      'yaml',
      'yml',
      'csv',
      'dart',
      'js',
      'ts',
      'css',
      'xml',
      'sh',
    }.contains(extension);
  }
}
