import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  test(
    'SkillsController loads OpenClaw skills through bridge request without legacy gateway connect',
    () async {
      final observedMethods = <String>[];
      final observedGatewayRequests = <Map<String, dynamic>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final rpc = jsonDecode(body) as Map<String, dynamic>;
        final method = rpc['method']?.toString().trim() ?? '';
        observedMethods.add(method);
        request.response.headers.contentType = ContentType.json;

        if (method == 'xworkmate.gateway.request') {
          final params = (rpc['params'] as Map).cast<String, dynamic>();
          observedGatewayRequests.add(params);
          request.response.write(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': rpc['id'],
              'result': <String, dynamic>{
                'ok': true,
                'payload': <String, dynamic>{
                  'workspaceDir': '/home/ubuntu/.openclaw/workspace',
                  'managedSkillsDir': '/home/ubuntu/.openclaw/skills',
                  'agentId': 'main',
                  'agentSkillFilter': <String>['it-infra-continuous-png'],
                  'skills': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'name': 'it-infra-continuous-png',
                      'description': 'Generate infrastructure PNGs.',
                      'source': 'openclaw-workspace',
                      'skillKey': 'it-infra-continuous-png',
                      'eligible': true,
                      'disabled': false,
                      'blockedByAgentFilter': false,
                      'modelVisible': true,
                      'commandVisible': true,
                      'missing': <String, dynamic>{
                        'bins': <String>[],
                        'env': <String>[],
                        'config': <String>[],
                      },
                    },
                    <String, dynamic>{
                      'name': 'blocked-for-agent',
                      'description': 'Visible in status, hidden from model.',
                      'source': 'openclaw-workspace',
                      'skillKey': 'blocked-for-agent',
                      'eligible': true,
                      'disabled': false,
                      'blockedByAgentFilter': true,
                      'modelVisible': false,
                      'commandVisible': false,
                      'missing': <String, dynamic>{
                        'bins': <String>[],
                        'env': <String>[],
                        'config': <String>[],
                      },
                    },
                  ],
                },
              },
            }),
          );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(
          jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': rpc['id'],
            'error': <String, dynamic>{
              'code': -32601,
              'message': 'unexpected method: $method',
            },
          }),
        );
        await request.response.close();
      });

      final tempDir = await Directory.systemTemp.createTemp(
        'xworkmate-bridge-skills-test-',
      );
      final store = SecureConfigStore(
        enableSecureStorage: false,
        appDataRootPathResolver: () async => '${tempDir.path}/settings.sqlite3',
        secretRootPathResolver: () async => tempDir.path,
      );
      final acpClient = GatewayAcpClient(
        endpointResolver: () => Uri.parse('http://127.0.0.1:${server.port}'),
        authorizationResolver: (_) async => 'bridge-token',
      );
      final identityStore = DeviceIdentityStore(store);
      final runtime = GatewayRuntime(
        store: store,
        identityStore: identityStore,
        sessionClient: GatewayAcpRuntimeSessionClient(client: acpClient),
      );
      await runtime.initialize();
      addTearDown(() async {
        runtime.dispose();
        await subscription.cancel();
        await server.close(force: true);
        await tempDir.delete(recursive: true);
      });

      final directConnectParams = await runtime.buildConnectParamsInternal(
        runtime,
        profile: GatewayConnectionProfile.defaults(),
        identity: await identityStore.loadOrCreate(),
        nonce: 'nonce',
        authToken: 'bridge-token',
        authDeviceToken: '',
        authPassword: '',
      );
      expect(directConnectParams['minProtocol'], kGatewayProtocolVersion);
      expect(directConnectParams['maxProtocol'], kGatewayProtocolVersion);

      final controller = SkillsController(runtime);
      await controller.refresh(agentId: 'main');

      expect(observedMethods, const <String>['xworkmate.gateway.request']);
      expect(observedGatewayRequests.single['method'], 'skills.status');
      expect(
        (observedGatewayRequests.single['params'] as Map)['agentId'],
        'main',
      );
      expect(controller.items, hasLength(2));
      expect(controller.items.map((item) => item.skillKey), const <String>[
        'it-infra-continuous-png',
        'blocked-for-agent',
      ]);
      expect(controller.items.first.eligible, isTrue);
    },
  );

  test(
    'SkillsController keeps bridge skill payload when OpenClaw gateway is offline',
    () async {
      final observedGatewayRequests = <Map<String, dynamic>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final rpc = jsonDecode(body) as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;

        if (rpc['method'] == 'xworkmate.gateway.request') {
          final params = (rpc['params'] as Map).cast<String, dynamic>();
          observedGatewayRequests.add(params);
          request.response.write(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': rpc['id'],
              'result': <String, dynamic>{
                'ok': false,
                'error': <String, dynamic>{
                  'code': 'OFFLINE',
                  'message': 'gateway not connected',
                },
                'payload': <String, dynamic>{
                  'skills': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'name': 'PDF Writer',
                      'description': 'Write PDF documents',
                      'source': 'openclaw-workspace',
                      'skillKey': 'pdf',
                      'eligible': false,
                      'disabled': false,
                      'missing': <String, dynamic>{
                        'bins': <String>[],
                        'env': <String>[],
                        'config': <String>[],
                      },
                    },
                  ],
                },
              },
            }),
          );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });

      final tempDir = await Directory.systemTemp.createTemp(
        'xworkmate-bridge-skills-offline-test-',
      );
      final store = SecureConfigStore(
        enableSecureStorage: false,
        appDataRootPathResolver: () async => '${tempDir.path}/settings.sqlite3',
        secretRootPathResolver: () async => tempDir.path,
      );
      final acpClient = GatewayAcpClient(
        endpointResolver: () => Uri.parse('http://127.0.0.1:${server.port}'),
        authorizationResolver: (_) async => 'bridge-token',
      );
      final runtime = GatewayRuntime(
        store: store,
        identityStore: DeviceIdentityStore(store),
        sessionClient: GatewayAcpRuntimeSessionClient(client: acpClient),
      );
      await runtime.initialize();
      addTearDown(() async {
        runtime.dispose();
        await subscription.cancel();
        await server.close(force: true);
        await tempDir.delete(recursive: true);
      });

      final controller = SkillsController(runtime);
      await controller.refresh(agentId: 'main');

      expect(observedGatewayRequests.single['method'], 'skills.status');
      expect(controller.error, isNull);
      expect(controller.items.map((item) => item.skillKey), const <String>[
        'pdf',
      ]);
      expect(controller.items.single.eligible, isFalse);
    },
  );

  test(
    'GatewayRuntime loads skills from nested bridge status payload',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final rpc = jsonDecode(body) as Map<String, dynamic>;
        final method = rpc['method']?.toString().trim() ?? '';
        request.response.headers.contentType = ContentType.json;

        if (method == 'xworkmate.gateway.connect') {
          request.response.write(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': rpc['id'],
              'result': <String, dynamic>{
                'ok': true,
                'snapshot': <String, dynamic>{
                  'status': 'connected',
                  'mode': 'remote',
                  'statusText': 'Connected',
                  'mainSessionKey': 'main',
                },
                'auth': <String, dynamic>{'role': 'operator'},
                'returnedDeviceToken': '',
              },
            }),
          );
          await request.response.close();
          return;
        }

        if (method == 'xworkmate.gateway.request') {
          request.response.write(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': rpc['id'],
              'result': <String, dynamic>{
                'ok': true,
                'payload': <String, dynamic>{
                  'status': <String, dynamic>{
                    'workspaceDir': '/home/ubuntu/.openclaw/workspace',
                    'managedSkillsDir': '/home/ubuntu/.openclaw/skills',
                    'skills': <Map<String, dynamic>>[
                      <String, dynamic>{
                        'name': 'Browser Automation',
                        'description': 'Drive browser workflows.',
                        'source': 'agent',
                        'id': 'browser-automation',
                        'eligible': true,
                        'disabled': false,
                        'missingBins': <String>[],
                        'missingEnv': <String>[],
                        'missingConfig': <String>[],
                      },
                    ],
                  },
                },
              },
            }),
          );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });

      final tempDir = await Directory.systemTemp.createTemp(
        'xworkmate-bridge-skills-nested-test-',
      );
      final store = SecureConfigStore(
        enableSecureStorage: false,
        appDataRootPathResolver: () async => '${tempDir.path}/settings.sqlite3',
        secretRootPathResolver: () async => tempDir.path,
      );
      final acpClient = GatewayAcpClient(
        endpointResolver: () => Uri.parse('http://127.0.0.1:${server.port}'),
        authorizationResolver: (_) async => 'bridge-token',
      );
      final identityStore = DeviceIdentityStore(store);
      final runtime = GatewayRuntime(
        store: store,
        identityStore: identityStore,
        sessionClient: GatewayAcpRuntimeSessionClient(client: acpClient),
      );
      await runtime.initialize();
      addTearDown(() async {
        runtime.dispose();
        await subscription.cancel();
        await server.close(force: true);
        await tempDir.delete(recursive: true);
      });

      final controller = SkillsController(runtime);
      await controller.refresh(agentId: 'main');

      expect(controller.error, isNull);
      expect(controller.items, hasLength(1));
      expect(controller.items.single.skillKey, 'browser-automation');
      expect(controller.items.single.missingBins, isEmpty);
    },
  );
}
