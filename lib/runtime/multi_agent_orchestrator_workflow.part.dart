part of 'multi_agent_orchestrator.dart';

extension _MultiAgentOrchestratorWorkflow on MultiAgentOrchestrator {
  /// 运行 Architect（调度/文档分析）
  Future<ArchitectResult> _runArchitect(
    String task, {
    required FrameworkPreset preset,
    required List<String> selectedSkills,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 根据配置选择 Architect 工具
      if (_config.architectEnabled) {
        final tool = await _resolveToolForRole(
          MultiAgentRole.architect,
          _config.architectTool,
        );
        final instructionBlock = await preset.roleInstructionBlock(
          role: MultiAgentRole.architect,
          tool: tool,
          selectedSkills: selectedSkills,
        );
        final result = await _runCliPrompt(
          role: MultiAgentRole.architect,
          tool: tool,
          model: _resolvedModelForRole(
            MultiAgentRole.architect,
            configuredModel: _config.architectModel,
          ),
          prompt: _buildArchitectPrompt(task, selectedSkills, instructionBlock),
          cwd: '',
          aiGatewayBaseUrl: aiGatewayBaseUrl,
          aiGatewayApiKey: aiGatewayApiKey,
        );
        stopwatch.stop();

        // 解析分解后的任务
        final tasks = _parseDecomposedTasks(result.output);
        return ArchitectResult(
          output: result.output,
          decomposedTasks: tasks,
          duration: stopwatch.elapsed,
        );
      } else {
        // Architect 被禁用，直接返回原任务作为单一子任务
        stopwatch.stop();
        return ArchitectResult(
          output: task,
          decomposedTasks: [
            SubTask(
              id: '1',
              description: task,
              order: 1,
              type: SubTaskType.implementation,
            ),
          ],
          duration: stopwatch.elapsed,
        );
      }
    } catch (e) {
      stopwatch.stop();
      rethrow;
    }
  }

