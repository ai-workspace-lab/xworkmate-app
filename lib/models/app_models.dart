import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

enum WorkspaceDestination {
  assistant,
  settings,
}

extension WorkspaceDestinationCopy on WorkspaceDestination {
  String get label => switch (this) {
    WorkspaceDestination.assistant => appText('助手', 'Assistant'),
    WorkspaceDestination.settings => appText('设置', 'Settings'),
  };

  IconData get icon => switch (this) {
    WorkspaceDestination.assistant => Icons.chat_bubble_outline_rounded,
    WorkspaceDestination.settings => Icons.tune_rounded,
  };

  String get description => switch (this) {
    WorkspaceDestination.assistant => appText(
      'AI 主入口，优先承接自然输入和高频工作发起。',
      'Primary AI entry point for natural input and frequent task starts.',
    ),
    WorkspaceDestination.settings => appText(
      '桥接、账户与集成配置统一收口到设置中心。',
      'Bridge, account, and integration settings are consolidated in Settings.',
    ),
  };

  static WorkspaceDestination? fromJsonValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    for (final item in WorkspaceDestination.values) {
      if (item.name == value.trim()) {
        return item;
      }
    }
    return null;
  }
}

enum AssistantFocusEntry {
  settings,
  language,
  theme,
}

extension AssistantFocusEntryCopy on AssistantFocusEntry {
  String get label => switch (this) {
    AssistantFocusEntry.settings => appText('设置', 'Settings'),
    AssistantFocusEntry.language => appText('语言', 'Language'),
    AssistantFocusEntry.theme => appText('主题/亮度', 'Theme / Brightness'),
  };

  IconData get icon => switch (this) {
    AssistantFocusEntry.settings => Icons.tune_rounded,
    AssistantFocusEntry.language => Icons.translate_rounded,
    AssistantFocusEntry.theme => Icons.brightness_6_rounded,
  };

  String get description => switch (this) {
    AssistantFocusEntry.settings => appText(
      '打开设置中心，管理 Bridge、账户与集成配置。',
      'Open Settings to manage bridge, account, and integration configuration.',
    ),
    AssistantFocusEntry.language => appText(
      '快速切换中英文界面语言，无需先进入设置页。',
      'Switch the interface language quickly without opening Settings first.',
    ),
    AssistantFocusEntry.theme => appText(
      '快速切换浅色/深色亮度模式，方便在当前上下文立即调整外观。',
      'Switch light and dark appearance modes directly from the current context.',
    ),
  };

  WorkspaceDestination? get destination => switch (this) {
    AssistantFocusEntry.settings => WorkspaceDestination.settings,
    AssistantFocusEntry.language => null,
    AssistantFocusEntry.theme => null,
  };

  bool get opensSettingsPage =>
      this == AssistantFocusEntry.language ||
      this == AssistantFocusEntry.theme ||
      this == AssistantFocusEntry.settings;

  static AssistantFocusEntry? fromJsonValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    for (final item in AssistantFocusEntry.values) {
      if (item.name == value.trim()) {
        return item;
      }
    }
    return null;
  }

  static AssistantFocusEntry fromDestination(WorkspaceDestination destination) {
    return switch (destination) {
      WorkspaceDestination.settings => AssistantFocusEntry.settings,
      WorkspaceDestination.assistant => throw ArgumentError.value(
        destination,
        'destination',
        'Focused assistant entries only support pinnable workspace targets.',
      ),
    };
  }
}

const List<AssistantFocusEntry> kAssistantNavigationDestinationDefaults =
    <AssistantFocusEntry>[];

const List<AssistantFocusEntry> kAssistantNavigationDestinationCandidates =
    <AssistantFocusEntry>[
      AssistantFocusEntry.settings,
      AssistantFocusEntry.language,
      AssistantFocusEntry.theme,
    ];

List<AssistantFocusEntry> normalizeAssistantNavigationDestinations(
  Iterable<AssistantFocusEntry> destinations,
) {
  final allowed = kAssistantNavigationDestinationCandidates.toSet();
  final seen = <AssistantFocusEntry>{};
  final normalized = <AssistantFocusEntry>[];
  for (final destination in destinations) {
    if (!allowed.contains(destination) || !seen.add(destination)) {
      continue;
    }
    normalized.add(destination);
  }
  return normalized;
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

enum SettingsTab { gateway }

extension SettingsTabCopy on SettingsTab {
  String get label => switch (this) {
    SettingsTab.gateway => appText('集成', 'Integrations'),
  };
}

enum SettingsDetailPage { gatewayConnection }

extension SettingsDetailPageCopy on SettingsDetailPage {
  String get label => switch (this) {
    SettingsDetailPage.gatewayConnection => appText(
      'Gateway 连接参数',
      'Gateway Connection',
    ),
  };

  SettingsTab get tab => switch (this) {
    SettingsDetailPage.gatewayConnection => SettingsTab.gateway,
  };
}

@immutable
class SettingsNavigationContext {
  const SettingsNavigationContext({
    required this.rootLabel,
    required this.destination,
    this.sectionLabel,
    this.settingsTab,
    this.gatewayProfileIndex,
    this.prefersGatewaySetupCode,
  });

  final String rootLabel;
  final WorkspaceDestination destination;
  final String? sectionLabel;
  final SettingsTab? settingsTab;
  final int? gatewayProfileIndex;
  final bool? prefersGatewaySetupCode;
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
