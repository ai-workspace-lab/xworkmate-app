import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

enum WorkspaceDestination {
  assistant,
  tasks,
  modules,
  secrets,
  settings,
  account,
}

extension WorkspaceDestinationCopy on WorkspaceDestination {
  String get label => switch (this) {
    WorkspaceDestination.assistant => appText('助手', 'Assistant'),
    WorkspaceDestination.tasks => appText('任务', 'Tasks'),
    WorkspaceDestination.modules => appText('模块', 'Modules'),
    WorkspaceDestination.secrets => appText('密钥', 'Secrets'),
    WorkspaceDestination.settings => appText('设置', 'Settings'),
    WorkspaceDestination.account => appText('账号', 'Account'),
  };

  IconData get icon => switch (this) {
    WorkspaceDestination.assistant => Icons.auto_awesome_rounded,
    WorkspaceDestination.tasks => Icons.layers_rounded,
    WorkspaceDestination.modules => Icons.extension_rounded,
    WorkspaceDestination.secrets => Icons.key_rounded,
    WorkspaceDestination.settings => Icons.tune_rounded,
    WorkspaceDestination.account => Icons.account_circle_rounded,
  };

  String get description => switch (this) {
    WorkspaceDestination.assistant => appText(
      'AI 主入口，优先承接自然输入和高频工作发起。',
      'Primary AI entry point for natural input and frequent task starts.',
    ),
    WorkspaceDestination.tasks => appText(
      '任务队列、运行态、失败项和调度历史的统一视图。',
      'Unified view for queue, running, failed, and history.',
    ),
    WorkspaceDestination.modules => appText(
      '平台能力中心，管理 Gateway、Nodes、Agents、Skills 与 Connectors。',
      'Capability center for gateway, nodes, agents, skills, and connectors.',
    ),
    WorkspaceDestination.secrets => appText(
      'Vault、Provider 凭证与审计信息的轻量管理面。',
      'Lightweight management for vault, provider credentials, and audit data.',
    ),
    WorkspaceDestination.settings => appText(
      '全局配置中心，只负责系统设置与诊断，不承担业务模块入口。',
      'Global settings and diagnostics, separated from business modules.',
    ),
    WorkspaceDestination.account => appText(
      '用户身份、工作区切换与登录会话管理。',
      'Identity, workspace switching, and session management.',
    ),
  };
}

enum StatusTone { neutral, accent, success, warning, danger }

class StatusInfo {
  const StatusInfo(this.label, this.tone);

  final String label;
  final StatusTone tone;
}

enum AppSidebarState { expanded, collapsed, hidden }

enum AssistantMode { code, office }

extension AssistantModeCopy on AssistantMode {
  String get label => switch (this) {
    AssistantMode.code => appText('代码开发', 'Code'),
    AssistantMode.office => appText('日常办公', 'Office'),
  };
}

enum TasksTab { queue, running, history, failed, scheduled }

extension TasksTabCopy on TasksTab {
  String get label => switch (this) {
    TasksTab.queue => appText('队列', 'Queue'),
    TasksTab.running => appText('运行中', 'Running'),
    TasksTab.history => appText('历史', 'History'),
    TasksTab.failed => appText('失败', 'Failed'),
    TasksTab.scheduled => appText('计划中', 'Scheduled'),
  };
}

enum ModulesTab { gateway, nodes, agents, skills, clawHub, connectors }

extension ModulesTabCopy on ModulesTab {
  String get label => switch (this) {
    ModulesTab.gateway => appText('网关', 'Gateway'),
    ModulesTab.nodes => appText('节点', 'Nodes'),
    ModulesTab.agents => appText('代理', 'Agents'),
    ModulesTab.skills => appText('技能', 'Skills'),
    ModulesTab.clawHub => 'ClawHub',
    ModulesTab.connectors => appText('连接器', 'Connectors'),
  };
}

enum SecretsTab { vault, localStore, providers, audit }

extension SecretsTabCopy on SecretsTab {
  String get label => switch (this) {
    SecretsTab.vault => 'Vault',
    SecretsTab.localStore => appText('本地存储', 'Local Store'),
    SecretsTab.providers => appText('提供方', 'Providers'),
    SecretsTab.audit => appText('审计', 'Audit'),
  };
}

enum SettingsTab {
  general,
  workspace,
  gateway,
  appearance,
  diagnostics,
  experimental,
  about,
}

extension SettingsTabCopy on SettingsTab {
  String get label => switch (this) {
    SettingsTab.general => appText('通用', 'General'),
    SettingsTab.workspace => appText('工作区', 'Workspace'),
    SettingsTab.gateway => appText('集成', 'Integrations'),
    SettingsTab.appearance => appText('外观', 'Appearance'),
    SettingsTab.diagnostics => appText('诊断', 'Diagnostics'),
    SettingsTab.experimental => appText('实验特性', 'Experimental'),
    SettingsTab.about => appText('关于', 'About'),
  };
}

