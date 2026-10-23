import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

class _CredentialStore extends SecureConfigStore {
  _CredentialStore() : super(enableSecureStorage: false);
  String? value = 'fixture-self-host';
  bool fail = false;
  final refs = <String>[];
  @override
  Future<String?> loadSecretValueByRef(String refName) async {
    refs.add(refName);
    if (fail) throw StateError('fixture credential read failed');
    return value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppControllerDesktopBotTeam Self-Hosted Fallback Tests', () {
    for (final source in ['bridge', 'cloud', 'default']) {
      test('rejects remote HTTP before reading credentials: $source', () async {
        final store = _CredentialStore();
        final controller = AppController(
          store: store,
          environmentOverride: const {
            'XWORKMATE_MANAGED_BRIDGE_URL': 'http://remote.example.com/team',
            'AI_WORKSPACE_AUTH_TOKEN': 'fixture-environment',
          },
        );
        addTearDown(controller.dispose);
        final settings = controller.settingsControllerInternal;
        if (source == 'cloud') {
          settings.accountSessionTokenInternal = 'fixture-cloud';
        }
        settings.snapshotInternal = settings.snapshot.copyWith(
          acpBridgeServerModeConfig: AcpBridgeServerModeConfig.defaults()
              .copyWith(
                effective: AcpBridgeServerEffectiveConfig(
                  endpoint: source == 'default'
                      ? ''
                      : 'http://remote.example.com/team',
                  source: source,
                  tokenRef: 'self-ref',
                  reason: 'test',
                ),
                selfHosted: source == 'bridge'
                    ? const AcpBridgeServerSelfHostedConfig(
                        serverUrl: 'http://remote.example.com/team',
                        username: 'fixture-user',
                        passwordRef: 'self-ref',
                      )
                    : null,
              ),
        );
        expect(
          await controller.resolveTaskSessionAuthTokenInternal(
            Uri.parse('http://remote.example.com/team'),
          ),
          isNull,
        );
        expect(await controller.resolveTaskSessionClientInternal(), isNull);
        expect(controller.createTaskSessionClient(), isNull);
        expect(store.refs, isEmpty);
      });
    }

    for (final host in ['127.0.0.1', 'localhost', '[::1]']) {
      test(
        'allows explicitly configured self-host HTTP loopback: $host',
        () async {
          final store = _CredentialStore();
          final controller = AppController(
            store: store,
            environmentOverride: const {},
          );
          addTearDown(controller.dispose);
          final endpoint = 'http://$host:8787/team/acp/rpc';
          final settings = controller.settingsControllerInternal;
          settings.snapshotInternal = settings.snapshot.copyWith(
            acpBridgeServerModeConfig: AcpBridgeServerModeConfig.defaults()
                .copyWith(
                  effective: AcpBridgeServerEffectiveConfig(
                    endpoint: endpoint,
                    source: 'bridge',
                    tokenRef: 'self-ref',
                    reason: 'test',
                  ),
                  selfHosted: AcpBridgeServerSelfHostedConfig(
                    serverUrl: endpoint,
                    username: 'fixture-user',
                    passwordRef: 'self-ref',
                  ),
                ),
          );
          expect(
            await controller.resolveTaskSessionAuthTokenInternal(
              Uri.parse(endpoint),
            ),
            'fixture-self-host',
          );
          expect(
            await controller.resolveTaskSessionClientInternal(),
            isNotNull,
          );
        },
      );
    }

    for (final missing in [false, true]) {
      test(
        'explicit self-host uses only its credential (missing=$missing)',
        () async {
          final store = _CredentialStore()
            ..value = missing ? null : 'fixture-self-host';
          final controller = AppController(
            store: store,
            environmentOverride: const {
              'AI_WORKSPACE_AUTH_TOKEN': 'fixture-environment',
            },
          );
          addTearDown(controller.dispose);
          final settings = controller.settingsControllerInternal;
          settings.accountSessionTokenInternal = 'fixture-stale-cloud';
          settings.snapshotInternal = settings.snapshot.copyWith(
            acpBridgeServerModeConfig: AcpBridgeServerModeConfig.defaults()
                .copyWith(
                  effective: const AcpBridgeServerEffectiveConfig(
                    endpoint: 'https://self.example.com/team/acp/rpc',
                    source: 'bridge',
                    tokenRef: 'self-ref',
                    reason: 'test',
                  ),
                  selfHosted: const AcpBridgeServerSelfHostedConfig(
                    serverUrl: 'https://self.example.com/team',
                    username: 'fixture-user',
                    passwordRef: 'self-ref',
                  ),
                ),
          );
          expect(
            await controller.resolveTaskSessionAuthTokenInternal(
              Uri.parse('https://self.example.com/team/acp/rpc'),
            ),
            missing ? isNull : equals('fixture-self-host'),
          );
          expect(store.refs, ['self-ref']);
          expect(controller.createTaskSessionClient(), isNull);
          expect(
            await controller.resolveTaskSessionAuthTokenInternal(
              Uri.parse('https://self.example.com/other'),
            ),
            isNull,
          );
          expect(store.refs, ['self-ref']);
          store.fail = true;
          await expectLater(
            controller.resolveTaskSessionClientInternal(),
            throwsStateError,
          );
        },
      );
    }

    test(
      'explicit cloud without its credential never uses environment',
      () async {
        final controller = AppController(
          environmentOverride: const {
            'AI_WORKSPACE_AUTH_TOKEN': 'fixture-environment',
          },
        );
        addTearDown(controller.dispose);
        final settings = controller.settingsControllerInternal;
        settings.snapshotInternal = settings.snapshot.copyWith(
          acpBridgeServerModeConfig: AcpBridgeServerModeConfig.defaults()
              .copyWith(
                effective: const AcpBridgeServerEffectiveConfig(
                  endpoint: 'https://cloud.example.com',
                  source: 'cloud',
                  tokenRef: '',
                  reason: 'test',
                ),
              ),
        );
        expect(await controller.resolveTaskSessionClientInternal(), isNull);
        expect(controller.createTaskSessionClient(), isNull);
      },
    );
    test(
      'resolveTaskSessionAuthTokenInternal resolves environment token when account token is empty',
      () async {
        final controller = AppController(
          environmentOverride: {
            'XWORKMATE_MANAGED_BRIDGE_URL': 'http://127.0.0.1:8787/acp/rpc',
            'AI_WORKSPACE_AUTH_TOKEN': 'env-ai-workspace-token-123',
          },
        );

        final endpoint = Uri.parse('http://127.0.0.1:8787/acp/rpc');
        final resolvedToken = await controller
            .resolveTaskSessionAuthTokenInternal(endpoint);
        expect(resolvedToken, equals('env-ai-workspace-token-123'));

        final client = controller.createTaskSessionClient();
        expect(client, isNotNull);
      },
    );

    test(
      'createTaskSessionClient supports ACP_BRIDGE_SERVER_TOKEN fallback',
      () {
        final controller = AppController(
          environmentOverride: {
            'XWORKMATE_MANAGED_BRIDGE_URL': 'http://127.0.0.1:8787/acp/rpc',
            'ACP_BRIDGE_SERVER_TOKEN': 'bridge-server-secret-key',
          },
        );

        final client = controller.createTaskSessionClient();
        expect(client, isNotNull);
      },
    );
  });
}
