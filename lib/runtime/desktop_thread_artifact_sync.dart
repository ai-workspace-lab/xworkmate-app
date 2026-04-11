import 'dart:convert';
import 'dart:io';

import 'go_task_service_client.dart';

class DesktopThreadArtifactSyncResult {
  const DesktopThreadArtifactSyncResult({
    required this.wroteArtifact,
    required this.writtenFiles,
  });

  final bool wroteArtifact;
  final List<String> writtenFiles;
}

Future<DesktopThreadArtifactSyncResult> syncInlineArtifactsToLocalWorkspace({
  required Directory root,
  required List<GoTaskServiceArtifact> artifacts,
}) async {
  await root.create(recursive: true);
  final writtenFiles = <String>[];
  for (final artifact in artifacts) {
    if (!artifact.hasInlineContent) {
      continue;
    }
    final relativePath = sanitizeArtifactRelativePath(artifact.relativePath);
    if (relativePath.isEmpty) {
      continue;
    }
    final target = await nextArtifactTargetFile(root, relativePath);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(decodeArtifactContent(artifact), flush: true);
    writtenFiles.add(target.path);
  }
  return DesktopThreadArtifactSyncResult(
    wroteArtifact: writtenFiles.isNotEmpty,
    writtenFiles: List<String>.unmodifiable(writtenFiles),
  );
}

String sanitizeArtifactRelativePath(String raw) {
  final trimmed = raw.trim().replaceAll('\\', '/');
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed
      .split('/')
      .where(
        (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
      )
      .join('/');
}

List<int> decodeArtifactContent(GoTaskServiceArtifact artifact) {
  final encoding = artifact.encoding.trim().toLowerCase();
  if (encoding == 'base64') {
    return base64Decode(artifact.content);
  }
  return utf8.encode(artifact.content);
}

Future<File> nextArtifactTargetFile(Directory root, String relativePath) async {
  final segments = relativePath.split('/');
  final fileName = segments.removeLast();
  final parent = segments.isEmpty
      ? root
      : Directory('${root.path}/${segments.join('/')}');
  final dotIndex = fileName.lastIndexOf('.');
  final baseName = dotIndex <= 0 ? fileName : fileName.substring(0, dotIndex);
  final extension = dotIndex <= 0 ? '' : fileName.substring(dotIndex);
  var candidate = File('${parent.path}/$fileName');
  if (!await candidate.exists()) {
    return candidate;
  }
  for (var version = 2; version < 1000; version += 1) {
    candidate = File('${parent.path}/$baseName.v$version$extension');
    if (!await candidate.exists()) {
      return candidate;
    }
  }
  return File(
    '${parent.path}/$baseName.${DateTime.now().millisecondsSinceEpoch}$extension',
  );
}
