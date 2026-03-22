@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  test(
    'SettingsController syncs AI Gateway models with an inline API key override',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = await _FakeAiGatewayServer.start();
      addTearDown(server.close);

      final store = SecureConfigStore();
      final controller = SettingsController(store);
      await controller.initialize();
      await controller.saveSnapshot(
        SettingsSnapshot.defaults().copyWith(
          aiGateway: AiGatewayProfile.defaults().copyWith(
            baseUrl: server.baseUrl,
          ),
        ),
      );

      final result = await controller.syncAiGatewayCatalog(
        controller.snapshot.aiGateway,
        apiKeyOverride: 'live-inline-key',
      );

      expect(server.lastAuthorization, 'Bearer live-inline-key');
      expect(result.availableModels, const <String>[
        'gpt-5.4',
        'o3-mini',
        'claude-3.7',
        'gemini-2.0',
        'deepseek-r1',
        'qwen-max',
      ]);
      expect(result.selectedModels, const <String>[
        'gpt-5.4',
        'o3-mini',
        'claude-3.7',
        'gemini-2.0',
        'deepseek-r1',
      ]);
      expect(controller.snapshot.defaultModel, 'gpt-5.4');
      expect(await store.loadAiGatewayApiKey(), isNull);
    },
  );

  test(
    'SettingsController keeps AI Gateway api key in secure storage while retaining local selected models',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = await _FakeAiGatewayServer.start();
      addTearDown(server.close);

      final store = SecureConfigStore();
      final controller = SettingsController(store);
      await controller.initialize();
      await controller.saveSnapshot(
        SettingsSnapshot.defaults().copyWith(
          aiGateway: AiGatewayProfile.defaults().copyWith(
            baseUrl: server.baseUrl,
            selectedModels: const <String>['gpt-5.4', 'claude-3.7'],
          ),
        ),
      );

      await controller.saveAiGatewayApiKey('stored-inline-key');

      final result = await controller.syncAiGatewayCatalog(
        controller.snapshot.aiGateway,
      );

      expect(server.lastAuthorization, 'Bearer stored-inline-key');
      expect(result.selectedModels, const <String>['gpt-5.4', 'claude-3.7']);
      expect(controller.snapshot.aiGateway.selectedModels, const <String>[
        'gpt-5.4',
        'claude-3.7',
      ]);
      expect(await store.loadAiGatewayApiKey(), 'stored-inline-key');
      expect(controller.snapshot.toJsonString(), isNot(contains('stored-inline-key')));
    },
  );

  test(
    'SettingsController tolerates OpenAI-compatible model payloads with a trailing JSON footer',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = await _FakeAiGatewayServer.start(appendFooterJson: true);
      addTearDown(server.close);

      final store = SecureConfigStore();
      final controller = SettingsController(store);
      await controller.initialize();
      await controller.saveSnapshot(
        SettingsSnapshot.defaults().copyWith(
          aiGateway: AiGatewayProfile.defaults().copyWith(
            baseUrl: server.baseUrl,
          ),
        ),
      );

      final result = await controller.syncAiGatewayCatalog(
        controller.snapshot.aiGateway,
        apiKeyOverride: 'live-inline-key',
      );

      expect(result.syncState, 'ready');
      expect(result.availableModels.first, 'gpt-5.4');
      expect(result.availableModels.last, 'qwen-max');
      expect(await store.loadAiGatewayApiKey(), isNull);
    },
  );

  test(
    'SettingsController tests AI Gateway auth without persisting draft values',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = await _FakeAiGatewayServer.start(
        expectedAuthorization: 'Bearer trusted-inline-key',
      );
      addTearDown(server.close);

      final store = SecureConfigStore();
      final controller = SettingsController(store);
      await controller.initialize();

      final result = await controller.testAiGatewayConnection(
        AiGatewayProfile.defaults().copyWith(baseUrl: server.baseUrl),
        apiKeyOverride: 'trusted-inline-key',
      );

      expect(result.state, 'ready');
      expect(result.message, 'Authenticated · 6 model(s) available');
      expect(result.endpoint, '${server.baseUrl}/models');
      expect(controller.snapshot.aiGateway.baseUrl, '');
      expect(await store.loadAiGatewayApiKey(), isNull);
    },
  );

  test(
    'SettingsController reports AI Gateway auth failures with a detailed message',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = await _FakeAiGatewayServer.start(
        expectedAuthorization: 'Bearer trusted-inline-key',
      );
      addTearDown(server.close);

      final store = SecureConfigStore();
      final controller = SettingsController(store);
      await controller.initialize();

      final result = await controller.testAiGatewayConnection(
        AiGatewayProfile.defaults().copyWith(baseUrl: server.baseUrl),
        apiKeyOverride: 'wrong-key',
      );

      expect(result.state, 'error');
      expect(result.message, 'Authentication failed (401) · invalid_api_key');
      expect(await store.loadAiGatewayApiKey(), isNull);
    },
  );
}

class _FakeAiGatewayServer {
  _FakeAiGatewayServer._(
    this._server,
    this.expectedAuthorization,
    this.appendFooterJson,
  );

  final HttpServer _server;
  final String expectedAuthorization;
  final bool appendFooterJson;
  String? lastAuthorization;

  String get baseUrl => 'http://127.0.0.1:${_server.port}/v1';

  static Future<_FakeAiGatewayServer> start({
    String expectedAuthorization = 'Bearer live-inline-key',
    bool appendFooterJson = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeAiGatewayServer._(
      server,
      expectedAuthorization,
      appendFooterJson,
    );
    unawaited(fake._serve());
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      lastAuthorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      request.response.headers.contentType = ContentType.json;
      if (lastAuthorization != expectedAuthorization) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write(
          jsonEncode(<String, dynamic>{
            'error': <String, dynamic>{'message': 'invalid_api_key'},
          }),
        );
        await request.response.close();
        continue;
      }
      final body = jsonEncode(<String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'gpt-5.4'},
          <String, dynamic>{'id': 'o3-mini'},
          <String, dynamic>{'id': 'claude-3.7'},
          <String, dynamic>{'id': 'gemini-2.0'},
          <String, dynamic>{'id': 'deepseek-r1'},
          <String, dynamic>{'id': 'qwen-max'},
        ],
      });
      request.response.write(
        appendFooterJson ? '$body\n{"Content-Type":"application/json"}' : body,
      );
      await request.response.close();
    }
  }
}
