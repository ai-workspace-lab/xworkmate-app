import 'package:flutter/material.dart';

import '../app/app_metadata.dart';
import '../models/app_models.dart';

class MockData {
  static const quickActions = [
    QuickAction(
      title: '写代码',
      icon: Icons.code_rounded,
      caption: '生成组件、修复 bug、搭建原型',
    ),
    QuickAction(
      title: '分析文档',
      icon: Icons.description_rounded,
      caption: '长文总结、要点抽取、风险提示',
    ),
    QuickAction(
      title: '生成 PPT',
      icon: Icons.slideshow_rounded,
      caption: '提纲生成、页面结构、讲述逻辑',
    ),
    QuickAction(
      title: '数据分析',
      icon: Icons.analytics_rounded,
      caption: '表格解读、趋势拆解、指标洞察',
    ),
    QuickAction(
      title: '设计方案',
      icon: Icons.draw_rounded,
      caption: '产品方案、交互思路、界面方向',
    ),
    QuickAction(
      title: '邮件处理',
      icon: Icons.mail_outline_rounded,
      caption: '总结线程、起草回复、提炼行动项',
    ),
    QuickAction(
      title: '自动化任务',
      icon: Icons.auto_mode_rounded,
      caption: '定时执行、跨工具协同、持续追踪',
    ),
  ];

  static const recentSessions = [
    RecentSession(
      title: '设计新的桌面 IA',
      timestamp: '12 分钟前',
      summary: '重排主导航，压平二级结构，保持 Assistant 为首页。',
    ),
    RecentSession(
      title: '梳理任务执行历史',
      timestamp: '今天 14:20',
      summary: '合并 Queue / Running / Failed 的追踪口径。',
    ),
    RecentSession(
      title: '检查 Gateway 轻量控制面',
      timestamp: '昨天',
      summary: '减少运维感，更多强调 AI 控制平面状态。',
    ),
  ];

  static const taskMetrics = [
    MetricSummary(
      label: 'Total',
      value: '128',
      caption: '总任务数',
      icon: Icons.layers_rounded,
    ),
    MetricSummary(
      label: 'Running',
      value: '12',
      caption: '当前运行中',
      icon: Icons.play_circle_outline_rounded,
      status: StatusInfo('Stable', StatusTone.success),
    ),
    MetricSummary(
      label: 'Failed',
      value: '3',
      caption: '需要人工介入',
      icon: Icons.error_outline_rounded,
      status: StatusInfo('Watch', StatusTone.warning),
    ),
    MetricSummary(
      label: 'Scheduled',
      value: '18',
      caption: '已排程任务',
      icon: Icons.event_repeat_rounded,
    ),
  ];

  static const queueTasks = [
    TaskSummary(
      name: 'Design Desktop IA Shell',
      owner: 'Coding Agent',
      status: StatusInfo('Queued', StatusTone.neutral),
      startedAt: '预计 16:50',
      duration: 'ETA 4m',
      surface: 'Assistant',
    ),
    TaskSummary(
      name: 'Daily Report Draft',
      owner: 'Job Autopilot',
      status: StatusInfo('Queued', StatusTone.neutral),
      startedAt: '预计 17:00',
      duration: 'ETA 2m',
      surface: 'Scheduled',
    ),
  ];

  static const runningTasks = [
    TaskSummary(
      name: 'XWorkmate Workspace Prototype',
      owner: 'Coding Agent',
      status: StatusInfo('Running', StatusTone.accent),
      startedAt: '刚刚',
      duration: '8m 12s',
      surface: 'Assistant',
    ),
    TaskSummary(
      name: 'Market Monitor Rollup',
      owner: 'Research Agent',
      status: StatusInfo('Streaming', StatusTone.success),
      startedAt: '16:12',
      duration: '2m 43s',
      surface: 'Tasks',
    ),
  ];

