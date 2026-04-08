import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/assistant/assistant_page.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

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
  testWidgets(
    'AssistantPage single agent can be selected and receive streaming reply',
    (WidgetTester tester) async {
      final server = await _ChatServer.start();
      addTearDown(server.close);

      final controller = await createTestController(tester);
      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            baseUrl: server.baseUri.toString(),
            availableModels: const <String>['codex-chat'],
            selectedModels: const <String>['codex-chat'],
          ),
          defaultModel: 'codex-chat',
        ),
      );
      await controller.settingsController.saveAiGatewayApiKey('test-key');
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      );

      final targetButton = find.byKey(
        const ValueKey<String>('assistant-execution-target-button'),
      );
      await tester.tap(targetButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('单机智能体').last);
      await tester.pumpAndSettle();

      expect(find.text('单机智能体'), findsWidgets);

      await tester.enterText(
        find.byKey(const ValueKey<String>('assistant-composer-input-area')),
        'hello codex',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('assistant-submit-button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await _waitForText(tester, find.textContaining('CODEX_REPLY'));

      expect(find.textContaining('CODEX_REPLY'), findsWidgets);
      expect(server.requestCount, greaterThanOrEqualTo(1));
      expect(controller.chatMessages.any((m) => m.text.contains('hello codex')),
          isTrue);
    },
  );
}

class _ChatServer {
  _ChatServer._(this._server);

  final HttpServer _server;
  int requestCount = 0;

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_ChatServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _ChatServer._(server);
    unawaited(fake._listen());
    return fake;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _listen() async {
    await for (final request in _server) {
      requestCount += 1;
      if (request.uri.path != '/v1/chat/completions') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      final response = <String, dynamic>{
        'id': 'chatcmpl-test',
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'index': 0,
            'delta': <String, dynamic>{'content': 'CODEX_REPLY'},
            'finish_reason': 'stop',
          },
        ],
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
