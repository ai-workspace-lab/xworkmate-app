@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/aris_bundle.dart';
import 'package:xworkmate/runtime/aris_llm_chat_client.dart';
import 'package:xworkmate/runtime/multi_agent_orchestrator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'MultiAgentOrchestrator falls back to local Ollama + ARIS Go core chat runtime',
    () async {
      final fakeOllama = await _FakeOllamaServer.start();
      addTearDown(fakeOllama.close);
      final bridgeClient = _FakeGoCoreClient();
      final orchestrator = MultiAgentOrchestrator(
        config: MultiAgentConfig.defaults().copyWith(
          enabled: true,
          framework: MultiAgentFramework.aris,
          arisEnabled: true,
          ollamaEndpoint: fakeOllama.baseUrl,
          architect: const AgentWorkerConfig(
            role: MultiAgentRole.architect,
            cliTool: 'gemini',
            model: 'qwen2.5-coder:latest',
            enabled: true,
          ),
          engineer: const AgentWorkerConfig(
            role: MultiAgentRole.engineer,
            cliTool: 'claude',
            model: 'qwen2.5-coder:latest',
            enabled: true,
          ),
          tester: const AgentWorkerConfig(
            role: MultiAgentRole.testerDoc,
            cliTool: 'codex',
            model: 'gpt-oss:20b',
            enabled: true,
          ),
        ),
        arisBundleRepository: _FakeArisBundleRepository(),
        binaryExistsResolver: (command) async => command == 'go',
        arisLlmChatClient: bridgeClient,
      );

      final events = <MultiAgentRunEvent>[];
      final result = await orchestrator.runCollaboration(
        taskPrompt: '实现一个 hello world 函数并补充测试',
        workingDirectory: Directory.systemTemp.path,
        selectedSkills: const <String>['research-pipeline'],
        onEvent: events.add,
      );

      expect(result.success, isTrue);
      expect(result.finalScore, 8);
      expect(result.steps.length, greaterThanOrEqualTo(3));
      expect(fakeOllama.requestCount, greaterThanOrEqualTo(2));
      expect(bridgeClient.chatCallCount, 1);
      expect(events.where((item) => item.role == 'architect'), isNotEmpty);
      expect(events.where((item) => item.role == 'engineer'), isNotEmpty);
      expect(events.where((item) => item.role == 'tester'), isNotEmpty);
    },
  );

  test(
    'MultiAgentOrchestrator routes tester claude reviews through the same Go core runtime',
    () async {
      final fakeOllama = await _FakeOllamaServer.start();
      addTearDown(fakeOllama.close);
      final bridgeClient = _FakeGoCoreClient();
      final orchestrator = MultiAgentOrchestrator(
        config: MultiAgentConfig.defaults().copyWith(
          enabled: true,
          framework: MultiAgentFramework.aris,
          arisEnabled: true,
          ollamaEndpoint: fakeOllama.baseUrl,
          architect: const AgentWorkerConfig(
            role: MultiAgentRole.architect,
            cliTool: 'gemini',
            model: 'qwen2.5-coder:latest',
            enabled: true,
          ),
          engineer: const AgentWorkerConfig(
            role: MultiAgentRole.engineer,
            cliTool: 'opencode',
            model: 'qwen2.5-coder:latest',
            enabled: true,
          ),
          tester: const AgentWorkerConfig(
            role: MultiAgentRole.testerDoc,
            cliTool: 'claude',
            model: 'claude-sonnet-4-20250514',
            enabled: true,
          ),
        ),
        arisBundleRepository: _FakeArisBundleRepository(),
        binaryExistsResolver: (command) async =>
            command == 'go' || command == 'claude',
        arisLlmChatClient: bridgeClient,
      );

      final result = await orchestrator.runCollaboration(
        taskPrompt: '实现一个 hello world 函数并补充测试',
        workingDirectory: Directory.systemTemp.path,
        selectedSkills: const <String>['research-pipeline'],
      );

      expect(result.success, isTrue);
      expect(result.finalScore, 8);
      expect(bridgeClient.claudeReviewCallCount, 1);
    },
  );
}

class _FakeGoCoreClient extends ArisLlmChatClient {
  _FakeGoCoreClient();

  int chatCallCount = 0;
  int claudeReviewCallCount = 0;

  @override
  Future<String> chat({
    required String endpoint,
    required String apiKey,
    required String model,
    required String prompt,
    String systemPrompt = '',
  }) async {
    chatCallCount += 1;
    return _reviewResponse;
  }

  @override
  Future<String> claudeReview({
    required String prompt,
    String model = '',
    String systemPrompt = '',
    String tools = '',
  }) async {
    claudeReviewCallCount += 1;
    return _reviewResponse;
  }

  static const String _reviewResponse = '''
评分: 8

## 问题列表
- 样例问题 (严重程度: 低)

## 改进建议
补充一点说明即可。
''';
}

class _FakeArisBundleRepository extends ArisBundleRepository {
  _FakeArisBundleRepository();

  @override
  Future<ResolvedArisBundle> ensureReady() async {
    return ResolvedArisBundle(
      rootPath: Directory.systemTemp.path,
      manifest: ArisBundleManifest(
        schemaVersion: 1,
        name: 'ARIS',
        bundleVersion: 'test',
        upstreamRepository: 'https://example.com',
        upstreamCommit: 'abc',
        llmChatServerPath: 'server.py',
        llmChatRequirementsPath: 'requirements.txt',
        roleSkills: const <MultiAgentRole, List<String>>{
          MultiAgentRole.architect: <String>[],
          MultiAgentRole.engineer: <String>[],
          MultiAgentRole.testerDoc: <String>[],
        },
        codexRoleSkills: const <MultiAgentRole, List<String>>{
          MultiAgentRole.architect: <String>[],
          MultiAgentRole.engineer: <String>[],
          MultiAgentRole.testerDoc: <String>[],
        },
      ),
    );
  }

  @override
  Future<Map<String, String>> loadSkillContents(
    List<String> absolutePaths,
  ) async {
    return const <String, String>{};
  }
}

class _FakeOllamaServer {
  _FakeOllamaServer._(this._server);

  final HttpServer _server;
  int requestCount = 0;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  static Future<_FakeOllamaServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeOllamaServer._(server);
    unawaited(fake._serve());
    return fake;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      requestCount += 1;
      final body = await utf8.decoder.bind(request).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      final messages = (payload['messages'] as List? ?? const <Object>[])
          .whereType<Map>()
          .toList(growable: false);
      final prompt = messages
          .map((item) => item['content']?.toString() ?? '')
          .join('\n');
      final responseText = prompt.contains('任务架构师')
          ? '''
## 概述
实现 hello world。

## 子任务
1. 实现 hello world 函数 | 复杂度：简单 | 关键技术：Dart
2. 编写回归测试 | 复杂度：简单 | 关键技术：flutter_test
'''
          : '''
```dart
String helloWorld() => 'hello';
```
''';
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'message': <String, dynamic>{'content': responseText},
            },
          ],
        }),
      );
      await request.response.close();
    }
  }
}
