import 'dart:io';

enum GoCoreLaunchSource {
  bundledHelper,
  buildArtifact,
}

class GoCoreLaunch {
  const GoCoreLaunch({
    required this.executable,
    required this.source,
    this.arguments = const <String>[],
    this.workingDirectory,
  });

  final String executable;
  final GoCoreLaunchSource source;
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

    for (final root in _candidateRoots()) {
      final path = '$root/build/bin/xworkmate-go-core';
      if (await _binaryExists(path)) {
        return GoCoreLaunch(
          executable: path,
          source: GoCoreLaunchSource.buildArtifact,
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
    if (await _binaryExists(bundledPath)) {
      return GoCoreLaunch(
        executable: bundledPath,
        source: GoCoreLaunchSource.bundledHelper,
      );
    }
    return null;
  }

  List<String> _candidateRoots() {
    final roots = <String>{};
    final explicitRoot = _workspaceRoot?.trim() ?? '';
    if (explicitRoot.isNotEmpty) {
      roots.add(explicitRoot);
      roots.addAll(_ancestorPaths(Directory(explicitRoot)));
    }

    final currentPath = Directory.current.path.trim();
    if (currentPath.isNotEmpty) {
      roots.add(currentPath);
      roots.addAll(_ancestorPaths(Directory(currentPath)));
    }

    final resolvedExecutable =
        (_resolvedExecutableResolver?.call() ?? Platform.resolvedExecutable)
            .trim();
    if (resolvedExecutable.isNotEmpty) {
      final executableDirectory = File(resolvedExecutable).parent;
      roots.add(executableDirectory.path);
      roots.addAll(_ancestorPaths(executableDirectory));
    }

    return roots.where((path) => path.trim().isNotEmpty).toList(growable: false);
  }

  List<String> _ancestorPaths(Directory start) {
    final ancestors = <String>[];
    var current = start.absolute;
    while (true) {
      final parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      ancestors.add(parent.path);
      current = parent;
    }
    return ancestors;
  }

  Future<bool> _binaryExists(String command) async =>
      (_binaryExistsResolver?.call(command)) ?? File(command).exists();
}
