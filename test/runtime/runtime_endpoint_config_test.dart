import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_endpoint_config.dart';

void main() {
  test(
    'authenticated profile endpoint takes precedence over build fallback',
    () {
      expect(
        configuredManagedBridgeServerUrl(
          remote: 'https://bridge.uat.onwalk.net?source=profile',
        ),
        'https://bridge.uat.onwalk.net',
      );
    },
  );

  test('invalid endpoint metadata fails closed', () {
    expect(configuredManagedBridgeServerUrl(remote: 'not a URL'), isNull);
  });
}
