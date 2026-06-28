import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/local_file_revealer.dart';

void main() {
  group('revealLocalFile', () {
    test('reveals the file in Finder on macOS', () async {
      final invocation = await _captureInvocation(
        operatingSystem: 'macos',
        targetPath: '/tmp/thread/report.pdf',
      );

      expect(invocation.executable, 'open');
      expect(invocation.arguments, <String>['-R', '/tmp/thread/report.pdf']);
      expect(invocation.mode, ProcessStartMode.detached);
    });

    test('opens the parent directory on Linux', () async {
      final invocation = await _captureInvocation(
        operatingSystem: 'linux',
        targetPath: '/tmp/thread/reports/report.pdf',
      );

      expect(invocation.executable, 'xdg-open');
      expect(invocation.arguments, <String>['/tmp/thread/reports']);
      expect(invocation.mode, ProcessStartMode.detached);
    });

    test('selects the file in Explorer on Windows', () async {
      final invocation = await _captureInvocation(
        operatingSystem: 'windows',
        targetPath: r'C:\thread\report.pdf',
      );

      expect(invocation.executable, 'explorer.exe');
      expect(invocation.arguments, <String>[r'/select,C:\thread\report.pdf']);
      expect(invocation.mode, ProcessStartMode.detached);
    });
  });
}

Future<_ProcessInvocation> _captureInvocation({
  required String operatingSystem,
  required String targetPath,
}) async {
  late _ProcessInvocation invocation;
  await revealLocalFile(
    targetPath,
    operatingSystem: operatingSystem,
    launchDetached: (executable, arguments, {required mode}) async {
      invocation = _ProcessInvocation(executable, arguments, mode);
    },
  );
  return invocation;
}

class _ProcessInvocation {
  const _ProcessInvocation(this.executable, this.arguments, this.mode);

  final String executable;
  final List<String> arguments;
  final ProcessStartMode mode;
}