  static const historyTasks = [
    TaskSummary(
      name: 'Slack Thread Summarization',
      owner: 'Research Agent',
      status: StatusInfo('Completed', StatusTone.success),
      startedAt: '今天 15:10',
      duration: '3m 42s',
      surface: 'CoreSetup',
    ),
    TaskSummary(
      name: 'Resume Scan Batch',
      owner: 'Job Autopilot',
      status: StatusInfo('Completed', StatusTone.success),
      startedAt: '今天 13:25',
      duration: '6m 03s',
      surface: 'Tasks',
    ),
  ];

  static const failedTasks = [
    TaskSummary(
      name: 'Connector Credential Refresh',
      owner: 'Browser Agent',
      status: StatusInfo('Failed', StatusTone.danger),
      startedAt: '今天 14:03',
      duration: '58s',
      surface: 'Secrets',
    ),
  ];

  static const scheduledTasks = [
    TaskSummary(
      name: 'Morning Standup Digest',
      owner: 'Job Autopilot',
      status: StatusInfo('Scheduled', StatusTone.accent),
      startedAt: '明天 08:40',
      duration: 'Daily',
      surface: 'Tasks',
    ),
    TaskSummary(
      name: 'Inbox Triage',
      owner: 'Research Agent',
      status: StatusInfo('Scheduled', StatusTone.accent),
      startedAt: '18:00',
      duration: 'Every 3h',
      surface: 'Tasks',
    ),
  ];

  static const workspaceModules = [
    ModuleSummary(
      name: 'Workspace Overview',
      description: '统一管理默认模型、默认 Agent、团队策略与入口偏好。',
      status: StatusInfo('Ready', StatusTone.success),
      meta: '3 workspaces · 12 members',
      icon: Icons.apartment_rounded,
    ),
  ];

  static const gatewayModules = [
    ModuleSummary(
      name: 'AI Gateway',
      description:
          'Healthy · version $kAppVersion · 3 nodes · 12 active sessions',
      status: StatusInfo('Healthy', StatusTone.success),
      meta: '87 runs today',
      icon: Icons.wifi_tethering_rounded,
    ),
    ModuleSummary(
      name: 'Edge Relay',
      description: 'Tokyo relay handling cross-region session routing.',
      status: StatusInfo('Healthy', StatusTone.success),
      meta: '3 active sessions',
      icon: Icons.hub_rounded,
    ),
  ];

  static const nodeModules = [
    ModuleSummary(
      name: 'Mac mini studio-01',
      description: 'Desktop automation node with screenshot + shell access.',
      status: StatusInfo('Healthy', StatusTone.success),
      meta: 'CPU 42% · RAM 61%',
      icon: Icons.desktop_mac_rounded,
    ),
    ModuleSummary(
      name: 'Cloud sandbox',
      description: 'Ephemeral workload node for heavy research tasks.',
      status: StatusInfo('Warning', StatusTone.warning),
      meta: 'Retry queue elevated',
      icon: Icons.cloud_queue_rounded,
    ),
  ];

  static const nodes = [
    NodeSummary(
      name: 'Mac mini studio-01',
      type: 'local',
      region: 'Shanghai',
      heartbeat: '12s ago',
      load: '42%',
      status: StatusInfo('Healthy', StatusTone.success),
    ),
    NodeSummary(
      name: 'Edge relay tokyo',
      type: 'edge',
      region: 'Tokyo',
      heartbeat: '28s ago',
      load: '31%',
      status: StatusInfo('Healthy', StatusTone.success),
    ),
    NodeSummary(
      name: 'Sandbox remote-03',
      type: 'remote',
      region: 'Frankfurt',
      heartbeat: '2m ago',
      load: '76%',
      status: StatusInfo('Warning', StatusTone.warning),
    ),
  ];

