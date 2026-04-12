import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/ui_feature_manifest.dart';
import '../../app/workspace_navigation.dart';
import '../../app/app_metadata.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';

class ModulesPage extends StatefulWidget {
  const ModulesPage({
    super.key,
    required this.controller,
    required this.onOpenDetail,
    this.initialTab,
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;
  final ModulesTab? initialTab;

  @override
  State<ModulesPage> createState() => _ModulesPageState();
}

class _ModulesPageState extends State<ModulesPage> {
  late ModulesTab _tab;

  ModulesTab _normalizeTab(ModulesTab tab) {
    final normalized = tab == ModulesTab.gateway ? ModulesTab.nodes : tab;
    if (_isTabVisible(normalized)) {
      return normalized;
    }
    return ModulesTab.skills;
  }

  bool _isTabVisible(ModulesTab tab) {
    if (tab == ModulesTab.clawHub) {
      final features = widget.controller.featuresFor(UiFeaturePlatform.desktop);
      return features.isEnabledPath(UiFeatureKeys.workspaceClawHub);
    }
    if (tab == ModulesTab.connectors) {
      final features = widget.controller.featuresFor(UiFeaturePlatform.desktop);
      return features.isEnabledPath(UiFeatureKeys.workspaceConnectors);
    }
    return true;
  }

  List<ModulesTab> get _visibleTabs => ModulesTab.values
      .where((item) => item != ModulesTab.gateway)
      .where(_isTabVisible)
      .toList(growable: false);

  ModulesTab _tabForLabel(String value) {
    return _visibleTabs.firstWhere(
      (item) => item.label == value,
      orElse: () => ModulesTab.skills,
    );
  }

  @override
  void initState() {
    super.initState();
    _tab = _normalizeTab(widget.initialTab ?? widget.controller.modulesTab);
  }

  @override
  void didUpdateWidget(covariant ModulesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextTab = _normalizeTab(
      widget.initialTab ?? widget.controller.modulesTab,
    );
    if (nextTab != _tab) {
      setState(() => _tab = nextTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final metrics = [
      MetricSummary(
        label: appText('网关', 'Gateway'),
        value: controller.connection.status.label,
        caption: controller.connection.remoteAddress ?? kAppVersionLabel,
        icon: Icons.wifi_tethering_rounded,
        status: _connectionStatus(controller.connection.status),
      ),
      MetricSummary(
        label: appText('节点', 'Nodes'),
        value: '${controller.instances.length}',
        caption: appText(
          '${controller.instances.where((item) => item.mode == 'active').length} 个活跃实例',
          '${controller.instances.where((item) => item.mode == 'active').length} active',
        ),
        icon: Icons.developer_board_rounded,
      ),
      MetricSummary(
        label: appText('代理', 'Agents'),
        value: '${controller.agents.length}',
        caption: controller.activeAgentName,
        icon: Icons.hub_rounded,
      ),
    ];

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                breadcrumbs: buildWorkspaceBreadcrumbs(
                  controller: controller,
                  rootLabel: appText('模块', 'Modules'),
                  sectionLabel: _tab.label,
                ),
                title: appText('模块', 'Modules'),
                subtitle: appText(
                  '管理代理、节点、技能和平台服务。',
                  'Manage agents, nodes, skills, and platform services.',
                ),
                trailing: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: appText('搜索模块', 'Search modules'),
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await controller.refreshGatewayHealth();
                        await controller.refreshAgents();
                        await controller.refreshSessions();
                        await controller.instancesController.refresh();
                        await controller.skillsController.refresh(
                          agentId: controller.selectedAgentId.isEmpty
                              ? null
                              : controller.selectedAgentId,
                        );
                        await controller.modelsController.refresh();
                        await controller.cronJobsController.refresh();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          controller.openSettings(tab: SettingsTab.gateway),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(appText('打开设置中心', 'Open Settings')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionTabs(
                items: _visibleTabs.map((item) => item.label).toList(),
                value: _tab.label,
                onChanged: (value) => setState(() {
                  _tab = _tabForLabel(value);
                  controller.openModules(tab: _tab);
                }),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth > 980
                      ? (constraints.maxWidth - 32) / 3
                      : constraints.maxWidth > 640
                      ? (constraints.maxWidth - 16) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: metrics
                        .map(
                          (metric) => SizedBox(
                            width: width,
                            child: MetricCard(metric: metric),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 28),
              switch (_tab) {
                ModulesTab.nodes => _NodesPanel(
                  controller: controller,
                  onOpenDetail: widget.onOpenDetail,
                ),
                ModulesTab.agents => _AgentsPanel(
                  controller: controller,
                  onOpenDetail: widget.onOpenDetail,
                ),
                ModulesTab.skills => _SkillsPanel(
                  controller: controller,
                  onOpenDetail: widget.onOpenDetail,
                ),
                ModulesTab.clawHub => _SkillsPanel(
                  controller: controller,
                  onOpenDetail: widget.onOpenDetail,
                ),
                ModulesTab.connectors => _SkillsPanel(
                  controller: controller,
                  onOpenDetail: widget.onOpenDetail,
                ),
                ModulesTab.gateway => _NodesPanel(
                  controller: controller,
                  onOpenDetail: widget.onOpenDetail,
                ),
              },
            ],
          ),
        );
      },
    );
  }
}

class _NodesPanel extends StatelessWidget {
  const _NodesPanel({required this.controller, required this.onOpenDetail});

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final items = controller.instances;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: appText('节点', 'Nodes'),
          subtitle: appText(
            '来自 Gateway 运行时的在线实例与存在性数据。',
            'Live system-presence data from the gateway runtime.',
          ),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          SurfaceCard(
            child: Text(
              controller.connection.status == RuntimeConnectionStatus.connected
                  ? appText('暂时还没有上报在线实例。', 'No live instances reported yet.')
                  : appText(
                      '恢复 xworkmate-bridge 连接后可加载实例与在线状态。',
                      'Instances and presence return after xworkmate-bridge reconnects.',
                    ),
            ),
          )
        else
          ...items.map(
            (node) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SurfaceCard(
                onTap: () => onOpenDetail(
                  DetailPanelData(
                    title: node.host ?? node.id,
                    subtitle: appText('实例', 'Instance'),
                    icon: Icons.developer_board_rounded,
                    status: _instanceStatus(node),
                    description: node.text,
                    meta: [
                      node.platform ?? appText('未知', 'unknown'),
                      node.deviceFamily ?? appText('未知', 'unknown'),
                    ],
                    actions: [appText('刷新', 'Refresh')],
                    sections: [
                      DetailSection(
                        title: appText('运行时', 'Runtime'),
                        items: [
                          DetailItem(label: 'IP', value: node.ip ?? 'n/a'),
                          DetailItem(
                            label: 'Version',
                            value: node.version ?? 'n/a',
                          ),
                          DetailItem(
                            label: appText('模式', 'Mode'),
                            value: node.mode ?? 'n/a',
                          ),
                          DetailItem(
                            label: appText('最近输入', 'Last Input'),
                            value: node.lastInputSeconds == null
                                ? 'n/a'
                                : '${node.lastInputSeconds}s',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.host ?? node.id,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${node.platform ?? appText('未知', 'unknown')} · ${node.deviceFamily ?? appText('未知', 'unknown')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: StatusBadge(status: _instanceStatus(node)),
                    ),
                    Expanded(flex: 2, child: Text(node.version ?? 'n/a')),
                    Expanded(flex: 2, child: Text(node.mode ?? 'n/a')),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AgentsPanel extends StatelessWidget {
  const _AgentsPanel({required this.controller, required this.onOpenDetail});

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final items = controller.agents;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 1220
            ? (constraints.maxWidth - 32) / 3
            : constraints.maxWidth > 760
            ? (constraints.maxWidth - 16) / 2
            : constraints.maxWidth;
        if (items.isEmpty) {
          return SurfaceCard(
            child: Text(
              controller.connection.status == RuntimeConnectionStatus.connected
                  ? appText(
                      '网关当前没有返回代理列表。',
                      'No agents reported by the gateway.',
                    )
                  : appText(
                      '恢复 xworkmate-bridge 连接后可加载代理。',
                      'Agents return after xworkmate-bridge reconnects.',
                    ),
            ),
          );
        }
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: items
              .map(
                (agent) => SizedBox(
                  width: width,
                  child: SurfaceCard(
                    onTap: () => onOpenDetail(
                      DetailPanelData(
                        title: agent.name,
                        subtitle: appText('代理', 'Agent'),
                        icon: Icons.hub_rounded,
                        status: controller.selectedAgentId == agent.id
                            ? StatusInfo(
                                appText('已选中', 'Selected'),
                                StatusTone.accent,
                              )
                            : StatusInfo(
                                appText('可用', 'Available'),
                                StatusTone.success,
                              ),
                        description: appText(
                          '可用于会话路由的 Gateway 执行代理。',
                          'Gateway operator agent available for session routing.',
                        ),
                        meta: [agent.id, agent.theme],
                        actions: [
                          appText('选择', 'Select'),
                          appText('打开会话', 'Open Session'),
                        ],
                        sections: [
                          DetailSection(
                            title: appText('身份信息', 'Identity'),
                            items: [
                              DetailItem(
                                label: appText('名称', 'Name'),
                                value: agent.name,
                              ),
                              DetailItem(label: 'ID', value: agent.id),
                              DetailItem(
                                label: appText('主题', 'Theme'),
                                value: agent.theme,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                agent.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            StatusBadge(
                              status: controller.selectedAgentId == agent.id
                                  ? StatusInfo(
                                      appText('已选中', 'Selected'),
                                      StatusTone.accent,
                                    )
                                  : StatusInfo(
                                      appText('就绪', 'Ready'),
                                      StatusTone.success,
                                    ),
                              compact: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'ID: ${agent.id}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: () => controller.selectAgent(agent.id),
                              child: Text(appText('选择', 'Select')),
                            ),
                            OutlinedButton(
                              onPressed: () => controller.refreshSessions(),
                              child: Text(appText('打开', 'Open')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _SkillsPanel extends StatelessWidget {
  const _SkillsPanel({required this.controller, required this.onOpenDetail});

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final items = controller.skills;
    final currentMode = controller.currentAssistantExecutionTarget;
    final modeCards = _buildModeCards(items, currentMode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: appText('技能模式', 'Skill modes'),
          subtitle: appText(
            '用相同界面简洁区分 Agent 与 Gateway 两种路径，以及各自可用的技能包。',
            'Keep the same page structure while separating the agent and gateway paths and their available skill packs.',
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth > 1220
                ? (constraints.maxWidth - 32) / 3
                : constraints.maxWidth > 760
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: modeCards
                  .map(
                    (card) => SizedBox(
                      width: width,
                      child: _SkillModeCard(data: card),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 24),
        SectionHeader(
          title: appText('技能明细', 'Skill details'),
          subtitle: appText(
            '保留当前运行时返回的原始技能列表，便于查看状态、来源和依赖。',
            'Keep the raw runtime skill list for status, source, and dependency inspection.',
          ),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          SurfaceCard(
            child: Text(
              controller.connection.status == RuntimeConnectionStatus.connected
                  ? appText(
                      '当前网关或代理没有加载技能。',
                      'No skills loaded for the active gateway / agent.',
                    )
                  : appText(
                      '恢复 xworkmate-bridge 连接后可加载技能。',
                      'Skills return after xworkmate-bridge reconnects.',
                    ),
            ),
          )
        else
          ...items.map(
            (skill) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SurfaceCard(
                onTap: () => onOpenDetail(
                  DetailPanelData(
                    title: skill.name,
                    subtitle: appText('技能', 'Skill'),
                    icon: Icons.extension_rounded,
                    status: skill.disabled
                        ? StatusInfo(
                            appText('已禁用', 'Disabled'),
                            StatusTone.warning,
                          )
                        : StatusInfo(
                            appText('已启用', 'Enabled'),
                            StatusTone.success,
                          ),
                    description: skill.description,
                    meta: [skill.source, skill.skillKey],
                    actions: [appText('刷新', 'Refresh')],
                    sections: [
                      DetailSection(
                        title: appText('依赖要求', 'Requirements'),
                        items: [
                          DetailItem(
                            label: appText('缺失二进制', 'Missing bins'),
                            value: skill.missingBins.isEmpty
                                ? appText('无', 'None')
                                : skill.missingBins.join(', '),
                          ),
                          DetailItem(
                            label: appText('缺失环境变量', 'Missing env'),
                            value: skill.missingEnv.isEmpty
                                ? appText('无', 'None')
                                : skill.missingEnv.join(', '),
                          ),
                          DetailItem(
                            label: appText('缺失配置', 'Missing config'),
                            value: skill.missingConfig.isEmpty
                                ? appText('无', 'None')
                                : skill.missingConfig.join(', '),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            skill.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            skill.description,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: StatusBadge(
                        status: skill.disabled
                            ? StatusInfo(
                                appText('已禁用', 'Disabled'),
                                StatusTone.warning,
                              )
                            : StatusInfo(
                                appText('已启用', 'Enabled'),
                                StatusTone.success,
                              ),
                      ),
                    ),
                    Expanded(flex: 2, child: Text(skill.source)),
                    Expanded(
                      flex: 2,
                      child: Text(skill.primaryEnv ?? 'workspace'),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<_SkillModeCardData> _buildModeCards(
    List<GatewaySkillSummary> items,
    AssistantExecutionTarget currentMode,
  ) {
    final singleAgentSkills = items
        .where((item) => _isSingleAgentSkill(item))
        .toList(growable: false);
    final gatewaySkills = items
        .where((item) => !_isSingleAgentSkill(item))
        .toList(growable: false);
    return <_SkillModeCardData>[
      _SkillModeCardData(
        title: appText('单机智能体', 'Single agent'),
        subtitle: appText(
          '直接挂载本地 / 已授权目录中的技能包，适合个人工作区快速调用。',
          'Mount local or authorized skill packs directly for fast personal workspace use.',
        ),
        icon: Icons.auto_awesome_rounded,
        status: currentMode == AssistantExecutionTarget.singleAgent
            ? StatusInfo(appText('当前模式', 'Current mode'), StatusTone.accent)
            : StatusInfo(appText('可切换', 'Available'), StatusTone.success),
        chips: [
          for (final provider in controller.bridgeProviderCatalog)
            provider.label,
        ],
        skills: singleAgentSkills.map((item) => item.name).toList(),
        emptyLabel: appText(
          '切换到 Agent 模式后，将显示当前可用的本地技能包。',
          'Switch to agent mode to inspect the currently available local skill packs.',
        ),
      ),
      _SkillModeCardData(
        title: appText('Gateway', 'Gateway'),
        subtitle: appText(
          '通过 xworkmate-bridge 暴露运行时技能，统一承接当前 gateway 路径。',
          'Expose runtime skill packs through xworkmate-bridge as the single gateway path.',
        ),
        icon: Icons.lan_rounded,
        status: currentMode == AssistantExecutionTarget.gateway
            ? StatusInfo(appText('当前模式', 'Current mode'), StatusTone.accent)
            : StatusInfo(appText('可切换', 'Available'), StatusTone.success),
        chips: <String>[
          appText('统一路由', 'Unified routing'),
          appText('xworkmate-bridge', 'xworkmate-bridge'),
        ],
        skills: currentMode == AssistantExecutionTarget.gateway
            ? gatewaySkills.map((item) => item.name).toList()
            : const <String>[],
        emptyLabel: appText(
          '切换到 Gateway 模式后，将显示当前 bridge 返回的技能包。',
          'Switch to gateway mode to inspect the active skill packs returned by the bridge.',
        ),
      ),
    ];
  }

  bool _isSingleAgentSkill(GatewaySkillSummary item) {
    const gatewaySources = <String>{'gateway', 'workspace', 'acp'};
    return !gatewaySources.contains(item.source.trim().toLowerCase());
  }
}

class _SkillModeCardData {
  const _SkillModeCardData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
    required this.chips,
    required this.skills,
    required this.emptyLabel,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final StatusInfo status;
  final List<String> chips;
  final List<String> skills;
  final String emptyLabel;
}

class _SkillModeCard extends StatelessWidget {
  const _SkillModeCard({required this.data});

  final _SkillModeCardData data;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 20, child: Icon(data.icon, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    StatusBadge(status: data.status, compact: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(data.subtitle, style: Theme.of(context).textTheme.bodySmall),
          if (data.chips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: data.chips
                  .map(
                    (item) => Chip(
                      label: Text(item),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            appText('可用技能包', 'Available skill packs'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          if (data.skills.isEmpty)
            Text(data.emptyLabel, style: Theme.of(context).textTheme.bodySmall)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: data.skills
                  .map(
                    (item) => Chip(
                      label: Text(item),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

StatusInfo _connectionStatus(RuntimeConnectionStatus status) =>
    switch (status) {
      RuntimeConnectionStatus.connected => StatusInfo(
        appText('健康', 'Healthy'),
        StatusTone.success,
      ),
      RuntimeConnectionStatus.connecting => StatusInfo(
        appText('连接中', 'Connecting'),
        StatusTone.accent,
      ),
      RuntimeConnectionStatus.error => StatusInfo(
        appText('错误', 'Error'),
        StatusTone.danger,
      ),
      RuntimeConnectionStatus.offline => StatusInfo(
        appText('离线', 'Offline'),
        StatusTone.neutral,
      ),
    };

StatusInfo _instanceStatus(GatewayInstanceSummary item) {
  final mode = (item.mode ?? '').toLowerCase();
  if (mode.contains('error') || mode.contains('warn')) {
    return StatusInfo(appText('告警', 'Warning'), StatusTone.warning);
  }
  if (mode.contains('active') || mode.contains('online')) {
    return StatusInfo(appText('在线', 'Online'), StatusTone.success);
  }
  return StatusInfo(appText('已发现', 'Seen'), StatusTone.neutral);
}
