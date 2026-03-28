part of 'multi_agent_orchestrator.dart';

extension _MultiAgentOrchestratorSupport on MultiAgentOrchestrator {
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

}
