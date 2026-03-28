part of 'web_workspace_pages.dart';

List<AppBreadcrumbItem> _buildWebBreadcrumbs(
  AppController controller, {
  required String rootLabel,
  String? sectionLabel,
}) {
  final items = <AppBreadcrumbItem>[
    AppBreadcrumbItem(
      label: appText('主页', 'Home'),
      icon: Icons.home_rounded,
      onTap: controller.navigateHome,
    ),
    AppBreadcrumbItem(label: rootLabel),
  ];
  if (sectionLabel != null && sectionLabel.trim().isNotEmpty) {
    items.add(AppBreadcrumbItem(label: sectionLabel));
  }
  return items;
}

class WebTasksPage extends StatefulWidget {
  const WebTasksPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebTasksPage> createState() => _WebTasksPageState();
}

class _WebTasksPageState extends State<WebTasksPage> {
  TasksTab _tab = TasksTab.queue;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedTaskId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final allItems = controller.taskItemsForTab(_tab.label);
        final items = allItems.where(_matchesQuery).toList(growable: false);
        final selected = _resolveSelectedTask(items);
        final metrics = [
          MetricSummary(
            label: appText('总数', 'Total'),
            value: '${controller.tasksController.totalCount}',
            caption: appText('任务 / 会话聚合', 'Task / session aggregate'),
            icon: Icons.layers_rounded,
          ),
          MetricSummary(
            label: appText('运行中', 'Running'),
            value: '${controller.tasksController.running.length}',
            caption: appText('当前活跃执行', 'Active executions'),
            icon: Icons.play_circle_outline_rounded,
            status: const StatusInfo('Running', StatusTone.success),
          ),
          MetricSummary(
            label: appText('失败', 'Failed'),
            value: '${controller.tasksController.failed.length}',
            caption: appText('中断或报错', 'Interrupted or failed'),
            icon: Icons.error_outline_rounded,
            status: const StatusInfo('Failed', StatusTone.danger),
          ),
          MetricSummary(
            label: appText('计划中', 'Scheduled'),
            value: '${controller.tasksController.scheduled.length}',
            caption: appText('来自 cron 调度器', 'Loaded from cron scheduler'),
            icon: Icons.event_repeat_rounded,
          ),
        ];

