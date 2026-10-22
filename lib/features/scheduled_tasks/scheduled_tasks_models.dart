import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';

enum ScheduledTaskType {
  qmdSync,
  codexAudit,
  geminiAnalysis,
  grokBuild,
  custom,
}

extension ScheduledTaskTypeDetails on ScheduledTaskType {
  String get label => switch (this) {
    ScheduledTaskType.qmdSync => appText('QMD 周期同步', 'QMD periodic sync'),
    ScheduledTaskType.codexAudit => appText('Codex 代码审计', 'Codex code audit'),
    ScheduledTaskType.geminiAnalysis => appText('Gemini 架构分析', 'Gemini architecture review'),
    ScheduledTaskType.grokBuild => appText('Grok 构建验证', 'Grok build verifier'),
    ScheduledTaskType.custom => appText('自定义计划任务', 'Custom scheduled task'),
  };

  IconData get icon => switch (this) {
    ScheduledTaskType.qmdSync => Icons.cloud_sync_rounded,
    ScheduledTaskType.codexAudit => Icons.code_rounded,
    ScheduledTaskType.geminiAnalysis => Icons.auto_awesome_rounded,
    ScheduledTaskType.grokBuild => Icons.terminal_rounded,
    ScheduledTaskType.custom => Icons.schedule_rounded,
  };
}

class ScheduledTaskConfig {
  const ScheduledTaskConfig({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.sourceAgent,
    required this.targetModel,
    required this.intervalMinutes,
    this.enabled = true,
    this.lastRunAt,
    this.lastStatus,
    this.lastError,
    this.sessionKey,
  });

  final String id;
  final ScheduledTaskType type;
  final String title;
  final String description;
  final String sourceAgent;
  final String targetModel;
  final int intervalMinutes;
  final bool enabled;
  final DateTime? lastRunAt;
  final String? lastStatus;
  final String? lastError;
  final String? sessionKey;

  String get intervalLabel {
    if (intervalMinutes < 60) {
      return appText('每 $intervalMinutes 分钟', 'Every $intervalMinutes min');
    }
    final hours = intervalMinutes ~/ 60;
    if (hours < 24) {
      return appText('每 $hours 小时', 'Every $hours hr');
    }
    final days = hours ~/ 24;
    return appText('每 $days 天', 'Every $days day');
  }

  ScheduledTaskConfig copyWith({
    String? id,
    ScheduledTaskType? type,
    String? title,
    String? description,
    String? sourceAgent,
    String? targetModel,
    int? intervalMinutes,
    bool? enabled,
    DateTime? lastRunAt,
    String? lastStatus,
    String? lastError,
    String? sessionKey,
  }) {
    return ScheduledTaskConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      sourceAgent: sourceAgent ?? this.sourceAgent,
      targetModel: targetModel ?? this.targetModel,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      enabled: enabled ?? this.enabled,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      lastStatus: lastStatus ?? this.lastStatus,
      lastError: lastError ?? this.lastError,
      sessionKey: sessionKey ?? this.sessionKey,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type.name,
    'title': title,
    'description': description,
    'sourceAgent': sourceAgent,
    'targetModel': targetModel,
    'intervalMinutes': intervalMinutes,
    'enabled': enabled,
    'lastRunAt': lastRunAt?.toIso8601String(),
    'lastStatus': lastStatus,
    'lastError': lastError,
    'sessionKey': sessionKey,
  };

  factory ScheduledTaskConfig.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? '';
    final type = ScheduledTaskType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => ScheduledTaskType.custom,
    );
    final lastRunAtStr = json['lastRunAt'] as String?;
    return ScheduledTaskConfig(
      id: json['id'] as String? ?? '',
      type: type,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      sourceAgent: json['sourceAgent'] as String? ?? '',
      targetModel: json['targetModel'] as String? ?? '',
      intervalMinutes: json['intervalMinutes'] as int? ?? 60,
      enabled: json['enabled'] as bool? ?? true,
      lastRunAt: lastRunAtStr != null ? DateTime.tryParse(lastRunAtStr) : null,
      lastStatus: json['lastStatus'] as String?,
      lastError: json['lastError'] as String?,
      sessionKey: json['sessionKey'] as String?,
    );
  }
}
