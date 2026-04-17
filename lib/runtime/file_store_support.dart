import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';

String? _persistentSupportRootOverride;

void debugOverridePersistentSupportRoot(String? path) {
  final trimmed = path?.trim() ?? '';
  _persistentSupportRootOverride = trimmed.isEmpty
      ? null
      : normalizeStoreDirectoryPath(trimmed);
}

String? defaultUserSettingsRootPath({
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final env = environment ?? Platform.environment;
  final os = operatingSystem ?? Platform.operatingSystem;
  final home = env['HOME']?.trim() ?? '';
  if (home.isEmpty) {
    return null;
  }
  if (os == 'macos') {
    return '$home/Library/Application Support/xworkmate';
  }
  if (os == 'linux') {
    final xdgConfigHome = env['XDG_CONFIG_HOME']?.trim() ?? '';
    if (xdgConfigHome.isNotEmpty) {
      return '$xdgConfigHome/xworkmate';
    }
    return '$home/.config/xworkmate';
  }
  if (os == 'windows') {
    final appData = env['APPDATA']?.trim() ?? '';
    if (appData.isNotEmpty) {
      return '$appData\\xworkmate';
    }
  }
  return '$home/.xworkmate';
}

String? defaultUserSettingsFilePath({
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final root = defaultUserSettingsRootPath(
    environment: environment,
    operatingSystem: operatingSystem,
  );
  if ((root ?? '').isEmpty) {
    return null;
  }
  return '$root/config/settings.yaml';
}

enum PersistentStoreScope { settings, tasks, secrets, audit }

class PersistentWriteFailure {
  const PersistentWriteFailure({
    required this.scope,
    required this.operation,
    required this.message,
    required this.timestampMs,
  });

  final PersistentStoreScope scope;
  final String operation;
  final String message;
  final int timestampMs;
}

class PersistentWriteFailures {
  const PersistentWriteFailures({
    this.settings,
    this.tasks,
    this.secrets,
    this.audit,
  });

  final PersistentWriteFailure? settings;
  final PersistentWriteFailure? tasks;
  final PersistentWriteFailure? secrets;
  final PersistentWriteFailure? audit;

  bool get hasFailures =>
      settings != null || tasks != null || secrets != null || audit != null;
}

class StoreLayout {
  const StoreLayout({
    required this.rootDirectory,
    required this.configDirectory,
    required this.tasksDirectory,
    required this.secretDirectory,
  });

  final Directory rootDirectory;
  final Directory configDirectory;
  final Directory tasksDirectory;
  final Directory secretDirectory;

  File get settingsFile => File('${configDirectory.path}/settings.yaml');

  File get auditFile => File('${configDirectory.path}/secret-audit.json');

  File get taskIndexFile => File('${tasksDirectory.path}/index.json');

  File taskFileForSessionKey(String sessionKey) {
    final encoded = encodeStableFileKey(sessionKey);
    return File('${tasksDirectory.path}/$encoded.json');
  }

  File secretFileForKey(String key) {
    final encoded = encodeStableFileKey(key);
    return File('${secretDirectory.path}/$encoded.secret');
  }
}

class StoreLayoutResolver {
  StoreLayoutResolver({
    Future<String?> Function()? appDataRootPathResolver,
    Future<String?> Function()? secretRootPathResolver,
    Future<String?> Function()? supportRootPathResolver,
  }) : _appDataRootPathResolver = appDataRootPathResolver,
       _secretRootPathResolver = secretRootPathResolver,
       _supportRootPathResolver = supportRootPathResolver;

  final Future<String?> Function()? _appDataRootPathResolver;
  final Future<String?> Function()? _secretRootPathResolver;
  final Future<String?> Function()? _supportRootPathResolver;

  StoreLayout? _cached;

  Future<StoreLayout> resolve() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final supportRootPath =
        await _resolvePath(_supportRootPathResolver) ??
        await _defaultSupportRootPath();
    if (supportRootPath == null) {
      // Fallback to a temporary directory instead of failing fast with an error.
      // This ensures the app remains usable in "memory-only" or "ephemeral" mode.
      final tempDir = await Directory.systemTemp.createTemp('xworkmate-fallback-');
      final layout = StoreLayout(
        rootDirectory: tempDir,
        configDirectory: await ensureDirectory('${tempDir.path}/config'),
        tasksDirectory: await ensureDirectory('${tempDir.path}/tasks'),
        secretDirectory: await ensureDirectory('${tempDir.path}/secrets'),
      );
      _cached = layout;
      return layout;
    }
    final appDataRootPath =
        await _resolvePath(_appDataRootPathResolver) ?? supportRootPath;
    final secretRootPath =
        await _resolvePath(_secretRootPathResolver) ??
        '$supportRootPath/secrets';
    final rootDirectory = await ensureDirectory(
      normalizeStoreDirectoryPath(appDataRootPath),
    );
    final configDirectory = await ensureDirectory(
      '${rootDirectory.path}/config',
    );
    final tasksDirectory = await ensureDirectory('${rootDirectory.path}/tasks');
    final secretDirectory = await ensureDirectory(
      normalizeStoreDirectoryPath(secretRootPath),
    );
    await ensureOwnerOnlyDirectory(secretDirectory);
    final layout = StoreLayout(
      rootDirectory: rootDirectory,
      configDirectory: configDirectory,
      tasksDirectory: tasksDirectory,
      secretDirectory: secretDirectory,
    );
    _cached = layout;
    return layout;
  }

  Future<String?> _defaultSupportRootPath() async {
    final override = _persistentSupportRootOverride;
    if (override != null && override.isNotEmpty) {
      return override;
    }
    if (Platform.isMacOS) {
      final macUserRoot = defaultUserSettingsRootPath();
      if ((macUserRoot ?? '').isNotEmpty) {
        return macUserRoot;
      }
    }
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      return '${supportDirectory.path}/xworkmate';
    } catch (_) {
      return defaultUserSettingsRootPath();
    }
  }

  Future<String?> _resolvePath(Future<String?> Function()? resolver) async {
    if (resolver == null) {
      return null;
    }
    try {
      final value = await resolver();
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) {
        return null;
      }
      return normalizeStoreDirectoryPath(trimmed);
    } catch (_) {
      return null;
    }
  }
}

String normalizeStoreDirectoryPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  final lower = trimmed.toLowerCase();
  if (lower.endsWith('.sqlite') ||
      lower.endsWith('.sqlite3') ||
      lower.endsWith('.db') ||
      lower.endsWith('.yaml') ||
      lower.endsWith('.yml') ||
      lower.endsWith('.json')) {
    return File(trimmed).parent.path;
  }
  return trimmed;
}

Future<Directory> ensureDirectory(String path) async {
  final directory = Directory(path);
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}

Future<void> ensureOwnerOnlyDirectory(Directory directory) async {
  if (Platform.isWindows) {
    return;
  }
  await _setUnixPermissions(directory.path, '700');
}

Future<void> ensureOwnerOnlyFile(File file) async {
  if (Platform.isWindows) {
    return;
  }
  await _setUnixPermissions(file.path, '600');
}

String encodeStableFileKey(String key) {
  return base64Url.encode(utf8.encode(key)).replaceAll('=', '');
}

Future<void> atomicWriteString(
  File file,
  String contents, {
  bool ownerOnly = false,
}) async {
  if (!await file.parent.exists()) {
    await file.parent.create(recursive: true);
  }
  final tempFile = File(
    '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
  );
  await tempFile.writeAsString(contents, flush: true);
  if (ownerOnly) {
    await ensureOwnerOnlyDirectory(file.parent);
    await ensureOwnerOnlyFile(tempFile);
  }
  await tempFile.rename(file.path);
  if (ownerOnly) {
    await ensureOwnerOnlyFile(file);
  }
}

Future<void> deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

