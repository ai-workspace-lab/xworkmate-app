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
      expect(launch.source, GoCoreLaunchSource.bundledHelper);
      expect(launch.arguments, isEmpty);
      expect(launch.workingDirectory, isNull);
    },
  );

  test(
    'GoCoreLocator resolves the local build artifact from the workspace root',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-go-core-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final bridgeFile = File('${tempDirectory.path}/build/bin/xworkmate-go-core');
      await bridgeFile.parent.create(recursive: true);
      await bridgeFile.writeAsString('#!/bin/sh\nexit 0\n');
      await Process.run('chmod', <String>['+x', bridgeFile.path]);

      final locator = GoCoreLocator(
        workspaceRoot: tempDirectory.path,
      );

      final launch = await locator.locate();

      expect(launch, isNotNull);
      expect(launch!.executable, bridgeFile.path);
      expect(launch.source, GoCoreLaunchSource.buildArtifact);
      expect(launch.arguments, isEmpty);
      expect(launch.workingDirectory, isNull);
    },
  );

  test(
    'GoCoreLocator resolves build-root bridge binaries from the executable ancestry when cwd is outside the repo',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-go-core-build-root-',
      );
      final outsideDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-go-core-outside-',
      );
      final originalCurrentDirectory = Directory.current;
      addTearDown(() async {
        Directory.current = originalCurrentDirectory;
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
        if (await outsideDirectory.exists()) {
          await outsideDirectory.delete(recursive: true);
        }
      });

      final bridgeFile = File('${tempDirectory.path}/build/bin/xworkmate-go-core');
      await bridgeFile.parent.create(recursive: true);
      await bridgeFile.writeAsString('#!/bin/sh\nexit 0\n');
      await Process.run('chmod', <String>['+x', bridgeFile.path]);

      final executablePath =
          '${tempDirectory.path}/build/macos/Build/Products/Debug/XWorkmate.app/Contents/MacOS/XWorkmate';
      await File(executablePath).parent.create(recursive: true);
      await File(executablePath).writeAsString('');

      Directory.current = outsideDirectory;

      final locator = GoCoreLocator(
        resolvedExecutableResolver: () => executablePath,
      );

      final launch = await locator.locate();

      expect(launch, isNotNull);
      expect(launch!.executable, bridgeFile.path);
      expect(launch.source, GoCoreLaunchSource.buildArtifact);
      expect(launch.arguments, isEmpty);
      expect(launch.workingDirectory, isNull);
    },
  );
}
