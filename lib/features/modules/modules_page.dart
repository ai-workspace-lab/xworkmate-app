import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_controllers.dart';
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
  ModulesTab _tab = ModulesTab.gateway;

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null) {
      _tab = widget.initialTab!;
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
                breadcrumbs: [
                  AppBreadcrumbItem(
                    label: appText('主页', 'Home'),
                    icon: Icons.home_rounded,
                    onTap: controller.navigateHome,
                  ),
                  AppBreadcrumbItem(label: appText('模块', 'Modules')),
                  AppBreadcrumbItem(label: _tab.label),
                ],
                title: appText('模块', 'Modules'),
                subtitle: appText(
                  '管理 Gateway、代理、节点、技能和平台服务。',
                  'Manage gateway, agents, nodes, skills, and platform services.',
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
                        await controller.connectorsController.refresh();
                        await controller.modelsController.refresh();
                        await controller.cronJobsController.refresh();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          controller.navigateTo(WorkspaceDestination.settings),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(appText('接入模块', 'Add Module')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionTabs(
                items: ModulesTab.values.map((item) => item.label).toList(),
                value: _tab.label,
                onChanged: (value) => setState(
                  () => _tab = ModulesTab.values.firstWhere(
                    (item) => item.label == value,
                  ),
                ),
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
                ModulesTab.gateway => _GatewayPanel(
                  controller: controller,
                  onOpenDetail: widget.onOpenDetail,
                ),
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
                ModulesTab.clawHub => _FallbackHubPanel(
                  controller: controller,
                  onOpenDetail: widget.onOpenDetail,
                ),
                ModulesTab.connectors => _FallbackConnectorsPanel(
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

class _GatewayPanel extends StatelessWidget {
  const _GatewayPanel({required this.controller, required this.onOpenDetail});

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final connection = controller.connection;
    final metrics = [
      MetricSummary(
        label: appText('模式', 'Mode'),
        value: controller.settings.gateway.mode.label,
        caption: controller.settings.gateway.useSetupCode
            ? appText('配置码', 'Setup code')
            : appText('手动配置', 'Manual profile'),
        icon: Icons.link_rounded,
      ),
      MetricSummary(
        label: appText('活跃会话', 'Active Sessions'),
        value: '${controller.sessions.length}',
        caption: appText(
          '当前 Key ${controller.currentSessionKey}',
          'Current key ${controller.currentSessionKey}',
        ),
        icon: Icons.chat_bubble_outline_rounded,
      ),
      MetricSummary(
        label: appText('今日运行', 'Today Runs'),
        value:
            '${controller.tasksController.running.length + controller.tasksController.history.length}',
        caption: appText('根据实时会话活动计算', 'Derived from live session activity'),
        icon: Icons.bolt_rounded,
      ),
      MetricSummary(
        label: appText('技能', 'Skills'),
        value: '${controller.skills.length}',
        caption: appText('来自网关加载', 'Loaded from gateway'),
        icon: Icons.extension_rounded,
      ),
    ];

    final statusPayload = connection.statusPayload ?? const <String, dynamic>{};
    final healthPayload = connection.healthPayload ?? const <String, dynamic>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth > 1180
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth > 860
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
        const SizedBox(height: 20),
        SurfaceCard(
          onTap: () => onOpenDetail(
            DetailPanelData(
              title: appText('网关概览', 'Gateway Overview'),
              subtitle: appText('运行时', 'Runtime'),
              icon: Icons.wifi_tethering_rounded,
              status: _connectionStatus(connection.status),
              description: appText(
                '与 macOS 工作台保持一致的实时 Gateway 控制面摘要。',
                'Live gateway control plane summary aligned with the macOS workspace shell.',
              ),
              meta: [
                connection.remoteAddress ?? appText('未连接目标', 'No target'),
                controller.activeAgentName,
              ],
              actions: [
                appText('刷新', 'Refresh'),
                appText('打开设置', 'Open Settings'),
              ],
              sections: [
                DetailSection(
                  title: appText('连接', 'Connection'),
                  items: [
                    DetailItem(
                      label: appText('状态', 'Status'),
                      value: connection.status.label,
                    ),
                    DetailItem(
                      label: appText('地址', 'Address'),
                      value:
                          connection.remoteAddress ?? appText('离线', 'Offline'),
                    ),
                    DetailItem(
                      label: appText('模式', 'Mode'),
                      value: controller.settings.gateway.mode.label,
                    ),
                    DetailItem(
                      label: appText('代理', 'Agent'),
                      value: controller.activeAgentName,
                    ),
                  ],
                ),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appText('网关', 'Gateway'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                '${connection.status.label} · ${connection.remoteAddress ?? appText('未连接目标', 'No target')} · ${controller.activeAgentName}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: controller.refreshGatewayHealth,
                    child: Text(appText('刷新状态', 'Refresh status')),
                  ),
                  OutlinedButton(
                    onPressed: controller.refreshSessions,
                    child: Text(appText('刷新会话', 'Refresh sessions')),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        controller.navigateTo(WorkspaceDestination.settings),
                    child: Text(appText('配置', 'Configure')),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appText('状态摘要', 'Status Summary'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              _KeyValueLine(
                label: 'Health',
                value: healthPayload.isEmpty
                    ? appText('不可用', 'Unavailable')
                    : encodePrettyJson(healthPayload),
              ),
              const SizedBox(height: 12),
              _KeyValueLine(
                label: 'Status',
                value: statusPayload.isEmpty
                    ? appText('不可用', 'Unavailable')
                    : encodePrettyJson(statusPayload),
              ),
            ],
          ),
        ),
      ],
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
                      '连接 Gateway 后可加载实例与在线状态。',
                      'Connect a gateway to load instances / presence.',
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
                      '连接 Gateway 后可加载代理。',
                      'Connect a gateway to load agents.',
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
    if (items.isEmpty) {
      return SurfaceCard(
        child: Text(
          controller.connection.status == RuntimeConnectionStatus.connected
              ? appText(
                  '当前网关或代理没有加载技能。',
                  'No skills loaded for the active gateway / agent.',
                )
              : appText(
                  '连接 Gateway 后可加载技能。',
                  'Connect a gateway to load skills.',
                ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
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
          )
          .toList(),
    );
  }
}

class _FallbackHubPanel extends StatelessWidget {
  const _FallbackHubPanel({
    required this.controller,
    required this.onOpenDetail,
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final items = controller.models;
    if (items.isEmpty) {
      final hasAiGateway = controller.settings.aiGateway.baseUrl
          .trim()
          .isNotEmpty;
      return SurfaceCard(
        child: Text(
          hasAiGateway
              ? appText(
                  '当前 AI Gateway 没有返回模型目录。',
                  'No model catalog returned by the AI Gateway.',
                )
              : appText(
                  '先在设置 -> 集成 中同步 AI Gateway 模型目录。',
                  'Sync the AI Gateway model catalog from Settings -> Integrations.',
                ),
        ),
      );
    }
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: items
          .map(
            (model) => SizedBox(
              width: 360,
              child: SurfaceCard(
                onTap: () => onOpenDetail(
                  DetailPanelData(
                    title: model.name,
                    subtitle: appText('模型', 'Model'),
                    icon: Icons.psychology_alt_rounded,
                    status: StatusInfo(model.provider, StatusTone.accent),
                    description: appText(
                      '来自 AI Gateway 的可用模型目录项。',
                      'Model catalog entry exposed by the AI Gateway.',
                    ),
                    meta: [model.id, model.provider],
                    actions: [appText('刷新', 'Refresh')],
                    sections: [
                      DetailSection(
                        title: appText('能力', 'Capabilities'),
                        items: [
                          DetailItem(label: 'ID', value: model.id),
                          DetailItem(
                            label: appText('提供方', 'Provider'),
                            value: model.provider,
                          ),
                          DetailItem(
                            label: appText('上下文窗口', 'Context Window'),
                            value: '${model.contextWindow ?? 0}',
                          ),
                          DetailItem(
                            label: appText('最大输出', 'Max Output'),
                            value: '${model.maxOutputTokens ?? 0}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('${model.provider} · ${model.id}'),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _FallbackConnectorsPanel extends StatelessWidget {
  const _FallbackConnectorsPanel({
    required this.controller,
    required this.onOpenDetail,
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final connectors = controller.connectors;
    if (connectors.isEmpty) {
      return SurfaceCard(
        child: Text(
          controller.connection.status == RuntimeConnectionStatus.connected
              ? appText(
                  '当前网关没有返回连接器状态。',
                  'No connector status returned by the gateway.',
                )
              : appText(
                  '连接 Gateway 后可加载连接器状态。',
                  'Connect a gateway to load connector status.',
                ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 1220
            ? (constraints.maxWidth - 32) / 3
            : constraints.maxWidth > 760
            ? (constraints.maxWidth - 16) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: connectors
              .map(
                (connector) => SizedBox(
                  width: width,
                  child: SurfaceCard(
                    onTap: () => onOpenDetail(
                      DetailPanelData(
                        title: connector.label,
                        subtitle: 'Connector',
                        icon: Icons.cable_rounded,
                        status: _connectorStatus(connector),
                        description:
                            connector.lastError ?? connector.detailLabel,
                        meta: [
                          if (connector.accountName != null)
                            connector.accountName!,
                          ...connector.meta,
                        ],
                        actions: const ['Refresh'],
                        sections: [
                          DetailSection(
                            title: 'Connector',
                            items: [
                              DetailItem(
                                label: appText('状态', 'Status'),
                                value: connector.status,
                              ),
                              DetailItem(
                                label: appText('账号', 'Account'),
                                value: connector.accountName ?? 'default',
                              ),
                              DetailItem(
                                label: appText('配置', 'Configured'),
                                value: '${connector.configured}',
                              ),
                              DetailItem(
                                label: appText('连接中', 'Connected'),
                                value: '${connector.connected}',
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
                                connector.label,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            StatusBadge(
                              status: _connectorStatus(connector),
                              compact: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          connector.accountName == null
                              ? connector.detailLabel
                              : '${connector.detailLabel} · ${connector.accountName}',
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

StatusInfo _connectorStatus(GatewayConnectorSummary connector) {
  return switch (connector.status) {
    'error' => StatusInfo(appText('异常', 'Error'), StatusTone.danger),
    'connected' => StatusInfo(appText('已连接', 'Connected'), StatusTone.success),
    'running' => StatusInfo(appText('运行中', 'Running'), StatusTone.accent),
    'configured' => StatusInfo(
      appText('已配置', 'Configured'),
      StatusTone.warning,
    ),
    _ => StatusInfo(appText('空闲', 'Idle'), StatusTone.neutral),
  };
}

class _KeyValueLine extends StatelessWidget {
  const _KeyValueLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            value,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
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