enum AccountTab { profile, workspace, sessions }

extension AccountTabCopy on AccountTab {
  String get label => switch (this) {
    AccountTab.profile => appText('资料', 'Profile'),
    AccountTab.workspace => appText('工作区', 'Workspace'),
    AccountTab.sessions => appText('会话', 'Sessions'),
  };
}

class QuickAction {
  const QuickAction({
    required this.title,
    required this.icon,
    required this.caption,
  });

  final String title;
  final IconData icon;
  final String caption;
}

class RecentSession {
  const RecentSession({
    required this.title,
    required this.timestamp,
    required this.summary,
  });

  final String title;
  final String timestamp;
  final String summary;
}

class MetricSummary {
  const MetricSummary({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    this.status,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final StatusInfo? status;
}

class TaskSummary {
  const TaskSummary({
    required this.name,
    required this.owner,
    required this.status,
    required this.startedAt,
    required this.duration,
    required this.surface,
  });

  final String name;
  final String owner;
  final StatusInfo status;
  final String startedAt;
  final String duration;
  final String surface;
}

class ModuleSummary {
  const ModuleSummary({
    required this.name,
    required this.description,
    required this.status,
    required this.meta,
    required this.icon,
  });

  final String name;
  final String description;
  final StatusInfo status;
  final String meta;
  final IconData icon;
}

class NodeSummary {
  const NodeSummary({
    required this.name,
    required this.type,
    required this.region,
    required this.heartbeat,
    required this.load,
    required this.status,
  });

  final String name;
  final String type;
  final String region;
  final String heartbeat;
  final String load;
  final StatusInfo status;
}

class AgentSummary {
  const AgentSummary({
    required this.name,
    required this.description,
    required this.status,
    required this.lastRun,
    required this.capabilities,
  });

  final String name;
  final String description;
  final StatusInfo status;
  final String lastRun;
  final List<String> capabilities;
}

class SkillSummary {
  const SkillSummary({
    required this.name,
    required this.type,
    required this.source,
    required this.status,
    required this.version,
    required this.modules,
  });

  final String name;
  final String type;
  final String source;
  final StatusInfo status;
  final String version;
  final String modules;
}

class ConnectorSummary {
  const ConnectorSummary({
    required this.name,
    required this.description,
    required this.status,
    required this.lastSync,
    required this.permission,
  });

  final String name;
  final String description;
  final StatusInfo status;
  final String lastSync;
  final String permission;
}

class SecretSummary {
  const SecretSummary({
    required this.name,
    required this.scope,
    required this.status,
    required this.updatedAt,
    required this.provider,
  });

  final String name;
  final String scope;
  final StatusInfo status;
  final String updatedAt;
  final String provider;
}

class SecretReference {
  const SecretReference({
    required this.name,
    required this.provider,
    required this.module,
    required this.status,
    required this.maskedValue,
  });

  final String name;
  final String provider;
  final String module;
  final StatusInfo status;
  final String maskedValue;
}

class ProviderSummary {
  const ProviderSummary({
    required this.name,
    required this.description,
    required this.status,
    required this.capabilities,
  });

  final String name;
  final String description;
  final StatusInfo status;
  final List<String> capabilities;
}

class AuditSummary {
  const AuditSummary({
    required this.time,
    required this.action,
    required this.provider,
    required this.target,
    required this.module,
    required this.status,
  });

  final String time;
  final String action;
  final String provider;
  final String target;
  final String module;
  final StatusInfo status;
}

class SettingSummary {
  const SettingSummary({
    required this.title,
    required this.description,
    required this.value,
  });

  final String title;
  final String description;
  final String value;
}

class WorkspaceProfile {
  const WorkspaceProfile({
    required this.name,
    required this.role,
    required this.members,
    required this.region,
  });

  final String name;
  final String role;
  final String members;
  final String region;
}

class DetailPanelData {
  const DetailPanelData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
    required this.description,
    required this.meta,
    required this.sections,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final StatusInfo status;
  final String description;
  final List<String> meta;
  final List<DetailSection> sections;
  final List<String> actions;
}

class DetailSection {
  const DetailSection({required this.title, required this.items});

  final String title;
  final List<DetailItem> items;
}

class DetailItem {
  const DetailItem({required this.label, required this.value});

  final String label;
  final String value;
}

class CommandEntry {
  const CommandEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.keyword,
    this.shortcut,
    this.destination,
    this.detail,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String keyword;
  final String? shortcut;
  final WorkspaceDestination? destination;
  final DetailPanelData? detail;
}
