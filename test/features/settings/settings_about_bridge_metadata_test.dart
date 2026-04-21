import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/settings_page_core.dart';

void main() {
  group('settings about bridge metadata', () {
    test('loads bridge metadata with bearer authorization', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      late Map<String, String> requestHeaders;
      server.listen((request) async {
        requestHeaders = {
          'authorization':
              request.headers.value(HttpHeaders.authorizationHeader) ?? '',
          'accept': request.headers.value(HttpHeaders.acceptHeader) ?? '',
        };
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, dynamic>{
              'status': 'ok',
              'version': '991ecb0',
              'commit': '991ecb0',
              'image': 'ghcr.io/x-evor/xworkmate-bridge:991ecb0',
              'buildDate': '2026-04-21',
            }),
          );
        await request.response.close();
      });

      final metadata = await loadBridgeMetadataForSettingsAbout(
        bridgeEndpoint: Uri.parse(
          'http://${server.address.address}:${server.port}',
        ),
        authorizationResolver: (_) async => 'bridge-token',
      );

      expect(requestHeaders['authorization'], 'Bearer bridge-token');
      expect(requestHeaders['accept'], 'application/json');
      expect(metadata['status'], 'ok');
      expect(metadata['version'], '991ecb0');
      expect(metadata['commit'], '991ecb0');
      expect(metadata['image'], 'ghcr.io/x-evor/xworkmate-bridge:991ecb0');
      expect(metadata['buildDate'], '2026-04-21');
    });

    test('returns unavailable when bridge authorization is missing', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      var receivedRequest = false;
      server.listen((request) async {
        receivedRequest = true;
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });

      final metadata = await loadBridgeMetadataForSettingsAbout(
        bridgeEndpoint: Uri.parse(
          'http://${server.address.address}:${server.port}',
        ),
        authorizationResolver: (_) async => null,
      );

      expect(receivedRequest, isFalse);
      expect(metadata['status'], 'unavailable');
      expect(metadata['version'], '');
      expect(metadata['commit'], '');
      expect(metadata['image'], '');
      expect(metadata['buildDate'], '');
    });

    test('returns unavailable when authorized bridge ping fails', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
      });

      final metadata = await loadBridgeMetadataForSettingsAbout(
        bridgeEndpoint: Uri.parse(
          'http://${server.address.address}:${server.port}',
        ),
        authorizationResolver: (_) async => 'bridge-token',
      );

      expect(metadata['status'], 'unavailable');
      expect(metadata['version'], '');
      expect(metadata['commit'], '');
      expect(metadata['image'], '');
      expect(metadata['buildDate'], '');
    });
  });
}
