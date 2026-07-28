import 'package:flutter/material.dart';

enum WorkbenchSection { overview, myWork, projects, inbox }

enum WorkItemState { overdue, needsReview, todo, blocked, done }

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.summary,
    required this.progress,
    required this.currentStage,
    required this.stages,
  });

  final String id;
  final String name;
  final String summary;
  final double progress;
  final String currentStage;
  final List<String> stages;
}

class WorkItem {
  const WorkItem({
    required this.id,
    required this.title,
    required this.source,
    required this.state,
    required this.meta,
    required this.projectId,
  });

  final String id;
  final String title;
  final String source;
  final WorkItemState state;
  final String meta;
  final String? projectId;
}

class WorkNote {
  const WorkNote({
    required this.id,
    required this.title,
    required this.body,
    required this.source,
  });

  final String id;
  final String title;
  final String body;
  final String source;
}

class TaskThread {
  const TaskThread({
    required this.id,
    required this.title,
    required this.projectId,
    required this.status,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String projectId;
  final String status;
  final String updatedAt;
}

class Artifact {
  const Artifact({
    required this.id,
    required this.name,
    required this.kind,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String kind;
  final String updatedAt;
}

class WorkbenchSnapshot {
  const WorkbenchSnapshot({
    required this.projects,
    required this.workItems,
    required this.notes,
    required this.threads,
    required this.artifacts,
    required this.weeklyPlanHours,
    required this.weeklyActualHours,
    required this.dailyLoad,
  });

  final List<Project> projects;
  final List<WorkItem> workItems;
  final List<WorkNote> notes;
  final List<TaskThread> threads;
  final List<Artifact> artifacts;
  final double weeklyPlanHours;
  final double weeklyActualHours;
  final List<double> dailyLoad;

  static const sample = WorkbenchSnapshot(
    projects: [
      Project(
        id: 'xworkmate',
        name: 'AI Workspace APP',
        summary: '核心工作空间与权限体系建设',
        progress: .65,
        currentStage: '开发中',
        stages: ['需求确认', '方案设计', '开发中', '测试', '上线'],
      ),
      Project(
        id: 'xstream',
        name: 'XStream 连接层',
        summary: '模型接入与连接治理',
        progress: .40,
        currentStage: '方案设计',
        stages: ['需求确认', '方案设计', '开发中', '测试', '上线'],
      ),
      Project(
        id: 'github-issues',
        name: 'GitHub Issues 连接器',
        summary: 'Issue 同步与映射增强',
        progress: .25,
        currentStage: '方案设计',
        stages: ['需求确认', '方案设计', '开发中', '测试', '上线'],
      ),
    ],
    workItems: [
      WorkItem(
        id: 'wi-1',
        title: '完善 AI Workspace 权限控制设计文档',
        source: 'AI Workspace',
        state: WorkItemState.overdue,
        meta: '截止：5月10日 · 逾期 2 天',
        projectId: 'xworkmate',
      ),
      WorkItem(
        id: 'wi-2',
        title: '会议纪要：XStream 连接层设计评审',
        source: '语音转写',
        state: WorkItemState.needsReview,
        meta: '10 分钟前 · 等待整理',
        projectId: 'xstream',
      ),
      WorkItem(
        id: 'wi-3',
        title: 'AI Workspace APP · Bug：登录后偶发 500 错误',
        source: 'GitHub Issue #245',
        state: WorkItemState.todo,
        meta: '3 小时前 · 待处理',
        projectId: 'xworkmate',
      ),
      WorkItem(
        id: 'wi-4',
        title: 'XStream 连接层 · 数据源适配开发',
        source: '项目依赖',
        state: WorkItemState.blocked,
        meta: '等待依赖：统一鉴权服务上线',
        projectId: 'xstream',
      ),
    ],
    notes: [
      WorkNote(
        id: 'note-1',
        title: '会议纪要：XStream 连接层设计评审',
        body: '待确认连接器授权范围与失败重试策略。',
        source: '语音转写',
      ),
    ],
    threads: [
      TaskThread(
        id: 'thread-1',
        title: '工作台设计评审',
        projectId: 'xworkmate',
        status: '已同步',
        updatedAt: '10 分钟前',
      ),
    ],
    artifacts: [
      Artifact(
        id: 'artifact-1',
        name: 'AI Workspace 权限控制设计文档',
        kind: 'Markdown',
        updatedAt: '今天 09:40',
      ),
    ],
    weeklyPlanHours: 20,
    weeklyActualHours: 12.5,
    dailyLoad: [10.5, 12.5, 15, 18.2, 16.1, 12.5, 17.8],
  );
}

extension WorkItemStateCopy on WorkItemState {
  String get label => switch (this) {
    WorkItemState.overdue => '逾期',
    WorkItemState.needsReview => '待整理',
    WorkItemState.todo => '待处理',
    WorkItemState.blocked => '被阻塞',
    WorkItemState.done => '已完成',
  };

  Color color(ColorScheme scheme) => switch (this) {
    WorkItemState.overdue => scheme.error,
    WorkItemState.needsReview => const Color(0xFFE89B21),
    WorkItemState.todo => scheme.primary,
    WorkItemState.blocked => scheme.error,
    WorkItemState.done => const Color(0xFF34A853),
  };
}
