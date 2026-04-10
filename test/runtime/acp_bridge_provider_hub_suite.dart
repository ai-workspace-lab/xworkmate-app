@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_controller_desktop_external_acp_routing.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

import '../test_support.dart';
import 'app_controller_ai_gateway_chat_suite_fakes.dart';

void main() {
  group('ACP bridge provider hub', () {
    test(
      'self-hosted ACP bridge base does not override builtin single-agent endpoints',
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
          '',
        );
      },
    );

    test(
      'builtin provider sync does not inject self-hosted bridge endpoint or auth fallback',
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
            externalAcpEndpoints: replaceExternalAcpEndpointForProvider(
              controller.settings.externalAcpEndpoints,
              SingleAgentProvider.opencode,
              controller.settings
                  .externalAcpEndpointForProvider(SingleAgentProvider.opencode)
                  .copyWith(endpoint: 'https://acp.example.com/opencode'),
            ),
          ),
          refreshAfterSave: false,
        );

        final providers = await controller
            .buildExternalAcpSyncedProvidersInternal();
        final opencode = providers.firstWhere(
          (item) => item.providerId == 'opencode',
        );

        expect(opencode.endpoint, 'https://acp.example.com/opencode');
        expect(opencode.authorizationHeader, '');
      },
    );

    test('single-agent picker follows bridge capabilities only', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = createIsolatedTestStore(enableSecureStorage: false);
      final controller = AppController(
        store: store,
        goTaskServiceClient: FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{
              SingleAgentProvider.codex,
              SingleAgentProvider.opencode,
            },
            raw: <String, dynamic>{},
          ),
        ),
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);

      await controller.refreshSingleAgentCapabilitiesInternal(
        forceRefresh: true,
      );

      expect(
        controller.singleAgentProviderOptions
            .map((item) => item.providerId)
            .toList(growable: false),
        const <String>['codex', 'opencode'],
      );
    });

    test(
      'self-hosted bridge capabilities add dynamic builtin providers to the single-agent picker',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final store = createIsolatedTestStore(enableSecureStorage: false);
        final controller = AppController(
          store: store,
          goTaskServiceClient: FakeGoTaskServiceClientInternal(
            capabilities: ExternalCodeAgentAcpCapabilities(
              singleAgent: true,
              multiAgent: false,
              providers: <SingleAgentProvider>{
                SingleAgentProvider.codex,
                SingleAgentProvider.opencode,
              },
              raw: <String, dynamic>{},
            ),
          ),
        );
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.initializing);

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
                      .copyWith(serverUrl: 'https://xworkmate-bridge.svc.plus'),
                ),
          ),
          refreshAfterSave: false,
        );

        await controller.refreshSingleAgentCapabilitiesInternal(
          forceRefresh: true,
        );

        expect(
          controller.singleAgentProviderOptions
              .map((item) => item.providerId)
              .toList(growable: false),
          const <String>['codex', 'opencode'],
        );
      },
    );

    test(
      'local sync-only custom provider does not appear unless bridge advertises it',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final store = createIsolatedTestStore(enableSecureStorage: false);
        final controller = AppController(
          store: store,
          goTaskServiceClient: FakeGoTaskServiceClientInternal(
            capabilities: ExternalCodeAgentAcpCapabilities(
              singleAgent: true,
              multiAgent: false,
              providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
              raw: <String, dynamic>{},
            ),
          ),
        );
        addTearDown(controller.dispose);
        await _waitFor(() => !controller.initializing);

        await controller.saveSettings(
          controller.settings.copyWith(
            externalAcpEndpoints: normalizeExternalAcpEndpoints(
              profiles: <ExternalAcpEndpointProfile>[
                ...controller.settings.externalAcpEndpoints,
                buildCustomExternalAcpEndpointProfile(
                  controller.settings.externalAcpEndpoints,
                  label: 'Lab Agent',
                  endpoint: 'wss://lab.example.com/acp',
                ),
              ],
            ),
          ),
          refreshAfterSave: false,
        );

        await controller.refreshSingleAgentCapabilitiesInternal(
          forceRefresh: true,
        );

        expect(
          controller.singleAgentProviderOptions
              .map((item) => item.providerId)
              .toList(growable: false),
          const <String>['opencode'],
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
