import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';

class McpServerPage extends StatelessWidget {
  const McpServerPage({
    super.key,
    required this.controller,
    required this.onOpenDetail,
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final items = controller.connectors;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                title: 'MCP Hub',
                subtitle: appText(
                  '管理 MCP 服务器连接与工具配置。',
                  'Manage MCP server connections and tool configurations.',
                ),
                trailing: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: appText('搜索服务器', 'Search servers'),
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await controller.connectorsController.refresh();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (items.isEmpty)
                SurfaceCard(
                  child: Text(
                    controller.connection.status ==
                            RuntimeConnectionStatus.connected
                        ? appText(
                            '当前没有连接的 MCP 服务器。',
                            'No MCP servers connected.',
                          )
                        : appText(
                            '连接 Gateway 后可查看 MCP 服务器。',
                            'Connect a gateway to view MCP servers.',
                          ),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items
                      .map(
                        (connector) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SurfaceCard(
                            onTap: () => onOpenDetail(
                              DetailPanelData(
                                title: connector.label,
                                subtitle: appText('连接器', 'Connector'),
                                icon: Icons.dns_rounded,
                                status: StatusInfo(
                                  connector.status,
                                  connector.connected
                                      ? StatusTone.success
                                      : StatusTone.neutral,
                                ),
                                description: connector.detailLabel,
                                meta: connector.meta,
                                actions: [appText('配置', 'Configure')],
                                sections: [
                                  DetailSection(
                                    title: appText('详情', 'Details'),
                                    items: [
                                      DetailItem(
                                        label: appText('ID', 'ID'),
                                        value: connector.id,
                                      ),
                                      DetailItem(
                                        label: appText('状态', 'Status'),
                                        value: connector.status,
                                      ),
                                      DetailItem(
                                        label: appText('已配置', 'Configured'),
                                        value: connector.configured
                                            ? appText('是', 'Yes')
                                            : appText('否', 'No'),
                                      ),
                                      DetailItem(
                                        label: appText('已启用', 'Enabled'),
                                        value: connector.enabled
                                            ? appText('是', 'Yes')
                                            : appText('否', 'No'),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        connector.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        connector.detailLabel,
                                        style:
                                            Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    connector.connected
                                        ? appText('已连接', 'Connected')
                                        : appText('未连接', 'Disconnected'),
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        );
      },
    );
  }
}
