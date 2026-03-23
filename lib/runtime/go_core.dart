import 'dart:io';

class GoCoreLaunch {
  const GoCoreLaunch({
    required this.executable,
    this.arguments = const <String>[],
    this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

typedef GoCoreBinaryExistsResolver = Future<bool> Function(String command);

class GoCoreLocator {
  GoCoreLocator({
    GoCoreBinaryExistsResolver? binaryExistsResolver,
    String? workspaceRoot,
    String Function()? resolvedExecutableResolver,
  }) : _binaryExistsResolver = binaryExistsResolver,
       _workspaceRoot = workspaceRoot,
       _resolvedExecutableResolver = resolvedExecutableResolver;

  final GoCoreBinaryExistsResolver? _binaryExistsResolver;
  final String? _workspaceRoot;
  final String Function()? _resolvedExecutableResolver;

  Future<GoCoreLaunch?> locate() async {
    final bundled = await _bundledHelper();
    if (bundled != null) {
      return bundled;
    }

    final override =
        (Platform.environment['XWORKMATE_GO_CORE_BIN'] ??
                Platform.environment['GO_CORE_BIN'] ??
                '')
            .trim();
    if (override.isNotEmpty && await _binaryExists(override)) {
      return GoCoreLaunch(executable: override);
    }

    for (final candidate in <String>['xworkmate-go-core', 'go-core']) {
      if (await _binaryExists(candidate)) {
        return GoCoreLaunch(executable: candidate);
      }
    }

    final root = (_workspaceRoot ?? Directory.current.path).trim();
    if (root.isNotEmpty) {
      for (final path in <String>[
        '$root/go/bin/xworkmate-go-core',
        '$root/go/bin/go-core',
        '$root/build/bin/xworkmate-go-core',
      ]) {
        if (await File(path).exists()) {
          return GoCoreLaunch(executable: path);
        }
      }

      final packageDirectory = Directory('$root/go/go_core');
      if (await packageDirectory.exists() && await _binaryExists('go')) {
        return GoCoreLaunch(
          executable: 'go',
          arguments: const <String>['run', '.'],
          workingDirectory: packageDirectory.path,
        );
      }
    }
    return null;
  }

  Future<bool> isAvailable() async => await locate() != null;

  Future<GoCoreLaunch?> _bundledHelper() async {
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
    final bundledPath = '${contentsDirectory.path}/Helpers/xworkmate-go-core';
    if (await File(bundledPath).exists()) {
      return GoCoreLaunch(executable: bundledPath);
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
