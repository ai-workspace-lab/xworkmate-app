import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/task_session_client.dart';

void main() {
  late HttpServer server;
  late List<Map<String, Object?>> seen;
  late Map<String, Object?> Function(HttpRequest request, String body) reply;
  late int replyStatus;

  setUp(() async {
    seen = <Map<String, Object?>>[];
    replyStatus = 200;
    reply = (request, body) => <String, Object?>{};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      seen.add(<String, Object?>{
        'method': request.method,
        'path': request.uri.path,
        'query': request.uri.queryParameters,
        'auth': request.headers.value(HttpHeaders.authorizationHeader),
        'body': body.isEmpty ? null : jsonDecode(body),
      });
      request.response
        ..statusCode = replyStatus
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(reply(request, body)));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  HttpTaskSessionClient client({String token = 'acct-token'}) =>
      HttpTaskSessionClient(
        bridgeBase: Uri.parse('http://127.0.0.1:${server.port}/bridge/'),
        accountToken: token,
      );

  test('reads the personal namespace and lists sessions under the bridge base path', () async {
    reply = (request, _) => request.uri.path.endsWith('/namespaces')
        ? <String, Object?>{
            'namespaces': <Object?>[
              <String, Object?>{'namespaceId': 'ns-team', 'slug': 'team'},
              <String, Object?>{'namespaceId': 'ns-personal', 'slug': 'personal'},
            ],
          }
        : <String, Object?>{
            'sessions': <Object?>[
              <String, Object?>{
                'sessionId': 's-1',
                'title': 'Fix tests',
                'lastEventSeq': 5,
                'context': <String, Object?>{'lastRunState': 'running'},
              },
            ],
          };
    final api = client();
    expect(await api.personalNamespaceId(), 'ns-personal');
    final sessions = await api.listSessions('ns-personal');
    expect(sessions.single.sessionId, 's-1');
    expect(sessions.single.lastRunState, 'running');
    expect(seen[0]['path'], '/bridge/api/v1/namespaces');
    expect(seen[1]['path'], '/bridge/api/v1/namespaces/ns-personal/sessions');
    expect(seen.every((call) => call['auth'] == 'Bearer acct-token'), isTrue);
  });

  test('appends a message with routing, pages events and cancels a run', () async {
    reply = (request, _) {
      if (request.uri.path.endsWith('/messages')) {
        return <String, Object?>{
          'event': <String, Object?>{'seq': 7},
          'taskRun': <String, Object?>{'id': 'run-1'},
        };
      }
      if (request.uri.path.endsWith('/events')) {
        return <String, Object?>{
          'events': <Object?>[
            <String, Object?>{
              'seq': 8,
              'type': 'run.progressed',
              'payload': <String, Object?>{'taskRunId': 'run-1', 'phase': 'selected'},
            },
          ],
          'lastEventSeq': 8,
        };
      }
      return <String, Object?>{};
    };
    final api = client();
    final receipt = await api.appendMessage(
      sessionId: 's-1',
      clientRequestId: 'req-1',
      text: 'fix it',
      routing: const <String, Object?>{'role': 'engineer', 'roleMode': 'auto', 'workspace': 'repo'},
    );
    expect(receipt.taskRunId, 'run-1');
    expect(receipt.eventSeq, 7);
    final page = await api.listEvents(sessionId: 's-1', afterSeq: 7);
    expect(page.events.single.taskRunId, 'run-1');
    expect(page.lastEventSeq, 8);
    await api.cancelRun(sessionId: 's-1', taskRunId: 'run-1', clientRequestId: 'req-2');

    expect(seen[0]['method'], 'POST');
    expect(seen[0]['path'], '/bridge/api/v1/sessions/s-1/messages');
    expect(seen[0]['body'], <String, Object?>{
      'clientRequestId': 'req-1',
      'text': 'fix it',
      'routing': <String, Object?>{'role': 'engineer', 'roleMode': 'auto', 'workspace': 'repo'},
    });
    expect(seen[1]['query'], <String, String>{'after_seq': '7', 'limit': '100'});
    expect(seen[2]['path'], '/bridge/api/v1/sessions/s-1/runs/run-1/cancel');
    expect(seen[2]['body'], <String, Object?>{'clientRequestId': 'req-2'});
  });

  test('maps the Accounts error envelope and refuses without a token', () async {
    replyStatus = 409;
    reply = (request, _) => <String, Object?>{
      'error': <String, Object?>{'code': 'task_run_finished', 'message': 'task run already finished'},
    };
    await expectLater(
      client().cancelRun(sessionId: 's', taskRunId: 'r', clientRequestId: 'c'),
      throwsA(
        isA<TaskSessionException>()
            .having((e) => e.statusCode, 'status', 409)
            .having((e) => e.code, 'code', 'task_run_finished'),
      ),
    );
    final before = seen.length;
    await expectLater(
      client(token: ' ').personalNamespaceId(),
      throwsA(isA<TaskSessionException>().having((e) => e.code, 'code', 'account_sign_in_required')),
    );
    expect(seen.length, before, reason: 'no request without an account token');
  });

  test('an unreachable service is reported, not thrown raw', () async {
    final port = server.port;
    await server.close(force: true);
    final api = HttpTaskSessionClient(
      bridgeBase: Uri.parse('http://127.0.0.1:$port'),
      accountToken: 't',
      timeout: const Duration(seconds: 2),
    );
    await expectLater(
      api.personalNamespaceId(),
      throwsA(isA<TaskSessionException>().having((e) => e.code, 'code', 'task_session_unreachable')),
    );
  });
}
