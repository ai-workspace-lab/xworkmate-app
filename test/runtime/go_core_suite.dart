@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/go_core.dart';

void main() {
  test(
    'GoCoreLocator prefers bundled helper inside macOS app bundle',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-go-core-bundle-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final helpersDir = Directory(
        '${tempDirectory.path}/XWorkmate.app/Contents/Helpers',
      );
      await helpersDir.create(recursive: true);
      final helperFile = File('${helpersDir.path}/xworkmate-go-core');
      await helperFile.writeAsString('#!/bin/sh\nexit 0\n');
      await Process.run('chmod', <String>['+x', helperFile.path]);

      final locator = GoCoreLocator(
        workspaceRoot: tempDirectory.path,
        binaryExistsResolver: (_) async => true,
        resolvedExecutableResolver: () =>
            '${tempDirectory.path}/XWorkmate.app/Contents/MacOS/XWorkmate',
      );

      final launch = await locator.locate();

      expect(launch, isNotNull);
      expect(launch!.executable, helperFile.path);
      expect(launch.arguments, isEmpty);
      expect(launch.workingDirectory, isNull);
    },
  );

  test(
    'GoCoreLocator falls back to go run in the local bridge package',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-go-core-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      await Directory(
        '${tempDirectory.path}/go/go_core',
      ).create(recursive: true);

      final locator = GoCoreLocator(
        workspaceRoot: tempDirectory.path,
        binaryExistsResolver: (command) async => command == 'go',
      );

      final launch = await locator.locate();

      expect(launch, isNotNull);
      expect(launch!.executable, 'go');
      expect(launch.arguments, const <String>['run', '.']);
      expect(launch.workingDirectory, '${tempDirectory.path}/go/go_core');
    },
  );
}
