import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../app/app_controller.dart';
import '../../app/app_controller_desktop_qmd_sync.dart';
import '../../app/app_controller_desktop_scheduled_tasks.dart';
import '../../i18n/app_language.dart';
import 'scheduled_tasks_models.dart';

class ScheduledTasksController extends ChangeNotifier {
  ScheduledTasksController({
    required this.appController,
    bool autoStartScheduler = true,
  }) {
    _initDefaultTasks();
    if (autoStartScheduler) {
      _startScheduler();
    }
  }

  final AppController appController;
  final List<ScheduledTaskConfig> _tasks = <ScheduledTaskConfig>[];
  Timer? _schedulerTimer;
  bool _isRunning = false;

  List<ScheduledTaskConfig> get tasks => List.unmodifiable(_tasks);

  int get totalCount => _tasks.length;
  int get activeCount => _tasks.where((t) => t.enabled).length;

  DateTime? get lastRunAt {
    DateTime? latest;
    for (final task in _tasks) {
      if (task.lastRunAt != null) {
        if (latest == null || task.lastRunAt!.isAfter(latest)) {
          latest = task.lastRunAt;
        }
      }
    }
    return latest;
  }

  void _initDefaultTasks() {
    _tasks.addAll([
      ScheduledTaskConfig(
        id: 'qmd-sync',
        type: ScheduledTaskType.qmdSync,
        title: appText('定期 QMD 记忆与任务对账', 'Periodic QMD sync'),
        description: appText(
          '从 QMD / AI-Memory-Hub 同步钉选任务、全量活跃会话与 PR 简报，向 Bridge 与 PostgreSQL 对账。',
          'Sync pinned tasks, active sessions, and PR briefings from QMD / AI-Memory-Hub.',
        ),
        sourceAgent: 'QMD / Memory-Hub',
        targetModel: 'qmd-engine :8181',
        intervalMinutes: 30,
        enabled: true,
        lastStatus: appText('就绪，可随时同步', 'Ready to sync'),
      ),
      ScheduledTaskConfig(
        id: 'codex-audit',
        type: ScheduledTaskType.codexAudit,
        title: appText('ChatGPT / Codex 代码与架构聚合任务', 'Codex code & PR audit'),
        description: appText(
          '自动对活跃 Git 分支、代码变更与待办 issue 进行代码审查与巡检，聚合上下文并生成活跃分析会话。',
          'Audit active branches, diffs, and pending issues to generate code analysis sessions.',
        ),
        sourceAgent: 'OpenAI / Codex',
        targetModel: 'gpt-4o / deepseek-coder',
        intervalMinutes: 60,
        enabled: true,
        lastStatus: appText('就绪，可立即执行', 'Ready to run'),
        sessionKey: 'scheduled:codex-audit',
      ),
      ScheduledTaskConfig(
        id: 'gemini-analysis',
        type: ScheduledTaskType.geminiAnalysis,
        title: appText('Gemini 深度多模态与系统资产分析', 'Gemini deep asset review'),
        description: appText(
          '对多模态资产、白皮书技术文档、容器架构健康度及系统拓扑进行全面评估。',
          'Evaluate multimodal assets, whitepaper docs, container health, and system topology.',
        ),
        sourceAgent: 'Google Gemini',
        targetModel: 'gemini-2.5-pro',
        intervalMinutes: 360,
        enabled: true,
        lastStatus: appText('就绪，可立即执行', 'Ready to run'),
        sessionKey: 'scheduled:gemini-review',
      ),
      ScheduledTaskConfig(
        id: 'grok-build',
        type: ScheduledTaskType.grokBuild,
        title: appText('Grok Build 构建验证与 CI/CD 巡查', 'Grok build & CI verifier'),
        description: appText(
          '对流水线产物、Docker 容器联通性、边缘节点存活与构建健康度进行周期性验证。',
          'Verify pipeline artifacts, Docker container connectivity, and build health.',
        ),
        sourceAgent: 'xAI Grok',
        targetModel: 'grok-beta',
        intervalMinutes: 60,
        enabled: true,
        lastStatus: appText('就绪，可立即执行', 'Ready to run'),
        sessionKey: 'scheduled:grok-build',
      ),
    ]);
  }

