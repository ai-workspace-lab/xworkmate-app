import 'dart:io';

import 'assistant_artifacts.dart';
import 'runtime_models.dart';

class DesktopThreadArtifactService {
  static const int _defaultResultLimit = 24;
  static const Set<String> _ignoredDirectoryNames = <String>{
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
    required String workspaceRef,
    required WorkspaceRefKind workspaceRefKind,
  }) async {
    final normalizedRef = workspaceRef.trim();
    if (normalizedRef.isEmpty) {
      return AssistantArtifactSnapshot(
        workspaceRef: normalizedRef,
        workspaceRefKind: workspaceRefKind,
        resultMessage: 'No recorded working directory for this thread.',
        filesMessage: 'No recorded working directory for this thread.',
        changesMessage: 'No recorded working directory for this thread.',
      );
    }
    if (workspaceRefKind == WorkspaceRefKind.objectStore) {
      return AssistantArtifactSnapshot(
        workspaceRef: normalizedRef,
        workspaceRefKind: workspaceRefKind,
        resultMessage:
            'This thread workspace is recorded as object storage and is not browsable from desktop.',
        filesMessage:
            'This thread workspace is recorded as object storage and is not browsable from desktop.',
        changesMessage:
            'This thread workspace is recorded as object storage and is not browsable from desktop.',
      );
    }
    final root = Directory(normalizedRef);
    if (!await root.exists()) {
      return AssistantArtifactSnapshot(
        workspaceRef: normalizedRef,
        workspaceRefKind: workspaceRefKind,
        resultMessage:
            'This thread workspace is recorded but is not available on the current machine.',
        filesMessage:
            'This thread workspace is recorded but is not available on the current machine.',
        changesMessage:
            'This thread workspace is recorded but is not available on the current machine.',
      );
    }

    final files = await _collectFiles(root);
    final fileEntries = await _buildEntries(files, normalizedRef);
    final changes = await _readGitChanges(root, normalizedRef);
    final results = await _buildResultEntries(
      changes: changes,
      fileEntries: fileEntries,
      workspaceRef: normalizedRef,
    );

    final resultMessage = results.isEmpty
        ? fileEntries.isEmpty
              ? 'No files found in the recorded working directory.'
              : 'No changed artifacts detected. Showing the latest files instead.'
        : '';
    final filesMessage = fileEntries.isEmpty
        ? 'No files found in the recorded working directory.'
        : '';
    final changesMessage = changes.isEmpty
        ? 'No Git changes found for the current thread workspace.'
        : '';

    return AssistantArtifactSnapshot(
      workspaceRef: normalizedRef,
      workspaceRefKind: workspaceRefKind,
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
    required String workspaceRef,
    required WorkspaceRefKind workspaceRefKind,
  }) async {
    if (workspaceRefKind == WorkspaceRefKind.objectStore) {
      return const AssistantArtifactPreview.empty(
        message:
            'Object storage artifacts are not directly readable on desktop.',
      );
    }
    final root = Directory(workspaceRef.trim());
    if (!await root.exists()) {
      return const AssistantArtifactPreview.empty(
        message:
            'The recorded working directory is not available on this machine.',
      );
    }
    final targetPath = _resolveAbsolutePath(workspaceRef, entry.relativePath);
    final file = File(targetPath);
    if (!await file.exists()) {
      return AssistantArtifactPreview.empty(
        message:
            'The selected file is no longer available: ${entry.relativePath}',
      );
    }

    final extension = _fileExtension(entry.relativePath);
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
        content: _sanitizeHtml(content),
      );
    }
    if (_isPlainTextExtension(extension)) {
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

  Future<List<File>> _collectFiles(Directory root) async {
    final files = <File>[];
    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is Directory) {
          if (_ignoredDirectoryNames.contains(_baseName(entity.path))) {
            continue;
          }
          files.addAll(await _collectFiles(entity));
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

  Future<List<AssistantArtifactEntry>> _buildEntries(
    List<File> files,
    String workspaceRef,
  ) async {
    final entries = <AssistantArtifactEntry>[];
    for (final file in files) {
      try {
        final stat = await file.stat();
        final relativePath =
            _relativePath(workspaceRef, file.path) ?? file.path;
        final extension = _fileExtension(relativePath);
        entries.add(
          AssistantArtifactEntry(
            id: '$workspaceRef::$relativePath',
            label: _baseName(relativePath),
            relativePath: relativePath,
            kind: AssistantArtifactEntryKind.file,
            mimeType: _guessMimeType(relativePath),
            sizeBytes: stat.size,
            updatedAtMs: stat.modified.millisecondsSinceEpoch.toDouble(),
            previewable: _isPreviewableExtension(extension),
            workspaceRef: workspaceRef,
          ),
        );
      } on FileSystemException {
        // Ignore files that cannot be stat'ed.
      }
    }
    entries.sort((a, b) {
      final updatedCompare = (b.updatedAtMs ?? 0).compareTo(a.updatedAtMs ?? 0);
      if (updatedCompare != 0) {
        return updatedCompare;
      }
      return a.relativePath.compareTo(b.relativePath);
    });
    return entries;
  }

  Future<List<AssistantArtifactEntry>> _buildResultEntries({
    required List<AssistantArtifactChangeEntry> changes,
    required List<AssistantArtifactEntry> fileEntries,
    required String workspaceRef,
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
    return fileEntries.take(_defaultResultLimit).toList(growable: false);
  }

  Future<List<AssistantArtifactChangeEntry>> _readGitChanges(
    Directory workspaceRoot,
    String workspaceRef,
  ) async {
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
        final absolutePath = _joinPath(repositoryRoot, path);
        final relativePath = _relativePath(workspaceRef, absolutePath);
        if (relativePath == null || relativePath.isEmpty) {
          continue;
        }
        items.add(
          AssistantArtifactChangeEntry(
            path: relativePath,
            changeType: statusCode,
            displayLabel: _statusLabelFor(statusCode),
          ),
        );
      }
      return items;
    } on ProcessException {
      return const <AssistantArtifactChangeEntry>[];
    }
  }

  static String _resolveAbsolutePath(String root, String relativePath) {
    if (relativePath.startsWith('/') ||
        relativePath.startsWith('\\') ||
        relativePath.contains(':\\')) {
      return relativePath;
    }
    return _joinPath(root, relativePath);
  }

  static String _sanitizeHtml(String value) {
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

  static String _joinPath(String root, String child) {
    final separator = Platform.pathSeparator;
    final normalizedRoot = root.endsWith(separator) ? root : '$root$separator';
    final normalizedChild = child.startsWith(separator)
        ? child.substring(1)
        : child;
    return '$normalizedRoot$normalizedChild';
  }

  static String? _relativePath(String root, String absolutePath) {
    final normalizedRoot = _normalizePath(root);
    final normalizedPath = _normalizePath(absolutePath);
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

  static String _normalizePath(String path) {
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

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? normalized : parts.last;
  }

  static String _fileExtension(String path) {
    final name = _baseName(path);
    final index = name.lastIndexOf('.');
    if (index <= 0 || index >= name.length - 1) {
      return '';
    }
    return name.substring(index + 1).toLowerCase();
  }

  static String _guessMimeType(String path) {
    final extension = _fileExtension(path);
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
      'pdf' => 'application/pdf',
      'dart' => 'text/x-dart',
      'js' => 'text/javascript',
      'ts' => 'text/typescript',
      'css' => 'text/css',
      'xml' => 'application/xml',
      _ => 'application/octet-stream',
    };
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

  static String _statusLabelFor(String code) {
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
