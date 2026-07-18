import 'dart:io';

import 'assistant_artifacts.dart';
import 'runtime_models.dart';

class DesktopThreadArtifactService {
  static const int defaultResultLimitInternal = 24;
  static const Set<String> ignoredDirectoryNamesInternal = <String>{
    '.git',
    '.dart_tool',
    'build',
    'Pods',
    'DerivedData',
    '.symlinks',
    '.gradle',
    'out',
  };

  Future<AssistantArtifactSnapshot> loadSnapshot({
    required String workspacePath,
    required WorkspaceRefKind workspaceKind,
    List<String> artifactRelativePaths = const <String>[],
  }) async {
    final normalizedRef = workspacePath.trim();
    if (normalizedRef.isEmpty) {
      return AssistantArtifactSnapshot(
        workspacePath: normalizedRef,
        workspaceKind: workspaceKind,
        resultMessage: 'No recorded working directory for this thread.',
        filesMessage: 'No recorded working directory for this thread.',
        changesMessage: 'No recorded working directory for this thread.',
      );
    }
    if (workspaceKind != WorkspaceRefKind.localPath) {
      return AssistantArtifactSnapshot(
        workspacePath: normalizedRef,
        workspaceKind: workspaceKind,
        resultMessage:
            'This thread workspace is recorded on a remote agent and is not browsable from desktop.',
        filesMessage:
            'This thread workspace is recorded on a remote agent and is not browsable from desktop.',
        changesMessage:
            'This thread workspace is recorded on a remote agent and is not browsable from desktop.',
      );
    }
    final root = Directory(normalizedRef);
    if (!await root.exists()) {
      return AssistantArtifactSnapshot(
        workspacePath: normalizedRef,
        workspaceKind: workspaceKind,
        resultMessage:
            'This thread workspace is recorded but is not available on the current machine.',
        filesMessage:
            'This thread workspace is recorded but is not available on the current machine.',
        changesMessage:
            'This thread workspace is recorded but is not available on the current machine.',
      );
    }

    final taskArtifactPaths = normalizeTaskArtifactPathsInternal(
      artifactRelativePaths,
    );
    final taskFiles = taskArtifactPaths.isEmpty
        ? const <File>[]
        : await collectTaskArtifactFilesInternal(
            root,
            normalizedRef,
            taskArtifactPaths,
          );
    final fileEntries = await buildEntriesInternal(taskFiles, normalizedRef);
    final changes = taskArtifactPaths.isEmpty
        ? const <AssistantArtifactChangeEntry>[]
        : await readGitChangesInternal(
            root,
            normalizedRef,
            artifactRelativePaths: taskArtifactPaths,
          );
    final results = await buildResultEntriesInternal(
      changes: changes,
      fileEntries: fileEntries,
      workspacePath: normalizedRef,
    );

    final resultMessage = results.isEmpty
        ? taskArtifactPaths.isEmpty
              ? 'No task artifacts recorded for this run.'
              : 'No current task artifacts found for this run.'
        : '';
    final filesMessage = taskArtifactPaths.isEmpty
        ? ''
        : fileEntries.isEmpty
        ? 'No current task artifact files found in the recorded working directory.'
        : '';
    final changesMessage = changes.isEmpty
        ? 'No Git changes found for the current thread workspace.'
        : '';

    return AssistantArtifactSnapshot(
      workspacePath: normalizedRef,
      workspaceKind: workspaceKind,
      resultEntries: results,
      fileEntries: fileEntries,
      changes: changes,
      resultMessage: resultMessage,
      filesMessage: filesMessage,
      changesMessage: changesMessage,
    );
  }

