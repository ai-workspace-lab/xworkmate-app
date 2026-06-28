import 'dart:io';

typedef DetachedProcessLauncher =
    Future<void> Function(
      String executable,
      List<String> arguments, {
      required ProcessStartMode mode,
    });

Future<void> revealLocalFile(
  String targetPath, {
  String? operatingSystem,
  DetachedProcessLauncher? launchDetached,
}) async {
  final launcher = launchDetached ?? _launchDetached;
  switch (operatingSystem ?? Platform.operatingSystem) {
    case 'macos':
      await launcher('open', <String>[
        '-R',
        targetPath,
      ], mode: ProcessStartMode.detached);
    case 'linux':
      await launcher('xdg-open', <String>[
        File(targetPath).parent.path,
      ], mode: ProcessStartMode.detached);
    case 'windows':
      await launcher('explorer.exe', <String>[
        '/select,$targetPath',
      ], mode: ProcessStartMode.detached);
  }
}

Future<void> _launchDetached(
  String executable,
  List<String> arguments, {
  required ProcessStartMode mode,
}) async {
  await Process.start(executable, arguments, mode: mode);
}
