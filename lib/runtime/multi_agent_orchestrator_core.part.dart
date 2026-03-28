part of 'multi_agent_orchestrator.dart';

typedef CliProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      String? workingDirectory,
    });

/// 多 Agent 协作编排器
///
/// 管理 Architect（调度/文档）→ Lead Engineer（主程）→ Worker/Review（并行 worker + 复审）
/// 的工作流，通过 Ollama 与外部 CLI 工具桥接首批云模型协作能力。
///
/// 角色分工：
/// - Architect（调度/文档）：负责任务分解、接受标准、工作流设计
/// - Lead Engineer（主程）：负责关键实现、重构、集成收口
/// - Worker/Review（并行 worker）：负责补充实现、复审、回归建议
class MultiAgentOrchestrator extends ChangeNotifier {
  MultiAgentOrchestrator({
    required MultiAgentConfig config,
    ArisBundleRepository? arisBundleRepository,
    GoCoreLocator? goCoreLocator,
    Future<bool> Function(String command)? binaryExistsResolver,
    HttpClient Function()? httpClientFactory,
    ArisLlmChatClient? arisLlmChatClient,
    CliProcessStarter? processStarter,
  }) : _config = config,
       _arisBundleRepository = arisBundleRepository ?? ArisBundleRepository(),
       _goCoreLocator =
           goCoreLocator ??
           GoCoreLocator(binaryExistsResolver: binaryExistsResolver),
       _binaryExistsResolver = binaryExistsResolver,
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _processStarter =
           processStarter ??
           ((executable, arguments, {environment, workingDirectory}) {
             return Process.start(
               executable,
               arguments,
               environment: environment,
               workingDirectory: workingDirectory,
             );
           }),
       _arisLlmChatClient =
           arisLlmChatClient ??
           ArisLlmChatClient(
             bridgeLocator:
                 goCoreLocator ??
                 GoCoreLocator(binaryExistsResolver: binaryExistsResolver),
           );

  /// 当前配置
  MultiAgentConfig _config;
  MultiAgentConfig get config => _config;
  final ArisBundleRepository _arisBundleRepository;
  final GoCoreLocator _goCoreLocator;
  final Future<bool> Function(String command)? _binaryExistsResolver;
  final HttpClient Function() _httpClientFactory;
  final CliProcessStarter _processStarter;
  final ArisLlmChatClient _arisLlmChatClient;
  Process? _activeCliProcess;
  HttpClient? _activeHttpClient;
  bool _abortRequested = false;

  /// 协作模式是否启用
  bool _collaborationEnabled = false;
  bool get collaborationEnabled => _collaborationEnabled;

  /// 是否正在运行
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// 最后错误
  String? _lastError;
  String? get lastError => _lastError;

  /// 当前迭代轮次
  int _currentIteration = 0;
  int get currentIteration => _currentIteration;

  /// 状态日志
  final List<CollaborationLogEntry> _logEntries = [];
  List<CollaborationLogEntry> get logEntries => List.unmodifiable(_logEntries);

  /// 更新配置
  void updateConfig(MultiAgentConfig config) {
    _config = config;
    _collaborationEnabled = config.enabled;
    notifyListeners();
  }

  Future<void> abort() async {
    _abortRequested = true;
    final process = _activeCliProcess;
    _activeCliProcess = null;
    if (process != null) {
      try {
        process.kill();
      } catch (_) {
        // Best effort only.
      }
    }
    final client = _activeHttpClient;
    _activeHttpClient = null;
    if (client != null) {
      try {
        client.close(force: true);
      } catch (_) {
        // Best effort only.
      }
    }
  }

  void _assertEmbeddedProcessesAllowed() {
    if (shouldBlockEmbeddedAgentLaunch(
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    )) {
      throw UnsupportedError(
        'App Store builds do not allow launching embedded multi-agent subprocesses.',
      );
    }
  }

  /// 启用协作模式
  void enable() {
    _config = _config.copyWith(enabled: true);
    _collaborationEnabled = true;
    _lastError = null;
    notifyListeners();
  }

