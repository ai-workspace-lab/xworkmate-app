import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models_profiles.dart';

import '../test_support.dart';

Future<void> _waitForText(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for ${finder.description}');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('SettingsPage Codex external ACP can test and save', (
    WidgetTester tester,
  ) async {
    final server = await _AcpServer.start();
    addTearDown(server.close);

    final controller = await createTestController(tester);
    await controller.saveSettings(
      controller.settings.copyWith(
        externalAcpEndpoints: <ExternalAcpEndpointProfile>[
          const ExternalAcpEndpointProfile(
            providerKey: 'codex',
            label: 'Codex',
            badge: 'C',
            endpoint: '',
            authRef: '',
            enabled: true,
          ),
          ...controller.settings.externalAcpEndpoints.skip(1),
        ],
      ),
    );

    await pumpPage(
      tester,
      child: SettingsPage(controller: controller, initialTab: SettingsTab.gateway),
    );

    final endpointField = find.byKey(
      const ValueKey<String>('external-acp-endpoint-Codex'),
    );
    final testButton = find.byKey(
      const ValueKey<String>('external-acp-test-Codex'),
    );
    final saveButton = find.byKey(
      const ValueKey<String>('external-acp-save-Codex'),
    );

    expect(endpointField, findsOneWidget);
    await tester.enterText(endpointField, server.baseUri.toString());
    await tester.pump();

    await tester.tap(testButton);
    await tester.pump(const Duration(milliseconds: 100));
    await _waitForText(tester, find.textContaining('连接成功'));

    expect(find.textContaining('连接成功'), findsOneWidget);

    await tester.tap(saveButton);
    await tester.pump();

    final saved = controller.settings.externalAcpEndpointForProviderId('codex');
    expect(saved?.endpoint, server.baseUri.toString());
    expect(server.requestCount, greaterThanOrEqualTo(1));
  });
}

class _AcpServer {
  _AcpServer._(this._server);

  final HttpServer _server;
  int requestCount = 0;

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_AcpServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _AcpServer._(server);
    unawaited(fake._listen());
    return fake;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _listen() async {
    await for (final request in _server) {
      requestCount += 1;
      if (request.uri.path != '/acp/rpc') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final response = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': decoded['id'],
        'result': <String, dynamic>{
          'singleAgent': true,
          'multiAgent': true,
          'providers': <String>['codex'],
        },
      };
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/event-stream; charset=utf-8',
      );
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.response.write('data: ${jsonEncode(response)}\n\n');
      await request.response.flush();
      await request.response.close();
    }
  }
}