  static const agents = [
    AgentSummary(
      name: 'Browser Agent',
      description: '网页探索、采集、表单操作与流程验证。',
      status: StatusInfo('Idle', StatusTone.neutral),
      lastRun: '18 分钟前',
      capabilities: ['Browse', 'Capture', 'Validate'],
    ),
    AgentSummary(
      name: 'Coding Agent',
      description: '读写代码、生成补丁、解释实现与验证构建。',
      status: StatusInfo('Running', StatusTone.accent),
      lastRun: '刚刚',
      capabilities: ['Code', 'Patch', 'Tests'],
    ),
    AgentSummary(
      name: 'Research Agent',
      description: '检索资料、比对来源、收敛结论。',
      status: StatusInfo('Idle', StatusTone.neutral),
      lastRun: '43 分钟前',
      capabilities: ['Search', 'Compare', 'Synthesis'],
    ),
    AgentSummary(
      name: 'Job Autopilot',
      description: '持续接单、编排子任务、回收输出物。',
      status: StatusInfo('Running', StatusTone.success),
      lastRun: '2 分钟前',
      capabilities: ['Delegation', 'Scheduling', 'Reports'],
    ),
    AgentSummary(
      name: 'Custom Agent',
      description: '面向团队流程定制的草稿 Agent。',
      status: StatusInfo('Draft', StatusTone.warning),
      lastRun: '未运行',
      capabilities: ['Custom Prompt', 'Tools', 'Context'],
    ),
  ];

  static const skills = [
    SkillSummary(
      name: 'db-migration-runbook',
      type: 'Runbook',
      source: 'Local skill',
      status: StatusInfo('Enabled', StatusTone.success),
      version: '1.4.0',
      modules: 'Tasks · Modules',
    ),
    SkillSummary(
      name: 'playwright',
      type: 'Automation',
      source: 'Shared skill',
      status: StatusInfo('Enabled', StatusTone.success),
      version: '2.1.3',
      modules: 'Modules · Secrets',
    ),
    SkillSummary(
      name: 'vercel-deploy',
      type: 'Deployment',
      source: 'Hub',
      status: StatusInfo('Preview', StatusTone.accent),
      version: '0.9.2',
      modules: 'Modules',
    ),
  ];

  static const agentModules = [
    ModuleSummary(
      name: 'Job Autopilot',
      description: '持续接单、自动整理输出物、分发下一步行动。',
      status: StatusInfo('Running', StatusTone.success),
      meta: 'Queue depth 4',
      icon: Icons.auto_awesome_motion_rounded,
    ),
    ModuleSummary(
      name: 'Coding Agent',
      description: '负责读写代码、补丁生成、编译检查与解释。',
      status: StatusInfo('Running', StatusTone.accent),
      meta: 'GPT-5 Code',
      icon: Icons.terminal_rounded,
    ),
  ];

  static const skillModules = [
    ModuleSummary(
      name: 'db-migration-runbook',
      description: '面向数据库迁移和演练的工作指引 skill。',
      status: StatusInfo('Installed', StatusTone.success),
      meta: 'Last updated 2d ago',
      icon: Icons.menu_book_rounded,
    ),
    ModuleSummary(
      name: 'playwright',
      description: '桌面与浏览器自动化能力封装。',
      status: StatusInfo('Installed', StatusTone.success),
      meta: 'Used in 18 runs',
      icon: Icons.web_asset_rounded,
    ),
  ];

  static const clawHubModules = [
    ModuleSummary(
      name: 'Hub Registry',
      description: '统一查看共享模块、预设 Agent 与团队模板。',
      status: StatusInfo('Connected', StatusTone.accent),
      meta: '24 shared assets',
      icon: Icons.grid_view_rounded,
    ),
  ];

  static const connectorModules = [
    ModuleSummary(
      name: 'Slack Connector',
      description: '线程总结、消息派发与任务回写。',
      status: StatusInfo('Warning', StatusTone.warning),
      meta: '480 events / day',
      icon: Icons.forum_rounded,
    ),
    ModuleSummary(
      name: 'Email Relay',
      description: '日报投递、邮件摘要与草稿生成。',
      status: StatusInfo('Healthy', StatusTone.success),
      meta: '126 messages / day',
      icon: Icons.mail_rounded,
    ),
  ];

