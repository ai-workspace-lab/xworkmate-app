import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/embedded_agent_launch_policy.dart';
import 'package:xworkmate/runtime/go_core.dart';

void main() {
  group('embedded agent launch policy', () {
    test('blocks Go core launch for App Store policy on Apple hosts', () {
      const launch = GoCoreLaunch(
        executable: '/tmp/build/bin/xworkmate-go-core',
        source: GoCoreLaunchSource.buildArtifact,
      );

      expect(
        shouldBlockGoCoreLaunch(launch, isAppleHost: true, enabled: true),
        isTrue,
      );
    });

    test('allows Go core launch when App Store policy is disabled', () {
      const launch = GoCoreLaunch(
        executable: '/tmp/build/bin/xworkmate-go-core',
        source: GoCoreLaunchSource.buildArtifact,
      );

      expect(
        shouldBlockGoCoreLaunch(launch, isAppleHost: true, enabled: false),
        isFalse,
      );
    });
  });
}
