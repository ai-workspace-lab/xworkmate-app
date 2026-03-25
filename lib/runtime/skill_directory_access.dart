import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'runtime_models.dart';

abstract class SkillDirectoryAccessService {
  bool get isSupported;

  Future<AuthorizedSkillDirectory?> authorizeDirectory({
    String suggestedPath = '',
  });

  Future<SkillDirectoryAccessHandle?> openDirectory(
    AuthorizedSkillDirectory directory,
  );
}

class SkillDirectoryAccessHandle {
  SkillDirectoryAccessHandle({
    required this.path,
    required Future<void> Function() onClose,
    this.refreshedBookmark = '',
  }) : _onClose = onClose;

  final String path;
  final String refreshedBookmark;
  final Future<void> Function() _onClose;

  Future<void> close() => _onClose();
}

SkillDirectoryAccessService createSkillDirectoryAccessService() {
  final isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
  if (Platform.isMacOS && !isFlutterTest) {
    return MacOsSkillDirectoryAccessService();
  }
  if (Platform.isLinux || Platform.isWindows || isFlutterTest) {
    return FileSelectorSkillDirectoryAccessService();
  }
  return UnsupportedSkillDirectoryAccessService();
}

class UnsupportedSkillDirectoryAccessService
    implements SkillDirectoryAccessService {
  @override
  bool get isSupported => false;

  @override
  Future<AuthorizedSkillDirectory?> authorizeDirectory({
    String suggestedPath = '',
  }) async {
    return null;
  }

  @override
  Future<SkillDirectoryAccessHandle?> openDirectory(
    AuthorizedSkillDirectory directory,
  ) async {
    return null;
  }
}

class FileSelectorSkillDirectoryAccessService
    implements SkillDirectoryAccessService {
  @override
  bool get isSupported => true;

  @override
  Future<AuthorizedSkillDirectory?> authorizeDirectory({
    String suggestedPath = '',
  }) async {
    final directoryPath = await getDirectoryPath(
      initialDirectory: _initialDirectoryForSuggestion(suggestedPath),
    );
    final normalized = normalizeAuthorizedSkillDirectoryPath(
      directoryPath ?? '',
    );
    if (normalized.isEmpty) {
      return null;
    }
    return AuthorizedSkillDirectory(path: normalized);
  }

  @override
  Future<SkillDirectoryAccessHandle?> openDirectory(
    AuthorizedSkillDirectory directory,
  ) async {
    final normalized = normalizeAuthorizedSkillDirectoryPath(directory.path);
    if (normalized.isEmpty) {
      return null;
    }
    return SkillDirectoryAccessHandle(
      path: normalized,
      refreshedBookmark: directory.bookmark,
      onClose: () async {},
    );
  }
}

class MacOsSkillDirectoryAccessService implements SkillDirectoryAccessService {
  static const MethodChannel _channel = MethodChannel(
    'plus.svc.xworkmate/skill_directory_access',
  );

  @override
  bool get isSupported => true;

  @override
  Future<AuthorizedSkillDirectory?> authorizeDirectory({
    String suggestedPath = '',
  }) async {
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'authorizeDirectory',
      <String, dynamic>{'suggestedPath': suggestedPath},
    );
    if (response == null) {
      return null;
    }
    final normalized = normalizeAuthorizedSkillDirectoryPath(
      response['path']?.toString() ?? '',
    );
    if (normalized.isEmpty) {
      return null;
    }
    return AuthorizedSkillDirectory(
      path: normalized,
      bookmark: response['bookmark']?.toString().trim() ?? '',
    );
  }

  @override
  Future<SkillDirectoryAccessHandle?> openDirectory(
    AuthorizedSkillDirectory directory,
  ) async {
    final bookmark = directory.bookmark.trim();
    final normalizedPath = normalizeAuthorizedSkillDirectoryPath(
      directory.path,
    );
    if (bookmark.isEmpty) {
      if (normalizedPath.isEmpty) {
        return null;
      }
      return SkillDirectoryAccessHandle(
        path: normalizedPath,
        refreshedBookmark: directory.bookmark,
        onClose: () async {},
      );
    }
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'startDirectoryAccess',
      <String, dynamic>{'bookmark': bookmark},
    );
    if (response == null) {
      return null;
    }
    final accessId = response['accessId']?.toString().trim() ?? '';
    final resolvedPath = normalizeAuthorizedSkillDirectoryPath(
      response['path']?.toString() ?? normalizedPath,
    );
    if (accessId.isEmpty || resolvedPath.isEmpty) {
      return null;
    }
    final refreshedBookmark =
        response['bookmark']?.toString().trim().isNotEmpty == true
        ? response['bookmark'].toString().trim()
        : directory.bookmark;
    return SkillDirectoryAccessHandle(
      path: resolvedPath,
      refreshedBookmark: refreshedBookmark,
      onClose: () async {
        await _channel.invokeMethod<void>(
          'stopDirectoryAccess',
          <String, dynamic>{'accessId': accessId},
        );
      },
    );
  }
}

String _initialDirectoryForSuggestion(String suggestedPath) {
  final trimmed = normalizeAuthorizedSkillDirectoryPath(suggestedPath);
  if (trimmed.isEmpty) {
    return '';
  }
  final directory = Directory(trimmed);
  if (directory.existsSync()) {
    return directory.parent.path;
  }
  return directory.parent.path;
}