  static const connectors = [
    ConnectorSummary(
      name: 'Vault',
      description: '管理远程 secret reference 与轮换策略。',
      status: StatusInfo('Connected', StatusTone.success),
      lastSync: '2 分钟前',
      permission: 'Read / Write',
    ),
    ConnectorSummary(
      name: 'GitHub',
      description: '用于 issue、PR 和仓库自动化。',
      status: StatusInfo('Connected', StatusTone.success),
      lastSync: '5 分钟前',
      permission: 'Repo scoped',
    ),
    ConnectorSummary(
      name: 'Google Drive',
      description: '读取文档、表格与共享目录。',
      status: StatusInfo('Pending', StatusTone.warning),
      lastSync: '未同步',
      permission: 'Awaiting OAuth',
    ),
    ConnectorSummary(
      name: 'Slack',
      description: '消息接入、线程总结、任务回写。',
      status: StatusInfo('Warning', StatusTone.warning),
      lastSync: '12 分钟前',
      permission: 'Messages',
    ),
    ConnectorSummary(
      name: 'MCP',
      description: '连接本地或远程 MCP 服务器。',
      status: StatusInfo('Connected', StatusTone.success),
      lastSync: '刚刚',
      permission: 'Tool access',
    ),
    ConnectorSummary(
      name: 'Local FS',
      description: '本地文件系统读写与目录索引。',
      status: StatusInfo('Connected', StatusTone.success),
      lastSync: '实时',
      permission: 'Workspace only',
    ),
  ];

  static const vaultSecrets = [
    SecretSummary(
      name: 'OPENAI_API_KEY',
      scope: 'Workspace',
      status: StatusInfo('Healthy', StatusTone.success),
      updatedAt: '2 小时前',
      provider: 'Vault',
    ),
    SecretSummary(
      name: 'SLACK_BOT_TOKEN',
      scope: 'Connector',
      status: StatusInfo('Rotating', StatusTone.warning),
      updatedAt: '昨天',
      provider: 'Vault',
    ),
  ];

  static const localSecrets = [
    SecretSummary(
      name: 'LOCAL_AGENT_CACHE',
      scope: 'Desktop',
      status: StatusInfo('Local', StatusTone.neutral),
      updatedAt: '今天',
      provider: 'Keychain',
    ),
  ];

  static const providerSecrets = [
    SecretSummary(
      name: '1Password',
      scope: 'Provider',
      status: StatusInfo('Connected', StatusTone.success),
      updatedAt: '刚刚',
      provider: 'Provider',
    ),
    SecretSummary(
      name: 'AWS Secrets Manager',
      scope: 'Provider',
      status: StatusInfo('Draft', StatusTone.warning),
      updatedAt: '未配置',
      provider: 'Provider',
    ),
  ];

  static const secretReferences = [
    SecretReference(
      name: 'indeed_cookie',
      provider: 'Vault',
      module: 'Job Autopilot',
      status: StatusInfo('In use', StatusTone.success),
      maskedValue: '••••••••4ae7',
    ),
    SecretReference(
      name: 'github_token',
      provider: 'Vault',
      module: 'Coding Agent',
      status: StatusInfo('In use', StatusTone.success),
      maskedValue: 'ghp_••••••8k2m',
    ),
    SecretReference(
      name: 'openai_key',
      provider: 'Local',
      module: 'Gateway',
      status: StatusInfo('Warning', StatusTone.warning),
      maskedValue: 'sk-••••••••••',
    ),
  ];

