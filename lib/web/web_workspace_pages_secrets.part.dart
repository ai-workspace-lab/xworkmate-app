part of 'web_workspace_pages.dart';

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
