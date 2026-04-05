@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/web/web_session_repository.dart';

void main() {
  test('normalizeBaseUrl requires https for remote hosts', () {
    expect(
      RemoteWebSessionRepository.normalizeBaseUrl(
        'https://xworkmate.svc.plus/api/web-sessions',
      )?.toString(),
      'https://xworkmate.svc.plus/api/web-sessions',
    );
    expect(
      RemoteWebSessionRepository.normalizeBaseUrl(
        'https://xworkmate.svc.plus/api/web-sessions/threads',
      )?.toString(),
      'https://xworkmate.svc.plus/api/web-sessions',
    );
    expect(
      RemoteWebSessionRepository.normalizeBaseUrl(
        'http://xworkmate.svc.plus/api/web-sessions',
      ),
      isNull,
    );
    expect(
      RemoteWebSessionRepository.normalizeBaseUrl(
        'http://127.0.0.1:8787/api/web-sessions',
      )?.toString(),
      'http://127.0.0.1:8787/api/web-sessions',
    );
  });

  test(
    'remote web session repository sends stable headers and payloads',
    () async {
      final requests = <http.BaseRequest>[];
      final bodies = <String>[];
      final records = <TaskThread>[
        TaskThread(
          threadId: 'direct:1',
          workspaceBinding: const WorkspaceBinding(
            workspaceId: 'direct:1',
            workspaceKind: WorkspaceKind.remoteFs,
            workspacePath: '/owners/remote/user/direct/threads/direct:1',
            displayPath: '/owners/remote/user/direct/threads/direct:1',
            writable: true,
          ),
          messages: const <GatewayChatMessage>[
            GatewayChatMessage(
              id: 'm1',
              role: 'user',
              text: 'hello',
              timestampMs: 1,
              toolCallId: null,
              toolName: null,
              stopReason: null,
              pending: false,
              error: false,
            ),
          ],
          updatedAtMs: 1,
          title: 'hello',
          archived: false,
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
        ),
      ];
      final client = MockClient((request) async {
        requests.add(request);
        bodies.add(request.body);
        if (request.method == 'PUT') {
          return http.Response('', 204);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'threads': records
                .map((item) => item.toJson())
                .toList(growable: false),
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final repository = RemoteWebSessionRepository(
        baseUrl: 'https://xworkmate.svc.plus/api/web-sessions',
        clientId: 'browser-client-id',
        accessToken: 'session-token',
        client: client,
      );

      await repository.saveThreadRecords(records);
      final reloaded = await repository.loadThreadRecords();

      expect(requests, hasLength(2));
      expect(requests.first.method, 'PUT');
      expect(
        requests.first.url.toString(),
        'https://xworkmate.svc.plus/api/web-sessions/threads',
      );
      expect(requests.first.headers['authorization'], 'Bearer session-token');
      expect(
        requests.first.headers['x-xworkmate-client-id'],
        'browser-client-id',
      );
      expect(
        (jsonDecode(bodies.first) as Map<String, dynamic>)['threads'],
        hasLength(1),
      );
      expect(requests.last.method, 'GET');
      expect(reloaded, hasLength(1));
      expect(reloaded.first.sessionKey, 'direct:1');
      expect(reloaded.first.messages.single.text, 'hello');
    },
  );
}