  static const providers = [
    ProviderSummary(
      name: 'HashiCorp Vault',
      description: '远程 secret provider，支持 namespace、TTL 和审计。',
      status: StatusInfo('Connected', StatusTone.success),
      capabilities: ['KV', 'TTL', 'Audit'],
    ),
    ProviderSummary(
      name: 'Environment Variables',
      description: '适合本地开发与 CI 运行时注入。',
      status: StatusInfo('Available', StatusTone.neutral),
      capabilities: ['Runtime', 'Process', 'Masking'],
    ),
    ProviderSummary(
      name: 'Local File',
      description: '为离线桌面环境提供本地加密存储。',
      status: StatusInfo('Enabled', StatusTone.success),
      capabilities: ['Encrypted', 'Local', 'Backup'],
    ),
    ProviderSummary(
      name: 'External Secret Manager',
      description: '预留给企业第三方 secret manager 的接入位。',
      status: StatusInfo('Draft', StatusTone.warning),
      capabilities: ['Enterprise', 'Sync', 'Policy'],
    ),
  ];

  static const auditSecrets = [
    AuditSummary(
      time: '16:12',
      action: 'Rotate token',
      provider: 'Vault',
      target: 'github_token',
      module: 'Coding Agent',
      status: StatusInfo('Success', StatusTone.success),
    ),
    AuditSummary(
      time: '15:40',
      action: 'Read secret',
      provider: 'Vault',
      target: 'indeed_cookie',
      module: 'Job Autopilot',
      status: StatusInfo('Success', StatusTone.success),
    ),
    AuditSummary(
      time: '14:52',
      action: 'Resolve reference',
      provider: 'Local',
      target: 'openai_key',
      module: 'Gateway',
      status: StatusInfo('Warning', StatusTone.warning),
    ),
  ];

  static const generalSettings = [
    SettingSummary(
      title: 'Default launch surface',
      description: '始终保持 Assistant 为默认首页。',
      value: 'Assistant',
    ),
    SettingSummary(
      title: 'Command palette shortcut',
      description: '桌面全局入口，Cmd/Ctrl + K。',
      value: 'Enabled',
    ),
  ];

  static const workspaceSettings = [
    SettingSummary(
      title: 'Data path',
      description: '本地运行数据与缓存目录。',
      value: '/opt/data',
    ),
    SettingSummary(
      title: 'Repo path',
      description: '默认代码工作区根目录。',
      value: '/opt/data/workspace',
    ),
    SettingSummary(
      title: 'Default agent',
      description: '新建任务时默认挂载的 Agent。',
      value: 'Coding Agent',
    ),
  ];

  static const gatewaySettings = [
    SettingSummary(
      title: 'Gateway default route',
      description: '控制面启动后默认挂载的主路由。',
      value: 'AI Gateway',
    ),
    SettingSummary(
      title: 'Session retention',
      description: '会话日志保留策略。',
      value: '14 days',
    ),
  ];

  static const appearanceSettings = [
    SettingSummary(
      title: 'Theme',
      description: '桌面浅色优先，同时支持暗色主题。',
      value: 'Auto / Manual',
    ),
    SettingSummary(
      title: 'Dense tables',
      description: '关闭后保持更轻的桌面留白。',
      value: 'Off',
    ),
  ];

  static const providerSettings = [
    SettingSummary(
      title: 'Module provider source',
      description: '决定 Skills / Agents / Connectors 的拉取来源。',
      value: 'ClawHub',
    ),
    SettingSummary(
      title: 'Connector sync policy',
      description: '共享模块更新时的同步行为。',
      value: 'Manual review',
    ),
  ];

  static const diagnosticSettings = [
    SettingSummary(
      title: 'Gateway health snapshot',
      description: '最近一次诊断汇总。',
      value: 'Healthy',
    ),
    SettingSummary(
      title: 'Local data directory',
      description: '本地运行数据与缓存入口。',
      value: '/opt/data/',
    ),
  ];

  static const experimentalSettings = [
    SettingSummary(
      title: 'Floating detail drawer',
      description: '在宽屏下保留右侧抽屉式详情。',
      value: 'Enabled',
    ),
    SettingSummary(
      title: 'Desktop inline previews',
      description: '在 Tasks 和 Secrets 中显示更多 hover 预览。',
      value: 'Preview',
    ),
  ];

