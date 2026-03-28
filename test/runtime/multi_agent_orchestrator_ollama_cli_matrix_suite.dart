@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/aris_bundle.dart';
import 'package:xworkmate/runtime/multi_agent_orchestrator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'MultiAgentOrchestrator launches first-batch external tools through ollama launch',
    () async {
      final recorder = CliInvocationRecorderInternal();
      final orchestrator = MultiAgentOrchestrator(
        config: MultiAgentConfig.defaults().copyWith(
          enabled: true,
          framework: MultiAgentFramework.aris,
          arisEnabled: true,
          aiGatewayInjectionPolicy: AiGatewayInjectionPolicy.disabled,
          ollamaEndpoint: 'http://127.0.0.1:11434',
          architect: const AgentWorkerConfig(
            role: MultiAgentRole.architect,
            cliTool: 'claude',
            model: 'kimi-k2.5:cloud',
            enabled: true,
          ),
          engineer: const AgentWorkerConfig(
            role: MultiAgentRole.engineer,
            cliTool: 'codex',
            model: 'minimax-m2.7:cloud',
            enabled: true,
          ),
          tester: const AgentWorkerConfig(
            role: MultiAgentRole.testerDoc,
            cliTool: 'opencode',
            model: 'glm-5:cloud',
            enabled: true,
          ),
        ),
        binaryExistsResolver: (command) async => command == 'ollama',
        arisBundleRepository: FakeArisBundleRepositoryInternal(),
        processStarter: recorder.start,
      );

      final result = await orchestrator.runCollaboration(
        taskPrompt: '实现一个 hello world 函数并补充测试',
        workingDirectory: Directory.systemTemp.path,
      );

      expect(result.success, isTrue);
      expect(result.finalScore, 8);

      final architectInvocation = recorder.lastLaunchFor('claude');
      expect(architectInvocation.executable, 'ollama');
      expect(
        architectInvocation.arguments,
        containsAllInOrder(<String>[
          'launch',
          'claude',
          '--model',
          'kimi-k2.5:cloud',
          '--yes',
          '--',
          '-p',
        ]),
      );

      final engineerInvocation = recorder.lastLaunchFor('codex');
      expect(
        engineerInvocation.arguments,
        containsAllInOrder(<String>[
          'launch',
          'codex',
          '--model',
          'minimax-m2.7:cloud',
          '--',
          'exec',
          '--skip-git-repo-check',
          '--color',
          'never',
        ]),
      );

      final workerInvocation = recorder.lastLaunchFor('opencode');
      expect(
        workerInvocation.arguments,
        containsAllInOrder(<String>[
          'launch',
          'opencode',
          '--model',
          'glm-5:cloud',
          '--',
          'run',
          '--format',
          'default',
        ]),
      );

      for (final invocation in <InvocationInternal>[
        architectInvocation,
        engineerInvocation,
        workerInvocation,
      ]) {
        expect(
          invocation.environment['OPENAI_BASE_URL'],
          'http://127.0.0.1:11434/v1',
        );
        expect(invocation.environment['OPENAI_API_KEY'], 'ollama');
        expect(
          invocation.environment['OLLAMA_BASE_URL'],
          'http://127.0.0.1:11434',
        );
        expect(invocation.environment['OLLAMA_HOST'], 'http://127.0.0.1:11434');
      }
      expect(
        architectInvocation.environment['ANTHROPIC_BASE_URL'],
        'http://127.0.0.1:11434',
      );
      expect(architectInvocation.environment['ANTHROPIC_AUTH_TOKEN'], 'ollama');
    },
  );

  test(
    'MultiAgentOrchestrator still injects Anthropic-compatible env for claude launches',
    () async {
      final recorder = CliInvocationRecorderInternal();
      final orchestrator = MultiAgentOrchestrator(
        config: MultiAgentConfig.defaults().copyWith(
          enabled: true,
          framework: MultiAgentFramework.aris,
          arisEnabled: true,
          aiGatewayInjectionPolicy: AiGatewayInjectionPolicy.disabled,
          ollamaEndpoint: 'http://127.0.0.1:11434',
          architect: const AgentWorkerConfig(
            role: MultiAgentRole.architect,
            cliTool: 'claude',
            model: 'kimi-k2.5:cloud',
            enabled: true,
          ),
          engineer: const AgentWorkerConfig(
            role: MultiAgentRole.engineer,
            cliTool: 'claude',
            model: 'qwen3.5:cloud',
            enabled: true,
          ),
          tester: const AgentWorkerConfig(
            role: MultiAgentRole.testerDoc,
            cliTool: 'codex',
            model: 'qwen3.5',
            enabled: true,
          ),
        ),
        binaryExistsResolver: (command) async => command == 'ollama',
        arisBundleRepository: FakeArisBundleRepositoryInternal(),
        processStarter: recorder.start,
      );

      final result = await orchestrator.runCollaboration(
        taskPrompt: '实现一个 hello world 函数并补充测试',
        workingDirectory: Directory.systemTemp.path,
      );

      expect(result.success, isTrue);
      expect(result.finalScore, 8);

      final claudeEnv = recorder.lastLaunchFor('claude').environment;
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

class CliInvocationRecorderInternal {
  final List<InvocationInternal> invocations = <InvocationInternal>[];

  Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    invocations.add(
      InvocationInternal(
        executable: executable,
        arguments: List<String>.from(arguments),
        environment: Map<String, String>.from(
          environment ?? <String, String>{},
        ),
        workingDirectory: workingDirectory,
      ),
    );
    final prompt = arguments.isEmpty ? '' : arguments.last;
    final stdout = prompt.contains('任务架构师') || prompt.contains('多 Agent 协作调度者')
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
    return FakeProcessInternal(stdoutText: stdout);
  }

  InvocationInternal lastLaunchFor(String tool) {
    final matches = invocations.where(
      (item) =>
          item.executable == 'ollama' &&
          item.arguments.length >= 2 &&
          item.arguments.first == 'launch' &&
          item.arguments[1] == tool,
    );
    expect(
      matches,
      isNotEmpty,
      reason: 'No ollama launch invocation recorded for $tool',
    );
    return matches.last;
  }
}

class FakeArisBundleRepositoryInternal extends ArisBundleRepository {
  FakeArisBundleRepositoryInternal();

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

class InvocationInternal {
  const InvocationInternal({
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

class FakeProcessInternal implements Process {
  FakeProcessInternal({
    required String stdoutText,
    String stderrText = '',
    int exitCode = 0,
  }) : stdoutInternal = Stream<List<int>>.value(utf8.encode(stdoutText)),
       stderrInternal = Stream<List<int>>.value(utf8.encode(stderrText)),
       exitCodeInternal = Future<int>.value(exitCode),
       stdinInternal = File(
         '${Directory.systemTemp.path}/fake-process-stdin-${DateTime.now().microsecondsSinceEpoch}.txt',
       ).openWrite();

  final Stream<List<int>> stdoutInternal;
  final Stream<List<int>> stderrInternal;
  final Future<int> exitCodeInternal;
  final IOSink stdinInternal;

  @override
  Future<int> get exitCode => exitCodeInternal;

  @override
  int get pid => 1;

  @override
  IOSink get stdin => stdinInternal;

  @override
  Stream<List<int>> get stderr => stderrInternal;

  @override
  Stream<List<int>> get stdout => stdoutInternal;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}