  /// 运行 Lead Engineer（主实现）
  Future<EngineerResult> _runEngineer(
    List<SubTask> tasks,
    String workingDirectory,
    List<CollaborationAttachment> attachments, {
    required FrameworkPreset preset,
    required List<String> selectedSkills,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) async {
    final stopwatch = Stopwatch()..start();
    final tool = await _resolveToolForRole(
      MultiAgentRole.engineer,
      _config.engineerTool,
    );
    final instructionBlock = await preset.roleInstructionBlock(
      role: MultiAgentRole.engineer,
      tool: tool,
      selectedSkills: selectedSkills,
    );

    final taskList = tasks
        .map((t) => '## ${t.order}. ${t.description}')
        .join('\n\n');

    final prompt =
        '''
$instructionBlock

你是一个资深工程师，负责完成以下编码任务：

### 任务列表
$taskList

### 工作目录
$workingDirectory

### 附件信息
${attachments.map((a) => '- ${a.name}: ${a.description}').join('\n')}

### 优先技能
${selectedSkills.isEmpty ? '- 无' : selectedSkills.map((item) => '- $item').join('\n')}

请完成这些任务，输出完整的代码实现。
''';

    final result = await _runCliPrompt(
      role: MultiAgentRole.engineer,
      tool: tool,
      model: _resolvedModelForRole(
        MultiAgentRole.engineer,
        configuredModel: _config.engineerModel,
      ),
      prompt: prompt,
      cwd: workingDirectory,
      aiGatewayBaseUrl: aiGatewayBaseUrl,
      aiGatewayApiKey: aiGatewayApiKey,
    );
    stopwatch.stop();

    return EngineerResult(
      output: result.output,
      codeOutput: result.output,
      completedTasks: tasks,
      duration: stopwatch.elapsed,
    );
  }

  /// 运行 Worker/Review（代码审阅）
  Future<TesterResult> _runTester(
    String codeOutput, {
    required FrameworkPreset preset,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) async {
    final stopwatch = Stopwatch()..start();
    final tool = await _resolveToolForRole(
      MultiAgentRole.testerDoc,
      _config.testerTool,
    );
    final instructionBlock = await preset.roleInstructionBlock(
      role: MultiAgentRole.testerDoc,
      tool: tool,
      selectedSkills: const <String>[],
    );

    final prompt =
        '''
$instructionBlock

请审阅以下代码，并按以下格式输出：

## 评分 (1-10)
[1-10 的分数，10 最高]

## 问题列表
[发现的问题，格式：- 问题描述 (严重程度: 高/中/低)]

## 改进建议
[具体的改进建议]

## 测试用例
```[语言]
[生成的测试用例代码]
```

## 文档建议
[如有需要补充的文档说明]

### 待审阅代码
${codeOutput.length > 4000 ? '${codeOutput.substring(0, 4000)}\n...[代码已截断]' : codeOutput}
''';

    final testerModel = _resolvedModelForRole(
      MultiAgentRole.testerDoc,
      configuredModel: _config.testerModel,
    );
    final result = _config.usesAris && tool == 'claude'
        ? await _runArisTesterViaClaudeReview(
            model: testerModel,
            prompt: prompt,
          )
        : await _runCliPrompt(
            role: MultiAgentRole.testerDoc,
            tool: tool,
            model: testerModel,
            prompt: prompt,
            cwd: '',
            aiGatewayBaseUrl: aiGatewayBaseUrl,
            aiGatewayApiKey: aiGatewayApiKey,
          );
    stopwatch.stop();

    final score = _parseReviewScore(result.output);
    final feedback = _extractFeedback(result.output);

    return TesterResult(
      output: result.output,
      score: score,
      feedback: feedback,
      duration: stopwatch.elapsed,
    );
  }

  /// 运行修复（迭代循环中）
  Future<EngineerResult> _runFix(
    String originalCode,
    String feedback,
    String workingDirectory, {
    required FrameworkPreset preset,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) async {
    final stopwatch = Stopwatch()..start();
    final tool = await _resolveToolForRole(
      MultiAgentRole.engineer,
      _config.engineerTool,
    );
    final instructionBlock = await preset.roleInstructionBlock(
      role: MultiAgentRole.engineer,
      tool: tool,
      selectedSkills: const <String>[],
    );

    final prompt =
        '''
$instructionBlock

你是一个资深工程师。请根据审阅反馈修复代码。

## 审阅反馈
$feedback

## 原始代码
$originalCode

请完成修复，输出修复后的完整代码。
''';

    final result = await _runCliPrompt(
      role: MultiAgentRole.engineer,
      tool: tool,
      model: _resolvedModelForRole(
        MultiAgentRole.engineer,
        configuredModel: _config.engineerModel,
      ),
      prompt: prompt,
      cwd: workingDirectory,
      aiGatewayBaseUrl: aiGatewayBaseUrl,
      aiGatewayApiKey: aiGatewayApiKey,
    );
    stopwatch.stop();

    return EngineerResult(
      output: result.output,
      codeOutput: result.output,
      completedTasks: [],
      duration: stopwatch.elapsed,
    );
  }

  /// 通用的 CLI 进程执行方法
  Future<CliResult> _runCliPrompt({
    required MultiAgentRole role,
    required String tool,
    required String model,
    required String prompt,
    required String cwd,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) async {
    late final List<String> args;
    late final String command;
    late final Map<String, String> envVars;
    final useOllamaLaunch = _prefersOllamaLaunch(tool: tool, model: model);

    switch (tool) {
      case 'claude':
        command = useOllamaLaunch ? 'ollama' : _resolveCliPath('claude');
        envVars = _buildCliEnvVars(
          tool: tool,
          aiGatewayBaseUrl: aiGatewayBaseUrl,
          aiGatewayApiKey: aiGatewayApiKey,
        );
        if (useOllamaLaunch) {
          args = _buildOllamaLaunchArgs(
            tool: tool,
            model: model,
            prompt: prompt,
            cwd: cwd,
          );
        } else if (model.isNotEmpty) {
          args = ['--model', model, '-p', prompt];
        } else {
          args = ['-p', prompt];
        }
        break;

      case 'codex':
        command = useOllamaLaunch ? 'ollama' : _resolveCliPath('codex');
        envVars = _buildCliEnvVars(
          tool: tool,
          aiGatewayBaseUrl: aiGatewayBaseUrl,
          aiGatewayApiKey: aiGatewayApiKey,
        );
        if (useOllamaLaunch) {
          args = _buildOllamaLaunchArgs(
            tool: tool,
            model: model,
            prompt: prompt,
            cwd: cwd,
          );
        } else if (model.isNotEmpty) {
          args = [
            'exec',
            '--skip-git-repo-check',
            '--color',
            'never',
            if (cwd.isNotEmpty) ...['-C', cwd],
            '-m',
            model,
            prompt,
          ];
        } else {
          args = [
            'exec',
            '--skip-git-repo-check',
            '--color',
            'never',
            if (cwd.isNotEmpty) ...['-C', cwd],
            prompt,
          ];
        }
        break;

      case 'gemini':
        command = _resolveCliPath('gemini');
        envVars = _buildCliEnvVars(
          tool: tool,
          aiGatewayBaseUrl: aiGatewayBaseUrl,
          aiGatewayApiKey: aiGatewayApiKey,
        );
        if (model.isNotEmpty) {
          args = ['--model', model, '-p', prompt];
        } else {
          args = ['-p', prompt];
        }
        break;

      case 'opencode':
        command = useOllamaLaunch ? 'ollama' : _resolveCliPath('opencode');
        envVars = _buildCliEnvVars(
          tool: tool,
          aiGatewayBaseUrl: aiGatewayBaseUrl,
          aiGatewayApiKey: aiGatewayApiKey,
        );
        args = useOllamaLaunch
            ? _buildOllamaLaunchArgs(
                tool: tool,
                model: model,
                prompt: prompt,
                cwd: cwd,
              )
            : [
                'run',
                '--format',
                'default',
                if (cwd.isNotEmpty) ...['--dir', cwd],
                if (model.isNotEmpty) ...['-m', model],
                prompt,
              ];
        break;

      default:
        throw ArgumentError('Unknown tool: $tool');
    }

    final cliAvailable = await _binaryExists(command);
    if (_config.usesAris && !cliAvailable) {
      return _runArisFallback(
        role: role,
        model: model,
        prompt: prompt,
        aiGatewayBaseUrl: aiGatewayBaseUrl,
        aiGatewayApiKey: aiGatewayApiKey,
      );
    }

    try {
      final process = await _processStarter(
        command,
        args,
        environment: envVars,
        workingDirectory: cwd.isNotEmpty ? cwd : null,
      );
      _activeCliProcess = process;

      await process.stdin.close();

      // 超时控制
      final timeout = Duration(seconds: _config.timeoutSeconds);

      final stdoutFuture = process.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(
            timeout,
            onTimeout: () {
              process.kill();
              return '[超时或进程已终止]';
            },
          );

      final stderrFuture = process.stderr
          .transform(utf8.decoder)
          .join()
          .timeout(timeout, onTimeout: () => '');

      final results = await Future.wait([stdoutFuture, stderrFuture]);
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () => -1,
      );
      _activeCliProcess = null;

      final cliResult = CliResult(
        output: results[0],
        error: results[1],
        exitCode: exitCode,
      );
      if (_config.usesAris && !cliResult.success) {
        return _runArisFallback(
          role: role,
          model: model,
          prompt: prompt,
          aiGatewayBaseUrl: aiGatewayBaseUrl,
          aiGatewayApiKey: aiGatewayApiKey,
        );
      }
      return cliResult;
    } catch (e) {
      _activeCliProcess = null;
      if (_config.usesAris) {
        return _runArisFallback(
          role: role,
          model: model,
          prompt: prompt,
          aiGatewayBaseUrl: aiGatewayBaseUrl,
          aiGatewayApiKey: aiGatewayApiKey,
        );
      }
      return CliResult(output: '', error: e.toString(), exitCode: -1);
    }
  }

  /// 构建 Architect 的 Prompt
  String _buildArchitectPrompt(
    String task,
    List<String> selectedSkills,
    String instructionBlock,
  ) {
    return '''
$instructionBlock

你是一个多 Agent 协作调度者。请先收敛 requirements -> acceptance evidence，再输出可执行的主程/worker分工。

## 用户需求
$task

## 优先技能
${selectedSkills.isEmpty ? '- 无' : selectedSkills.map((item) => '- $item').join('\n')}

请输出：
1. 任务概述（2-3 句话）
2. 子任务列表（3-5 个），每个子任务包含：
   - 任务编号和描述
   - 负责角色（文档/主程/worker）
   - 接受标准
   - 关键技术点
3. 推荐的执行顺序与关键里程碑

请严格按以下格式输出：
## 概述
[你的概述]

## 子任务
1. [任务描述] | 角色：[文档/主程/worker] | 接受标准：[可验证结果] | 关键技术：[技术点]
2. [任务描述] | 角色：[文档/主程/worker] | 接受标准：[可验证结果] | 关键技术：[技术点]
...
''';
  }

  Future<String> _resolveToolForRole(
    MultiAgentRole role,
    String configuredTool,
  ) async {
    if (!_config.usesAris) {
      return configuredTool;
    }
    final configuredModel = _resolvedModelForRole(
      role,
      configuredModel: _modelForRole(role).trim(),
    );
    final candidates = switch (role) {
      MultiAgentRole.architect => <String>[
        configuredTool,
        'claude',
        'codex',
        'opencode',
        'gemini',
      ],
      MultiAgentRole.engineer => <String>[
        configuredTool,
        'codex',
        'opencode',
        'claude',
        'gemini',
      ],
      MultiAgentRole.testerDoc => <String>[
        configuredTool,
        'opencode',
        'codex',
        'claude',
        'gemini',
      ],
    };
    for (final candidate in candidates) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (_prefersOllamaLaunch(tool: trimmed, model: configuredModel)) {
        if (await _binaryExists('ollama')) {
          return trimmed;
        }
      } else if (await _binaryExists(_resolveCliPath(trimmed))) {
        return trimmed;
      }
    }
    return configuredTool;
  }

  String _resolvedModelForRole(
    MultiAgentRole role, {
    required String configuredModel,
  }) {
    final trimmed = configuredModel.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    switch (role) {
      case MultiAgentRole.architect:
        return 'kimi-k2.5:cloud';
      case MultiAgentRole.engineer:
        return 'minimax-m2.7:cloud';
      case MultiAgentRole.testerDoc:
        return 'glm-5:cloud';
    }
  }

  Future<bool> _binaryExists(String command) async {
    final resolver = _binaryExistsResolver;
    if (resolver != null) {
      return resolver(command);
    }
    final check = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      <String>[command],
      runInShell: true,
    );
    return check.exitCode == 0 && '${check.stdout}'.trim().isNotEmpty;
  }

  Future<CliResult> _runArisFallback({
    required MultiAgentRole role,
    required String model,
    required String prompt,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) async {
    if (role == MultiAgentRole.testerDoc) {
      final viaLlmChat = await _runArisTesterViaLlmChat(
        model: model,
        prompt: prompt,
        aiGatewayBaseUrl: aiGatewayBaseUrl,
        aiGatewayApiKey: aiGatewayApiKey,
      );
      if (viaLlmChat.success) {
        return viaLlmChat;
      }
    }
    return _runOpenAiCompatiblePrompt(
      role: role,
      model: model,
      prompt: prompt,
      aiGatewayBaseUrl: aiGatewayBaseUrl,
      aiGatewayApiKey: aiGatewayApiKey,
    );
  }

  Future<CliResult> _runArisTesterViaLlmChat({
    required String model,
    required String prompt,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) async {
    try {
      if (!await _goCoreLocator.isAvailable()) {
        return const CliResult(
          output: '',
          error: 'Go core is unavailable for llm-chat',
          exitCode: -1,
        );
      }
      final endpoint = _openAiCompatibleBaseUrl(
        aiGatewayBaseUrl: aiGatewayBaseUrl,
      );
      final apiKey = _openAiCompatibleApiKey(aiGatewayApiKey: aiGatewayApiKey);
      final output = await _arisLlmChatClient.chat(
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        prompt: prompt,
        systemPrompt:
            'You are the ARIS reviewer. Review the provided implementation and return actionable feedback.',
      );
      return CliResult(output: output, error: '', exitCode: 0);
    } catch (error) {
      return CliResult(output: '', error: error.toString(), exitCode: -1);
    }
  }

  Future<CliResult> _runArisTesterViaClaudeReview({
    required String model,
    required String prompt,
  }) async {
    try {
      if (!await _goCoreLocator.isAvailable()) {
        return const CliResult(
          output: '',
          error: 'Go core is unavailable for claude-review',
          exitCode: -1,
        );
      }
      if (!await _binaryExists(_resolveCliPath('claude'))) {
        return const CliResult(
          output: '',
          error: 'Claude CLI is unavailable for claude-review',
          exitCode: -1,
        );
      }
      final output = await _arisLlmChatClient.claudeReview(
        prompt: prompt,
        model: model,
        systemPrompt:
            'You are the ARIS reviewer. Review the provided implementation and return actionable feedback.',
      );
      return CliResult(output: output, error: '', exitCode: 0);
    } catch (error) {
      return CliResult(output: '', error: error.toString(), exitCode: -1);
    }
  }

  Future<CliResult> _runOpenAiCompatiblePrompt({
    required MultiAgentRole role,
    required String model,
    required String prompt,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) async {
    final client = _httpClientFactory();
    _activeHttpClient = client;
    try {
      final request = await client.postUrl(
        Uri.parse(
          '${_openAiCompatibleBaseUrl(aiGatewayBaseUrl: aiGatewayBaseUrl).replaceAll(RegExp(r'/$'), '')}/chat/completions',
        ),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${_openAiCompatibleApiKey(aiGatewayApiKey: aiGatewayApiKey)}',
      );
      request.add(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'model': model,
            'stream': false,
            'messages': <Map<String, String>>[
              <String, String>{
                'role': 'system',
                'content': _systemPromptForRole(role),
              },
              <String, String>{'role': 'user', 'content': prompt},
            ],
          }),
        ),
      );
      final response = await request.close().timeout(
        Duration(seconds: _config.timeoutSeconds),
      );
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CliResult(
          output: '',
          error: body,
          exitCode: response.statusCode,
        );
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List? ?? const <Object>[];
      final firstChoice = choices.isNotEmpty ? choices.first : null;
      final output =
          ((firstChoice as Map?)?['message'] as Map?)?['content']?.toString() ??
          '';
      return CliResult(output: output, error: '', exitCode: 0);
    } catch (error) {
      return CliResult(output: '', error: error.toString(), exitCode: -1);
    } finally {
      _activeHttpClient = null;
      try {
        client.close(force: true);
      } catch (_) {
        // Best effort only.
      }
    }
  }


}
