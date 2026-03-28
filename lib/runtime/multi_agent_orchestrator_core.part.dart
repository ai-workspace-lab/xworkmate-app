part of 'multi_agent_orchestrator.dart';

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