  /// 禁用协作模式
  void disable() {
    _config = _config.copyWith(enabled: false);
    _collaborationEnabled = false;
    notifyListeners();
  }

  /// 切换协作模式
  void toggle() {
    if (_collaborationEnabled) {
      disable();
    } else {
      enable();
    }
  }

  /// 执行完整的协作工作流
  ///
  /// 流程：Architect 分析 → Engineer 实现 → Tester 审阅 → 迭代（如需要）
  Future<CollaborationResult> runCollaboration({
    required String taskPrompt,
    required String workingDirectory,
    List<CollaborationAttachment> attachments = const [],
    List<String> selectedSkills = const [],
    String aiGatewayBaseUrl = '',
    String aiGatewayApiKey = '',
    void Function(MultiAgentRunEvent event)? onEvent,
  }) async {
    _assertEmbeddedProcessesAllowed();
    if (_isRunning) {
      throw StateError('Collaboration is already running');
    }

    _isRunning = true;
    _currentIteration = 0;
    _abortRequested = false;
    _logEntries.clear();
    _lastError = null;
    notifyListeners();

    final startTime = DateTime.now();
    final steps = <CollaborationStep>[];
    final preset = _config.usesAris
        ? ArisFrameworkPreset(_arisBundleRepository)
        : const NativeFrameworkPreset();

    try {
      // === Phase 1: Architect 分析任务 ===
      _throwIfAborted();
      _log(
        CollaborationLogLevel.info,
        '🎨',
        '${_roleLabel(MultiAgentRole.architect)} 开始分析任务...',
      );
      _emitEvent(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: _roleLabel(MultiAgentRole.architect),
          message: '${_roleLabel(MultiAgentRole.architect)} 开始分析任务…',
          pending: true,
          error: false,
          role: 'architect',
        ),
      );
      final architectResult = await _runArchitect(
        taskPrompt,
        preset: preset,
        selectedSkills: selectedSkills,
        aiGatewayBaseUrl: aiGatewayBaseUrl,
        aiGatewayApiKey: aiGatewayApiKey,
      );
      steps.add(
        CollaborationStep(
          role: 'architect',
          status: StepStatus.completed,
          output: architectResult.output,
          duration: architectResult.duration,
        ),
      );
      _emitEvent(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: _roleLabel(MultiAgentRole.architect),
          message: '完成任务分析并生成执行分解。',
          pending: false,
          error: false,
          role: 'architect',
          data: <String, dynamic>{
            'taskCount': architectResult.decomposedTasks.length,
          },
        ),
      );

