import 'dart:io';

import 'runtime_models.dart';

class RuntimeBootstrapConfig {
  const RuntimeBootstrapConfig({
    required this.workspacePath,
    required this.remoteProjectRoot,
    required this.cliPath,
    required this.localGateway,
    required this.remoteGateway,
  });

  final String? workspacePath;
  final String? remoteProjectRoot;
  final String? cliPath;
  final GatewayBootstrapTarget? localGateway;
  final GatewayBootstrapTarget? remoteGateway;

  static Future<RuntimeBootstrapConfig> load({
    String? workspacePathHint,
    String? cliPathHint,
  }) async {
    final workspaceRoot = _resolveWorkspaceRoot(workspacePathHint);
    final openClawRoot = _resolveOpenClawRoot(
      workspaceRoot,
      cliPathHint: cliPathHint,
    );
    final env = await _loadEnvFile(
      workspacePathHint: workspacePathHint,
      cliPathHint: cliPathHint,
      workspaceRoot: workspaceRoot,
      openClawRoot: openClawRoot,
    );
    return RuntimeBootstrapConfig(
      workspacePath: workspaceRoot?.path,
      remoteProjectRoot: workspaceRoot?.path,
      cliPath: _resolveCliPath(openClawRoot),
      localGateway: GatewayBootstrapTarget.tryParse(
        env['local'],
        token: env['local-token'],
      ),
      remoteGateway: GatewayBootstrapTarget.tryParse(
        env['remote'],
        token: env['remote-token'],
      ),
    );
  }

  SettingsSnapshot mergeIntoSettings(SettingsSnapshot snapshot) {
    var next = snapshot;

    final resolvedWorkspacePath = workspacePath?.trim() ?? '';
    final resolvedRemoteProjectRoot = remoteProjectRoot?.trim() ?? '';
    final replaceWorkspacePath =
        _isDefaultWorkspacePath(snapshot.workspacePath) ||
        _isMissingTransientWorkspacePath(snapshot.workspacePath);
    final replaceRemoteProjectRoot =
        _isDefaultRemoteRoot(snapshot.remoteProjectRoot) ||
        _isMissingTransientWorkspacePath(snapshot.remoteProjectRoot);

    if (replaceWorkspacePath) {
      next = next.copyWith(
        workspacePath: resolvedWorkspacePath.isNotEmpty
            ? resolvedWorkspacePath
            : SettingsSnapshot.defaults().workspacePath,
      );
    }
    if (replaceRemoteProjectRoot) {
      next = next.copyWith(
        remoteProjectRoot: resolvedRemoteProjectRoot.isNotEmpty
            ? resolvedRemoteProjectRoot
            : (resolvedWorkspacePath.isNotEmpty
                  ? resolvedWorkspacePath
                  : SettingsSnapshot.defaults().remoteProjectRoot),
      );
    }
    if (_isDefaultCliPath(snapshot.cliPath) &&
        cliPath != null &&
        cliPath!.trim().isNotEmpty) {
      next = next.copyWith(cliPath: cliPath);
    }

    return next;
  }

  GatewayBootstrapTarget? preferredGatewayFor(RuntimeConnectionMode mode) {
    return switch (mode) {
      RuntimeConnectionMode.local => localGateway ?? remoteGateway,
      RuntimeConnectionMode.remote => remoteGateway ?? localGateway,
      RuntimeConnectionMode.unconfigured => remoteGateway ?? localGateway,
    };
  }

  static bool _isDefaultWorkspacePath(String value) =>
      value.trim().isEmpty || value.trim() == '/opt/data';

  static bool _isDefaultRemoteRoot(String value) =>
      value.trim().isEmpty || value.trim() == '/opt/data/workspace';

  static bool _isDefaultCliPath(String value) =>
      value.trim().isEmpty || value.trim() == 'openclaw';

  static bool _isMissingTransientWorkspacePath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (_isLikelyTransientPath(trimmed) &&
        FileSystemEntity.typeSync(trimmed) == FileSystemEntityType.notFound) {
      return true;
    }
    return false;
  }

  static bool _isLikelyTransientPath(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final systemTemp = Directory.systemTemp.path;
    if (normalized == systemTemp || normalized.startsWith('$systemTemp/')) {
      return true;
    }
    if (normalized.startsWith('/tmp/') ||
        normalized.startsWith('/private/tmp/')) {
      return true;
    }
    return false;
  }
}

