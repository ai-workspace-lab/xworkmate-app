import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/external_code_agent_acp_desktop_transport.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  group('GoTaskService ACP response parsing', () {
    test('uses direct bridge output text', () {
      final result = goTaskServiceResultFromAcpResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'request-id',
        'result': <String, dynamic>{
          'success': true,
          'output': 'direct response',
        },
      }, route: GoTaskServiceRoute.externalAcpSingle);

      expect(result.success, isTrue);
      expect(result.message, 'direct response');
    });

    test('uses nested provider result output text', () {
      final result = goTaskServiceResultFromAcpResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'request-id',
        'result': <String, dynamic>{
          'success': true,
          'result': <String, dynamic>{
            'success': true,
            'output': 'nested provider response',
          },
        },
      }, route: GoTaskServiceRoute.externalAcpSingle);

      expect(result.success, isTrue);
      expect(result.message, 'nested provider response');
    });

    test('uses output content list text', () {
      final result = goTaskServiceResultFromAcpResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'request-id',
        'result': <String, dynamic>{
          'success': true,
          'payload': <String, dynamic>{
            'output': <Map<String, dynamic>>[
              <String, dynamic>{
                'content': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'type': 'output_text',
                    'text': 'content list response',
                  },
                ],
              },
            ],
          },
        },
      }, route: GoTaskServiceRoute.externalAcpSingle);

      expect(result.success, isTrue);
      expect(result.message, 'content list response');
    });

    test('uses bridge failure text instead of empty output fallback', () {
      final result = goTaskServiceResultFromAcpResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'request-id',
        'result': <String, dynamic>{
          'success': false,
          'error': 'codex returned no displayable output',
        },
      }, route: GoTaskServiceRoute.externalAcpSingle);

      expect(result.success, isFalse);
      expect(result.message, 'codex returned no displayable output');
      expect(result.errorMessage, 'codex returned no displayable output');
    });

    test('uses bridge failure message when error field is absent', () {
      final result = goTaskServiceResultFromAcpResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'request-id',
        'result': <String, dynamic>{
          'success': false,
          'message': 'OpenClaw gateway returned artifact_missing',
        },
      }, route: GoTaskServiceRoute.externalAcpSingle);

      expect(result.success, isFalse);
      expect(result.message, 'OpenClaw gateway returned artifact_missing');
      expect(result.errorMessage, 'OpenClaw gateway returned artifact_missing');
    });

    test('uses unavailable message when bridge reports provider failure', () {
      final result = goTaskServiceResultFromAcpResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'request-id',
        'result': <String, dynamic>{
          'success': false,
          'unavailableMessage': 'codex execution environment is unavailable',
        },
      }, route: GoTaskServiceRoute.externalAcpSingle);

      expect(result.success, isFalse);
      expect(result.message, 'codex execution environment is unavailable');
      expect(result.errorMessage, 'codex execution environment is unavailable');
    });

    test('keeps provider failure diagnostics for empty upstream output', () {
      final result = goTaskServiceResultFromAcpResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'request-id',
        'result': <String, dynamic>{
          'success': false,
          'provider': 'hermes',
          'error': 'hermes upstream returned empty response',
          'unavailableCode': 'PROVIDER_EMPTY_RESPONSE',
          'upstreamMethod': 'session/prompt',
        },
      }, route: GoTaskServiceRoute.externalAcpSingle);

      expect(result.success, isFalse);
      expect(
        result.message,
        'hermes upstream returned empty response (code: PROVIDER_EMPTY_RESPONSE, upstream: session/prompt)',
      );
      expect(
        result.errorMessage,
        'hermes upstream returned empty response (code: PROVIDER_EMPTY_RESPONSE, upstream: session/prompt)',
      );
    });

    test('keeps bridge message and inline artifacts together', () {
      final result = goTaskServiceResultFromAcpResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'request-id',
        'result': <String, dynamic>{
          'success': true,
          'message': 'hello',
          'artifacts': <Map<String, dynamic>>[
            <String, dynamic>{
              'relativePath': 'notes/hello.txt',
              'content': 'artifact body',
              'contentType': 'text/plain',
            },
          ],
        },
      }, route: GoTaskServiceRoute.externalAcpSingle);

      expect(result.success, isTrue);
      expect(result.message, 'hello');
      expect(result.artifacts, hasLength(1));
      expect(result.artifacts.single.relativePath, 'notes/hello.txt');
      expect(result.artifacts.single.content, 'artifact body');
    });

    test('uses nested bridge inline artifacts when provider wraps payload', () {
      final result = goTaskServiceResultFromAcpResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'request-id',
        'result': <String, dynamic>{
          'success': true,
          'payload': <String, dynamic>{
            'message': 'hello',
            'artifacts': <Map<String, dynamic>>[
              <String, dynamic>{
                'relativePath': 'hello.txt',
                'content': 'nested artifact body',
              },
            ],
          },
        },
      }, route: GoTaskServiceRoute.externalAcpSingle);

      expect(result.message, 'hello');
      expect(result.artifacts, hasLength(1));
      expect(result.artifacts.single.relativePath, 'hello.txt');
      expect(result.artifacts.single.content, 'nested artifact body');
    });

    test('uses bridge artifact record items as artifacts', () {
      final result = goTaskServiceResultFromAcpResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'request-id',
        'result': <String, dynamic>{
          'success': true,
          'message': 'created from snapshot record',
          'artifacts': <String, dynamic>{
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'relativePath': 'exports/report.md',
                'content': 'snapshot artifact body',
                'contentType': 'text/markdown',
              },
            ],
          },
        },
      }, route: GoTaskServiceRoute.externalAcpSingle);

      expect(result.message, 'created from snapshot record');
      expect(result.artifacts, hasLength(1));
      expect(result.artifacts.single.relativePath, 'exports/report.md');
      expect(result.artifacts.single.content, 'snapshot artifact body');
    });

    test('uses bridge files and attachments aliases as artifacts', () {
      final result = goTaskServiceResultFromAcpResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'request-id',
        'result': <String, dynamic>{
          'success': true,
          'message': 'created files',
          'payload': <String, dynamic>{
            'files': <Map<String, dynamic>>[
              <String, dynamic>{
                'path': 'reports/summary.pdf',
                'downloadUrl':
                    'https://xworkmate-bridge.svc.plus/artifacts/summary.pdf',
                'contentType': 'application/pdf',
              },
            ],
          },
          'data': <String, dynamic>{
            'attachments': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'deck.pptx',
                'content': 'pptx-body',
                'contentType':
                    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
              },
            ],
          },
        },
      }, route: GoTaskServiceRoute.externalAcpSingle);

      expect(result.message, 'created files');
      expect(
        result.artifacts.map((item) => item.relativePath),
        containsAll(<String>['reports/summary.pdf', 'deck.pptx']),
      );
      expect(
        result.artifacts
            .singleWhere((item) => item.relativePath == 'reports/summary.pdf')
            .downloadUrl,
        'https://xworkmate-bridge.svc.plus/artifacts/summary.pdf',
      );
    });

    test('uses OpenClaw finalArtifacts as required deliverables', () {
      final result = goTaskServiceResultFromAcpResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'request-id',
        'result': <String, dynamic>{
          'success': true,
          'message': 'created final deliverable',
          'finalArtifacts': <Map<String, dynamic>>[
            <String, dynamic>{
              'relativePath': 'exports/final.pdf',
              'downloadUrl':
                  'https://xworkmate-bridge.svc.plus/artifacts/final.pdf',
              'contentType': 'application/pdf',
            },
          ],
        },
      }, route: GoTaskServiceRoute.externalAcpSingle);

      expect(result.success, isTrue);
      expect(result.artifacts, hasLength(1));
      expect(result.artifacts.single.relativePath, 'exports/final.pdf');
      expect(
        result.artifacts.single.downloadUrl,
        'https://xworkmate-bridge.svc.plus/artifacts/final.pdf',
      );
    });
  });

  group('GatewayAcpClient authorization', () {
    test('normalizes raw resolver token into bearer header for HTTP', () async {
      final capture = await _startAcpHttpServer();
      addTearDown(capture.close);

      final client = GatewayAcpClient(
        endpointResolver: () => capture.baseEndpoint,
        authorizationResolver: (_) async => 'bridge-token',
      );

      final response = await client.request(
        method: 'acp.capabilities',
        params: const <String, dynamic>{},
      );

      expect(capture.authorizationHeader, 'Bearer bridge-token');
      expect(capture.acceptHeader, 'text/event-stream, application/json');
      expect(capture.requestPath, '/acp/rpc');
      expect((response['result'] as Map)['ok'], true);
    });

    test(
      'returns SSE final response before a truncated chunked close is reported',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close());
        server.listen((socket) async {
          final requestBytes = <int>[];
          var headerEnd = -1;
          await for (final chunk in socket) {
            requestBytes.addAll(chunk);
            final raw = utf8.decode(requestBytes, allowMalformed: true);
            headerEnd = raw.indexOf('\r\n\r\n');
            if (headerEnd < 0) {
              continue;
            }
            if (raw.contains('"id"') && raw.contains('"method"')) {
              break;
            }
          }
          final rawRequest = utf8.decode(requestBytes, allowMalformed: true);
          final id =
              RegExp(
                r'"id"\s*:\s*"([^"]+)"',
              ).firstMatch(rawRequest)?.group(1) ??
              'request-id';
          final event = utf8.encode(
            'data: ${jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': id,
              'result': <String, dynamic>{'ok': true},
            })}\n\n',
          );
          socket
            ..add(
              ascii.encode(
                'HTTP/1.1 200 OK\r\n'
                'Content-Type: text/event-stream\r\n'
                'Transfer-Encoding: chunked\r\n'
                'Connection: keep-alive\r\n'
                '\r\n'
                '${event.length.toRadixString(16)}\r\n',
              ),
            )
            ..add(event)
            ..add(ascii.encode('\r\n'));
          await socket.flush();
          socket.destroy();
        });

        final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
        final client = GatewayAcpClient(endpointResolver: () => endpoint);

        final response = await client.request(
          method: 'acp.capabilities',
          params: const <String, dynamic>{},
        );

        expect((response['result'] as Map)['ok'], true);
      },
    );

    test(
      'normalizes raw authorization override into bearer header for HTTP',
      () async {
        final capture = await _startAcpHttpServer();
        addTearDown(capture.close);

        final client = GatewayAcpClient(
          endpointResolver: () => capture.baseEndpoint,
        );

        await client.request(
          method: 'acp.capabilities',
          params: const <String, dynamic>{},
          authorizationOverride: 'override-token',
        );

        expect(capture.authorizationHeader, 'Bearer override-token');
      },
    );

    test('preserves prebuilt bearer authorization header', () async {
      final capture = await _startAcpHttpServer();
      addTearDown(capture.close);

      final client = GatewayAcpClient(
        endpointResolver: () => capture.baseEndpoint,
      );

      await client.request(
        method: 'acp.capabilities',
        params: const <String, dynamic>{},
        authorizationOverride: 'Bearer ready-token',
      );

      expect(capture.authorizationHeader, 'Bearer ready-token');
    });

    test('surfaces structured bridge HTTP 502 diagnostics', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response
          ..statusCode = HttpStatus.badGateway
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, dynamic>{
              'error': <String, dynamic>{
                'message': 'openclaw upstream request failed',
                'data': <String, dynamic>{
                  'unavailableCode': 'UPSTREAM_BAD_GATEWAY',
                  'upstreamMethod': 'session.start',
                },
              },
            }),
          );
        await request.response.close();
      });
      final client = GatewayAcpClient(
        endpointResolver: () => Uri.parse('http://127.0.0.1:${server.port}'),
      );

      await expectLater(
        client.request(
          method: 'session.start',
          params: const <String, dynamic>{},
        ),
        throwsA(
          isA<GatewayAcpException>()
              .having((error) => error.code, 'code', 'ACP_HTTP_502')
              .having(
                (error) => error.message,
                'message',
                contains('openclaw upstream request failed'),
              )
              .having(
                (error) => error.message,
                'diagnostic code',
                contains('UPSTREAM_BAD_GATEWAY'),
              )
              .having(
                (error) => error.message,
                'upstream',
                contains('session.start'),
              ),
        ),
      );
    });

    test('surfaces plain-text bridge HTTP 502 diagnostics', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response
          ..statusCode = HttpStatus.badGateway
          ..headers.contentType = ContentType.text
          ..write('openclaw upstream returned empty response');
        await request.response.close();
      });
      final client = GatewayAcpClient(
        endpointResolver: () => Uri.parse('http://127.0.0.1:${server.port}'),
      );

      await expectLater(
        client.request(
          method: 'session.start',
          params: const <String, dynamic>{},
        ),
        throwsA(
          isA<GatewayAcpException>()
              .having((error) => error.code, 'code', 'ACP_HTTP_502')
              .having(
                (error) => error.message,
                'message',
                contains('openclaw upstream returned empty response'),
              )
              .having(
                (error) => error.message,
                'content type',
                contains('unexpected content type: text/plain'),
              ),
        ),
      );
    });

    test(
      'surfaces closed-before-header HTTP failures as ACP diagnostics',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close());
        server.listen((socket) {
          socket.listen((_) {
            socket.destroy();
          });
        });
        final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
        final client = GatewayAcpClient(endpointResolver: () => endpoint);

        await expectLater(
          client.request(
            method: 'session.start',
            params: const <String, dynamic>{},
          ),
          throwsA(
            isA<GatewayAcpException>()
                .having(
                  (error) => error.code,
                  'code',
                  'ACP_HTTP_CONNECTION_CLOSED',
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('closed before the response finished arriving'),
                )
                .having(
                  (error) => error.details,
                  'details',
                  containsPair('requestUrl', '$endpoint/acp/rpc'),
                ),
          ),
        );
      },
    );

    test(
      'uses complete SSE final envelope buffered before abrupt body close',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          final envelope = jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': _decodeRequestId(body),
            'result': <String, dynamic>{
              'output': 'stable final output',
              'artifacts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'relativePath': 'exports/final.md',
                  'downloadUrl':
                      'https://xworkmate-bridge.svc.plus/artifacts/openclaw/download'
                      '?sessionKey=session-1&runId=run-1&relativePath=exports%2Ffinal.md',
                  'contentType': 'text/markdown',
                  'sizeBytes': 42,
                },
              ],
            },
          });
          final event = 'data: $envelope\n';
          final eventBytes = utf8.encode(event);
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'text/event-stream',
          );
          request.response.contentLength = eventBytes.length + 128;
          final socket = await request.response.detachSocket();
          socket.add(eventBytes);
          await socket.flush();
          socket.destroy();
        });
        final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
        final client = GatewayAcpClient(endpointResolver: () => endpoint);

        final response = await client.request(
          method: 'session.start',
          params: const <String, dynamic>{},
        );

        expect((response['result'] as Map)['output'], 'stable final output');
        expect(
          ((response['result'] as Map)['artifacts'] as List),
          hasLength(1),
        );
        final diagnostics = (response['_xworkmateDiagnostics'] as Map)
            .cast<String, dynamic>();
        expect(diagnostics['transport'], 'http-sse');
        expect(diagnostics['bodyRead'], isTrue);
      },
    );

    test(
      'recovers OpenClaw task result from completed session update when final SSE envelope is lost',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          await utf8.decoder.bind(request).join();
          final event = jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'session.update',
            'params': <String, dynamic>{
              'sessionId': 'unit-fixture-task-a',
              'threadId': 'unit-fixture-task-a',
              'turnId': 'turn-1',
              'type': 'status',
              'event': 'completed',
              'pending': false,
              'error': false,
              'message': <String, dynamic>{
                'content': 'stable completed output',
              },
              'result': <String, dynamic>{
                'success': true,
                'output': 'stable completed output',
                'turnId': 'turn-1',
                'artifacts': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'relativePath': 'exports/final.md',
                    'downloadUrl':
                        'https://xworkmate-bridge.svc.plus/artifacts/openclaw/download'
                        '?sessionKey=unit-fixture-task-a&runId=turn-1&relativePath=exports%2Ffinal.md',
                    'contentType': 'text/markdown',
                    'sizeBytes': 42,
                  },
                ],
              },
            },
          });
          final eventBytes = utf8.encode('data: $event\n\n');
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'text/event-stream',
          );
          request.response.contentLength = eventBytes.length + 128;
          final socket = await request.response.detachSocket();
          socket.add(eventBytes);
          await socket.flush();
          socket.destroy();
        });
        final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: GatewayAcpClient(endpointResolver: () => endpoint),
          endpointResolver: (_) => endpoint,
        );
        addTearDown(transport.dispose);

        final result = await transport.executeTask(
          const GoTaskServiceRequest(
            sessionId: 'unit-fixture-task-a',
            threadId: 'unit-fixture-task-a',
            target: AssistantExecutionTarget.gateway,
            provider: SingleAgentProvider.openclaw,
            prompt: 'create files',
            workingDirectory: '/tmp/workspace',
            model: '',
            thinking: 'off',
            selectedSkills: <String>[],
            inlineAttachments: <GatewayChatAttachmentPayload>[],
            localAttachments: <CollaborationAttachment>[],
            agentId: '',
            metadata: <String, dynamic>{},
          ),
          onUpdate: (_) {},
        );

        expect(result.success, isTrue);
        expect(result.message, 'stable completed output');
        expect(result.artifacts, hasLength(1));
        expect(result.artifacts.single.relativePath, 'exports/final.md');
      },
    );

    test(
      'recovers OpenClaw task result from bridge task snapshot after SSE connection close',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requestPaths = <String>[];
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          requestPaths.add(request.uri.path);
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          final method = decoded['method']?.toString() ?? '';
          final id = decoded['id']?.toString() ?? 'request-id';
          if (method == 'session.start') {
            final event = jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'xworkmate.bridge.accepted',
              'params': <String, dynamic>{'sessionId': 'unit-fixture-task-a'},
            });
            final eventBytes = utf8.encode('data: $event\n\n');
            request.response.headers.set(
              HttpHeaders.contentTypeHeader,
              'text/event-stream',
            );
            request.response.contentLength = eventBytes.length + 128;
            final socket = await request.response.detachSocket();
            socket.add(eventBytes);
            await socket.flush();
            socket.destroy();
            return;
          }
          if (method == 'xworkmate.tasks.get') {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(<String, dynamic>{
                'jsonrpc': '2.0',
                'id': id,
                'result': <String, dynamic>{
                  'status': 'completed',
                  'sessionId': 'unit-fixture-task-a',
                  'threadId': 'unit-fixture-task-a',
                  'task': <String, dynamic>{
                    'state': 'completed',
                    'turnId': 'turn-recovered',
                  },
                  'result': <String, dynamic>{
                    'success': true,
                    'output': 'recovered from bridge task snapshot',
                    'turnId': 'turn-recovered',
                  },
                  'artifacts': <String, dynamic>{
                    'items': <Map<String, dynamic>>[
                      <String, dynamic>{
                        'relativePath': 'exports/snapshot.md',
                        'downloadUrl':
                            'https://xworkmate-bridge.svc.plus/artifacts/openclaw/download'
                            '?sessionKey=unit-fixture-task-a&runId=turn-recovered&relativePath=exports%2Fsnapshot.md',
                        'contentType': 'text/markdown',
                        'sizeBytes': 64,
                      },
                    ],
                    'remoteWorkingDirectory': '/remote/openclaw/workspace',
                    'remoteWorkspaceRefKind': 'remotePath',
                    'resultSummary': 'recovered from top-level artifacts',
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
        final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: GatewayAcpClient(endpointResolver: () => endpoint),
          endpointResolver: (_) => endpoint,
          taskEndpointResolver: (_) => endpoint,
        );
        addTearDown(transport.dispose);

        final result = await transport.executeTask(
          const GoTaskServiceRequest(
            sessionId: 'unit-fixture-task-a',
            threadId: 'unit-fixture-task-a',
            target: AssistantExecutionTarget.gateway,
            provider: SingleAgentProvider.openclaw,
            prompt: 'create files',
            workingDirectory: '/tmp/workspace',
            model: '',
            thinking: 'off',
            selectedSkills: <String>[],
            inlineAttachments: <GatewayChatAttachmentPayload>[],
            localAttachments: <CollaborationAttachment>[],
            agentId: '',
            metadata: <String, dynamic>{},
          ),
          onUpdate: (_) {},
        );

        expect(result.success, isTrue);
        expect(result.message, 'recovered from bridge task snapshot');
        expect(result.artifacts.single.relativePath, 'exports/snapshot.md');
        expect(result.remoteWorkingDirectory, '/remote/openclaw/workspace');
        expect(result.remoteWorkspaceRefKind, WorkspaceRefKind.remotePath);
        expect(requestPaths, everyElement('/acp/rpc'));
      },
    );

    test(
      'prefers final OpenClaw snapshot over early completed SSE update after connection close',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requestMethods = <String>[];
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          final method = decoded['method']?.toString() ?? '';
          final id = decoded['id']?.toString() ?? 'request-id';
          requestMethods.add(method);
          if (method == 'session.start') {
            final event = jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'session.update',
              'params': <String, dynamic>{
                'sessionId': 'unit-fixture-task-final',
                'threadId': 'unit-fixture-task-final',
                'turnId': 'turn-final',
                'type': 'status',
                'event': 'completed',
                'message': 'early completed output without artifacts',
                'success': true,
              },
            });
            final eventBytes = utf8.encode('data: $event\n\n');
            request.response.headers.set(
              HttpHeaders.contentTypeHeader,
              'text/event-stream',
            );
            request.response.contentLength = eventBytes.length + 128;
            final socket = await request.response.detachSocket();
            socket.add(eventBytes);
            await socket.flush();
            socket.destroy();
            return;
          }
          if (method == 'xworkmate.tasks.get') {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(<String, dynamic>{
                'jsonrpc': '2.0',
                'id': id,
                'result': <String, dynamic>{
                  'status': 'completed',
                  'sessionId': 'unit-fixture-task-final',
                  'threadId': 'unit-fixture-task-final',
                  'task': <String, dynamic>{
                    'state': 'completed',
                    'turnId': 'turn-final',
                  },
                  'result': <String, dynamic>{
                    'success': true,
                    'output': 'final snapshot output with artifacts',
                    'turnId': 'turn-final',
                  },
                  'artifacts': <String, dynamic>{
                    'items': <Map<String, dynamic>>[
                      <String, dynamic>{
                        'relativePath': 'reports/final.md',
                        'downloadUrl':
                            'https://xworkmate-bridge.svc.plus/artifacts/openclaw/download'
                            '?sessionKey=unit-fixture-task-final&runId=turn-final&relativePath=reports%2Ffinal.md',
                        'contentType': 'text/markdown',
                        'sizeBytes': 64,
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
        final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: GatewayAcpClient(endpointResolver: () => endpoint),
          endpointResolver: (_) => endpoint,
          taskEndpointResolver: (_) => endpoint,
        );
        addTearDown(transport.dispose);

        final result = await transport.executeTask(
          const GoTaskServiceRequest(
            sessionId: 'unit-fixture-task-final',
            threadId: 'unit-fixture-task-final',
            target: AssistantExecutionTarget.gateway,
            provider: SingleAgentProvider.openclaw,
            prompt: 'create files',
            workingDirectory: '/tmp/workspace',
            model: '',
            thinking: 'off',
            selectedSkills: <String>[],
            inlineAttachments: <GatewayChatAttachmentPayload>[],
            localAttachments: <CollaborationAttachment>[],
            agentId: '',
            metadata: <String, dynamic>{},
          ),
          onUpdate: (_) {},
        );

        expect(result.success, isTrue);
        expect(result.message, 'final snapshot output with artifacts');
        expect(result.artifacts.single.relativePath, 'reports/final.md');
        expect(requestMethods, <String>[
          'session.start',
          'xworkmate.tasks.get',
        ]);
      },
    );

    test(
      'recovers OpenClaw follow-up from bridge task snapshot after SSE ends without final envelope',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requestPaths = <String>[];
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          requestPaths.add(request.uri.path);
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          final method = decoded['method']?.toString() ?? '';
          final id = decoded['id']?.toString() ?? 'request-id';
          if (method == 'session.message') {
            final event = jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'xworkmate.bridge.accepted',
              'params': <String, dynamic>{'sessionId': 'unit-fixture-task-sse'},
            });
            request.response.headers.set(
              HttpHeaders.contentTypeHeader,
              'text/event-stream',
            );
            request.response.write('data: $event\n\n');
            await request.response.close();
            return;
          }
          if (method == 'xworkmate.tasks.get') {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(<String, dynamic>{
                'jsonrpc': '2.0',
                'id': id,
                'result': <String, dynamic>{
                  'status': 'completed',
                  'sessionId': 'unit-fixture-task-sse',
                  'threadId': 'unit-fixture-task-sse',
                  'task': <String, dynamic>{
                    'state': 'completed',
                    'turnId': 'turn-recovered-sse',
                  },
                  'result': <String, dynamic>{
                    'success': true,
                    'output': 'recovered after SSE no result',
                    'turnId': 'turn-recovered-sse',
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
        final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: GatewayAcpClient(endpointResolver: () => endpoint),
          endpointResolver: (_) => endpoint,
          taskEndpointResolver: (_) => endpoint,
          recoveryPollDelay: Duration.zero,
          recoveryMaxAttempts: 1,
        );
        addTearDown(transport.dispose);

        final result = await transport.executeTask(
          const GoTaskServiceRequest(
            sessionId: 'unit-fixture-task-sse',
            threadId: 'unit-fixture-task-sse',
            target: AssistantExecutionTarget.gateway,
            provider: SingleAgentProvider.openclaw,
            prompt: 'recover from graceful SSE close',
            workingDirectory: '/tmp/workspace',
            model: '',
            thinking: 'off',
            resumeSession: true,
            selectedSkills: <String>[],
            inlineAttachments: <GatewayChatAttachmentPayload>[],
            localAttachments: <CollaborationAttachment>[],
            agentId: '',
            metadata: <String, dynamic>{},
          ),
          onUpdate: (_) {},
        );

        expect(result.success, isTrue);
        expect(result.message, 'recovered after SSE no result');
        expect(requestPaths, everyElement('/acp/rpc'));
      },
    );

    test(
      'keeps polling running OpenClaw snapshot after SSE connection close',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var snapshotPolls = 0;
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          final method = decoded['method']?.toString() ?? '';
          final id = decoded['id']?.toString() ?? 'request-id';
          if (method == 'session.start') {
            final event = jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'xworkmate.bridge.accepted',
              'params': <String, dynamic>{'sessionId': 'unit-fixture-task-b'},
            });
            final eventBytes = utf8.encode('data: $event\n\n');
            request.response.headers.set(
              HttpHeaders.contentTypeHeader,
              'text/event-stream',
            );
            request.response.contentLength = eventBytes.length + 128;
            final socket = await request.response.detachSocket();
            socket.add(eventBytes);
            await socket.flush();
            socket.destroy();
            return;
          }
          if (method == 'xworkmate.tasks.get') {
            snapshotPolls += 1;
            final completed = snapshotPolls >= 3;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(<String, dynamic>{
                'jsonrpc': '2.0',
                'id': id,
                'result': <String, dynamic>{
                  'status': completed ? 'completed' : 'running',
                  'sessionId': 'unit-fixture-task-b',
                  'threadId': 'unit-fixture-task-b',
                  'task': <String, dynamic>{
                    'state': completed ? 'completed' : 'running',
                    'turnId': 'turn-recovered-running',
                  },
                  if (completed)
                    'result': <String, dynamic>{
                      'success': true,
                      'output': 'recovered after running snapshot',
                      'turnId': 'turn-recovered-running',
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
        final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: GatewayAcpClient(endpointResolver: () => endpoint),
          endpointResolver: (_) => endpoint,
          taskEndpointResolver: (_) => endpoint,
          recoveryPollDelay: Duration.zero,
          recoveryMaxAttempts: 4,
        );
        addTearDown(transport.dispose);

        final result = await transport.executeTask(
          const GoTaskServiceRequest(
            sessionId: 'unit-fixture-task-b',
            threadId: 'unit-fixture-task-b',
            target: AssistantExecutionTarget.gateway,
            provider: SingleAgentProvider.openclaw,
            prompt: 'wait for result',
            workingDirectory: '/tmp/workspace',
            model: '',
            thinking: 'off',
            selectedSkills: <String>[],
            inlineAttachments: <GatewayChatAttachmentPayload>[],
            localAttachments: <CollaborationAttachment>[],
            agentId: '',
            metadata: <String, dynamic>{},
          ),
          onUpdate: (_) {},
        );

        expect(snapshotPolls, 3);
        expect(result.success, isTrue);
        expect(result.message, 'recovered after running snapshot');
      },
    );

    test(
      'recovers terminal failed OpenClaw snapshot without displayable result',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          final method = decoded['method']?.toString() ?? '';
          final id = decoded['id']?.toString() ?? 'request-id';
          if (method == 'session.start') {
            final event = jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'xworkmate.bridge.accepted',
              'params': <String, dynamic>{'sessionId': 'unit-fixture-task-c'},
            });
            final eventBytes = utf8.encode('data: $event\n\n');
            request.response.headers.set(
              HttpHeaders.contentTypeHeader,
              'text/event-stream',
            );
            request.response.contentLength = eventBytes.length + 128;
            final socket = await request.response.detachSocket();
            socket.add(eventBytes);
            await socket.flush();
            socket.destroy();
            return;
          }
          if (method == 'xworkmate.tasks.get') {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(<String, dynamic>{
                'jsonrpc': '2.0',
                'id': id,
                'result': <String, dynamic>{
                  'status': 'failed',
                  'sessionId': 'unit-fixture-task-c',
                  'threadId': 'unit-fixture-task-c',
                  'task': <String, dynamic>{
                    'state': 'failed',
                    'turnId': 'turn-failed',
                  },
                  'error': <String, dynamic>{
                    'code': 'OPENCLAW_WAIT_FAILED',
                    'message': 'openclaw wait failed',
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
        final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: GatewayAcpClient(endpointResolver: () => endpoint),
          endpointResolver: (_) => endpoint,
          taskEndpointResolver: (_) => endpoint,
          recoveryPollDelay: Duration.zero,
          recoveryMaxAttempts: 1,
        );
        addTearDown(transport.dispose);

        final result = await transport.executeTask(
          const GoTaskServiceRequest(
            sessionId: 'unit-fixture-task-c',
            threadId: 'unit-fixture-task-c',
            target: AssistantExecutionTarget.gateway,
            provider: SingleAgentProvider.openclaw,
            prompt: 'fail task',
            workingDirectory: '/tmp/workspace',
            model: '',
            thinking: 'off',
            selectedSkills: <String>[],
            inlineAttachments: <GatewayChatAttachmentPayload>[],
            localAttachments: <CollaborationAttachment>[],
            agentId: '',
            metadata: <String, dynamic>{},
          ),
          onUpdate: (_) {},
        );

        expect(result.success, isFalse);
        expect(result.status, 'failed');
        expect(result.code, 'OPENCLAW_WAIT_FAILED');
        expect(result.errorMessage, contains('openclaw wait failed'));
      },
    );

    test(
      'retries interrupted TLS handshakes before surfacing ACP diagnostics',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        var acceptedSockets = 0;
        addTearDown(() => server.close());
        server.listen((socket) {
          acceptedSockets += 1;
          socket.destroy();
        });
        final endpoint = Uri.parse('https://127.0.0.1:${server.port}');
        final client = GatewayAcpClient(endpointResolver: () => endpoint);

        await expectLater(
          client.request(
            method: 'session.start',
            params: const <String, dynamic>{},
          ),
          throwsA(
            isA<GatewayAcpException>()
                .having(
                  (error) => error.code,
                  'code',
                  gatewayAcpHttpHandshakeInterruptedCode,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('handshake was interrupted'),
                )
                .having(
                  (error) => error.details,
                  'details',
                  allOf(
                    containsPair('requestUrl', '$endpoint/acp/rpc'),
                    containsPair(
                      'maxRetryAttempts',
                      gatewayAcpHttpHandshakeInterruptedRetryCount,
                    ),
                    containsPair(
                      'retryAttempt',
                      gatewayAcpHttpHandshakeInterruptedRetryCount,
                    ),
                  ),
                ),
          ),
        );
        expect(
          acceptedSockets,
          gatewayAcpHttpHandshakeInterruptedRetryCount + 1,
        );
      },
    );

    test(
      'retries failed connect attempts before surfacing unconfirmed diagnostics',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = server.port;
        await server.close();
        final endpoint = Uri.parse('http://127.0.0.1:$port');
        final client = GatewayAcpClient(endpointResolver: () => endpoint);

        await expectLater(
          client.request(
            method: 'session.start',
            params: const <String, dynamic>{},
          ),
          throwsA(
            isA<GatewayAcpException>()
                .having(
                  (error) => error.code,
                  'code',
                  gatewayAcpHttpConnectFailedCode,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('before the request was confirmed'),
                )
                .having(
                  (error) => error.details,
                  'details',
                  allOf(
                    containsPair('requestUrl', '$endpoint/acp/rpc'),
                    containsPair(
                      'maxRetryAttempts',
                      gatewayAcpHttpConnectFailureRetryCount,
                    ),
                    containsPair(
                      'retryAttempt',
                      gatewayAcpHttpConnectFailureRetryCount,
                    ),
                    containsPair('phase', 'connect'),
                  ),
                ),
          ),
        );
      },
    );

    test(
      'desktop transport preserves socket timeout as unconfirmed ACP diagnostics',
      () async {
        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: _SocketThrowingGatewayAcpClient(
            const SocketException(
              'HTTP connection timed out after 0:00:08.000000, host: xworkmate-bridge.svc.plus, port: 443',
            ),
          ),
          endpointResolver: (_) =>
              Uri.parse('https://xworkmate-bridge.svc.plus'),
        );

        await expectLater(
          transport.executeTask(
            _taskRequest(
              target: AssistantExecutionTarget.gateway,
              provider: SingleAgentProvider.openclaw,
            ),
            onUpdate: (_) {},
          ),
          throwsA(
            isA<GatewayAcpException>()
                .having(
                  (error) => error.code,
                  'code',
                  gatewayAcpHttpConnectTimeoutCode,
                )
                .having(
                  (error) => error.toString(),
                  'diagnostic',
                  isNot(contains('EXTERNAL_ACP_GATEWAY_ERROR')),
                ),
          ),
        );
      },
    );

    test('desktop bridge auth resolver skips unrelated endpoints', () async {
      final storeRoot = await Directory.systemTemp.createTemp(
        'xworkmate-acp-auth-unrelated-',
      );
      addTearDown(() async {
        if (await storeRoot.exists()) {
          await storeRoot.delete(recursive: true);
        }
      });

      final store = SecureConfigStore(
        secretRootPathResolver: () async => '${storeRoot.path}/secrets',
        appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
        supportRootPathResolver: () async => '${storeRoot.path}/support',
        enableSecureStorage: false,
      );
      await store.initialize();
      await store.saveAccountManagedSecret(
        target: kAccountManagedSecretTargetBridgeAuthToken,
        value: 'bridge-token',
      );

      final controller = AppController(
        environmentOverride: const <String, String>{},
        store: store,
      );
      addTearDown(controller.dispose);

      final header = await controller
          .resolveGatewayAcpAuthorizationHeaderInternal(
            Uri.parse('https://unrelated.example.com/acp/rpc'),
          );

      expect(header, isNull);
    });

    test(
      'desktop auth resolver does not reuse gateway profile token for bridge ACP',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-acp-auth-matching-profile-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best effort here. The controller does not own
              // the lifecycle of the OS temp directory.
            }
          }
        });

        final store = SecureConfigStore(
          secretRootPathResolver: () async => '${storeRoot.path}/secrets',
          appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
          supportRootPathResolver: () async => '${storeRoot.path}/support',
          enableSecureStorage: false,
        );
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWithGatewayProfileAt(
            kGatewayRemoteProfileIndex,
            GatewayConnectionProfile.defaults().copyWith(
              host: 'gateway.example.com',
              port: 8443,
              tls: true,
            ),
          ),
        );
        await store.saveSecretValueByRef('gateway_token_0', 'gateway-token');

        final controller = AppController(
          environmentOverride: const <String, String>{},
          store: store,
        );
        addTearDown(controller.dispose);
        await controller.settingsControllerInternal.resetSnapshot(
          await store.loadSettingsSnapshot(),
        );

        final header = await controller
            .resolveGatewayAcpAuthorizationHeaderInternal(
              Uri.parse('https://gateway.example.com:8443/acp/rpc'),
            );

        expect(header, isNull);
      },
    );

    test(
      'desktop bridge auth resolver sends bearer when the caller asks for managed bridge auth',
      () async {
        final capture = await _startAcpHttpServer();
        addTearDown(capture.close);

        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-acp-auth-managed-bridge-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best effort here. The client may still be
              // releasing files when teardown starts.
            }
          }
        });

        final store = SecureConfigStore(
          secretRootPathResolver: () async => '${storeRoot.path}/secrets',
          appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
          supportRootPathResolver: () async => '${storeRoot.path}/support',
          enableSecureStorage: false,
        );
        await store.initialize();
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetBridgeAuthToken,
          value: 'bridge-token',
        );
        final client = GatewayAcpClient(
          endpointResolver: () => capture.baseEndpoint,
          authorizationResolver: (_) async => 'bridge-token',
        );

        await client.request(
          method: 'acp.capabilities',
          params: const <String, dynamic>{},
        );

        expect(capture.authorizationHeader, 'Bearer bridge-token');
        expect(capture.requestPath, '/acp/rpc');
      },
    );

    test(
      'desktop bridge auth resolver prefers synced managed bridge token over stale environment token',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-acp-auth-managed-bridge-env-priority-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best effort here. The controller may still be
              // releasing files when teardown starts.
            }
          }
        });

        final store = SecureConfigStore(
          secretRootPathResolver: () async => '${storeRoot.path}/secrets',
          appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
          supportRootPathResolver: () async => '${storeRoot.path}/support',
          enableSecureStorage: false,
        );
        await store.initialize();
        await store.saveAccountSessionToken('session-token');
        await store.saveAccountSessionSummary(
          const AccountSessionSummary(
            userId: 'user-1',
            email: 'review@svc.plus',
            name: 'Review User',
            role: 'reviewer',
            mfaEnabled: true,
          ),
        );
        await store.saveAccountSyncState(
          AccountSyncState.defaults().copyWith(
            syncState: 'ready',
            tokenConfigured: const AccountTokenConfigured(
              bridge: true,
              vault: false,
            ),
          ),
        );
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetBridgeAuthToken,
          value: 'fresh-bridge-token',
        );

        final controller = AppController(
          environmentOverride: const <String, String>{
            'BRIDGE_AUTH_TOKEN': 'stale-env-token',
          },
          store: store,
        );
        addTearDown(controller.dispose);
        await controller.settingsControllerInternal.initialize();

        final header = await controller
            .resolveGatewayAcpAuthorizationHeaderInternal(
              Uri.parse('https://xworkmate-bridge.svc.plus/acp/rpc'),
            );

        expect(header, 'fresh-bridge-token');
      },
    );

    test(
      'desktop bridge auth resolver does not fallback to the remote gateway token for bridge ACP',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-acp-auth-bridge-fallback-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best effort here. The controller may still be
              // releasing files when teardown starts.
            }
          }
        });

        final store = SecureConfigStore(
          secretRootPathResolver: () async => '${storeRoot.path}/secrets',
          appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
          supportRootPathResolver: () async => '${storeRoot.path}/support',
          enableSecureStorage: false,
        );
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWithGatewayProfileAt(
            kGatewayRemoteProfileIndex,
            GatewayConnectionProfile.defaults().copyWith(
              host: 'xworkmate.svc.plus',
              port: 443,
              tls: true,
            ),
          ),
        );
        await store.saveSecretValueByRef('gateway_token_0', 'gateway-token');

        final controller = AppController(
          environmentOverride: const <String, String>{},
          store: store,
        );
        addTearDown(controller.dispose);
        await controller.settingsControllerInternal.initialize();

        final header = await controller
            .resolveGatewayAcpAuthorizationHeaderInternal(
              Uri.parse('https://xworkmate-bridge.svc.plus/acp/rpc'),
            );

        expect(header, isNull);
      },
    );

    test(
      'desktop agent task execution routes bridge-owned providers through bridge RPC',
      () async {
        for (final providerId in <String>[
          'codex',
          'opencode',
          'gemini',
          'hermes',
        ]) {
          final capture = await _startAcpHttpServer();
          addTearDown(capture.close);
          final client = GatewayAcpClient(
            endpointResolver: () => capture.baseEndpoint,
            authorizationResolver: (_) async => 'bridge-token',
          );

          final transport = ExternalCodeAgentAcpDesktopTransport(
            client: client,
            endpointResolver: (_) => capture.baseEndpoint,
            taskEndpointResolver: (_) => capture.baseEndpoint,
          );

          await transport.executeTask(
            _taskRequest(
              target: AssistantExecutionTarget.agent,
              provider: SingleAgentProvider.fromJsonValue(providerId),
            ),
            onUpdate: (_) {},
          );

          final params = _lastRequestParams(capture);
          final routing = params['routing'] as Map<String, dynamic>;
          expect(capture.authorizationHeader, 'Bearer bridge-token');
          expect(capture.requestPath, '/acp/rpc');
          expect(capture.requestPath, isNot(contains('/acp-server')));
          expect(capture.requestPath, isNot(contains('/gateway/openclaw')));
          expect(params['provider'], providerId);
          expect(params['requestedExecutionTarget'], 'agent');
          expect(routing['explicitProviderId'], providerId);
          expect(routing['explicitExecutionTarget'], 'agent');
          expect(params.containsKey('gatewayProvider'), isFalse);
          expect(params.containsKey('gatewayProviderId'), isFalse);
        }
      },
    );

    test(
      'desktop task execution rejects provider endpoint paths as bridge RPC bases',
      () async {
        final capture = await _startAcpHttpServer();
        addTearDown(capture.close);
        final client = GatewayAcpClient(
          endpointResolver: () => capture.baseEndpoint,
          authorizationResolver: (_) async => 'bridge-token',
        );

        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: client,
          endpointResolver: (_) => capture.baseEndpoint,
          taskEndpointResolver: (_) =>
              capture.baseEndpoint.replace(path: '/acp-server/codex'),
        );

        await expectLater(
          transport.executeTask(
            _taskRequest(
              target: AssistantExecutionTarget.agent,
              provider: SingleAgentProvider.codex,
            ),
            onUpdate: (_) {},
          ),
          throwsA(
            isA<GatewayAcpException>().having(
              (error) => error.code,
              'code',
              'ACP_HTTP_ENDPOINT_MISSING',
            ),
          ),
        );

        expect(capture.requestBodies, isEmpty);
      },
    );

    test(
      'desktop task execution rejects OpenClaw gateway path as bridge RPC base',
      () async {
        final capture = await _startAcpHttpServer();
        addTearDown(capture.close);
        final client = GatewayAcpClient(
          endpointResolver: () =>
              capture.baseEndpoint.replace(path: '/gateway/openclaw'),
          authorizationResolver: (_) async => 'bridge-token',
        );

        await expectLater(
          client.request(
            method: 'acp.capabilities',
            params: const <String, dynamic>{},
          ),
          throwsA(
            isA<GatewayAcpException>().having(
              (error) => error.code,
              'code',
              'ACP_HTTP_ENDPOINT_MISSING',
            ),
          ),
        );

        expect(capture.requestBodies, isEmpty);
      },
    );

    test(
      'desktop task execution routes OpenClaw through unified bridge RPC',
      () async {
        final capture = await _startAcpHttpServer(
          streamResponse: true,
          result: <String, dynamic>{
            'success': true,
            'status': 'completed',
            'output': 'created files',
            'remoteWorkingDirectory': '/owners/local/user/demo/threads/main',
            'remoteWorkspaceRefKind': 'remotePath',
            'artifacts': <Map<String, dynamic>>[
              <String, dynamic>{
                'relativePath': 'exports/k8s-networking.pdf',
                'downloadUrl':
                    'https://xworkmate-bridge.svc.plus/artifacts/openclaw/download'
                    '?sessionKey=session-1&runId=run-1&relativePath=exports%2Fk8s-networking.pdf',
                'contentType': 'application/pdf',
                'sizeBytes': 123,
                'sha256':
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              },
            ],
          },
        );
        addTearDown(capture.close);
        final client = GatewayAcpClient(
          endpointResolver: () => capture.baseEndpoint,
          authorizationResolver: (_) async => 'bridge-token',
        );

        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: client,
          endpointResolver: (_) => capture.baseEndpoint,
          taskEndpointResolver: (_) => capture.baseEndpoint,
        );

        final result = await transport.executeTask(
          _taskRequest(
            target: AssistantExecutionTarget.gateway,
            provider: SingleAgentProvider.openclaw,
          ),
          onUpdate: (_) {},
        );

        expect(capture.authorizationHeader, 'Bearer bridge-token');
        expect(capture.acceptHeader, 'text/event-stream, application/json');
        expect(capture.requestPath, '/acp/rpc');
        expect(capture.requestPath, isNot(contains('/acp-server')));
        expect(capture.requestPath, isNot(contains('/gateway/openclaw')));
        final params = _lastRequestParams(capture);
        final routing = params['routing'] as Map<String, dynamic>;
        expect(params.containsKey('gatewayProvider'), isFalse);
        expect(params.containsKey('gatewayProviderId'), isFalse);
        expect(params['executionTarget'], 'gateway');
        expect(params['requestedExecutionTarget'], 'gateway');
        expect(routing['preferredGatewayProviderId'], 'openclaw');
        expect(routing['explicitExecutionTarget'], 'gateway');
        expect(routing.containsKey('explicitProviderId'), isFalse);
        expect(capture.requestBody, contains('"method":"session.start"'));
        expect(capture.requestBody, isNot(contains('"method":"thread/start"')));
        expect(result.success, isTrue);
        expect(result.message, 'created files');
        expect(
          result.remoteWorkingDirectory,
          '/owners/local/user/demo/threads/main',
        );
        expect(result.remoteWorkspaceRefKind, WorkspaceRefKind.remotePath);
        expect(result.artifacts, hasLength(1));
        expect(
          result.artifacts.single.relativePath,
          'exports/k8s-networking.pdf',
        );
        expect(
          result.artifacts.single.downloadUrl,
          contains('/artifacts/openclaw/download'),
        );
        expect(result.artifacts.single.content, isEmpty);
        expect(result.artifacts.single.encoding, isEmpty);
      },
    );

    test(
      'desktop task execution keeps OpenClaw SSE alive until final result',
      () async {
        final capture = await _startAcpHttpServer(
          streamResponse: true,
          streamNotifications: <Map<String, dynamic>>[
            <String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'xworkmate.bridge.accepted',
              'params': <String, dynamic>{
                'sessionId': 'session-1',
                'threadId': 'session-1',
              },
            },
            <String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'xworkmate.bridge.keepalive',
              'params': <String, dynamic>{'intervalMs': 20000},
            },
            <String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'xworkmate.bridge.keepalive',
              'params': <String, dynamic>{'intervalMs': 20000},
            },
          ],
          result: <String, dynamic>{
            'success': true,
            'status': 'completed',
            'output': 'done',
          },
        );
        addTearDown(capture.close);
        final client = GatewayAcpClient(
          endpointResolver: () => capture.baseEndpoint,
          authorizationResolver: (_) async => 'bridge-token',
        );
        final notifications = <Map<String, dynamic>>[];

        final response = await client.request(
          method: 'session.start',
          params: <String, dynamic>{
            'sessionId': 'session-1',
            'threadId': 'session-1',
            'taskPrompt': 'Reply done',
            'executionTarget': 'gateway',
            'routing': <String, dynamic>{
              'routingMode': 'explicit',
              'explicitExecutionTarget': 'gateway',
              'preferredGatewayProviderId': 'openclaw',
            },
          },
          endpointOverride: capture.baseEndpoint,
          onNotification: notifications.add,
        );

        final diagnostics = (response['_xworkmateDiagnostics'] as Map)
            .cast<String, dynamic>();
        expect(capture.requestPath, '/acp/rpc');
        expect((response['result'] as Map)['output'], 'done');
        expect(diagnostics['transport'], 'http-sse');
        expect(diagnostics['requestUrl'], contains('/acp/rpc'));
        expect(diagnostics['requestUrl'], isNot(contains('/gateway/openclaw')));
        expect(diagnostics['bodyRead'], isTrue);
        expect(diagnostics['sseKeepaliveReceived'], isTrue);
        expect(diagnostics['sseLastEventAtMs'], isPositive);
        expect(diagnostics['sseEventCount'], 4);
        expect(
          notifications.map((item) => item['method']),
          containsAllInOrder(<String>[
            'xworkmate.bridge.accepted',
            'xworkmate.bridge.keepalive',
            'xworkmate.bridge.keepalive',
          ]),
        );
      },
    );

    test(
      'desktop OpenClaw follow-up routes through unified bridge RPC',
      () async {
        final capture = await _startAcpHttpServer();
        addTearDown(capture.close);
        final client = GatewayAcpClient(
          endpointResolver: () => capture.baseEndpoint,
          authorizationResolver: (_) async => 'bridge-token',
        );

        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: client,
          endpointResolver: (_) => capture.baseEndpoint,
          taskEndpointResolver: (_) => capture.baseEndpoint,
        );

        await transport.executeTask(
          _taskRequest(
            target: AssistantExecutionTarget.gateway,
            provider: SingleAgentProvider.openclaw,
            resumeSession: true,
          ),
          onUpdate: (_) {},
        );

        expect(capture.acceptHeader, 'text/event-stream, application/json');
        expect(capture.requestPath, '/acp/rpc');
        expect(capture.requestBody, contains('"method":"session.message"'));
      },
    );

    test('task submit uses short HTTP response timeout', () {
      final openClawEndpoint = Uri.parse(
        'https://xworkmate-bridge.svc.plus/acp/rpc',
      );
      final acpEndpoint = Uri.parse(
        'https://xworkmate-bridge.svc.plus/acp/rpc',
      );

      expect(
        gatewayAcpHttpResponseTimeoutFor(
          openClawEndpoint,
          'session.start',
          const <String, dynamic>{'requestedExecutionTarget': 'gateway'},
        ),
        const Duration(seconds: 120),
      );
      expect(
        gatewayAcpHttpResponseTimeoutFor(
          openClawEndpoint,
          'session.message',
          const <String, dynamic>{
            'taskPrompt': '输出 完整调研PPT 和 Markdown格式 文件',
            'requestedExecutionTarget': 'gateway',
          },
        ),
        const Duration(seconds: 120),
      );
      expect(
        gatewayAcpHttpResponseTimeoutFor(acpEndpoint, 'session.start'),
        const Duration(seconds: 120),
      );
      expect(
        gatewayAcpHttpResponseTimeoutFor(openClawEndpoint, 'acp.capabilities'),
        const Duration(seconds: 120),
      );
    });

    test('desktop controller uses unified bridge RPC for all task submits', () {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      final openClawStart = controller
          .resolveExternalAcpEndpointForRequestInternal(
            _taskRequest(
              target: AssistantExecutionTarget.gateway,
              provider: SingleAgentProvider.openclaw,
            ),
          );
      final openClawFollowUp = controller
          .resolveExternalAcpEndpointForRequestInternal(
            _taskRequest(
              target: AssistantExecutionTarget.gateway,
              provider: SingleAgentProvider.openclaw,
              resumeSession: true,
            ),
          );
      final unspecifiedGateway = controller
          .resolveExternalAcpEndpointForRequestInternal(
            _taskRequest(
              target: AssistantExecutionTarget.gateway,
              provider: SingleAgentProvider.unspecified,
            ),
          );
      final agentTask = controller.resolveExternalAcpEndpointForRequestInternal(
        _taskRequest(
          target: AssistantExecutionTarget.agent,
          provider: SingleAgentProvider.codex,
        ),
      );

      expect(openClawStart?.path, '/acp/rpc');
      expect(openClawFollowUp?.path, '/acp/rpc');
      expect(unspecifiedGateway?.path, '/acp/rpc');
      expect(agentTask?.path, '/acp/rpc');
    });

    test(
      'desktop controller resolves OpenClaw gateway submit to unified bridge RPC',
      () {
        final controller = AppController(
          environmentOverride: const <String, String>{},
        );
        addTearDown(controller.dispose);

        final endpoint = controller
            .resolveExternalAcpEndpointForRequestInternal(
              _taskRequest(
                target: AssistantExecutionTarget.gateway,
                provider: SingleAgentProvider.openclaw,
              ),
            );

        expect(
          endpoint.toString(),
          'https://xworkmate-bridge.svc.plus/acp/rpc',
        );
        expect(endpoint, isNotNull);
        expect(endpoint!.path, '/acp/rpc');
      },
    );

    test(
      'desktop task execution uses session.start for new sessions',
      () async {
        final capture = await _startAcpHttpServer();
        addTearDown(capture.close);
        final client = GatewayAcpClient(
          endpointResolver: () => capture.baseEndpoint,
          authorizationResolver: (_) async => 'bridge-token',
        );

        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: client,
          endpointResolver: (_) => capture.baseEndpoint,
          taskEndpointResolver: (_) => capture.baseEndpoint,
        );

        await transport.executeTask(
          _taskRequest(
            target: AssistantExecutionTarget.agent,
            provider: SingleAgentProvider.codex,
          ),
          onUpdate: (_) {},
        );

        expect(capture.requestBody, contains('"method":"session.start"'));
        expect(capture.requestBody, isNot(contains('"method":"thread/start"')));
      },
    );

    test(
      'desktop transport preserves gateway ACP HTTP failure detail',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          await utf8.decoder.bind(request).join();
          request.response
            ..statusCode = HttpStatus.badGateway
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, dynamic>{
                'error': <String, dynamic>{
                  'message': 'openclaw upstream request failed',
                  'data': <String, dynamic>{
                    'unavailableCode': 'UPSTREAM_BAD_GATEWAY',
                  },
                },
              }),
            );
          await request.response.close();
        });
        final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: GatewayAcpClient(endpointResolver: () => endpoint),
          endpointResolver: (_) => endpoint,
          taskEndpointResolver: (_) => endpoint,
        );

        await expectLater(
          transport.executeTask(
            _taskRequest(
              target: AssistantExecutionTarget.gateway,
              provider: SingleAgentProvider.openclaw,
            ),
            onUpdate: (_) {},
          ),
          throwsA(
            isA<GatewayAcpException>()
                .having((error) => error.code, 'code', 'ACP_HTTP_502')
                .having(
                  (error) => error.message,
                  'message',
                  contains('openclaw upstream request failed'),
                ),
          ),
        );
      },
    );

    test('preserves OpenClaw gateway socket close detail code', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': 'request-id',
              'error': <String, dynamic>{
                'code': -32002,
                'message':
                    'OPENCLAW_GATEWAY_SOCKET_CLOSED: OpenClaw gateway connection closed during task execution',
                'data': <String, dynamic>{
                  'code': 'OPENCLAW_GATEWAY_SOCKET_CLOSED',
                  'originalCode': 'SOCKET_CLOSED',
                },
              },
            }),
          );
        await request.response.close();
      });
      final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
      final client = GatewayAcpClient(endpointResolver: () => endpoint);

      await expectLater(
        client.request(
          method: 'session.start',
          params: const <String, dynamic>{},
        ),
        throwsA(
          isA<GatewayAcpException>()
              .having((error) => error.code, 'code', '-32002')
              .having(
                (error) => error.detailCode,
                'detailCode',
                'OPENCLAW_GATEWAY_SOCKET_CLOSED',
              )
              .having(
                (error) => error.details,
                'details',
                containsPair('originalCode', 'SOCKET_CLOSED'),
              ),
        ),
      );
    });

    test('desktop follow-up execution uses session.message', () async {
      final capture = await _startAcpHttpServer();
      addTearDown(capture.close);
      final client = GatewayAcpClient(
        endpointResolver: () => capture.baseEndpoint,
        authorizationResolver: (_) async => 'bridge-token',
      );

      final transport = ExternalCodeAgentAcpDesktopTransport(
        client: client,
        endpointResolver: (_) => capture.baseEndpoint,
        taskEndpointResolver: (_) => capture.baseEndpoint,
      );

      await transport.executeTask(
        _taskRequest(
          target: AssistantExecutionTarget.agent,
          provider: SingleAgentProvider.codex,
          resumeSession: true,
        ),
        onUpdate: (_) {},
      );

      expect(capture.requestBody, contains('"method":"session.message"'));
      expect(capture.requestBody, isNot(contains('"method":"turn/start"')));
    });

    test(
      'desktop execution keeps local cwd and sends remote workspace as hint',
      () async {
        final capture = await _startAcpHttpServer();
        addTearDown(capture.close);
        final client = GatewayAcpClient(
          endpointResolver: () => capture.baseEndpoint,
          authorizationResolver: (_) async => 'bridge-token',
        );

        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: client,
          endpointResolver: (_) => capture.baseEndpoint,
          taskEndpointResolver: (_) => capture.baseEndpoint,
        );

        await transport.executeTask(
          _taskRequest(
            target: AssistantExecutionTarget.agent,
            provider: SingleAgentProvider.codex,
            remoteWorkingDirectoryHint: '/owners/local/user/demo/threads/main',
          ),
          onUpdate: (_) {},
        );

        expect(capture.requestBody, contains('"workingDirectory":"/tmp"'));
        expect(
          capture.requestBody,
          contains(
            '"remoteWorkingDirectoryHint":"/owners/local/user/demo/threads/main"',
          ),
        );
      },
    );
  });
}