  Future<AssistantArtifactPreview> loadPreview({
    required AssistantArtifactEntry entry,
    required String workspacePath,
    required WorkspaceRefKind workspaceKind,
    List<String> artifactRelativePaths = const <String>[],
  }) async {
    if (workspaceKind != WorkspaceRefKind.localPath) {
      return const AssistantArtifactPreview.empty(
        message: 'Remote agent artifacts are not directly readable on desktop.',
      );
    }
    final resolvedWorkspacePath = workspacePathForEntryInternal(
      entry,
      fallbackWorkspacePath: workspacePath,
    );
    final root = Directory(resolvedWorkspacePath);
    if (!await root.exists()) {
      return const AssistantArtifactPreview.empty(
        message:
            'The recorded working directory is not available on this machine.',
      );
    }
    final entryRelativePath = normalizeArtifactPathInternal(entry.relativePath);
    if (entryRelativePath.isEmpty) {
      return const AssistantArtifactPreview.empty(
        message:
            'The selected file is not part of the current thread workspace.',
      );
    }
    final taskArtifactPaths = normalizeTaskArtifactPathsInternal(
      artifactRelativePaths,
    );
    final isAllowed = taskArtifactPaths.any(
      (path) =>
          entryRelativePath == path || entryRelativePath.startsWith('$path/'),
    );
    if (taskArtifactPaths.isEmpty || !isAllowed) {
      return const AssistantArtifactPreview.empty(
        message: 'The selected file is not part of the current task artifacts.',
      );
    }
    final targetPath = resolveAbsolutePathInternal(
      resolvedWorkspacePath,
      entryRelativePath,
    );
    final file = File(targetPath);
    if (!await file.exists()) {
      return AssistantArtifactPreview.empty(
        message:
            'The selected file is no longer available: ${entry.relativePath}',
      );
    }
    final resolvedRelativePath = relativePathInternal(
      resolvedWorkspacePath,
      file.path,
    );
    if (resolvedRelativePath == null ||
        resolvedRelativePath != entryRelativePath) {
      return const AssistantArtifactPreview.empty(
        message:
            'The selected file is not part of the current thread workspace.',
      );
    }

    final extension = fileExtensionInternal(entryRelativePath);
    final content = await file.readAsString();
    final title = entry.label;
    if (extension == 'md' || extension == 'markdown') {
      return AssistantArtifactPreview(
        kind: AssistantArtifactPreviewKind.markdown,
        title: title,
        content: content,
      );
    }
    if (extension == 'html' || extension == 'htm') {
      return AssistantArtifactPreview(
        kind: AssistantArtifactPreviewKind.html,
        title: title,
        content: sanitizeHtmlInternal(content),
      );
    }
    if (isPlainTextExtensionInternal(extension)) {
      return AssistantArtifactPreview(
        kind: AssistantArtifactPreviewKind.text,
        title: title,
        content: content,
      );
    }
    return AssistantArtifactPreview.unsupported(
      title: title,
      message: 'Preview is not available for this file type.',
    );
  }

  /// Resolves a current-task artifact to a local file without reading it as
  /// text. Mobile and desktop share/export flows use this for binary media.
  Future<File?> loadFile({
    required AssistantArtifactEntry entry,
    required String workspacePath,
    required WorkspaceRefKind workspaceKind,
    List<String> artifactRelativePaths = const <String>[],
  }) async {
    if (workspaceKind != WorkspaceRefKind.localPath) {
      return null;
    }
    final normalizedWorkspacePath = workspacePathForEntryInternal(
      entry,
      fallbackWorkspacePath: workspacePath,
    );
    final root = Directory(normalizedWorkspacePath);
    if (normalizedWorkspacePath.isEmpty || !await root.exists()) {
      return null;
    }
    final entryRelativePath = normalizeArtifactPathInternal(entry.relativePath);
    if (entryRelativePath.isEmpty) {
      return null;
    }
    final taskArtifactPaths = normalizeTaskArtifactPathsInternal(
      artifactRelativePaths,
    );
    final isAllowed = taskArtifactPaths.any(
      (path) =>
          entryRelativePath == path || entryRelativePath.startsWith('$path/'),
    );
    if (!isAllowed) {
      return null;
    }
    final targetPath = resolveAbsolutePathInternal(
      normalizedWorkspacePath,
      entryRelativePath,
    );
    final file = File(targetPath);
    if (!await file.exists()) {
      return null;
    }
    final resolvedRelativePath = relativePathInternal(
      normalizedWorkspacePath,
      file.path,
    );
    if (resolvedRelativePath != entryRelativePath) {
      return null;
    }
    return file;
  }