      // === Phase 2: Engineer 实现 ===
      _throwIfAborted();
      _log(
        CollaborationLogLevel.info,
        '🔧',
        '${_roleLabel(MultiAgentRole.engineer)} 开始实现...',
      );
      _emitEvent(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: _roleLabel(MultiAgentRole.engineer),
          message: '${_roleLabel(MultiAgentRole.engineer)} 开始实现任务…',
          pending: true,
          error: false,
          role: 'engineer',
        ),
      );
      final engineerResult = await _runEngineer(
        architectResult.decomposedTasks,
        workingDirectory,
        attachments,
        preset: preset,
        selectedSkills: selectedSkills,
        aiGatewayBaseUrl: aiGatewayBaseUrl,
        aiGatewayApiKey: aiGatewayApiKey,
      );
      steps.add(
        CollaborationStep(
          role: 'engineer',
          status: StepStatus.completed,
          output: engineerResult.output,
          duration: engineerResult.duration,
        ),
      );
      _emitEvent(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: _roleLabel(MultiAgentRole.engineer),
          message: '完成首轮实现。',
          pending: false,
          error: false,
          role: 'engineer',
        ),
      );

      // === Phase 3: Tester 审阅 ===
      _throwIfAborted();
      _log(
        CollaborationLogLevel.info,
        '🔍',
        '${_roleLabel(MultiAgentRole.testerDoc)} 开始审阅...',
      );
      _emitEvent(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: _roleLabel(MultiAgentRole.testerDoc),
          message: '${_roleLabel(MultiAgentRole.testerDoc)} 开始审阅实现…',
          pending: true,
          error: false,
          role: 'tester',
        ),
      );
      final testerResult = await _runTester(
        engineerResult.codeOutput,
        preset: preset,
        aiGatewayBaseUrl: aiGatewayBaseUrl,
        aiGatewayApiKey: aiGatewayApiKey,
      );
      steps.add(
        CollaborationStep(
          role: 'tester',
          status: StepStatus.completed,
          output: testerResult.output,
          duration: testerResult.duration,
          score: testerResult.score,
        ),
      );
      _emitEvent(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: _roleLabel(MultiAgentRole.testerDoc),
          message: '完成代码审阅。',
          pending: false,
          error: false,
          role: 'tester',
          score: testerResult.score,
        ),
      );

      // === Phase 4: 迭代审阅循环（如需要）===
      if (testerResult.score < _config.minAcceptableScore) {
        _log(
          CollaborationLogLevel.warning,
          '⚠️',
          '质量评分 ${testerResult.score}/10 未达标，开始迭代审阅...',
        );

        for (var i = 0; i < _config.maxIterations; i++) {
          _throwIfAborted();
          _currentIteration = i + 1;
          _log(
            CollaborationLogLevel.info,
            '🔄',
            '迭代 $_currentIteration/${_config.maxIterations}...',
          );
          notifyListeners();

          // Lead Engineer 接收反馈并修复
          final fixedResult = await _runFix(
            engineerResult.codeOutput,
            testerResult.feedback,
            workingDirectory,
            preset: preset,
            aiGatewayBaseUrl: aiGatewayBaseUrl,
            aiGatewayApiKey: aiGatewayApiKey,
          );
          steps.add(
            CollaborationStep(
              role: 'engineer',
              status: StepStatus.completed,
              output: fixedResult.output,
              duration: fixedResult.duration,
              iteration: _currentIteration,
            ),
          );

          // Tester 重新审阅
          final reReview = await _runTester(
            fixedResult.codeOutput,
            preset: preset,
            aiGatewayBaseUrl: aiGatewayBaseUrl,
            aiGatewayApiKey: aiGatewayApiKey,
          );
          steps.add(
            CollaborationStep(
              role: 'tester',
              status: StepStatus.completed,
              output: reReview.output,
              duration: reReview.duration,
              score: reReview.score,
              iteration: _currentIteration,
            ),
          );

          if (reReview.score >= _config.minAcceptableScore) {
            _log(
              CollaborationLogLevel.success,
              '✅',
              '质量达标 (${reReview.score}/10)，迭代结束',
            );
            engineerResult.codeOutput = fixedResult.codeOutput;
            break;
          } else if (_currentIteration >= _config.maxIterations) {
            _log(
              CollaborationLogLevel.error,
              '❌',
              '达到最大迭代次数 ${_config.maxIterations}，质量仍未达标',
            );
          }
        }
      } else {
        _log(
          CollaborationLogLevel.success,
          '✅',
          '质量达标 (${testerResult.score}/10)，无需迭代',
        );
      }

      final duration = DateTime.now().difference(startTime);
      _isRunning = false;
      notifyListeners();

      return CollaborationResult(
        success: true,
        steps: steps,
        finalCode: engineerResult.codeOutput,
        finalScore: testerResult.score,
        duration: duration,
        iterations: _currentIteration,
      );
    } catch (e) {
      _lastError = e.toString();
      _log(CollaborationLogLevel.error, '❌', '协作失败: $_lastError');
      _isRunning = false;
      notifyListeners();

      return CollaborationResult(
        success: false,
        steps: steps,
        finalCode: '',
        finalScore: 0,
        duration: DateTime.now().difference(startTime),
        iterations: _currentIteration,
        error: _lastError,
      );
    }
  }

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

  String _openAiCompatibleBaseUrl({required String aiGatewayBaseUrl}) {
    if (_config.aiGatewayInjectionPolicy != AiGatewayInjectionPolicy.disabled &&
        aiGatewayBaseUrl.trim().isNotEmpty) {
      final normalized = aiGatewayBaseUrl.trim();
      return normalized.endsWith('/v1') ? normalized : '$normalized/v1';
    }
    final normalized = _config.ollamaEndpoint.trim();
    return normalized.endsWith('/v1') ? normalized : '$normalized/v1';
  }

  String _openAiCompatibleApiKey({required String aiGatewayApiKey}) {
    if (_config.aiGatewayInjectionPolicy != AiGatewayInjectionPolicy.disabled &&
        aiGatewayApiKey.trim().isNotEmpty) {
      return aiGatewayApiKey.trim();
    }
    return 'ollama';
  }

  String _systemPromptForRole(MultiAgentRole role) {
    return switch (role) {
      MultiAgentRole.architect =>
        'You are the architecture and documentation lane in a multi-agent coding workflow. Focus on requirements, acceptance evidence, task slicing, and milestones.',
      MultiAgentRole.engineer =>
        'You are the lead engineer in a multi-agent coding workflow. Produce implementation-oriented output for the critical path.',
      MultiAgentRole.testerDoc =>
        'You are the worker-review lane in a multi-agent coding workflow. Review, score, and suggest follow-up fixes and worker follow-ups.',
    };
  }

  String _roleLabel(MultiAgentRole role) {
    return switch (role) {
      MultiAgentRole.architect => 'Architect',
      MultiAgentRole.engineer => 'Lead Engineer',
      MultiAgentRole.testerDoc => 'Worker/Review',
    };
  }

  String _modelForRole(MultiAgentRole role) {
    return switch (role) {
      MultiAgentRole.architect => _config.architect.model,
      MultiAgentRole.engineer => _config.engineer.model,
      MultiAgentRole.testerDoc => _config.tester.model,
    };
  }

  bool _prefersOllamaLaunch({required String tool, required String model}) {
    final normalizedTool = tool.trim().toLowerCase();
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty) {
      return false;
    }
    if (normalizedTool != 'claude' &&
        normalizedTool != 'codex' &&
        normalizedTool != 'opencode') {
      return false;
    }
    return true;
  }

  List<String> _buildOllamaLaunchArgs({
    required String tool,
    required String model,
    required String prompt,
    required String cwd,
  }) {
    final args = <String>['launch', tool, '--model', model];
    if (tool == 'claude') {
      args.add('--yes');
      args.addAll(<String>['--', '-p', prompt]);
      return args;
    }
    if (tool == 'codex') {
      args.addAll(<String>[
        '--',
        'exec',
        '--skip-git-repo-check',
        '--color',
        'never',
        if (cwd.isNotEmpty) ...<String>['-C', cwd],
        prompt,
      ]);
      return args;
    }
    if (tool == 'opencode') {
      args.addAll(<String>[
        '--',
        'run',
        '--format',
        'default',
        if (cwd.isNotEmpty) ...<String>['--dir', cwd],
        prompt,
      ]);
      return args;
    }
    args.addAll(<String>['--', '-p', prompt]);
    return args;
  }

  void _throwIfAborted() {
    if (_abortRequested) {
      throw StateError('Multi-agent collaboration aborted.');
    }
  }

  /// 解析 Architect 分解的任务
  List<SubTask> _parseDecomposedTasks(String architectOutput) {
    final tasks = <SubTask>[];
    final lines = architectOutput.split('\n');

    var order = 1;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 匹配 "- 描述" 或 "1. 描述" 格式
      final dashMatch = RegExp(r'^[-*]\s+(.+)').firstMatch(trimmed);
      final numMatch = RegExp(r'^\d+[.、)]\s*(.+)').firstMatch(trimmed);

      String? description;
      if (dashMatch != null) {
        description = dashMatch.group(1);
      } else if (numMatch != null) {
        description = numMatch.group(1);
      }

      if (description != null && description.isNotEmpty) {
        // 去除复杂度等技术注释
        description = description.replaceAll(RegExp(r'\s*\|.*'), '').trim();

        // 判断任务类型
        SubTaskType type = SubTaskType.implementation;
        final lower = description.toLowerCase();
        if (lower.contains('测试') || lower.contains('test')) {
          type = SubTaskType.testing;
        } else if (lower.contains('文档') || lower.contains('doc')) {
          type = SubTaskType.documentation;
        } else if (lower.contains('设计') || lower.contains('design')) {
          type = SubTaskType.design;
        } else if (lower.contains('部署') || lower.contains('deploy')) {
          type = SubTaskType.deployment;
        }

        tasks.add(
          SubTask(
            id: order.toString(),
            description: description,
            order: order,
            type: type,
          ),
        );
        order++;
      }
    }

    // 如果解析失败，至少返回一个包含完整需求的子任务
    if (tasks.isEmpty) {
      tasks.add(
        SubTask(
          id: '1',
          description: architectOutput.length > 200
              ? '${architectOutput.substring(0, 200)}...'
              : architectOutput,
          order: 1,
          type: SubTaskType.implementation,
        ),
      );
    }

    return tasks;
  }

  /// 解析审阅评分
  int _parseReviewScore(String output) {
    // 尝试匹配 "评分 (1-10)" 模式
    final patterns = [
      RegExp(r'评分\s*\(?[1１00]\)?\s*[:：]?\s*(\d+)'),
      RegExp(r'score\s*[:：]?\s*(\d+)', caseSensitive: false),
      RegExp(r'评分[：:\s]*(\d+)'),
      RegExp(r'\*\*(\d+)\s*/\s*10\*\*'),
      RegExp(r'(\d+)\s*/\s*10'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(output);
      if (match != null) {
        final scoreStr = match.group(1)!;
        final score = int.tryParse(
          scoreStr.replaceAll('１', '1').replaceAll('０', '0'),
        );
        if (score != null && score >= 1 && score <= 10) {
          return score;
        }
      }
    }

    // 默认中等评分
    return 5;
  }

  /// 提取审阅反馈
  String _extractFeedback(String output) {
    final feedbackIndex = output.indexOf(RegExp(r'##?\s*问题|##?\s*改进|##?\s*建议'));
    if (feedbackIndex >= 0) {
      final endIndex = output.indexOf(
        RegExp(r'##?\s*测试|##?\s*文档'),
        feedbackIndex + 1,
      );
      if (endIndex > feedbackIndex) {
        return output.substring(feedbackIndex, endIndex).trim();
      }
      return output.substring(feedbackIndex).trim();
    }
    return output;
  }

  /// 构建 Ollama 环境变量
  Map<String, String> _buildCliEnvVars({
    required String tool,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) {
    final baseEnv = <String, String>{...Platform.environment};
    if (_config.aiGatewayInjectionPolicy != AiGatewayInjectionPolicy.disabled &&
        aiGatewayBaseUrl.trim().isNotEmpty &&
        aiGatewayApiKey.trim().isNotEmpty) {
      baseEnv['OPENAI_BASE_URL'] = aiGatewayBaseUrl.trim();
      baseEnv['OPENAI_API_KEY'] = aiGatewayApiKey.trim();
      baseEnv['OLLAMA_BASE_URL'] = aiGatewayBaseUrl.trim();
      baseEnv['OLLAMA_HOST'] = aiGatewayBaseUrl.trim();
      if (tool == 'claude') {
        baseEnv['ANTHROPIC_BASE_URL'] = aiGatewayBaseUrl.trim();
        baseEnv['ANTHROPIC_AUTH_TOKEN'] = aiGatewayApiKey.trim();
        baseEnv['ANTHROPIC_API_KEY'] = aiGatewayApiKey.trim();
      }
      return baseEnv;
    }
    final ollamaEndpoint = _config.ollamaEndpoint.trim();
    if (ollamaEndpoint.isNotEmpty) {
      baseEnv['OLLAMA_BASE_URL'] = ollamaEndpoint;
      baseEnv['OLLAMA_HOST'] = ollamaEndpoint;
      baseEnv['OPENAI_API_KEY'] = 'ollama';
      baseEnv['OPENAI_BASE_URL'] = ollamaEndpoint.endsWith('/v1')
          ? ollamaEndpoint
          : '$ollamaEndpoint/v1';
    }
    if (tool == 'claude' || tool == 'codex') {
      baseEnv['ANTHROPIC_AUTH_TOKEN'] = 'ollama';
      baseEnv['ANTHROPIC_API_KEY'] = '';
      baseEnv['ANTHROPIC_BASE_URL'] = ollamaEndpoint;
    }
    return baseEnv;
  }

  /// 解析 CLI 工具路径
  String _resolveCliPath(String tool) {
    switch (tool) {
      case 'claude':
        return 'claude';
      case 'codex':
        return 'codex';
      case 'gemini':
        return 'gemini';
      case 'opencode':
        return 'opencode';
      default:
        return tool;
    }
  }

  void _emitEvent(
    void Function(MultiAgentRunEvent event)? onEvent,
    MultiAgentRunEvent event,
  ) {
    onEvent?.call(event);
  }

  /// 记录日志
  void _log(CollaborationLogLevel level, String emoji, String message) {
    _logEntries.add(
      CollaborationLogEntry(
        timestamp: DateTime.now(),
        level: level,
        emoji: emoji,
        message: message,
      ),
    );
    notifyListeners();
  }

  /// 清除日志
  void clearLogs() {
    _logEntries.clear();
    notifyListeners();
  }
}

// ============================================================
// 数据模型
// ============================================================

/// 协作日志条目
class CollaborationLogEntry {
  const CollaborationLogEntry({
    required this.timestamp,
    required this.level,
    required this.emoji,
    required this.message,
  });

  final DateTime timestamp;
  final CollaborationLogLevel level;
  final String emoji;
  final String message;

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

enum CollaborationLogLevel { debug, info, warning, error, success }

/// CLI 执行结果
class CliResult {
  const CliResult({
    required this.output,
    required this.error,
    required this.exitCode,
  });

  final String output;
  final String error;
  final int exitCode;

  bool get success => exitCode == 0 && error.isEmpty;
}

/// Architect 执行结果
class ArchitectResult {
  ArchitectResult({
    required this.output,
    required this.decomposedTasks,
    required this.duration,
  });

  final String output;
  final List<SubTask> decomposedTasks;
  final Duration duration;
}

/// Engineer 执行结果
class EngineerResult {
  EngineerResult({
    required this.output,
    required this.codeOutput,
    required this.completedTasks,
    required this.duration,
  });

  final String output;
  String codeOutput;
  final List<SubTask> completedTasks;
  final Duration duration;
}

/// Tester 执行结果
class TesterResult {
  TesterResult({
    required this.output,
    required this.score,
    required this.feedback,
    required this.duration,
  });

  final String output;
  final int score;
  final String feedback;
  final Duration duration;
}

/// 协作步骤
class CollaborationStep {
  const CollaborationStep({
    required this.role,
    required this.status,
    required this.output,
    required this.duration,
    this.iteration,
    this.score,
  });

  final String role;
  final StepStatus status;
  final String output;
  final Duration duration;
  final int? iteration;
  final int? score;

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'status': status.name,
      'output': output,
      'durationMs': duration.inMilliseconds,
      if (iteration != null) 'iteration': iteration,
      if (score != null) 'score': score,
    };
  }
}

enum StepStatus { pending, running, completed, failed }

/// 子任务
class SubTask {
  const SubTask({
    required this.id,
    required this.description,
    required this.order,
    required this.type,
  });

  final String id;
  final String description;
  final int order;
  final SubTaskType type;
}

enum SubTaskType { design, implementation, testing, documentation, deployment }

/// 附件
class CollaborationAttachment {
  const CollaborationAttachment({
    required this.name,
    required this.description,
    required this.path,
  });

  final String name;
  final String description;
  final String path;
}

/// 协作最终结果
class CollaborationResult {
  const CollaborationResult({
    required this.success,
    required this.steps,
    required this.finalCode,
    required this.finalScore,
    required this.duration,
    required this.iterations,
    this.error,
  });

  final bool success;
  final List<CollaborationStep> steps;
  final String finalCode;
  final int finalScore;
  final Duration duration;
  final int iterations;
  final String? error;

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'steps': steps.map((item) => item.toJson()).toList(growable: false),
      'finalCode': finalCode,
      'finalScore': finalScore,
      'durationMs': duration.inMilliseconds,
      'iterations': iterations,
      if (error != null) 'error': error,
    };
  }
}