class _SocketThrowingGatewayAcpClient extends GatewayAcpClient {
  _SocketThrowingGatewayAcpClient(this.error)
    : super(
        endpointResolver: () => Uri.parse('https://xworkmate-bridge.svc.plus'),
      );

  final SocketException error;

  @override
  Future<Map<String, dynamic>> request({
    required String method,
    required Map<String, dynamic> params,
    void Function(Map<String, dynamic>)? onNotification,
    Uri? endpointOverride,
    String authorizationOverride = '',
  }) async {
    throw error;
  }
}

GoTaskServiceRequest _taskRequest({
  required AssistantExecutionTarget target,
  required SingleAgentProvider provider,
  bool resumeSession = false,
  String remoteWorkingDirectoryHint = '',
}) {
  return GoTaskServiceRequest(
    sessionId: 'session-1',
    threadId: 'session-1',
    target: target,
    prompt: 'hi',
    workingDirectory: '/tmp',
    model: '',
    thinking: 'off',
    selectedSkills: const <String>[],
    inlineAttachments: const <GatewayChatAttachmentPayload>[],
    localAttachments: const <CollaborationAttachment>[],
    agentId: '',
    metadata: const <String, dynamic>{},
    provider: provider,
    remoteWorkingDirectoryHint: remoteWorkingDirectoryHint,
    resumeSession: resumeSession,
  );
}

