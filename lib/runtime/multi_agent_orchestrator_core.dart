// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'aris_bundle.dart';
import 'embedded_agent_launch_policy.dart';
import 'go_core.dart';
import 'aris_llm_chat_client.dart';
import 'multi_agent_frameworks.dart';
import 'runtime_models.dart';
import 'multi_agent_orchestrator_protocol.dart';
import 'multi_agent_orchestrator_workflow.dart';
import 'multi_agent_orchestrator_support.dart';

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
  }) : configInternal = config,
       arisBundleRepositoryInternal =
           arisBundleRepository ?? ArisBundleRepository(),
       goCoreLocatorInternal =
           goCoreLocator ??
           GoCoreLocator(binaryExistsResolver: binaryExistsResolver),
       binaryExistsResolverInternal = binaryExistsResolver,
       httpClientFactoryInternal = httpClientFactory ?? HttpClient.new,
       processStarterInternal =
           processStarter ??
           ((executable, arguments, {environment, workingDirectory}) {
             return Process.start(
               executable,
               arguments,
               environment: environment,
               workingDirectory: workingDirectory,
             );
           }),
       arisLlmChatClientInternal =
           arisLlmChatClient ??
           ArisLlmChatClient(
             bridgeLocator:
                 goCoreLocator ??
                 GoCoreLocator(binaryExistsResolver: binaryExistsResolver),
           );

  /// 当前配置
  MultiAgentConfig configInternal;
  MultiAgentConfig get config => configInternal;
  final ArisBundleRepository arisBundleRepositoryInternal;
  final GoCoreLocator goCoreLocatorInternal;
  final Future<bool> Function(String command)? binaryExistsResolverInternal;
  final HttpClient Function() httpClientFactoryInternal;
  final CliProcessStarter processStarterInternal;
  final ArisLlmChatClient arisLlmChatClientInternal;
  Process? activeCliProcessInternal;
  HttpClient? activeHttpClientInternal;
  bool abortRequestedInternal = false;

  /// 协作模式是否启用
  bool collaborationEnabledInternal = false;
  bool get collaborationEnabled => collaborationEnabledInternal;

  /// 是否正在运行
  bool isRunningInternal = false;
  bool get isRunning => isRunningInternal;

  /// 最后错误
  String? lastErrorInternal;
  String? get lastError => lastErrorInternal;

  /// 当前迭代轮次
  int currentIterationInternal = 0;
  int get currentIteration => currentIterationInternal;

  /// 状态日志
  final List<CollaborationLogEntry> logEntriesInternal = [];
  List<CollaborationLogEntry> get logEntries =>
      List.unmodifiable(logEntriesInternal);

  /// 更新配置
  void updateConfig(MultiAgentConfig config) {
    configInternal = config;
    collaborationEnabledInternal = config.enabled;
    notifyListeners();
  }

  Future<void> abort() async {
    abortRequestedInternal = true;
    final process = activeCliProcessInternal;
    activeCliProcessInternal = null;
    if (process != null) {
      try {
        process.kill();
      } catch (_) {
        // Best effort only.
      }
    }
    final client = activeHttpClientInternal;
    activeHttpClientInternal = null;
    if (client != null) {
      try {
        client.close(force: true);
      } catch (_) {
        // Best effort only.
      }
    }
  }

  void assertEmbeddedProcessesAllowedInternal() {
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
    configInternal = configInternal.copyWith(enabled: true);
    collaborationEnabledInternal = true;
    lastErrorInternal = null;
    notifyListeners();
  }

  /// 禁用协作模式
  void disable() {
    configInternal = configInternal.copyWith(enabled: false);
    collaborationEnabledInternal = false;
    notifyListeners();
  }

  /// 切换协作模式
  void toggle() {
    if (collaborationEnabledInternal) {
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
    assertEmbeddedProcessesAllowedInternal();
    if (isRunningInternal) {
      throw StateError('Collaboration is already running');
    }

    isRunningInternal = true;
    currentIterationInternal = 0;
    abortRequestedInternal = false;
    logEntriesInternal.clear();
    lastErrorInternal = null;
    notifyListeners();

    final startTime = DateTime.now();
    final steps = <CollaborationStep>[];
    final preset = configInternal.usesAris
        ? ArisFrameworkPreset(arisBundleRepositoryInternal)
        : const NativeFrameworkPreset();

    try {
      // === Phase 1: Architect 分析任务 ===
      throwIfAbortedInternal();
      logInternal(
        CollaborationLogLevel.info,
        '🎨',
        '${roleLabelInternal(MultiAgentRole.architect)} 开始分析任务...',
      );
      emitEventInternal(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: roleLabelInternal(MultiAgentRole.architect),
          message: '${roleLabelInternal(MultiAgentRole.architect)} 开始分析任务…',
          pending: true,
          error: false,
          role: 'architect',
        ),
      );
      final architectResult = await runArchitectInternal(
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
      emitEventInternal(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: roleLabelInternal(MultiAgentRole.architect),
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
      throwIfAbortedInternal();
      logInternal(
        CollaborationLogLevel.info,
        '🔧',
        '${roleLabelInternal(MultiAgentRole.engineer)} 开始实现...',
      );
      emitEventInternal(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: roleLabelInternal(MultiAgentRole.engineer),
          message: '${roleLabelInternal(MultiAgentRole.engineer)} 开始实现任务…',
          pending: true,
          error: false,
          role: 'engineer',
        ),
      );
      final engineerResult = await runEngineerInternal(
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
      emitEventInternal(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: roleLabelInternal(MultiAgentRole.engineer),
          message: '完成首轮实现。',
          pending: false,
          error: false,
          role: 'engineer',
        ),
      );

      // === Phase 3: Tester 审阅 ===
      throwIfAbortedInternal();
      logInternal(
        CollaborationLogLevel.info,
        '🔍',
        '${roleLabelInternal(MultiAgentRole.testerDoc)} 开始审阅...',
      );
      emitEventInternal(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: roleLabelInternal(MultiAgentRole.testerDoc),
          message: '${roleLabelInternal(MultiAgentRole.testerDoc)} 开始审阅实现…',
          pending: true,
          error: false,
          role: 'tester',
        ),
      );
      final testerResult = await runTesterInternal(
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
      emitEventInternal(
        onEvent,
        MultiAgentRunEvent(
          type: 'step',
          title: roleLabelInternal(MultiAgentRole.testerDoc),
          message: '完成代码审阅。',
          pending: false,
          error: false,
          role: 'tester',
          score: testerResult.score,
        ),
      );

      // === Phase 4: 迭代审阅循环（如需要）===
      if (testerResult.score < configInternal.minAcceptableScore) {
        logInternal(
          CollaborationLogLevel.warning,
          '⚠️',
          '质量评分 ${testerResult.score}/10 未达标，开始迭代审阅...',
        );

        for (var i = 0; i < configInternal.maxIterations; i++) {
          throwIfAbortedInternal();
          currentIterationInternal = i + 1;
          logInternal(
            CollaborationLogLevel.info,
            '🔄',
            '迭代 $currentIterationInternal/${configInternal.maxIterations}...',
          );
          notifyListeners();

          // Lead Engineer 接收反馈并修复
          final fixedResult = await runFixInternal(
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
              iteration: currentIterationInternal,
            ),
          );

          // Tester 重新审阅
          final reReview = await runTesterInternal(
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
              iteration: currentIterationInternal,
            ),
          );

          if (reReview.score >= configInternal.minAcceptableScore) {
            logInternal(
              CollaborationLogLevel.success,
              '✅',
              '质量达标 (${reReview.score}/10)，迭代结束',
            );
            engineerResult.codeOutput = fixedResult.codeOutput;
            break;
          } else if (currentIterationInternal >= configInternal.maxIterations) {
            logInternal(
              CollaborationLogLevel.error,
              '❌',
              '达到最大迭代次数 ${configInternal.maxIterations}，质量仍未达标',
            );
          }
        }
      } else {
        logInternal(
          CollaborationLogLevel.success,
          '✅',
          '质量达标 (${testerResult.score}/10)，无需迭代',
        );
      }

      final duration = DateTime.now().difference(startTime);
      isRunningInternal = false;
      notifyListeners();

      return CollaborationResult(
        success: true,
        steps: steps,
        finalCode: engineerResult.codeOutput,
        finalScore: testerResult.score,
        duration: duration,
        iterations: currentIterationInternal,
      );
    } catch (e) {
      lastErrorInternal = e.toString();
      logInternal(CollaborationLogLevel.error, '❌', '协作失败: $lastErrorInternal');
      isRunningInternal = false;
      notifyListeners();

      return CollaborationResult(
        success: false,
        steps: steps,
        finalCode: '',
        finalScore: 0,
        duration: DateTime.now().difference(startTime),
        iterations: currentIterationInternal,
        error: lastErrorInternal,
      );
    }
  }

  /// 记录日志
  void logInternal(CollaborationLogLevel level, String emoji, String message) {
    logEntriesInternal.add(
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
    logEntriesInternal.clear();
    notifyListeners();
  }
}
