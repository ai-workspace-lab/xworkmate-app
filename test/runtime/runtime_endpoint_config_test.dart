import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_endpoint_config.dart';

void main() {
  test(
    'authenticated profile endpoint takes precedence over build fallback',
    () {
      expect(
        configuredManagedBridgeServerUrl(
          remote: 'https://bridge.uat.onwalk.net?source=profile',
          environment: const <String, String>{},
        ),
        'https://bridge.uat.onwalk.net',
      );
    },
  );

  test('invalid endpoint metadata fails closed', () {
    expect(
      configuredManagedBridgeServerUrl(
        remote: 'not a URL',
        environment: const <String, String>{},
      ),
      isNull,
    );
  });

  test('environment endpoint is used when no profile endpoint is synced', () {
    expect(
      configuredManagedBridgeServerUrl(
        environment: const <String, String>{
          kManagedBridgeServerUrlEnvKey: 'https://bridge.self-hosted.example',
        },
      ),
      'https://bridge.self-hosted.example',
    );
  });

  test('authenticated profile endpoint takes precedence over environment', () {
    expect(
      configuredManagedBridgeServerUrl(
        remote: 'https://bridge.uat.onwalk.net',
        environment: const <String, String>{
          kManagedBridgeServerUrlEnvKey: 'https://bridge.self-hosted.example',
        },
      ),
      'https://bridge.uat.onwalk.net',
    );
  });
}