Future<_CapturedAcpHttpServer> _startAcpHttpServer({
  Map<String, dynamic> result = const <String, dynamic>{'ok': true},
  bool streamResponse = false,
  List<Map<String, dynamic>> streamNotifications =
      const <Map<String, dynamic>>[],
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final capture = _CapturedAcpHttpServer._(
    server,
    Uri.parse('http://127.0.0.1:${server.port}'),
  );
  server.listen((request) async {
    capture.authorizationHeader =
        request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    capture.acceptHeader =
        request.headers.value(HttpHeaders.acceptHeader) ?? '';
    capture.requestPath = request.uri.path;
    final body = await utf8.decoder.bind(request).join();
    capture.requestBody = body;
    capture.requestBodies.add(body);
    final id = _decodeRequestId(body);
    final envelope = jsonEncode(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    });
    if (streamResponse) {
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/event-stream',
      );
      for (final notification in streamNotifications) {
        request.response.write('data: ${jsonEncode(notification)}\n\n');
        await request.response.flush();
      }
      request.response.write('data: $envelope\n\n');
      request.response.write('data: [DONE]\n\n');
    } else {
      request.response.headers.contentType = ContentType.json;
      request.response.write(envelope);
    }
    await request.response.close();
  });
  return capture;
}

String _decodeRequestId(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map && decoded['id'] != null) {
    return decoded['id'].toString();
  }
  return 'request-id';
}

Map<String, dynamic> _lastRequestParams(_CapturedAcpHttpServer capture) {
  final decoded = jsonDecode(capture.requestBody) as Map<String, dynamic>;
  return (decoded['params'] as Map).cast<String, dynamic>();
}

class _CapturedAcpHttpServer {
  _CapturedAcpHttpServer._(this._server, this.baseEndpoint);

  final HttpServer _server;
  final Uri baseEndpoint;
  String authorizationHeader = '';
  String acceptHeader = '';
  String requestPath = '';
  String requestBody = '';
  final List<String> requestBodies = <String>[];

  Future<void> close() => _server.close(force: true);
}
