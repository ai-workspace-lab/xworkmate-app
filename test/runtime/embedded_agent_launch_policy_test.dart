import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/embedded_agent_launch_policy.dart';

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
}