class GatewayBootstrapTarget {
  const GatewayBootstrapTarget({
    required this.mode,
    required this.url,
    required this.host,
    required this.port,
    required this.tls,
    required this.token,
  });

  final RuntimeConnectionMode mode;
  final String url;
  final String host;
  final int port;
  final bool tls;
  final String token;

  static GatewayBootstrapTarget? tryParse(String? raw, {String? token}) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || (uri.host).trim().isEmpty) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    final tls = scheme == 'wss' || scheme == 'https';
    final port = uri.hasPort ? uri.port : (tls ? 443 : 18789);
    final host = uri.host.trim();
    final isLocal = host == '127.0.0.1' || host == 'localhost';
    return GatewayBootstrapTarget(
      mode: isLocal
          ? RuntimeConnectionMode.local
          : RuntimeConnectionMode.remote,
      url: trimmed,
      host: host,
      port: port,
      tls: tls,
      token: token?.trim() ?? '',
    );
  }
}

Future<Map<String, String>> _loadEnvFile({
  String? workspacePathHint,
  String? cliPathHint,
  Directory? workspaceRoot,
  Directory? openClawRoot,
}) async {
  final candidateDirectories = <Directory>{
    Directory.current,
    ..._ancestorDirectories(Directory.current),
    ..._pathCandidates(workspacePathHint),
    ..._pathCandidates(
      cliPathHint == null ? null : File(cliPathHint).parent.path,
    ),
    ...?workspaceRoot == null ? null : <Directory>[workspaceRoot],
    ...?workspaceRoot == null ? null : _ancestorDirectories(workspaceRoot),
    ...?openClawRoot == null ? null : <Directory>[openClawRoot],
    ...?openClawRoot == null ? null : _ancestorDirectories(openClawRoot),
  };
  final candidates = candidateDirectories
      .map((directory) => File('${directory.path}/.env'))
      .toList(growable: false);

  for (final file in candidates) {
    if (!await file.exists()) {
      continue;
    }
    final values = <String, String>{};
    for (final line in await file.readAsLines()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      final separator = trimmed.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final key = trimmed.substring(0, separator).trim();
      final value = trimmed.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        values[key] = value;
      }
    }
    if (values.isNotEmpty) {
      return values;
    }
  }
  return const <String, String>{};
}

Directory? _resolveWorkspaceRoot(String? workspacePathHint) {
  final candidates = <Directory>{
    ..._pathCandidates(workspacePathHint),
    Directory.current,
    ..._ancestorDirectories(Directory.current),
  }.toList(growable: false);
  for (final candidate in candidates) {
    if (File('${candidate.path}/pubspec.yaml').existsSync() &&
        File('${candidate.path}/lib/main.dart').existsSync()) {
      return candidate;
    }
  }
  return null;
}

Directory? _resolveOpenClawRoot(
  Directory? workspaceRoot, {
  String? cliPathHint,
}) {
  final cliFile = cliPathHint == null ? null : File(cliPathHint);
  if (cliFile != null && cliFile.existsSync()) {
    final cliParent = cliFile.parent;
    if (File('${cliParent.path}/openclaw.mjs').existsSync()) {
      return cliParent;
    }
  }
  if (workspaceRoot == null) {
    return null;
  }
  final sibling = Directory('${workspaceRoot.parent.path}/openclaw.svc.plus');
  if (File('${sibling.path}/openclaw.mjs').existsSync()) {
    return sibling;
  }
  return null;
}

String? _resolveCliPath(Directory? openClawRoot) {
  if (openClawRoot == null) {
    return null;
  }
  final candidate = File('${openClawRoot.path}/openclaw.mjs');
  if (!candidate.existsSync()) {
    return null;
  }
  return candidate.path;
}

List<Directory> _ancestorDirectories(Directory start) {
  final ancestors = <Directory>[];
  var current = start.absolute;
  while (true) {
    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    ancestors.add(parent);
    current = parent;
  }
  return ancestors;
}

List<Directory> _pathCandidates(String? rawPath) {
  final trimmed = rawPath?.trim() ?? '';
  if (trimmed.isEmpty) {
    return const <Directory>[];
  }
  final fileSystemEntityType = FileSystemEntity.typeSync(trimmed);
  final directory = switch (fileSystemEntityType) {
    FileSystemEntityType.directory => Directory(trimmed),
    FileSystemEntityType.file => File(trimmed).parent,
    _ => Directory(trimmed),
  };
  if (!directory.existsSync()) {
    return const <Directory>[];
  }
  return <Directory>[directory, ..._ancestorDirectories(directory)];
}