Object? decodeYamlDocument(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  try {
    return _yamlToObject(loadYaml(trimmed));
  } catch (_) {
    return null;
  }
}

Object? _yamlToObject(Object? value) {
  if (value is YamlMap) {
    return value.map(
      (Object? key, Object? item) =>
          MapEntry(key?.toString() ?? '', _yamlToObject(item)),
    );
  }
  if (value is YamlList) {
    return value.map(_yamlToObject).toList(growable: false);
  }
  return value;
}

String encodeYamlDocument(Object? value) {
  final buffer = StringBuffer('---\n');
  _writeYamlValue(buffer, value, 0, listItem: false);
  if (!buffer.toString().endsWith('\n')) {
    buffer.writeln();
  }
  return buffer.toString();
}

Future<void> _setUnixPermissions(String path, String mode) async {
  final result = await Process.run('chmod', <String>[mode, path]);
  if (result.exitCode == 0) {
    return;
  }
  throw ProcessException(
    'chmod',
    <String>[mode, path],
    '${result.stderr}'.trim(),
    result.exitCode,
  );
}

void _writeYamlValue(
  StringBuffer buffer,
  Object? value,
  int indent, {
  required bool listItem,
}) {
  final prefix = '  ' * indent;
  if (value is Map) {
    if (value.isEmpty) {
      if (listItem) {
        buffer.writeln('{}');
      } else {
        buffer.writeln('$prefix{}');
      }
      return;
    }
    if (listItem) {
      buffer.writeln();
    }
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final item = entry.value;
      if (_isInlineYamlValue(item)) {
        buffer.writeln('$prefix$key: ${_yamlInlineValue(item)}');
      } else if (item is String && item.contains('\n')) {
        buffer.writeln('$prefix$key: |-');
        for (final line in item.split('\n')) {
          buffer.writeln('${'  ' * (indent + 1)}$line');
        }
      } else {
        buffer.writeln('$prefix$key:');
        _writeYamlValue(buffer, item, indent + 1, listItem: false);
      }
    }
    return;
  }
  if (value is List) {
    if (value.isEmpty) {
      if (listItem) {
        buffer.writeln('[]');
      } else {
        buffer.writeln('$prefix[]');
      }
      return;
    }
    if (listItem) {
      buffer.writeln();
    }
    for (final item in value) {
      if (_isInlineYamlValue(item)) {
        buffer.writeln('$prefix- ${_yamlInlineValue(item)}');
      } else if (item is String && item.contains('\n')) {
        buffer.writeln('$prefix- |-');
        for (final line in item.split('\n')) {
          buffer.writeln('${'  ' * (indent + 1)}$line');
        }
      } else {
        buffer.writeln('$prefix-');
        _writeYamlValue(buffer, item, indent + 1, listItem: false);
      }
    }
    return;
  }
  if (listItem) {
    buffer.writeln(_yamlInlineValue(value));
    return;
  }
  buffer.writeln('$prefix${_yamlInlineValue(value)}');
}

bool _isInlineYamlValue(Object? value) {
  if (value == null || value is bool || value is num) {
    return true;
  }
  if (value is String) {
    return !value.contains('\n');
  }
  if (value is List) {
    return value.isEmpty;
  }
  if (value is Map) {
    return value.isEmpty;
  }
  return false;
}

String _yamlInlineValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool || value is num) {
    return value.toString();
  }
  if (value is List && value.isEmpty) {
    return '[]';
  }
  if (value is Map && value.isEmpty) {
    return '{}';
  }
  final stringValue = value.toString();
  if (stringValue.isEmpty) {
    return "''";
  }
  final safe = RegExp(r'^[A-Za-z0-9_./:@+%-]+$');
  final reserved = <String>{'null', 'true', 'false', '~'};
  if (safe.hasMatch(stringValue) && !reserved.contains(stringValue)) {
    return stringValue;
  }
  final escaped = stringValue.replaceAll("'", "''");
  return "'$escaped'";
}
