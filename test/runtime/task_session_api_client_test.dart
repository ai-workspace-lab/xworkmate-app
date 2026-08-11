import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/task_session_api_client.dart';

void main() {
  group('TaskSessionApiClient', () {
    test('creates a session inside the namespace resource', () async {
      final transport = _QueueTransport(<TaskSessionHttpResponse>[
        _jsonResponse(<String, Object?>{
          'sessionId': 'session-1',
          'namespaceId': 'namespace-1',
          'title': 'Shared task',
          'snapshotVersion': 1,
          'lastEventSeq': 0,
          'lifecycleState': 'ready',
          'context': <String, Object?>{},
        }, statusCode: 201),
      ]);
      final client = TaskSessionApiClient(
        baseUri: Uri.parse('https://bridge.example.test'),
        transport: transport,
      );

      final snapshot = await client.createSession(
        namespaceId: 'namespace-1',
        title: 'Shared task',
      );

      expect(snapshot.sessionId, 'session-1');
      expect(snapshot.snapshotVersion, 1);
      final request = transport.requests.single;
      expect(request.method, TaskSessionHttpMethod.post);
      expect(
        request.uri.toString(),
        'https://bridge.example.test/api/v1/namespaces/namespace-1/sessions',
      );
      expect(jsonDecode(request.body!), <String, Object?>{
        'title': 'Shared task',
      });
      expect(request.headers['Authorization'], isNull);
    });

    test('loads an exact session snapshot without envelope fallback', () async {
      final transport = _QueueTransport(<TaskSessionHttpResponse>[
        _jsonResponse(<String, Object?>{
          'sessionId': 'session/with space',
          'namespaceId': 'namespace-1',
          'title': 'Shared task',
          'snapshotVersion': 7,
          'lastEventSeq': 12,
          'lifecycleState': 'running',
          'context': <String, Object?>{'summary': 'authoritative'},
        }),
      ]);
      final client = TaskSessionApiClient(
        baseUri: Uri.parse('https://bridge.example.test/base-is-ignored'),
        transport: transport,
      );

      final snapshot = await client.loadSnapshot('session/with space');

      expect(snapshot.lastEventSeq, 12);
      expect(snapshot.context['summary'], 'authoritative');
      expect(transport.requests.single.uri.pathSegments, <String>[
        'api',
        'v1',
        'sessions',
        'session/with space',
      ]);
    });

    test('rejects response envelopes outside the frozen contract', () async {
      final transport = _QueueTransport(<TaskSessionHttpResponse>[
        _jsonResponse(<String, Object?>{
          'data': <String, Object?>{
            'sessionId': 'session-1',
            'namespaceId': 'namespace-1',
            'snapshotVersion': 1,
            'lastEventSeq': 0,
            'lifecycleState': 'ready',
          },
        }),
      ]);
      final client = TaskSessionApiClient(
        baseUri: Uri.parse('https://bridge.example.test'),
        transport: transport,
      );

      await expectLater(
        client.loadSnapshot('session-1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('requests ordered events after the supplied server cursor', () async {
      final transport = _QueueTransport(<TaskSessionHttpResponse>[
        _jsonResponse(<String, Object?>{
          'events': <Object?>[
            <String, Object?>{
              'seq': 4,
              'type': 'message.created',
              'payload': <String, Object?>{'text': 'hello'},
              'createdAt': '2026-08-11T02:00:00Z',
            },
          ],
        }),
      ]);
      final client = TaskSessionApiClient(
        baseUri: Uri.parse('https://bridge.example.test'),
        transport: transport,
      );

      final events = await client.loadEvents(
        'session-1',
        afterSeq: 3,
        limit: 50,
      );

      expect(events.single.seq, 4);
      expect(events.single.createdAt, DateTime.utc(2026, 8, 11, 2));
      expect(
        transport.requests.single.uri.toString(),
        'https://bridge.example.test/api/v1/sessions/session-1/events'
        '?after_seq=3&limit=50',
      );
    });

    test('posts a message and decodes the nested event and task run', () async {
      final transport = _QueueTransport(<TaskSessionHttpResponse>[
        _jsonResponse(<String, Object?>{
          'sessionId': 'session-1',
          'namespaceId': 'namespace-1',
          'snapshotVersion': 8,
          'event': <String, Object?>{
            'seq': 13,
            'type': 'message.created',
            'payload': <String, Object?>{'text': 'continue'},
            'createdAt': '2026-08-11T02:01:00Z',
          },
          'taskRun': <String, Object?>{'id': 'run-1', 'state': 'queued'},
        }, statusCode: 201),
      ]);
      final client = TaskSessionApiClient(
        baseUri: Uri.parse('https://bridge.example.test'),
        transport: transport,
      );

      final receipt = await client.sendMessage(
        sessionId: 'session-1',
        clientRequestId: 'device-1:message-9',
        text: 'continue',
        run: TaskSessionRunRequest(
          priority: 3,
          notBefore: DateTime.utc(2026, 8, 11, 3),
        ),
      );

      expect(receipt.event.seq, 13);
      expect(receipt.taskRun.id, 'run-1');
      expect(receipt.snapshotVersion, 8);
      expect(
        transport.requests.single.uri.path,
        '/api/v1/sessions/session-1/messages',
      );
      expect(jsonDecode(transport.requests.single.body!), <String, Object?>{
        'clientRequestId': 'device-1:message-9',
        'text': 'continue',
        'run': <String, Object?>{
          'priority': 3,
          'notBefore': '2026-08-11T03:00:00.000Z',
        },
      });
    });

    test(
      'reports structured HTTP failures without including raw body',
      () async {
        final transport = _QueueTransport(<TaskSessionHttpResponse>[
          const TaskSessionHttpResponse(
            statusCode: 403,
            body:
                '{"error":"session_forbidden","message":"denied",'
                '"token":"must-not-surface"}',
          ),
        ]);
        final client = TaskSessionApiClient(
          baseUri: Uri.parse('https://bridge.example.test'),
          transport: transport,
        );

        await expectLater(
          client.loadSnapshot('session-1'),
          throwsA(
            isA<TaskSessionApiException>()
                .having((error) => error.statusCode, 'statusCode', 403)
                .having((error) => error.code, 'code', 'session_forbidden')
                .having(
                  (error) => error.toString(),
                  'redacted string',
                  isNot(contains('must-not-surface')),
                ),
          ),
        );
      },
    );

    test('rejects non-TLS remote Bridge origins', () {
      expect(
        () => TaskSessionApiClient(
          baseUri: Uri.parse('http://bridge.example.test'),
          transport: _QueueTransport(<TaskSessionHttpResponse>[]),
        ),
        throwsArgumentError,
      );
    });
  });
}

TaskSessionHttpResponse _jsonResponse(
  Map<String, Object?> body, {
  int statusCode = 200,
}) => TaskSessionHttpResponse(statusCode: statusCode, body: jsonEncode(body));

class _QueueTransport implements TaskSessionHttpTransport {
  _QueueTransport(this.responses);

  final List<TaskSessionHttpResponse> responses;
  final List<TaskSessionHttpRequest> requests = <TaskSessionHttpRequest>[];

  @override
  Future<TaskSessionHttpResponse> send(TaskSessionHttpRequest request) async {
    requests.add(request);
    return responses.removeAt(0);
  }
}
