// ignore_for_file: unused_import, unnecessary_import

import 'package:flutter/material.dart';
import '../app/app_controller_web.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../widgets/desktop_workspace_scaffold.dart';
import '../widgets/metric_card.dart';
import '../widgets/section_tabs.dart';
import '../widgets/status_badge.dart';
import '../widgets/surface_card.dart';
import '../widgets/top_bar.dart';
import 'web_workspace_pages_core.dart';
import 'web_workspace_pages_tasks.dart';
import 'web_workspace_pages_skills.dart';
import 'web_workspace_pages_secrets.dart';
import 'web_workspace_pages_ai_gateway.dart';

class WebNodesPage extends StatefulWidget {
  const WebNodesPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebNodesPage> createState() => WebNodesPageStateInternal();
}

enum WebNodesTabInternal { nodes, agents, connectors, models }

class WebNodesPageStateInternal extends State<WebNodesPage> {
  final TextEditingController searchControllerInternal =
      TextEditingController();
  WebNodesTabInternal tabInternal = WebNodesTabInternal.nodes;
  String queryInternal = '';
  String? selectedIdInternal;

  @override
  void dispose() {
    searchControllerInternal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final items = itemsForTabInternal(
          controller,
        ).where(matchesQueryInternal).toList(growable: false);
        final selected = resolveSelectedInternal(items);
        return DesktopWorkspaceScaffold(
          breadcrumbs: buildWebBreadcrumbsInternal(
            controller,
            rootLabel: WorkspaceDestination.nodes.label,
            sectionLabel: tabLabelInternal(tabInternal),
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
                  controller: searchControllerInternal,
                  onChanged: (value) {
                    setState(() {
                      queryInternal = value.trim().toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: appText('搜索节点资源', 'Search resources'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: queryInternal.isEmpty
                        ? null
                        : IconButton(
                            tooltip: appText('清除', 'Clear'),
                            onPressed: () {
                              searchControllerInternal.clear();
                              setState(() => queryInternal = '');
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
                  items: WebNodesTabInternal.values
                      .map(tabLabelInternal)
                      .toList(),
                  value: tabLabelInternal(tabInternal),
                  onChanged: (value) {
                    setState(() {
                      tabInternal = WebNodesTabInternal.values.firstWhere(
                        (item) => tabLabelInternal(item) == value,
                      );
                      selectedIdInternal = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                WorkspaceStatusBannerInternal(
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
                            child: ResourceListPanelInternal(
                              title: tabLabelInternal(tabInternal),
                              emptyLabel: emptyLabelInternal(tabInternal),
                              items: items,
                              selectedId: selected?.id,
                              onSelect: (item) {
                                setState(() => selectedIdInternal = item.id);
                              },
                            ),
                          ),
                          Container(
                            width: 1,
                            color: context.palette.strokeSoft,
                          ),
                          Expanded(
                            child: ResourceDetailPanelInternal(
                              title: tabLabelInternal(tabInternal),
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

  List<WorkspaceResourceItemInternal> itemsForTabInternal(
    AppController controller,
  ) {
    return switch (tabInternal) {
      WebNodesTabInternal.nodes =>
        controller.instances
            .map(
              (item) => WorkspaceResourceItemInternal(
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
      WebNodesTabInternal.agents =>
        controller.agents
            .map(
              (item) => WorkspaceResourceItemInternal(
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
      WebNodesTabInternal.connectors =>
        controller.connectors
            .map(
              (item) => WorkspaceResourceItemInternal(
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
      WebNodesTabInternal.models =>
        controller.models
            .map(
              (item) => WorkspaceResourceItemInternal(
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

  bool matchesQueryInternal(WorkspaceResourceItemInternal item) {
    if (queryInternal.isEmpty) {
      return true;
    }
    final haystack = [
      item.title,
      item.subtitle,
      item.status,
      ...item.detailLines,
    ].join(' ').toLowerCase();
    return haystack.contains(queryInternal);
  }

  WorkspaceResourceItemInternal? resolveSelectedInternal(
    List<WorkspaceResourceItemInternal> items,
  ) {
    if (items.isEmpty) {
      return null;
    }
    for (final item in items) {
      if (item.id == selectedIdInternal) {
        return item;
      }
    }
    return items.first;
  }

  String tabLabelInternal(WebNodesTabInternal tab) {
    return switch (tab) {
      WebNodesTabInternal.nodes => appText('节点', 'Nodes'),
      WebNodesTabInternal.agents => appText('代理', 'Agents'),
      WebNodesTabInternal.connectors => appText('连接器', 'Connectors'),
      WebNodesTabInternal.models => appText('模型', 'Models'),
    };
  }

  String emptyLabelInternal(WebNodesTabInternal tab) {
    return switch (tab) {
      WebNodesTabInternal.nodes => appText(
        '当前没有节点。',
        'No nodes are available.',
      ),
      WebNodesTabInternal.agents => appText(
        '当前没有代理。',
        'No agents are available.',
      ),
      WebNodesTabInternal.connectors => appText(
        '当前没有连接器。',
        'No connectors are available.',
      ),
      WebNodesTabInternal.models => appText(
        '当前没有模型。',
        'No models are available.',
      ),
    };
  }
}

class WorkspaceStatusBannerInternal extends StatelessWidget {
  const WorkspaceStatusBannerInternal({
    super.key,
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

class WorkspaceResourceItemInternal {
  const WorkspaceResourceItemInternal({
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

class ResourceListPanelInternal extends StatelessWidget {
  const ResourceListPanelInternal({
    super.key,
    required this.title,
    required this.emptyLabel,
    required this.items,
    required this.selectedId,
    required this.onSelect,
  });

  final String title;
  final String emptyLabel;
  final List<WorkspaceResourceItemInternal> items;
  final String? selectedId;
  final ValueChanged<WorkspaceResourceItemInternal> onSelect;

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

class ResourceDetailPanelInternal extends StatelessWidget {
  const ResourceDetailPanelInternal({
    super.key,
    required this.title,
    required this.item,
  });

  final String title;
  final WorkspaceResourceItemInternal? item;

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