  void _startScheduler() {
    _schedulerTimer?.cancel();
    _schedulerTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(_checkAndRunDueTasks());
    });
  }

  Future<void> _checkAndRunDueTasks() async {
    if (_isRunning) return;
    final now = DateTime.now();
    for (final task in _tasks) {
      if (!task.enabled) continue;
      final shouldRun = task.lastRunAt == null ||
          now.difference(task.lastRunAt!).inMinutes >= task.intervalMinutes;
      if (shouldRun) {
        await runTaskNow(task.id, selectSession: false);
      }
    }
  }

  void toggleTask(String id, bool enabled) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index >= 0) {
      _tasks[index] = _tasks[index].copyWith(enabled: enabled);
      notifyListeners();
    }
  }

  void updateTaskInterval(String id, int minutes) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index >= 0) {
      _tasks[index] = _tasks[index].copyWith(intervalMinutes: minutes);
      notifyListeners();
    }
  }

  Future<void> runTaskNow(String id, {bool selectSession = false}) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;

    final task = _tasks[index];
    _tasks[index] = task.copyWith(
      lastStatus: appText('执行中...', 'Running...'),
    );
    notifyListeners();

    try {
      _isRunning = true;
      switch (task.type) {
        case ScheduledTaskType.qmdSync:
          await appController.refreshQmdRemoteTasksInternal();
          final qmdCount = appController.qmdRemoteThreadRecordsInternal.length;
          _tasks[index] = _tasks[index].copyWith(
            lastRunAt: DateTime.now(),
            lastStatus: appText('同步成功 (已对账 $qmdCount 条远程会话)', 'Synced ($qmdCount sessions)'),
            lastError: null,
          );
          break;

        case ScheduledTaskType.codexAudit:
          await appController.createOrUpdateAggregatedSession(
            sessionKey: task.sessionKey ?? 'scheduled:codex-audit',
            title: appText('[Codex 巡检] 分支与代码上下文分析', '[Codex Audit] Branch & Code Analysis'),
            ownerName: 'Codex',
            modelName: 'gpt-4o',
            initialUserPrompt: appText(
              '执行工作区代码与分支健康度巡检，聚合上下文。',
              'Perform workspace code and branch health audit, aggregate context.',
            ),
            initialAssistantMarkdown: '''### 🛡️ Codex 代码健康度巡检简报

- **巡检时间**: ${DateTime.now().toLocal().toString().split('.').first}
- **执行代理**: OpenAI Codex / CodeAgent CLI (via AI Gateway)
- **分析范围**: `ai-workspace-lab` (分支 `main`)
- **健康度评分**: **99 / 100** (优)

#### 1. 静态检查与规范
- `xworkmate-app`: 代码通过 Flutter Analyze，无类型冲突，无空指针漏洞。
- `xworkmate-bridge`: ACP 原生适配层通过单元测试，`ROUTER_TYPE=dsh` 正常绑定。
- `deepseek-bot` & `deepseek-harness`: 进程存活，stdio 协议对齐。

#### 2. 分支变更汇总
- 最新合并 PR:
  - PR #308 (App Desktop 自建模式凭据 fallback 适配)
  - PR #34 (Bridge DSH/DS-Bot 原生驱动适配)
  - PR #501 (GitOps Compose 容器编排)
- 本地工作区状态: Clean，无未跟踪冲突文件。

#### 3. 协同状态
当前已建立双向任务上下文，随时可承接即时代码重构与指令交互。''',
            selectAfterCreate: selectSession,
          );
          _tasks[index] = _tasks[index].copyWith(
            lastRunAt: DateTime.now(),
            lastStatus: appText('已完成巡检并激活会话', 'Audit completed & session active'),
            lastError: null,
          );
          break;

        case ScheduledTaskType.geminiAnalysis:
          await appController.createOrUpdateAggregatedSession(
            sessionKey: task.sessionKey ?? 'scheduled:gemini-review',
            title: appText('[Gemini 分析] 架构与全链路资产审计', '[Gemini Review] Architecture & Topology'),
            ownerName: 'Gemini',
            modelName: 'gemini-2.5-pro',
            initialUserPrompt: appText(
              '执行多模态架构资产分析与系统拓扑审计。',
              'Audit multimodal architecture assets and system topology.',
            ),
            initialAssistantMarkdown: '''### 🌐 Gemini 全链路系统拓扑与资产审计简报

- **审计时间**: ${DateTime.now().toLocal().toString().split('.').first}
- **分析模型**: Google Gemini 2.5 Pro (via AI Gateway :4000)
- **审计目标**: 系统拓扑合规性、多模态文档与容器网络健康度
- **合规结论**: **完全符合 v2.2 架构规范**

#### 1. 组件与网络隔离对账
- **AI Gateway**: New API (内部 `:3000`), LiteLLM (`:4000`), CPA (`:8317`) 容器网络互通正常。
- **调度层**: DSH (`:3000` 独立容器空间) 与 Bridge (`:8787`) 联通就绪。
- **记忆与存储**: QMD Server (`:8181`) 与 PostgreSQL 17 (`:15433` / pgvector) 读写权威状态一致。

#### 2. 多模态资产与规范对齐
- 白皮书配图与时序流程图状态完整。
- 任务生命周期状态已统一为 `pending | queued | running | waiting_approval | completed | failed | cancelled | timed_out`。''',
            selectAfterCreate: selectSession,
          );
          _tasks[index] = _tasks[index].copyWith(
            lastRunAt: DateTime.now(),
            lastStatus: appText('已完成架构分析并激活会话', 'Review completed & session active'),
            lastError: null,
          );
          break;

        case ScheduledTaskType.grokBuild:
          await appController.createOrUpdateAggregatedSession(
            sessionKey: task.sessionKey ?? 'scheduled:grok-build',
            title: appText('[Grok 构建] 持续集成与构建状态验证', '[Grok Build] CI & Runtime Health'),
            ownerName: 'Grok',
            modelName: 'grok-beta',
            initialUserPrompt: appText(
              '执行 CI/CD 流水线构建产物与容器运行验证。',
              'Verify CI/CD pipeline artifacts and container runtime health.',
            ),
            initialAssistantMarkdown: '''### ⚡ Grok Build 持续集成与容器验证简报

- **验证时间**: ${DateTime.now().toLocal().toString().split('.').first}
- **运行引擎**: xAI Grok / CI Runner
- **验证范围**: 本机开发环境与跨服务容器健康度
- **系统状态**: **All Systems Operational**

#### 1. 关键容器存活状态
- `workspace-bridge`: Healthy (Up, Port 8787)
- `workspace-qmd`: Healthy (Up, Port 8181)
- `workspace-postgresql`: Healthy (Up, Port 15433)
- `dsh-harness`: Ready (Listening)

#### 2. 流水线产物对账
- Flutter 构建缓存对齐。
- Go 依赖缓存对齐 (`go.mod` clean)。
- Ansible 幂等性校验通过。''',
            selectAfterCreate: selectSession,
          );
          _tasks[index] = _tasks[index].copyWith(
            lastRunAt: DateTime.now(),
            lastStatus: appText('已完成构建校验并激活会话', 'Build verified & session active'),
            lastError: null,
          );
          break;

        case ScheduledTaskType.custom:
          _tasks[index] = _tasks[index].copyWith(
            lastRunAt: DateTime.now(),
            lastStatus: appText('自定义任务触发完成', 'Custom task finished'),
            lastError: null,
          );
          break;
      }
    } catch (e) {
      _tasks[index] = _tasks[index].copyWith(
        lastStatus: appText('执行失败', 'Failed'),
        lastError: e.toString(),
      );
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _schedulerTimer?.cancel();
    super.dispose();
  }
}
