import 'dart:io';

class ArisBridgeLaunch {
  const ArisBridgeLaunch({
    required this.executable,
    this.arguments = const <String>[],
    this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

typedef ArisBinaryExistsResolver = Future<bool> Function(String command);

class ArisBridgeLocator {
  ArisBridgeLocator({
    ArisBinaryExistsResolver? binaryExistsResolver,
    String? workspaceRoot,
    String Function()? resolvedExecutableResolver,
  }) : _binaryExistsResolver = binaryExistsResolver,
       _workspaceRoot = workspaceRoot,
       _resolvedExecutableResolver = resolvedExecutableResolver;

  final ArisBinaryExistsResolver? _binaryExistsResolver;
  final String? _workspaceRoot;
  final String Function()? _resolvedExecutableResolver;

  Future<ArisBridgeLaunch?> locate() async {
    final bundled = await _bundledHelper();
    if (bundled != null) {
      return bundled;
    }

    final override =
        (Platform.environment['XWORKMATE_ARIS_BRIDGE_BIN'] ??
                Platform.environment['ARIS_BRIDGE_BIN'] ??
                '')
            .trim();
    if (override.isNotEmpty && await _binaryExists(override)) {
      return ArisBridgeLaunch(executable: override);
    }

    for (final candidate in <String>['xworkmate-aris-bridge', 'aris-bridge']) {
      if (await _binaryExists(candidate)) {
        return ArisBridgeLaunch(executable: candidate);
      }
    }

    final root = (_workspaceRoot ?? Directory.current.path).trim();
    if (root.isNotEmpty) {
      for (final path in <String>[
        '$root/go/bin/xworkmate-aris-bridge',
        '$root/go/bin/aris-bridge',
        '$root/build/bin/xworkmate-aris-bridge',
      ]) {
        if (await File(path).exists()) {
          return ArisBridgeLaunch(executable: path);
        }
      }

      final packageDirectory = Directory('$root/go/aris_bridge');
      if (await packageDirectory.exists() && await _binaryExists('go')) {
        return ArisBridgeLaunch(
          executable: 'go',
          arguments: const <String>['run', '.'],
          workingDirectory: packageDirectory.path,
        );
      }
    }
    return null;
  }

  Future<bool> isAvailable() async => await locate() != null;

  Future<ArisBridgeLaunch?> _bundledHelper() async {
    final resolvedExecutable =
        (_resolvedExecutableResolver?.call() ?? Platform.resolvedExecutable)
            .trim();
    if (resolvedExecutable.isEmpty) {
      return null;
    }
    final executableFile = File(resolvedExecutable);
    final executableDirectory = executableFile.parent;
    final contentsDirectory = executableDirectory.parent;
    final macOsDirectoryName = executableDirectory.path
        .split(Platform.pathSeparator)
        .last;
    final contentsDirectoryName = contentsDirectory.path
        .split(Platform.pathSeparator)
        .last;
    if (macOsDirectoryName != 'MacOS' || contentsDirectoryName != 'Contents') {
      return null;
    }
    final bundledPath =
        '${contentsDirectory.path}/Helpers/xworkmate-aris-bridge';
    if (await File(bundledPath).exists()) {
      return ArisBridgeLaunch(executable: bundledPath);
    }
    return null;
  }

  Future<bool> _binaryExists(String command) async {
    final resolver = _binaryExistsResolver;
    if (resolver != null) {
      return resolver(command);
    }
    if (command.contains(Platform.pathSeparator)) {
      return File(command).exists();
    }
    final check = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      <String>[command],
      runInShell: true,
    );
    return check.exitCode == 0 && '${check.stdout}'.trim().isNotEmpty;
  }
}