        return DesktopWorkspaceScaffold(
          breadcrumbs: _buildWebBreadcrumbs(
            controller,
            rootLabel: WorkspaceDestination.tasks.label,
          ),
          eyebrow: appText('任务与线程', 'Tasks and sessions'),
          title: appText('任务工作台', 'Task workspace'),
          subtitle: appText(
            '左侧筛选和切换任务，右侧查看当前任务详情。',
            'Filter and switch tasks on the left, inspect the current task on the right.',
          ),
          toolbar: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() => _query = value.trim().toLowerCase());
                  },
                  decoration: InputDecoration(
                    hintText: appText('搜索任务 / 会话', 'Search tasks / sessions'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: appText('清除', 'Clear'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              IconButton(
                tooltip: appText('刷新任务', 'Refresh tasks'),
                onPressed: controller.refreshSessions,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SectionTabs(
                  items: TasksTab.values.map((item) => item.label).toList(),
                  value: _tab.label,
                  onChanged: (value) {
                    setState(() {
                      _tab = TasksTab.values.firstWhere(
                        (item) => item.label == value,
                      );
                      _selectedTaskId = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 172,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: metrics.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => SizedBox(
                      width: 240,
                      child: MetricCard(metric: metrics[index]),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SurfaceCard(
                    padding: EdgeInsets.zero,
                    borderRadius: 20,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 360,
                            child: _TaskListPanel(
                              tab: _tab,
                              items: items,
                              selectedTaskId: selected?.id,
                              onSelectTask: (task) {
                                setState(() => _selectedTaskId = task.id);
                              },
                            ),
                          ),
                          Container(
                            width: 1,
                            color: context.palette.strokeSoft,
                          ),
                          Expanded(
                            child: _TaskDetailPanel(
                              controller: controller,
                              tab: _tab,
                              selected: selected,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _matchesQuery(DerivedTaskItem item) {
    if (_query.isEmpty) {
      return true;
    }
    final haystack = [
      item.title,
      item.summary,
      item.owner,
      item.surface,
      item.sessionKey,
    ].join(' ').toLowerCase();
    return haystack.contains(_query);
  }

  DerivedTaskItem? _resolveSelectedTask(List<DerivedTaskItem> items) {
    if (items.isEmpty) {
      return null;
    }
    for (final item in items) {
      if (item.id == _selectedTaskId) {
        return item;
      }
    }
    return items.first;
  }
}

class WebSkillsPage extends StatefulWidget {
  const WebSkillsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebSkillsPage> createState() => _WebSkillsPageState();
}

class _WebSkillsPageState extends State<WebSkillsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedSkillKey;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final skills = controller.skills
            .where(_matchesQuery)
            .toList(growable: false);
        final selected = _resolveSelectedSkill(skills);
        return DesktopWorkspaceScaffold(
          breadcrumbs: _buildWebBreadcrumbs(
            controller,
            rootLabel: WorkspaceDestination.skills.label,
          ),
          eyebrow: appText('技能与能力包', 'Skills and capabilities'),
          title: appText('技能工作台', 'Skills workspace'),
          subtitle: appText(
            '左侧浏览技能包，右侧查看描述、依赖和使用建议。',
            'Browse skills on the left, inspect descriptions, dependencies, and usage guidance on the right.',
          ),
          toolbar: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() => _query = value.trim().toLowerCase());
                  },
                  decoration: InputDecoration(
                    hintText: appText('搜索技能', 'Search skills'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: appText('清除', 'Clear'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              IconButton(
                tooltip: appText('刷新技能', 'Refresh skills'),
                onPressed: () => controller.skillsController.refresh(
                  agentId: controller.selectedAgentId.isEmpty
                      ? null
                      : controller.selectedAgentId,
                ),
                icon: const Icon(Icons.refresh_rounded),
              ),
              FilledButton.tonalIcon(
                onPressed: () =>
                    controller.navigateTo(WorkspaceDestination.assistant),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(appText('回到对话使用', 'Use in assistant')),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SurfaceCard(
              padding: EdgeInsets.zero,
              borderRadius: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Row(
                  children: [
                    SizedBox(
                      width: 360,
                      child: _SkillsListPanel(
                        skills: skills,
                        selectedSkillKey: selected?.skillKey,
                        onSelectSkill: (skill) {
                          setState(() => _selectedSkillKey = skill.skillKey);
                        },
                      ),
                    ),
                    Container(width: 1, color: context.palette.strokeSoft),
                    Expanded(
                      child: _SkillDetailPanel(
                        controller: controller,
                        selected: selected,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _matchesQuery(GatewaySkillSummary skill) {
    if (_query.isEmpty) {
      return true;
    }
    final haystack = [
      skill.name,
      skill.description,
      skill.source,
      skill.skillKey,
      skill.primaryEnv ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(_query);
  }

  GatewaySkillSummary? _resolveSelectedSkill(List<GatewaySkillSummary> skills) {
    if (skills.isEmpty) {
      return null;
    }
    for (final skill in skills) {
      if (skill.skillKey == _selectedSkillKey) {
        return skill;
      }
    }
    return skills.first;
  }
}

class WebNodesPage extends StatefulWidget {
  const WebNodesPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebNodesPage> createState() => _WebNodesPageState();
}

enum _WebNodesTab { nodes, agents, connectors, models }

class _WebNodesPageState extends State<WebNodesPage> {
  final TextEditingController _searchController = TextEditingController();
  _WebNodesTab _tab = _WebNodesTab.nodes;
  String _query = '';
  String? _selectedId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final items = _itemsForTab(
          controller,
        ).where(_matchesQuery).toList(growable: false);
        final selected = _resolveSelected(items);
        return DesktopWorkspaceScaffold(
          breadcrumbs: _buildWebBreadcrumbs(
            controller,
            rootLabel: WorkspaceDestination.nodes.label,
            sectionLabel: _tabLabel(_tab),
          ),
          eyebrow: appText('节点与运行资源', 'Nodes and runtime resources'),
          title: appText('节点工作台', 'Nodes workspace'),
          subtitle: appText(
            '查看节点、代理、连接器和模型目录，保持 Web 与桌面工作台的信息层级一致。',
            'Inspect nodes, agents, connectors, and model catalogs with the same information hierarchy as the desktop workspace.',
          ),
          toolbar: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _query = value.trim().toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: appText('搜索节点资源', 'Search resources'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: appText('清除', 'Clear'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              IconButton(
                tooltip: appText('刷新资源', 'Refresh resources'),
                onPressed: controller.refreshAgents,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SectionTabs(
                  items: _WebNodesTab.values.map(_tabLabel).toList(),
                  value: _tabLabel(_tab),
                  onChanged: (value) {
                    setState(() {
                      _tab = _WebNodesTab.values.firstWhere(
                        (item) => _tabLabel(item) == value,
                      );
                      _selectedId = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                _WorkspaceStatusBanner(
                  controller: controller,
                  emptyMessage: appText(
                    '连接 Gateway 后这里会显示节点和运行资源摘要。',
                    'Connect a gateway to load node and runtime summaries.',
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SurfaceCard(
                    padding: EdgeInsets.zero,
                    borderRadius: 20,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 360,
                            child: _ResourceListPanel(
                              title: _tabLabel(_tab),
                              emptyLabel: _emptyLabel(_tab),
                              items: items,
                              selectedId: selected?.id,
                              onSelect: (item) {
                                setState(() => _selectedId = item.id);
                              },
                            ),
                          ),
                          Container(
                            width: 1,
                            color: context.palette.strokeSoft,
                          ),
                          Expanded(
                            child: _ResourceDetailPanel(
                              title: _tabLabel(_tab),
                              item: selected,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_WorkspaceResourceItem> _itemsForTab(AppController controller) {
    return switch (_tab) {
      _WebNodesTab.nodes =>
        controller.instances
            .map(
              (item) => _WorkspaceResourceItem(
                id: item.id,
                title: item.host?.trim().isNotEmpty == true
                    ? item.host!
                    : item.id,
                subtitle: [item.platform, item.deviceFamily, item.ip]
                    .whereType<String>()
                    .where((item) => item.trim().isNotEmpty)
                    .join(' · '),
                status: item.mode ?? item.reason ?? appText('未知', 'Unknown'),
                detailLines: <String>[
                  '${appText('实例 ID', 'Instance ID')}: ${item.id}',
                  if (item.version?.trim().isNotEmpty == true)
                    '${appText('版本', 'Version')}: ${item.version}',
                  if (item.modelIdentifier?.trim().isNotEmpty == true)
                    '${appText('机型', 'Model')}: ${item.modelIdentifier}',
                  if (item.text.trim().isNotEmpty)
                    '${appText('状态说明', 'Status note')}: ${item.text}',
                ],
              ),
            )
            .toList(growable: false),
      _WebNodesTab.agents =>
        controller.agents
            .map(
              (item) => _WorkspaceResourceItem(
                id: item.id,
                title: '${item.emoji} ${item.name}',
                subtitle: item.id,
                status: item.theme,
                detailLines: <String>[
                  '${appText('代理 ID', 'Agent ID')}: ${item.id}',
                  '${appText('主题', 'Theme')}: ${item.theme}',
                ],
              ),
            )
            .toList(growable: false),
      _WebNodesTab.connectors =>
        controller.connectors
            .map(
              (item) => _WorkspaceResourceItem(
                id: '${item.id}:${item.accountName ?? 'default'}',
                title: item.label,
                subtitle: [item.detailLabel, item.accountName]
                    .whereType<String>()
                    .where((item) => item.trim().isNotEmpty)
                    .join(' · '),
                status: item.status,
                detailLines: <String>[
                  '${appText('连接器', 'Connector')}: ${item.id}',
                  '${appText('状态', 'Status')}: ${item.status}',
                  if (item.meta.isNotEmpty) item.meta.join(' · '),
                  if (item.lastError?.trim().isNotEmpty == true)
                    '${appText('错误', 'Error')}: ${item.lastError}',
                ],
              ),
            )
            .toList(growable: false),
      _WebNodesTab.models =>
        controller.models
            .map(
              (item) => _WorkspaceResourceItem(
                id: item.id,
                title: item.name,
                subtitle: item.provider,
                status: item.id,
                detailLines: <String>[
                  '${appText('模型 ID', 'Model ID')}: ${item.id}',
                  '${appText('提供方', 'Provider')}: ${item.provider}',
                  if (item.contextWindow != null)
                    '${appText('上下文窗口', 'Context window')}: ${item.contextWindow}',
                  if (item.maxOutputTokens != null)
                    '${appText('最大输出', 'Max output')}: ${item.maxOutputTokens}',
                ],
              ),
            )
            .toList(growable: false),
    };
  }

  bool _matchesQuery(_WorkspaceResourceItem item) {
    if (_query.isEmpty) {
      return true;
    }
    final haystack = [
      item.title,
      item.subtitle,
      item.status,
      ...item.detailLines,
    ].join(' ').toLowerCase();
    return haystack.contains(_query);
  }

  _WorkspaceResourceItem? _resolveSelected(List<_WorkspaceResourceItem> items) {
    if (items.isEmpty) {
      return null;
    }
    for (final item in items) {
      if (item.id == _selectedId) {
        return item;
      }
    }
    return items.first;
  }

  String _tabLabel(_WebNodesTab tab) {
    return switch (tab) {
      _WebNodesTab.nodes => appText('节点', 'Nodes'),
      _WebNodesTab.agents => appText('代理', 'Agents'),
      _WebNodesTab.connectors => appText('连接器', 'Connectors'),
      _WebNodesTab.models => appText('模型', 'Models'),
    };
  }

  String _emptyLabel(_WebNodesTab tab) {
    return switch (tab) {
      _WebNodesTab.nodes => appText('当前没有节点。', 'No nodes are available.'),
      _WebNodesTab.agents => appText('当前没有代理。', 'No agents are available.'),
      _WebNodesTab.connectors => appText(
        '当前没有连接器。',
        'No connectors are available.',
      ),
      _WebNodesTab.models => appText('当前没有模型。', 'No models are available.'),
    };
  }
}

class WebSecretsPage extends StatefulWidget {
  const WebSecretsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebSecretsPage> createState() => _WebSecretsPageState();
}

class _WebSecretsPageState extends State<WebSecretsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedName;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final items = controller.secretReferences
            .where((item) => _matches(item))
            .toList(growable: false);
        final selected = _resolveSelected(items);
        return DesktopWorkspaceScaffold(
          breadcrumbs: _buildWebBreadcrumbs(
            controller,
            rootLabel: WorkspaceDestination.secrets.label,
          ),
          eyebrow: appText('密钥与引用', 'Secrets and references'),
          title: appText('密钥工作台', 'Secrets workspace'),
          subtitle: appText(
            'Web 端只显示脱敏引用和来源摘要，具体编辑仍统一回到 Settings。',
            'Web exposes masked references and source summaries here, while editing still lives in Settings.',
          ),
          toolbar: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() => _query = value.trim().toLowerCase());
                  },
                  decoration: InputDecoration(
                    hintText: appText('搜索密钥引用', 'Search secret references'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: appText('清除', 'Clear'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () =>
                    controller.openSettings(tab: SettingsTab.gateway),
                icon: const Icon(Icons.tune_rounded),
                label: Text(appText('打开设置', 'Open settings')),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SurfaceCard(
                  child: Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        color: context.palette.accent,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          appText(
                            'Web 只显示脱敏引用。凭证编辑和连通性测试仍统一走 Settings -> Integrations。',
                            'Web shows masked references only. Credential editing and connectivity tests continue to flow through Settings -> Integrations.',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SurfaceCard(
                    padding: EdgeInsets.zero,
                    borderRadius: 20,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 360,
                            child: _SecretListPanel(
                              items: items,
                              selectedName: selected?.name,
                              onSelect: (item) {
                                setState(() => _selectedName = item.name);
                              },
                            ),
                          ),
                          Container(
                            width: 1,
                            color: context.palette.strokeSoft,
                          ),
                          Expanded(child: _SecretDetailPanel(item: selected)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _matches(SecretReferenceEntry item) {
    if (_query.isEmpty) {
      return true;
    }
    final haystack = [
      item.name,
      item.provider,
      item.module,
      item.maskedValue,
      item.status,
    ].join(' ').toLowerCase();
    return haystack.contains(_query);
  }

  SecretReferenceEntry? _resolveSelected(List<SecretReferenceEntry> items) {
    if (items.isEmpty) {
      return null;
    }
    for (final item in items) {
      if (item.name == _selectedName) {
        return item;
      }
    }
    return items.first;
  }
}

class WebAiGatewayPage extends StatefulWidget {
  const WebAiGatewayPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebAiGatewayPage> createState() => _WebAiGatewayPageState();
}

class _WebAiGatewayPageState extends State<WebAiGatewayPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedModelId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final models = controller.models
            .where((item) => _matches(item))
            .toList(growable: false);
        final selected = _resolveSelected(models);
        return DesktopWorkspaceScaffold(
          breadcrumbs: _buildWebBreadcrumbs(
            controller,
            rootLabel: WorkspaceDestination.aiGateway.label,
          ),
          eyebrow: appText('模型接入与目录', 'Model access and catalog'),
          title: appText('LLM API 工作台', 'LLM API workspace'),
          subtitle: appText(
            '查看当前默认接入点、默认模型和模型目录；具体配置仍统一回到 Settings。',
            'Inspect the current default endpoint, default model, and catalog here, while configuration remains centralized in Settings.',
          ),
          toolbar: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() => _query = value.trim().toLowerCase());
                  },
                  decoration: InputDecoration(
                    hintText: appText('搜索模型', 'Search models'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: appText('清除', 'Clear'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () =>
                    widget.controller.openSettings(tab: SettingsTab.gateway),
                icon: const Icon(Icons.tune_rounded),
                label: Text(appText('打开设置', 'Open settings')),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SurfaceCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              controller.settings.aiGateway.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              controller.settings.aiGateway.baseUrl
                                      .trim()
                                      .isEmpty
                                  ? appText(
                                      '当前还没有配置 endpoint。',
                                      'No endpoint is configured yet.',
                                    )
                                  : controller.settings.aiGateway.baseUrl
                                        .trim(),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: context.palette.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      StatusBadge(
                        status: StatusInfo(
                          controller.settings.aiGateway.syncState,
                          controller.settings.aiGateway.syncState == 'ready'
                              ? StatusTone.success
                              : StatusTone.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SurfaceCard(
                    padding: EdgeInsets.zero,
                    borderRadius: 20,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 360,
                            child: _ModelListPanel(
                              items: models,
                              selectedId: selected?.id,
                              onSelect: (item) {
                                setState(() => _selectedModelId = item.id);
                              },
                            ),
                          ),
                          Container(
                            width: 1,
                            color: context.palette.strokeSoft,
                          ),
                          Expanded(child: _ModelDetailPanel(model: selected)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _matches(GatewayModelSummary item) {
    if (_query.isEmpty) {
      return true;
    }
    final haystack = [
      item.id,
      item.name,
      item.provider,
      '${item.contextWindow ?? ''}',
      '${item.maxOutputTokens ?? ''}',
    ].join(' ').toLowerCase();
    return haystack.contains(_query);
  }

  GatewayModelSummary? _resolveSelected(List<GatewayModelSummary> items) {
    if (items.isEmpty) {
      return null;
    }
    for (final item in items) {
      if (item.id == _selectedModelId) {
        return item;
      }
    }
    return items.first;
  }
}

class _TaskListPanel extends StatelessWidget {
  const _TaskListPanel({
    required this.tab,
    required this.items,
    required this.selectedTaskId,
    required this.onSelectTask,
  });

  final TasksTab tab;
  final List<DerivedTaskItem> items;
  final String? selectedTaskId;
  final ValueChanged<DerivedTaskItem> onSelectTask;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final emptyLabel = tab == TasksTab.scheduled
        ? appText('当前没有计划任务。', 'No scheduled tasks right now.')
        : appText('当前筛选下没有任务。', 'No tasks match the current filter.');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(
            children: [
              Text(
                appText('任务列表', 'Task list'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Text(
                '${items.length}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
        Container(height: 1, color: palette.strokeSoft),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      emptyLabel,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final task = items[index];
                    final selected = task.id == selectedTaskId;
                    return _TaskListTile(
                      task: task,
                      selected: selected,
                      onTap: () => onSelectTask(task),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TaskListTile extends StatelessWidget {
  const _TaskListTile({
    required this.task,
    required this.selected,
    required this.onTap,
  });

  final DerivedTaskItem task;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: selected ? palette.surfacePrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: ValueKey<String>('tasks-list-item-${task.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? palette.surfaceSecondary : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: palette.shadow.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  StatusBadge(status: _taskStatusInfo(task.status)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                task.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  _InlineMeta(label: task.owner),
                  _InlineMeta(label: task.startedAtLabel),
                  _InlineMeta(label: task.surface),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskDetailPanel extends StatelessWidget {
  const _TaskDetailPanel({
    required this.controller,
    required this.tab,
    required this.selected,
  });

  final AppController controller;
  final TasksTab tab;
  final DerivedTaskItem? selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (selected == null) {
      return Center(
        child: Text(
          appText('选择左侧任务查看详情。', 'Select a task on the left.'),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: palette.textSecondary),
        ),
      );
    }

    return Padding(
      key: const Key('tasks-detail-panel'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                selected!.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              StatusBadge(status: _taskStatusInfo(selected!.status)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            selected!.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _DetailStat(
                label: appText('任务来源', 'Surface'),
                value: selected!.surface,
              ),
              _DetailStat(
                label: appText('执行代理', 'Owner'),
                value: selected!.owner,
              ),
              _DetailStat(
                label: appText('开始时间', 'Started'),
                value: selected!.startedAtLabel,
              ),
              _DetailStat(
                label: appText('耗时', 'Duration'),
                value: selected!.durationLabel,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.surfaceSecondary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appText('会话上下文', 'Conversation context'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  selected!.sessionKey,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: controller.refreshSessions,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(appText('刷新', 'Refresh')),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillsListPanel extends StatelessWidget {
  const _SkillsListPanel({
    required this.skills,
    required this.selectedSkillKey,
    required this.onSelectSkill,
  });

  final List<GatewaySkillSummary> skills;
  final String? selectedSkillKey;
  final ValueChanged<GatewaySkillSummary> onSelectSkill;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(
            children: [
              Text(
                appText('技能列表', 'Skill list'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Text(
                '${skills.length}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
        Container(height: 1, color: palette.strokeSoft),
        Expanded(
          child: skills.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      appText(
                        '当前没有可展示的技能。',
                        'No skills are available right now.',
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: skills.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final skill = skills[index];
                    return _SkillListTile(
                      skill: skill,
                      selected: skill.skillKey == selectedSkillKey,
                      onTap: () => onSelectSkill(skill),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SkillListTile extends StatelessWidget {
  const _SkillListTile({
    required this.skill,
    required this.selected,
    required this.onTap,
  });

  final GatewaySkillSummary skill;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: selected ? palette.surfacePrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected ? palette.surfaceSecondary : Colors.transparent,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: palette.shadow.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: Text(
            skill.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: selected ? palette.textPrimary : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillDetailPanel extends StatelessWidget {
  const _SkillDetailPanel({required this.controller, required this.selected});

  final AppController controller;
  final GatewaySkillSummary? selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (selected == null) {
      return Center(
        child: Text(
          appText('选择左侧技能查看详情。', 'Select a skill on the left.'),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: palette.textSecondary),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                selected!.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              StatusBadge(
                status: selected!.disabled
                    ? _skillStatus(
                        appText('已禁用', 'Disabled'),
                        StatusTone.warning,
                      )
                    : _skillStatus(
                        appText('已启用', 'Enabled'),
                        StatusTone.success,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            selected!.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _DependencyCard(
                title: appText('缺失二进制', 'Missing bins'),
                values: selected!.missingBins,
              ),
              _DependencyCard(
                title: appText('缺失环境变量', 'Missing env'),
                values: selected!.missingEnv,
              ),
              _DependencyCard(
                title: appText('缺失配置', 'Missing config'),
                values: selected!.missingConfig,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.surfaceSecondary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appText('在对话中使用', 'Use in the assistant'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  appText(
                    '回到 Assistant 后，可通过下方建议按钮或直接描述需求来调用该技能上下文。',
                    'After returning to Assistant, use the suggested chips or describe the task directly to route into this skill context.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () =>
                    controller.navigateTo(WorkspaceDestination.assistant),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(appText('去对话中使用', 'Use in assistant')),
              ),
              OutlinedButton.icon(
                onPressed: () => controller.skillsController.refresh(
                  agentId: controller.selectedAgentId.isEmpty
                      ? null
                      : controller.selectedAgentId,
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(appText('刷新', 'Refresh')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DependencyCard extends StatelessWidget {
  const _DependencyCard({required this.title, required this.values});

  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            values.isEmpty ? appText('无', 'None') : values.join(', '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _InlineMeta extends StatelessWidget {
  const _InlineMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
    );
  }
}

StatusInfo _taskStatusInfo(String status) => switch (status) {
  'running' ||
  'Running' => StatusInfo(appText('运行中', 'Running'), StatusTone.accent),
  'failed' ||
  'Failed' => StatusInfo(appText('失败', 'Failed'), StatusTone.danger),
  'queued' ||
  'Queued' => StatusInfo(appText('排队中', 'Queued'), StatusTone.neutral),
  _ => StatusInfo(appText('可继续', 'Open'), StatusTone.success),
};

StatusInfo _skillStatus(String label, StatusTone tone) =>
    StatusInfo(label, tone);

class _WorkspaceStatusBanner extends StatelessWidget {
  const _WorkspaceStatusBanner({
    required this.controller,
    required this.emptyMessage,
  });

  final AppController controller;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final connected =
        controller.connection.status == RuntimeConnectionStatus.connected;
    return SurfaceCard(
      child: Row(
        children: [
          Icon(
            connected ? Icons.check_circle_outline_rounded : Icons.info_outline,
            color: connected
                ? context.palette.success
                : context.palette.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              connected
                  ? appText(
                      '当前使用 ${controller.connection.status.label} 连接，可刷新查看最新资源摘要。',
                      'The gateway connection is available. Refresh to load the latest resource summaries.',
                    )
                  : emptyMessage,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceResourceItem {
  const _WorkspaceResourceItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.detailLines,
  });

  final String id;
  final String title;
  final String subtitle;
  final String status;
  final List<String> detailLines;
}

class _ResourceListPanel extends StatelessWidget {
  const _ResourceListPanel({
    required this.title,
    required this.emptyLabel,
    required this.items,
    required this.selectedId,
    required this.onSelect,
  });

  final String title;
  final String emptyLabel;
  final List<_WorkspaceResourceItem> items;
  final String? selectedId;
  final ValueChanged<_WorkspaceResourceItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 8),
              Text(
                '${items.length}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
        Container(height: 1, color: palette.strokeSoft),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      emptyLabel,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = item.id == selectedId;
                    return SurfaceCard(
                      key: ValueKey<String>('resource-item-${item.id}'),
                      tone: selected
                          ? SurfaceCardTone.chrome
                          : SurfaceCardTone.standard,
                      onTap: () => onSelect(item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (item.subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            item.status,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: palette.textMuted),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ResourceDetailPanel extends StatelessWidget {
  const _ResourceDetailPanel({required this.title, required this.item});

  final String title;
  final _WorkspaceResourceItem? item;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (item == null) {
      return Center(
        child: Text(
          appText('请选择一项查看详情。', 'Select an item to inspect details.'),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Text(
          item!.title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (item!.subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            item!.subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [Chip(label: Text(item!.status))],
        ),
        const SizedBox(height: 16),
        ...item!.detailLines.map(
          (line) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(line, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
      ],
    );
  }
}

class _SecretListPanel extends StatelessWidget {
  const _SecretListPanel({
    required this.items,
    required this.selectedName,
    required this.onSelect,
  });

  final List<SecretReferenceEntry> items;
  final String? selectedName;
  final ValueChanged<SecretReferenceEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(
            children: [
              Text(
                appText('密钥引用', 'Secret references'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Text(
                '${items.length}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
        Container(height: 1, color: palette.strokeSoft),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    appText(
                      '当前没有可显示的密钥引用。',
                      'No masked secret references are available yet.',
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = item.name == selectedName;
                    return SurfaceCard(
                      tone: selected
                          ? SurfaceCardTone.chrome
                          : SurfaceCardTone.standard,
                      onTap: () => onSelect(item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.provider} · ${item.module}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Text(item.maskedValue),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SecretDetailPanel extends StatelessWidget {
  const _SecretDetailPanel({required this.item});

  final SecretReferenceEntry? item;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (item == null) {
      return Center(
        child: Text(
          appText('请选择一个密钥引用。', 'Select a secret reference.'),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(item!.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '${item!.provider} · ${item!.module}',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: 16),
        Chip(label: Text(item!.status)),
        const SizedBox(height: 16),
        Text(
          appText('脱敏值', 'Masked value'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SelectableText(item!.maskedValue),
      ],
    );
  }
}

class _ModelListPanel extends StatelessWidget {
  const _ModelListPanel({
    required this.items,
    required this.selectedId,
    required this.onSelect,
  });

  final List<GatewayModelSummary> items;
  final String? selectedId;
  final ValueChanged<GatewayModelSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(
            children: [
              Text(
                appText('模型目录', 'Model catalog'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Text(
                '${items.length}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
        Container(height: 1, color: palette.strokeSoft),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    appText('当前没有可显示的模型。', 'No models are available yet.'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = item.id == selectedId;
                    return SurfaceCard(
                      tone: selected
                          ? SurfaceCardTone.chrome
                          : SurfaceCardTone.standard,
                      onTap: () => onSelect(item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.provider,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Text(item.id),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ModelDetailPanel extends StatelessWidget {
  const _ModelDetailPanel({required this.model});

  final GatewayModelSummary? model;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (model == null) {
      return Center(
        child: Text(
          appText('请选择一个模型。', 'Select a model.'),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(model!.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          model!.provider,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: 16),
        Chip(label: Text(model!.id)),
        const SizedBox(height: 16),
        Text('ID: ${model!.id}'),
        if (model!.contextWindow != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${appText('上下文窗口', 'Context window')}: ${model!.contextWindow}',
            ),
          ),
        if (model!.maxOutputTokens != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${appText('最大输出', 'Max output')}: ${model!.maxOutputTokens}',
            ),
          ),
      ],
    );
  }
}
