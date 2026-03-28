part of 'web_workspace_pages.dart';

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
