@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_controller_desktop_external_acp_routing.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

import '../test_support.dart';

void main() {
  group('ACP bridge provider hub', () {
    test(
      'self-hosted ACP bridge base makes builtin single-agent providers visible without per-provider endpoints',
      () {
        final snapshot = SettingsSnapshot.defaults().copyWith(
          acpBridgeServerModeConfig: AcpBridgeServerModeConfig.defaults()
              .copyWith(
                mode: AcpBridgeServerMode.selfHosted,
                selfHosted: AcpBridgeServerSelfHostedConfig.defaults().copyWith(
                  serverUrl: 'https://bridge.example.com',
                  username: 'review@example.com',
                ),
              ),
        );

        expect(
          snapshot
              .externalAcpEndpointForProvider(SingleAgentProvider.codex)
              .endpoint,
          'https://bridge.example.com',
        );
        expect(
          snapshot.savedSingleAgentProviders.map((item) => item.providerId),
          contains('opencode'),
        );
      },
    );

    test(
      'builtin provider sync uses bridge base endpoint and self-hosted basic auth when endpoint auth is empty',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final store = createIsolatedTestStore(enableSecureStorage: false);
        final controller = AppController(store: store);
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.initializing);

        await controller.settingsController.saveSecretValueByRef(
          'acp_bridge_server_password',
          'top-secret',
          provider: 'ACP Bridge Server',
          module: 'Settings',
        );
        await controller.saveSettings(
          controller.settings.copyWith(
            acpBridgeServerModeConfig: controller
                .settings
                .acpBridgeServerModeConfig
                .copyWith(
                  mode: AcpBridgeServerMode.selfHosted,
                  selfHosted: controller
                      .settings
                      .acpBridgeServerModeConfig
                      .selfHosted
                      .copyWith(
                        serverUrl: 'https://bridge.example.com',
                        username: 'review@example.com',
                      ),
                ),
          ),
          refreshAfterSave: false,
        );

        final providers = await controller
            .buildExternalAcpSyncedProvidersInternal();
        final opencode = providers.firstWhere(
          (item) => item.providerId == 'opencode',
        );

        expect(opencode.endpoint, 'https://bridge.example.com');
        expect(
          opencode.authorizationHeader,
          'Basic ${base64Encode(utf8.encode('review@example.com:top-secret'))}',
        );
      },
    );
  });
}

Future<void> _waitFor(bool Function() predicate) async {
  final stopwatch = Stopwatch()..start();
  while (!predicate()) {
    if (stopwatch.elapsed > const Duration(seconds: 10)) {
      throw StateError('Timed out waiting for predicate');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
