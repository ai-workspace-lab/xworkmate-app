import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/aris_bridge.dart';

void main() {
  test(
    'ArisBridgeLocator falls back to go run in the local bridge package',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-aris-bridge-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      await Directory(
        '${tempDirectory.path}/go/aris_bridge',
      ).create(recursive: true);

      final locator = ArisBridgeLocator(
        workspaceRoot: tempDirectory.path,
        binaryExistsResolver: (command) async => command == 'go',
      );

      final launch = await locator.locate();

      expect(launch, isNotNull);
      expect(launch!.executable, 'go');
      expect(launch.arguments, const <String>['run', '.']);
      expect(launch.workingDirectory, '${tempDirectory.path}/go/aris_bridge');
    },
  );
}
