import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'app_controller_assistant_flow_suite.dart' as support;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'AppController resolves a bridge verification code through accounts and bridge before connecting',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final gateway = await support.FakeGatewayServerSupport.start();
        final accountServer = await _BridgeFakeAccountServer.start();
        final bridgeServer = await _BridgeFakeBootstrapServer.start(
          gatewayPort: gateway.port,
        );
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-bridge-bootstrap-flow-',
        );
        addTearDown(() async {
          if (await tempDirectory.exists()) {
            await tempDirectory.delete(recursive: true);
          }
        });
        final store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => '${tempDirectory.path}/settings.db',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final controller = AppController(
          store: store,
          goTaskServiceClient: support.FakeGoTaskServiceClientSupport(
            onExecute: gateway.recordGoCoreTurn,
          ),
        );
        addTearDown(controller.dispose);
        addTearDown(gateway.close);
        addTearDown(accountServer.close);
        addTearDown(bridgeServer.close);

        await _waitFor(() => !controller.initializing);
        await controller.storeInternal.saveAccountSessionToken(
          _BridgeFakeAccountServer.sessionToken,
        );
        await controller.saveSettings(
          controller.settings.copyWith(
            accountBaseUrl: accountServer.baseUrl,
            workspacePath: tempDirectory.path,
          ),
          refreshAfterSave: false,
        );

        await controller.connectWithSetupCode(
          setupCode: _BridgeFakeAccountServer.shortCode,
        );

        expect(
          accountServer.lastLookupCode,
          _BridgeFakeAccountServer.shortCode,
        );
        expect(
          bridgeServer.lastConsumedTicket,
          _BridgeFakeAccountServer.ticketId,
        );
        expect(controller.connection.status, RuntimeConnectionStatus.connected);
        expect(controller.connection.mode, RuntimeConnectionMode.local);
        expect(
          gateway.connectAuthToken,
          _BridgeFakeBootstrapServer.exchangeToken,
        );
        expect(
          controller.settings.primaryLocalGatewayProfile.host,
          '127.0.0.1',
        );
        expect(
          await controller.settingsController.loadGatewayToken(),
          _BridgeFakeBootstrapServer.exchangeToken,
        );
      }, _BridgeRealHttpOverrides());
    },
  );
}

class _BridgeRealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 10),
  Duration pollInterval = const Duration(milliseconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met before timeout.');
    }
    await Future<void>.delayed(pollInterval);
  }
}

class _BridgeFakeAccountServer {
  _BridgeFakeAccountServer._(this._server);

  static const sessionToken = 'account-session-token';
  static const shortCode = 'AB12CD34';
  static const ticketId = 'ticket-123';

  final HttpServer _server;
  String? lastLookupCode;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  static Future<_BridgeFakeAccountServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _BridgeFakeAccountServer._(server);
    unawaited(fake._serve());
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      if (request.method == 'GET' &&
          request.uri.path ==
              '/api/auth/xworkmate/bridge/bootstrap/$shortCode') {
        lastLookupCode = shortCode;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'ticket': ticketId,
            'shortCode': shortCode,
            'bridge': _BridgeFakeBootstrapServer.currentBridgeOrigin,
            'scheme': 'xworkmate-bridge-bootstrap',
            'expiresAt': '2026-04-10T00:00:00Z',
            'scopes': const <String>['connect', 'pairing.bootstrap'],
            'oneTime': true,
            'qrPayload':
                '{"scheme":"xworkmate-bridge-bootstrap","ticket":"$ticketId","bridge":"${_BridgeFakeBootstrapServer.currentBridgeOrigin}"}',
          }),
        );
        await request.response.close();
        continue;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }
}

class _BridgeFakeBootstrapServer {
  _BridgeFakeBootstrapServer._(this._server, this.gatewayPort);

  static const exchangeToken = 'bridge-exchange-token';
  static String currentBridgeOrigin = '';

  final HttpServer _server;
  final int gatewayPort;
  String? lastConsumedTicket;

  static Future<_BridgeFakeBootstrapServer> start({
    required int gatewayPort,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _BridgeFakeBootstrapServer._(server, gatewayPort);
    currentBridgeOrigin = 'http://127.0.0.1:${server.port}';
    unawaited(fake._serve());
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      if (request.method == 'POST' &&
          request.uri.path == '/bridge/bootstrap/consume') {
        final body = await utf8.decoder.bind(request).join();
        final payload = (jsonDecode(body) as Map).cast<String, dynamic>();
        lastConsumedTicket = payload['ticket']?.toString();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'setupCode': jsonEncode(<String, Object?>{
              'url': 'ws://127.0.0.1:$gatewayPort',
              'token': exchangeToken,
              'exchangeToken': exchangeToken,
              'authMode': 'shared-token',
              'bridgeOrigin': currentBridgeOrigin,
              'issuedBy': 'xworkmate-bridge',
            }),
            'bridgeOrigin': currentBridgeOrigin,
            'authMode': 'shared-token',
            'expiresAt': '2026-04-10T00:00:00Z',
            'issuedBy': 'xworkmate-bridge',
          }),
        );
        await request.response.close();
        continue;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }
}
