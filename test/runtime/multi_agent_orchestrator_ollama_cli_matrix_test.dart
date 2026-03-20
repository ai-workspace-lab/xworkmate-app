import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/aris_bundle.dart';
import 'package:xworkmate/runtime/multi_agent_orchestrator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'MultiAgentOrchestrator injects local Ollama env into gemini, opencode, and codex CLI runs',
    () async {
      final recorder = _CliInvocationRecorder();
      final orchestrator = MultiAgentOrchestrator(
        config: MultiAgentConfig.defaults().copyWith(
          enabled: true,
          framework: MultiAgentFramework.aris,
          arisEnabled: true,
          aiGatewayInjectionPolicy: AiGatewayInjectionPolicy.disabled,
          ollamaEndpoint: 'http://127.0.0.1:11434',
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
            cliTool: 'codex',
            model: 'gpt-oss:20b',
            enabled: true,
          ),
        ),
        binaryExistsResolver: (command) async =>
            command == 'gemini' || command == 'opencode' || command == 'codex',
        arisBundleRepository: _FakeArisBundleRepository(),
        processStarter: recorder.start,
      );

      final result = await orchestrator.runCollaboration(
        taskPrompt: '实现一个 hello world 函数并补充测试',
        workingDirectory: Directory.systemTemp.path,
      );

      expect(result.success, isTrue);
      expect(result.finalScore, 8);

      final geminiEnv = recorder.lastEnvironmentFor('gemini');
      expect(geminiEnv['OPENAI_BASE_URL'], 'http://127.0.0.1:11434/v1');
      expect(geminiEnv['OPENAI_API_KEY'], 'ollama');
      expect(geminiEnv['OLLAMA_BASE_URL'], 'http://127.0.0.1:11434');
      expect(geminiEnv['OLLAMA_HOST'], 'http://127.0.0.1:11434');

      final opencodeEnv = recorder.lastEnvironmentFor('opencode');
      expect(opencodeEnv['OPENAI_BASE_URL'], 'http://127.0.0.1:11434/v1');
      expect(opencodeEnv['OPENAI_API_KEY'], 'ollama');
      expect(opencodeEnv['OLLAMA_BASE_URL'], 'http://127.0.0.1:11434');
      expect(opencodeEnv['OLLAMA_HOST'], 'http://127.0.0.1:11434');

      final codexEnv = recorder.lastEnvironmentFor('codex');
      expect(codexEnv['OPENAI_BASE_URL'], 'http://127.0.0.1:11434/v1');
      expect(codexEnv['OPENAI_API_KEY'], 'ollama');
      expect(codexEnv['OLLAMA_BASE_URL'], 'http://127.0.0.1:11434');
      expect(codexEnv['OLLAMA_HOST'], 'http://127.0.0.1:11434');
      expect(codexEnv['ANTHROPIC_BASE_URL'], 'http://127.0.0.1:11434');
      expect(codexEnv['ANTHROPIC_AUTH_TOKEN'], 'ollama');
      expect(codexEnv['ANTHROPIC_API_KEY'], isEmpty);
    },
  );

  test(
    'MultiAgentOrchestrator injects local Ollama env into claude CLI runs',
    () async {
      final recorder = _CliInvocationRecorder();
      final orchestrator = MultiAgentOrchestrator(
        config: MultiAgentConfig.defaults().copyWith(
          enabled: true,
          framework: MultiAgentFramework.aris,
          arisEnabled: true,
          aiGatewayInjectionPolicy: AiGatewayInjectionPolicy.disabled,
          ollamaEndpoint: 'http://127.0.0.1:11434',
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
        binaryExistsResolver: (command) async =>
            command == 'gemini' || command == 'claude' || command == 'codex',
        arisBundleRepository: _FakeArisBundleRepository(),
        processStarter: recorder.start,
      );

      final result = await orchestrator.runCollaboration(
        taskPrompt: '实现一个 hello world 函数并补充测试',
        workingDirectory: Directory.systemTemp.path,
      );

      expect(result.success, isTrue);
      expect(result.finalScore, 8);

      final claudeEnv = recorder.lastEnvironmentFor('claude');
      expect(claudeEnv['OPENAI_BASE_URL'], 'http://127.0.0.1:11434/v1');
      expect(claudeEnv['OPENAI_API_KEY'], 'ollama');
      expect(claudeEnv['OLLAMA_BASE_URL'], 'http://127.0.0.1:11434');
      expect(claudeEnv['OLLAMA_HOST'], 'http://127.0.0.1:11434');
      expect(claudeEnv['ANTHROPIC_BASE_URL'], 'http://127.0.0.1:11434');
      expect(claudeEnv['ANTHROPIC_AUTH_TOKEN'], 'ollama');
      expect(claudeEnv['ANTHROPIC_API_KEY'], isEmpty);
    },
  );
}

class _CliInvocationRecorder {
  final List<_Invocation> invocations = <_Invocation>[];

  Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    invocations.add(
      _Invocation(
        executable: executable,
        arguments: List<String>.from(arguments),
        environment: Map<String, String>.from(
          environment ?? <String, String>{},
        ),
        workingDirectory: workingDirectory,
      ),
    );
    final prompt = arguments.isEmpty ? '' : arguments.last;
    final stdout = prompt.contains('任务架构师')
        ? '''
## 概述
实现 hello world。

## 子任务
1. 实现 hello world 函数 | 复杂度：简单 | 关键技术：Dart
2. 编写回归测试 | 复杂度：简单 | 关键技术：flutter_test
'''
        : prompt.contains('请审阅以下代码')
        ? '''
评分: 8

## 问题列表
- 样例问题 (严重程度: 低)

## 改进建议
补充一点说明即可。
'''
        : '''
```dart
String helloWorld() => 'hello';
```
''';
    return _FakeProcess(stdoutText: stdout);
  }

  Map<String, String> lastEnvironmentFor(String executable) {
    final matches = invocations.where((item) => item.executable == executable);
    expect(
      matches,
      isNotEmpty,
      reason: 'No invocation recorded for $executable',
    );
    return matches.last.environment;
  }
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

class _Invocation {
  const _Invocation({
    required this.executable,
    required this.arguments,
    required this.environment,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;
}

class _FakeProcess implements Process {
  _FakeProcess({
    required String stdoutText,
    String stderrText = '',
    int exitCode = 0,
  }) : _stdout = Stream<List<int>>.value(utf8.encode(stdoutText)),
       _stderr = Stream<List<int>>.value(utf8.encode(stderrText)),
       _exitCode = Future<int>.value(exitCode),
       _stdin = File(
         '${Directory.systemTemp.path}/fake-process-stdin-${DateTime.now().microsecondsSinceEpoch}.txt',
       ).openWrite();

  final Stream<List<int>> _stdout;
  final Stream<List<int>> _stderr;
  final Future<int> _exitCode;
  final IOSink _stdin;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  int get pid => 1;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stderr => _stderr;

  @override
  Stream<List<int>> get stdout => _stdout;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}
