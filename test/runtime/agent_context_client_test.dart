import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/agent_context_client.dart';

void main() {
  late HttpServer server;
  late List<Map<String, Object?>> seen;
  late Map<String, Object?> Function(HttpRequest request) reply;
  late int replyStatus;

  setUp(() async {
    seen = <Map<String, Object?>>[];
    replyStatus = 200;
    reply = (request) => <String, Object?>{};
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
        ..write(jsonEncode(reply(request)));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  HttpAgentContextClient client({String token = 'test-bridge-token'}) =>
      HttpAgentContextClient(
        bridgeBase: Uri.parse('http://127.0.0.1:${server.port}/bridge/'),
        authToken: token,
      );

  test('fetches task catalog and filters machine-specific absolute paths', () async {
    reply = (request) => <String, Object?>{
      'ok': true,
      'catalog': <String, Object?>{
        'pinnedTasks': <Object?>[
          <String, Object?>{
            'id': 'pin-1',
            'source': 'codex',
            'title': 'Fix regional entrypoint',
            'scope': 'github.com/ai-workspace-service',
            'location': 'dir:ai-workspace-service',
            'projectName': 'ai-workspace-service',
            'gitBranch': 'main',
            'position': 0,
            'updatedAt': '2026-10-22T06:00:00Z',
          },
          <String, Object?>{
            'id': 'pin-2',
            'source': 'codex',
            'title': 'Leaked absolute path task',
            'scope': null,
            'location': '/Users/someone/secret/repo',
            'updatedAt': '2026-10-22T06:00:00Z',
          },
          <String, Object?>{
            'id': 'pin-3',
            'source': 'codex',
            'title': 'Tombstoned task',
            'location': 'dir:old',
            'removedAt': '2026-10-22T05:00:00Z',
          },
        ],
        'sharedProjects': <Object?>[
          <String, Object?>{
            'key': 'dir:ai-workspace-service',
            'name': 'ai-workspace-service',
            'kind': 'directory',
            'sources': <Object?>['codex'],
            'updatedAt': '2026-10-22T06:00:00Z',
          },
          <String, Object?>{
            'key': '/Users/someone/leaked',
            'name': 'leaked',
            'kind': 'directory',
          },
        ],
        'recentThreads': <Object?>[
          <String, Object?>{
            'id': 'thread-1',
            'scope': 'github.com/ai-workspace-service',
            'title': 'Fix regional entrypoint',
            'state': 'open',
            'headBranch': 'feat/entrypoint',
            'fence': 2,
            'updatedAt': '2026-10-22T06:00:00Z',
          },
        ],
        'page': <String, Object?>{
          'limit': 50,
          'offset': 0,
          'pinnedTotal': 2,
          'projectsTotal': 1,
        },
      },
    };

    final api = client();
    final catalog = await api.fetchCatalog(scope: 'github.com/ai-workspace-service');

    expect(catalog.pinnedTasks.length, 2);
    expect(catalog.pinnedTasks[0].id, 'pin-1');
    expect(catalog.pinnedTasks[0].location, 'dir:ai-workspace-service');
    // pin-2 had an absolute path which was sanitized to null
    expect(catalog.pinnedTasks[1].id, 'pin-2');
    expect(catalog.pinnedTasks[1].location, isNull);
    // pin-3 was removedAt, so excluded
    expect(catalog.pinnedTasks.any((p) => p.id == 'pin-3'), isFalse);

    // sharedProjects filtered out absolute path key
    expect(catalog.sharedProjects.length, 1);
    expect(catalog.sharedProjects[0].key, 'dir:ai-workspace-service');

    expect(catalog.recentThreads.single.id, 'thread-1');
    expect(seen.single['path'], '/bridge/api/v1/agent/catalog');
    expect(seen.single['query'], <String, String>{
      'limit': '50',
      'scope': 'github.com/ai-workspace-service',
    });
    expect(seen.single['auth'], 'Bearer test-bridge-token');
  });

  test('lists threads with state and pagination', () async {
    reply = (request) => <String, Object?>{
      'ok': true,
      'threads': <Object?>[
        <String, Object?>{
          'id': 'th-1',
          'scope': 'github.com/ai-workspace-infra/gitops',
          'title': 'feat: refund webhook reconciliation',
          'state': 'open',
          'headBranch': 'bugfix/refund-r12',
          'items': 5,
          'sessions': 2,
          'updatedAt': '2026-10-22T06:00:00Z',
        },
      ],
      'page': <String, Object?>{
        'limit': 20,
        'offset': 10,
        'total': 42,
      },
    };

    final api = client();
    final page = await api.listThreads(state: 'all', limit: 20, offset: 10);

    expect(page.threads.single.id, 'th-1');
    expect(page.threads.single.itemsCount, 5);
    expect(page.threads.single.sessionsCount, 2);
    expect(page.threads.single.displayLabel, 'feat: refund webhook reconciliation');
    expect(page.total, 42);

    expect(seen.single['path'], '/bridge/api/v1/agent/threads');
    expect(seen.single['query'], <String, String>{
      'state': 'all',
      'limit': '20',
      'offset': '10',
    });
  });

  test('fetches briefing and filters out absolute path items', () async {
    reply = (request) => <String, Object?>{
      'ok': true,
      'briefing': <String, Object?>{
        'thread': <String, Object?>{
          'id': 'th-1',
          'scope': 'github.com/ai-workspace-services/portal',
          'title': 'Dedicated console',
          'state': 'open',
        },
        'items': <Object?>[
          <String, Object?>{
            'kind': 'goal',
            'key': 'goal',
            'status': 'active',
            'text': 'Support team dedicated console',
            'sources': <Object?>['codex'],
          },
          <String, Object?>{
            'kind': 'decision',
            'key': 'd1',
            'status': 'active',
            'text': 'Read routes from Bridge',
            'sources': <Object?>['codex'],
          },
          <String, Object?>{
            'kind': 'path',
            'key': 'p1',
            'status': 'active',
            'text': 'lib/app/app_controller.dart',
            'sources': <Object?>['codex'],
          },
          <String, Object?>{
            'kind': 'path',
            'key': 'p2',
            'status': 'active',
            'text': '/Users/shenlan/secrets/token.txt',
            'sources': <Object?>['codex'],
          },
        ],
        'contributors': <Object?>[
          <String, Object?>{
            'source': 'codex',
            'sessions': 3,
            'lastSeenAt': '2026-10-22T06:00:00Z',
          },
        ],
      },
    };

    final api = client();
    final briefing = await api.fetchBriefing('th-1', events: 15);

    expect(briefing.thread.id, 'th-1');
    expect(briefing.contributors.single.source, 'codex');
    // The absolute path item (/Users/...) was filtered out!
    expect(briefing.items.length, 3);
    expect(briefing.items.map((i) => i.kind).toList(), <String>[
      'goal',
      'decision',
      'path',
    ]);
    expect(briefing.items[2].text, 'lib/app/app_controller.dart');
    expect(seen.single['path'], '/bridge/api/v1/agent/threads/th-1/briefing');
    expect(seen.single['query'], <String, String>{'events': '15'});
  });

  test('throws AgentContextException on 401 unauthorized or 503 unavailable', () async {
    replyStatus = 401;
    reply = (_) => <String, Object?>{
      'error': <String, Object?>{
        'code': 'unauthorized',
        'message': 'Token missing or invalid',
      },
    };

    final api = client();
    expect(
      () => api.fetchCatalog(),
      throwsA(
        isA<AgentContextException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.code, 'code', 'unauthorized'),
      ),
    );
  });

  test('strips leading Bearer prefix from authToken constructor argument', () async {
    reply = (_) => <String, Object?>{'ok': true, 'catalog': <String, Object?>{}};
    final api = client(token: 'Bearer my-special-token');
    await api.fetchCatalog();
    expect(seen.single['auth'], 'Bearer my-special-token');
  });
}