  static String workspacePathForEntryInternal(
    AssistantArtifactEntry entry, {
    required String fallbackWorkspacePath,
  }) {
    final entryWorkspacePath = entry.workspacePath.trim();
    final isAbsolute =
        entryWorkspacePath.startsWith('/') ||
        entryWorkspacePath.startsWith(r'\') ||
        entryWorkspacePath.contains(r':\');
    if (entryWorkspacePath.isNotEmpty &&
        isAbsolute &&
        !entryWorkspacePath.startsWith('/owners/')) {
      return entryWorkspacePath;
    }
    return fallbackWorkspacePath.trim();
  }

  Future<List<File>> collectFilesInternal(Directory root) async {
    final files = <File>[];
    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is Directory) {
          if (ignoredDirectoryNamesInternal.contains(
            baseNameInternal(entity.path),
          )) {
            continue;
          }
          files.addAll(await collectFilesInternal(entity));
          continue;
        }
        if (entity is File) {
          files.add(entity);
        }
      }
    } on FileSystemException {
      // Best effort only. A single unreadable directory should not block the panel.
    }
    return files;
  }

  Future<List<File>> collectTaskArtifactFilesInternal(
    Directory root,
    String workspacePath,
    List<String> artifactRelativePaths,
  ) async {
    final files = <File>[];
    for (final relativePath in artifactRelativePaths) {
      final absolutePath = resolveAbsolutePathInternal(root.path, relativePath);
      try {
        final type = await FileSystemEntity.type(
          absolutePath,
          followLinks: true,
        );
        if (type == FileSystemEntityType.file) {
          final target = File(absolutePath);
          final resolvedRelativePath = relativePathInternal(
            workspacePath,
            target.path,
          );
          if (resolvedRelativePath == null || resolvedRelativePath.isEmpty) {
            continue;
          }
          files.add(target);
        } else if (type == FileSystemEntityType.directory) {
          final collected = await collectFilesInternal(Directory(absolutePath));
          for (final file in collected) {
            final resolvedRelativePath = relativePathInternal(
              workspacePath,
              file.path,
            );
            if (resolvedRelativePath == null || resolvedRelativePath.isEmpty) {
              continue;
            }
            files.add(file);
          }
        }
      } on FileSystemException {
        continue;
      }
    }
    return files;
  }

  Future<List<AssistantArtifactEntry>> buildEntriesInternal(
    List<File> files,
    String workspacePath,
  ) async {
    final entries = <AssistantArtifactEntry>[];
    for (final file in files) {
      try {
        final stat = await file.stat();
        final relativePath =
            relativePathInternal(workspacePath, file.path) ?? file.path;
        final extension = fileExtensionInternal(relativePath);
        entries.add(
          AssistantArtifactEntry(
            id: '$workspacePath::$relativePath',
            label: baseNameInternal(relativePath),
            relativePath: relativePath,
            kind: AssistantArtifactEntryKind.file,
            mimeType: guessMimeTypeInternal(relativePath),
            sizeBytes: stat.size,
            updatedAtMs: stat.modified.millisecondsSinceEpoch.toDouble(),
            previewable: isPreviewableExtensionInternal(extension),
            workspacePath: workspacePath,
          ),
        );
      } on FileSystemException {
        // Ignore files that cannot be stat'ed.
      }
    }
    entries.sort((a, b) {
      final deliveryCompare = artifactDisplayPriorityInternal(
        a.relativePath,
      ).compareTo(artifactDisplayPriorityInternal(b.relativePath));
      if (deliveryCompare != 0) {
        return deliveryCompare;
      }
      if (fileExtensionInternal(a.relativePath) == 'pdf') {
        final depthCompare = artifactPathDepthInternal(
          a.relativePath,
        ).compareTo(artifactPathDepthInternal(b.relativePath));
        if (depthCompare != 0) {
          return depthCompare;
        }
      }
      final updatedCompare = (b.updatedAtMs ?? 0).compareTo(a.updatedAtMs ?? 0);
      if (updatedCompare != 0) {
        return updatedCompare;
      }
      return a.relativePath.compareTo(b.relativePath);
    });
    return entries;
  }

  static int artifactDisplayPriorityInternal(String relativePath) {
    return fileExtensionInternal(relativePath) == 'pdf' ? 0 : 1;
  }

  static int artifactPathDepthInternal(String relativePath) {
    return normalizeArtifactPathInternal(
      relativePath,
    ).split('/').where((segment) => segment.isNotEmpty).length;
  }

  Future<List<AssistantArtifactEntry>> buildResultEntriesInternal({
    required List<AssistantArtifactChangeEntry> changes,
    required List<AssistantArtifactEntry> fileEntries,
    required String workspacePath,
  }) async {
    final filesByPath = <String, AssistantArtifactEntry>{
      for (final entry in fileEntries) entry.relativePath: entry,
    };
    final results = <AssistantArtifactEntry>[];
    for (final change in changes) {
      final entry = filesByPath[change.path];
      if (entry != null) {
        results.add(entry);
      }
    }
    if (results.isNotEmpty) {
      return results;
    }
    return fileEntries.take(defaultResultLimitInternal).toList(growable: false);
  }

  Future<List<AssistantArtifactChangeEntry>> readGitChangesInternal(
    Directory workspaceRoot,
    String workspacePath, {
    List<String> artifactRelativePaths = const <String>[],
  }) async {
    final allowedPaths = normalizeTaskArtifactPathsInternal(
      artifactRelativePaths,
    ).toSet();
    String? repositoryRoot;
    try {
      final revParse = await Process.run('git', <String>[
        '-C',
        workspaceRoot.path,
        'rev-parse',
        '--show-toplevel',
      ]);
      if (revParse.exitCode != 0) {
        return const <AssistantArtifactChangeEntry>[];
      }
      repositoryRoot = revParse.stdout.toString().trim();
      if (repositoryRoot.isEmpty) {
        return const <AssistantArtifactChangeEntry>[];
      }
      final status = await Process.run('git', <String>[
        '-C',
        repositoryRoot,
        'status',
        '--short',
        '--untracked-files=all',
      ]);
      if (status.exitCode != 0) {
        return const <AssistantArtifactChangeEntry>[];
      }
      final items = <AssistantArtifactChangeEntry>[];
      final lines = status.stdout
          .toString()
          .split('\n')
          .map((item) => item.trimRight())
          .where((item) => item.isNotEmpty);
      for (final line in lines) {
        if (line.length < 3) {
          continue;
        }
        final statusCode = line.substring(0, 2).trim();
        final rawPath = line.substring(3).trim();
        final path = rawPath.contains(' -> ')
            ? rawPath.split(' -> ').last.trim()
            : rawPath;
        final absolutePath = joinPathInternal(repositoryRoot, path);
        final relativePath = relativePathInternal(workspacePath, absolutePath);
        if (relativePath == null || relativePath.isEmpty) {
          continue;
        }
        final isAllowed =
            allowedPaths.isEmpty ||
            allowedPaths.any(
              (path) =>
                  relativePath == path || relativePath.startsWith('$path/'),
            );
        if (!isAllowed) {
          continue;
        }
        items.add(
          AssistantArtifactChangeEntry(
            path: relativePath,
            changeType: statusCode,
            displayLabel: statusLabelForInternal(statusCode),
          ),
        );
      }
      return items;
    } on ProcessException {
      return const <AssistantArtifactChangeEntry>[];
    }
  }

  static String resolveAbsolutePathInternal(String root, String relativePath) {
    if (relativePath.startsWith('/') ||
        relativePath.startsWith('\\') ||
        relativePath.contains(':\\')) {
      return relativePath;
    }
    return joinPathInternal(root, relativePath);
  }

  static String sanitizeHtmlInternal(String value) {
    final withoutBlockedTags = value
        .replaceAll(
          RegExp(
            r'<(script|iframe|object|embed|link|meta|base)[^>]*>[\s\S]*?<\/\1>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'<(script|iframe|object|embed|link|meta|base)[^>]*\/?>',
            caseSensitive: false,
          ),
          '',
        );
    final withoutEventHandlers = withoutBlockedTags.replaceAll(
      RegExp(r'''\son\w+\s*=\s*(".*?"|'.*?'|[^\s>]+)''', caseSensitive: false),
      '',
    );
    return withoutEventHandlers.replaceAllMapped(
      RegExp(
        r'''\s(href|src)\s*=\s*(".*?"|'.*?'|[^\s>]+)''',
        caseSensitive: false,
      ),
      (match) {
        final quoteWrapped = match.group(2) ?? '';
        final raw = quoteWrapped
            .replaceAll('"', '')
            .replaceAll('\'', '')
            .trim();
        final lower = raw.toLowerCase();
        if (lower.startsWith('javascript:') ||
            lower.startsWith('http://') ||
            lower.startsWith('https://') ||
            lower.startsWith('//')) {
          return ' ${match.group(1)}="#"';
        }
        return match.group(0) ?? '';
      },
    );
  }

  static String joinPathInternal(String root, String child) {
    final separator = Platform.pathSeparator;
    final normalizedRoot = root.endsWith(separator) ? root : '$root$separator';
    final normalizedChild = child.startsWith(separator)
        ? child.substring(1)
        : child;
    return '$normalizedRoot$normalizedChild';
  }

  static String? relativePathInternal(String root, String absolutePath) {
    final normalizedRoot = normalizePathInternal(root);
    final normalizedPath = normalizePathInternal(absolutePath);
    if (normalizedRoot == normalizedPath) {
      return '';
    }
    final prefix = normalizedRoot.endsWith('/')
        ? normalizedRoot
        : '$normalizedRoot/';
    if (!normalizedPath.startsWith(prefix)) {
      return null;
    }
    return normalizedPath.substring(prefix.length);
  }

  static List<String> normalizeTaskArtifactPathsInternal(
    List<String> relativePaths,
  ) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final relativePath in relativePaths) {
      final item = normalizeArtifactPathInternal(relativePath);
      if (item.isEmpty || !seen.add(item)) {
        continue;
      }
      normalized.add(item);
    }
    return normalized;
  }

  static String normalizeArtifactPathInternal(String relativePath) {
    final trimmed = relativePath.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty ||
        trimmed.startsWith('/') ||
        trimmed.startsWith('~') ||
        trimmed.contains(':')) {
      return '';
    }
    final segments = trimmed
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList(growable: false);
    if (segments.isEmpty || segments.any((segment) => segment == '..')) {
      return '';
    }
    return segments.join('/');
  }

  static String normalizePathInternal(String path) {
    try {
      final type = FileSystemEntity.typeSync(path, followLinks: true);
      final resolved = switch (type) {
        FileSystemEntityType.directory => Directory(
          path,
        ).resolveSymbolicLinksSync(),
        FileSystemEntityType.file ||
        FileSystemEntityType.link => File(path).resolveSymbolicLinksSync(),
        FileSystemEntityType.notFound => File(path).absolute.path,
        _ => File(path).absolute.path,
      };
      return resolved.replaceAll('\\', '/');
    } on FileSystemException {
      return File(path).absolute.path.replaceAll('\\', '/');
    }
  }

  static String baseNameInternal(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? normalized : parts.last;
  }

  static String fileExtensionInternal(String path) {
    final name = baseNameInternal(path);
    final index = name.lastIndexOf('.');
    if (index <= 0 || index >= name.length - 1) {
      return '';
    }
    return name.substring(index + 1).toLowerCase();
  }

  static String guessMimeTypeInternal(String path) {
    final extension = fileExtensionInternal(path);
    return switch (extension) {
      'md' || 'markdown' => 'text/markdown',
      'html' || 'htm' => 'text/html',
      'txt' || 'log' => 'text/plain',
      'json' => 'application/json',
      'yaml' || 'yml' => 'application/yaml',
      'csv' => 'text/csv',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'wav' => 'audio/wav',
      'aac' => 'audio/aac',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'zip' => 'application/zip',
      'dart' => 'text/x-dart',
      'js' => 'text/javascript',
      'ts' => 'text/typescript',
      'css' => 'text/css',
      'xml' => 'application/xml',
      _ => 'application/octet-stream',
    };
  }

  static bool isPreviewableExtensionInternal(String extension) {
    return extension == 'md' ||
        extension == 'markdown' ||
        extension == 'html' ||
        extension == 'htm' ||
        isPlainTextExtensionInternal(extension);
  }

  static bool isPlainTextExtensionInternal(String extension) {
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

  static String statusLabelForInternal(String code) {
    if (code == '??') {
      return 'Untracked';
    }
    if (code.contains('A')) {
      return 'Added';
    }
    if (code.contains('M')) {
      return 'Modified';
    }
    if (code.contains('D')) {
      return 'Deleted';
    }
    if (code.contains('R')) {
      return 'Renamed';
    }
    if (code.contains('C')) {
      return 'Copied';
    }
    if (code.contains('U')) {
      return 'Updated';
    }
    return code.isEmpty ? 'Changed' : code;
  }
}