  static const aboutSettings = [
    SettingSummary(
      title: kSystemAppName,
      description: 'Flutter Material 3 UI shell for macOS and Windows.',
      value: kAppVersionLabel,
    ),
    SettingSummary(
      title: 'Build channel',
      description: 'Prototype only, mock data mode.',
      value: 'Desktop alpha',
    ),
  ];

  static const workspaces = [
    WorkspaceProfile(
      name: 'XWorkmate Design Lab',
      role: 'Owner',
      members: '12 members',
      region: 'Asia Pacific',
    ),
    WorkspaceProfile(
      name: 'Client Operations',
      role: 'Editor',
      members: '8 members',
      region: 'Global',
    ),
  ];

  static const accountSessions = [
    TaskSummary(
      name: 'MacBook Pro · Desktop App',
      owner: 'This device',
      status: StatusInfo('Active', StatusTone.success),
      startedAt: '今天 16:00',
      duration: 'Current',
      surface: 'Desktop',
    ),
    TaskSummary(
      name: 'Windows workstation',
      owner: 'Remote sign-in',
      status: StatusInfo('Idle', StatusTone.neutral),
      startedAt: '昨天',
      duration: '23h ago',
      surface: 'Desktop',
    ),
  ];

  static DetailPanelData taskDetail(TaskSummary task) {
    return DetailPanelData(
      title: task.name,
      subtitle: 'Task Detail',
      icon: Icons.bolt_rounded,
      status: task.status,
      description: '任务来自 ${task.surface}，当前由 ${task.owner} 持有。',
      meta: [task.surface, task.owner, task.duration],
      actions: const ['打开', '重试', '复制链接'],
      sections: [
        DetailSection(
          title: 'Execution',
          items: [
            DetailItem(label: '开始时间', value: task.startedAt),
            DetailItem(label: '耗时', value: task.duration),
            DetailItem(label: '状态', value: task.status.label),
          ],
        ),
      ],
    );
  }

  static DetailPanelData moduleDetail(ModuleSummary module) {
    return DetailPanelData(
      title: module.name,
      subtitle: 'Module Detail',
      icon: module.icon,
      status: module.status,
      description: module.description,
      meta: [module.meta, module.status.label],
      actions: const ['打开', '配置', '查看状态'],
      sections: [
        DetailSection(
          title: 'Overview',
          items: [
            DetailItem(label: '状态', value: module.status.label),
            DetailItem(label: '摘要', value: module.meta),
          ],
        ),
      ],
    );
  }

  static DetailPanelData secretDetail(SecretSummary secret) {
    return DetailPanelData(
      title: secret.name,
      subtitle: 'Secret Detail',
      icon: Icons.key_rounded,
      status: secret.status,
      description: '该密钥当前归属 ${secret.scope}，由 ${secret.provider} 管理。',
      meta: [secret.scope, secret.provider, secret.updatedAt],
      actions: const ['查看审计', '轮换', '复制引用'],
      sections: [
        DetailSection(
          title: 'Metadata',
          items: [
            DetailItem(label: 'Scope', value: secret.scope),
            DetailItem(label: 'Provider', value: secret.provider),
            DetailItem(label: 'Updated', value: secret.updatedAt),
          ],
        ),
      ],
    );
  }

  static DetailPanelData workspaceDetail(WorkspaceProfile workspace) {
    return DetailPanelData(
      title: workspace.name,
      subtitle: 'Workspace Detail',
      icon: Icons.apartment_rounded,
      status: const StatusInfo('Healthy', StatusTone.success),
      description: '工作区用于组织共享模块、成员权限和默认执行策略。',
      meta: [workspace.role, workspace.members, workspace.region],
      actions: const ['切换', '管理成员', '查看策略'],
      sections: [
        DetailSection(
          title: 'Profile',
          items: [
            DetailItem(label: 'Role', value: workspace.role),
            DetailItem(label: 'Members', value: workspace.members),
            DetailItem(label: 'Region', value: workspace.region),
          ],
        ),
      ],
    );
  }
}
