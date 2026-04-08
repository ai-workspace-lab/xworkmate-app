import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/embedded_agent_launch_policy.dart';
import 'package:xworkmate/runtime/go_core.dart';

void main() {
  test('apple app store policy blocks embedded agent launches', () {
    expect(
      shouldBlockEmbeddedAgentLaunch(isAppleHost: true, enabled: true),
      isTrue,
    );
    expect(
      shouldBlockEmbeddedAgentLaunch(isAppleHost: false, enabled: true),
      isFalse,
    );
  });

  test('apple app store policy blocks all go core launches', () {
    const bundled = GoCoreLaunch(
      executable: '/Applications/XWorkmate.app/Contents/Helpers/xworkmate-go-core',
      source: GoCoreLaunchSource.bundledHelper,
    );
    const buildArtifact = GoCoreLaunch(
      executable: '/tmp/build/bin/xworkmate-go-core',
      source: GoCoreLaunchSource.buildArtifact,
    );

    expect(
      shouldBlockGoCoreLaunch(bundled, isAppleHost: true, enabled: true),
      isTrue,
    );
    expect(
      shouldBlockGoCoreLaunch(buildArtifact, isAppleHost: true, enabled: true),
      isTrue,
    );
    expect(
      shouldBlockGoCoreLaunch(buildArtifact, isAppleHost: false, enabled: true),
      isFalse,
    );
  });
}
