import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'runtime_models.dart';

/// 多 Agent 协作编排器
///
/// 管理 Architect (Gemini) → Engineer (Claude Code) → Tester/Doc (Codex)
/// 的工作流，通过 Ollama 驱动本地模型，在现有 UI 基础上补充协作能力。
///
/// 角色分工：
/// - Architect（调度者）：负责任务分解、流程编排（Gemini CLI 或云端模型）
/// - Engineer（工程师）：负责代码实现（Claude Code via Ollama）
/// - Tester/Doc（评审）：负责测试、审阅、文档（Codex CLI via Ollama）
class MultiAgentOrchestrator extends ChangeNotifier {
  MultiAgentOrchestrator({required MultiAgentConfig config}) : _config = config;

  /// 当前配置
  MultiAgentConfig _config;
  MultiAgentConfig get config => _config;

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
    if (_isRunning) {
      throw StateError('Collaboration is already running');
    }

    _isRunning = true;
    _currentIteration = 0;
    _logEntries.clear();
    _lastError = null;
    notifyListeners();

    final startTime = DateTime.now();
    final steps = <CollaborationStep>[];

    try {
      // === Phase 1: Architect 分析任务 ===
      _log(CollaborationLogLevel.info, '🎨', 'Architect 开始分析任务...');
      _emitEvent(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: 'Architect',
          message: 'Architect 开始分析任务…',
          pending: true,
          error: false,
          role: 'architect',
        ),
      );
      final architectResult = await _runArchitect(
        taskPrompt,
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
          title: 'Architect',
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
      _log(CollaborationLogLevel.info, '🔧', 'Engineer 开始实现...');
      _emitEvent(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: 'Engineer',
          message: 'Engineer 开始实现任务…',
          pending: true,
          error: false,
          role: 'engineer',
        ),
      );
      final engineerResult = await _runEngineer(
        architectResult.decomposedTasks,
        workingDirectory,
        attachments,
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
          title: 'Engineer',
          message: '完成首轮实现。',
          pending: false,
          error: false,
          role: 'engineer',
        ),
      );

      // === Phase 3: Tester 审阅 ===
      _log(CollaborationLogLevel.info, '🔍', 'Tester 开始审阅...');
      _emitEvent(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: 'Tester',
          message: 'Tester 开始审阅实现…',
          pending: true,
          error: false,
          role: 'tester',
        ),
      );
      final testerResult = await _runTester(
        engineerResult.codeOutput,
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
          title: 'Tester',
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
          _currentIteration = i + 1;
          _log(
            CollaborationLogLevel.info,
            '🔄',
            '迭代 $_currentIteration/${_config.maxIterations}...',
          );
          notifyListeners();

          // Engineer 接收反馈并修复
          final fixedResult = await _runFix(
            engineerResult.codeOutput,
            testerResult.feedback,
            workingDirectory,
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

  /// 运行 Architect（任务分析）
  Future<ArchitectResult> _runArchitect(
    String task, {
    required List<String> selectedSkills,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 根据配置选择 Architect 工具
      if (_config.architectEnabled) {
        final result = await _runCliPrompt(
          tool: _config.architectTool,
          model: _config.architectModel,
          prompt: _buildArchitectPrompt(task, selectedSkills),
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

  /// 运行 Engineer（代码实现）
  Future<EngineerResult> _runEngineer(
    List<SubTask> tasks,
    String workingDirectory,
    List<CollaborationAttachment> attachments, {
    required List<String> selectedSkills,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) async {
    final stopwatch = Stopwatch()..start();

    final taskList = tasks
        .map((t) => '## ${t.order}. ${t.description}')
        .join('\n\n');

    final prompt =
        '''
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
      tool: _config.engineerTool,
      model: _config.engineerModel,
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

  /// 运行 Tester（代码审阅）
  Future<TesterResult> _runTester(
    String codeOutput, {
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) async {
    final stopwatch = Stopwatch()..start();

    final prompt =
        '''
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

    final result = await _runCliPrompt(
      tool: _config.testerTool,
      model: _config.testerModel,
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
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) async {
    final stopwatch = Stopwatch()..start();

    final prompt =
        '''
你是一个资深工程师。请根据审阅反馈修复代码。

## 审阅反馈
$feedback

## 原始代码
$originalCode

请完成修复，输出修复后的完整代码。
''';

    final result = await _runCliPrompt(
      tool: _config.engineerTool,
      model: _config.engineerModel,
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

    switch (tool) {
      case 'claude':
        command = _resolveCliPath('claude');
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

      case 'codex':
        command = _resolveCliPath('codex');
        envVars = _buildCliEnvVars(
          tool: tool,
          aiGatewayBaseUrl: aiGatewayBaseUrl,
          aiGatewayApiKey: aiGatewayApiKey,
        );
        if (model.isNotEmpty) {
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
        command = _resolveCliPath('opencode');
        envVars = _buildCliEnvVars(
          tool: tool,
          aiGatewayBaseUrl: aiGatewayBaseUrl,
          aiGatewayApiKey: aiGatewayApiKey,
        );
        args = [
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

    try {
      final process = await Process.start(
        command,
        args,
        environment: envVars,
        workingDirectory: cwd.isNotEmpty ? cwd : null,
      );

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

      return CliResult(
        output: results[0],
        error: results[1],
        exitCode: exitCode,
      );
    } catch (e) {
      return CliResult(output: '', error: e.toString(), exitCode: -1);
    }
  }

  /// 构建 Architect 的 Prompt
  String _buildArchitectPrompt(String task, List<String> selectedSkills) {
    return '''
你是一个任务架构师（Architect）。请分析以下需求并分解为可执行的子任务。

## 用户需求
$task

## 优先技能
${selectedSkills.isEmpty ? '- 无' : selectedSkills.map((item) => '- $item').join('\n')}

请输出：
1. 任务概述（2-3 句话）
2. 子任务列表（3-5 个），每个子任务包含：
   - 任务编号和描述
   - 预计复杂度（简单/中等/复杂）
   - 关键技术点
3. 推荐的执行顺序

请严格按以下格式输出：
## 概述
[你的概述]

## 子任务
1. [任务描述] | 复杂度：[简单/中等/复杂] | 关键技术：[技术点]
2. [任务描述] | 复杂度：[简单/中等/复杂] | 关键技术：[技术点]
...
''';
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
      if (tool == 'claude') {
        baseEnv['ANTHROPIC_BASE_URL'] = aiGatewayBaseUrl.trim();
        baseEnv['ANTHROPIC_AUTH_TOKEN'] = aiGatewayApiKey.trim();
        baseEnv['ANTHROPIC_API_KEY'] = aiGatewayApiKey.trim();
      }
      return baseEnv;
    }
    if (tool == 'claude' || tool == 'codex') {
      baseEnv['ANTHROPIC_AUTH_TOKEN'] = 'ollama';
      baseEnv['ANTHROPIC_API_KEY'] = '';
      baseEnv['ANTHROPIC_BASE_URL'] = _config.ollamaEndpoint;
      baseEnv['OPENAI_API_KEY'] = '';
      baseEnv['OPENAI_BASE_URL'] = '${_config.ollamaEndpoint}/v1';
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
