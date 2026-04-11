import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/go_core.dart';

void main() {
  group('GoCoreLocator', () {
    test(
      'finds workspace build artifact and never depends on app bundle helpers',
      () async {
        final locator = GoCoreLocator(
          workspaceRoot: '/repo/app',
          resolvedExecutableResolver: () =>
              '/repo/app/build/macos/Build/Products/Release/XWorkmate.app/Contents/MacOS/XWorkmate',
          binaryExistsResolver: (path) async =>
              path == '/repo/app/build/bin/xworkmate-go-core',
        );

        final launch = await locator.locate();

        expect(launch, isNotNull);
        expect(launch!.executable, '/repo/app/build/bin/xworkmate-go-core');
        expect(launch.source, GoCoreLaunchSource.buildArtifact);
      },
    );
  });
}
