import 'dart:async';

/// DEPRECATED: Local Go core execution is disabled.
enum GoCoreLaunchSource { buildArtifact }

/// DEPRECATED: Local Go core execution is disabled.
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

/// DEPRECATED: Local Go core locator is disabled.
class GoCoreLocator {
  GoCoreLocator({
    GoCoreBinaryExistsResolver? binaryExistsResolver,
    String? workspaceRoot,
    String Function()? resolvedExecutableResolver,
  });

  /// Always returns null as local execution is disabled.
  Future<GoCoreLaunch?> locate() async => null;

  /// Always returns false as local execution is disabled.
  Future<bool> isAvailable() async => false;
}
