import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/workspace_navigation.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';

class SecretsPage extends StatefulWidget {
  const SecretsPage({
    super.key,
    required this.controller,
    required this.onOpenDetail,
    this.initialTab,
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;
  final SecretsTab? initialTab;

  @override
  State<SecretsPage> createState() => _SecretsPageState();
}

class _SecretsPageState extends State<SecretsPage> {
  late SecretsTab _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab ?? widget.controller.secretsTab;
  }

  @override
  void didUpdateWidget(covariant SecretsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextTab = widget.initialTab ?? widget.controller.secretsTab;
    if (nextTab != _tab) {
      setState(() => _tab = nextTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
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
                  rootLabel: appText('密钥', 'Secrets'),
                  sectionLabel: _tab.label,
                ),
                title: appText('密钥', 'Secrets'),
                subtitle: appText(
                  '管理密钥提供方、凭证和模块间的安全引用。',
                  'Manage secret providers, credentials, and secure references across modules.',
                ),
                trailing: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: appText('搜索密钥', 'Search secrets'),
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await controller.testVaultConnection();
                        await controller.settingsController.initialize();
                      },
                      icon: const Icon(Icons.sync_rounded),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          controller.openSettings(tab: SettingsTab.gateway),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(appText('新增密钥', 'Add Secret')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionTabs(
                items: SecretsTab.values.map((item) => item.label).toList(),
                value: _tab.label,
                onChanged: (value) => setState(() {
                  _tab = SecretsTab.values.firstWhere(
                    (item) => item.label == value,
                  );
                  controller.openSecrets(tab: _tab);
                }),
              ),
              const SizedBox(height: 24),
              switch (_tab) {
                SecretsTab.vault => _VaultPanel(
                  controller: controller,
                  onOpenDetail: widget.onOpenDetail,
                ),
                SecretsTab.localStore => _LocalStorePanel(
                  controller: controller,
                  onOpenDetail: widget.onOpenDetail,
                ),
                SecretsTab.providers => _ProvidersPanel(
                  controller: controller,
                  onOpenDetail: widget.onOpenDetail,
                ),
                SecretsTab.audit => _AuditPanel(
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

SettingsNavigationContext _secretsNavigationContext(SecretsTab tab) {
  return SettingsNavigationContext(
    rootLabel: appText('密钥', 'Secrets'),
    destination: WorkspaceDestination.secrets,
    sectionLabel: tab.label,
    secretsTab: tab,
  );
}

SettingsDetailPage _secretsDetailForTab(SecretsTab tab) {
  return switch (tab) {
    SecretsTab.vault => SettingsDetailPage.vaultProvider,
    SecretsTab.providers => SettingsDetailPage.ollamaProvider,
    SecretsTab.audit => SettingsDetailPage.diagnosticsAdvanced,
    SecretsTab.localStore => SettingsDetailPage.ollamaProvider,
  };
}

class _VaultPanel extends StatelessWidget {
  const _VaultPanel({required this.controller, required this.onOpenDetail});

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final vault = controller.settings.vault;
    final metrics = [
      MetricSummary(
        label: appText('提供方', 'Provider'),
        value: 'Vault',
        caption: controller.settingsController.vaultStatus,
        icon: Icons.key_rounded,
        status: _statusForString(controller.settingsController.vaultStatus),
      ),
      MetricSummary(
        label: appText('Token 引用', 'Token Ref'),
        value: vault.tokenRef,
        caption: appText('通过安全引用保存', 'Stored via secure refs'),
        icon: Icons.lock_rounded,
      ),
      MetricSummary(
        label: appText('密钥引用', 'Secret Refs'),
        value:
            '${controller.secretReferences.where((item) => item.provider == 'Vault').length}',
        caption: appText('被模块引用', 'Referenced by modules'),
        icon: Icons.link_rounded,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        const SizedBox(height: 20),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appText('Vault 服务', 'Vault Server'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                '${appText('地址', 'Address')}: ${vault.address}\n'
                '${appText('命名空间', 'Namespace')}: ${vault.namespace}\n'
                '${appText('认证模式', 'Auth mode')}: ${vault.authMode}\n'
                '${appText('Token 引用', 'Token ref')}: ${vault.tokenRef}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: controller.testVaultConnection,
                    child: Text(appText('连接测试', 'Test Connection')),
                  ),
                  OutlinedButton(
                    onPressed: () => controller.openSettings(
                      detail: _secretsDetailForTab(SecretsTab.vault),
                      navigationContext: _secretsNavigationContext(
                        SecretsTab.vault,
                      ),
                    ),
                    child: Text(appText('编辑设置', 'Edit settings')),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionHeader(
          title: appText('引用列表', 'Reference List'),
          subtitle: appText(
            '仅展示脱敏引用，不暴露真实密钥值。',
            'Only masked references are shown, never raw secret values.',
          ),
        ),
        const SizedBox(height: 14),
        _SecretRefsTable(
          entries: controller.secretReferences
              .where((item) => item.provider == 'Vault')
              .toList(growable: false),
          onOpenDetail: onOpenDetail,
        ),
      ],
    );
  }
}

class _LocalStorePanel extends StatelessWidget {
  const _LocalStorePanel({
    required this.controller,
    required this.onOpenDetail,
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final refs = controller.secretReferences;
    final metrics = [
      MetricSummary(
        label: appText('本地存储', 'Local Store'),
        value: appText('已启用', 'Enabled'),
        caption: 'flutter_secure_storage + shared prefs',
        icon: Icons.lock_rounded,
      ),
      MetricSummary(
        label: appText('条目数', 'Entries'),
        value: '${refs.length}',
        caption: appText('脱敏密钥引用', 'Masked secret references'),
        icon: Icons.key_rounded,
      ),
      MetricSummary(
        label: appText('最近审计', 'Last Audit'),
        value: controller.secretAuditTrail.isEmpty
            ? appText('无', 'None')
            : controller.secretAuditTrail.first.timeLabel,
        caption: appText('最近一次安全操作', 'Most recent security action'),
        icon: Icons.schedule_rounded,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        const SizedBox(height: 20),
        _SecretRefsTable(entries: refs, onOpenDetail: onOpenDetail),
      ],
    );
  }
}

class _ProvidersPanel extends StatelessWidget {
  const _ProvidersPanel({required this.controller, required this.onOpenDetail});

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final providers = [
      _ProviderCardData(
        name: 'HashiCorp Vault',
        description: appText(
          '支持命名空间和 token 引用的 Vault 集成。',
          'Namespace-aware Vault integration with token refs.',
        ),
        status: _statusForString(controller.settingsController.vaultStatus),
        capabilities: ['KV', 'Namespace', 'Health'],
      ),
      _ProviderCardData(
        name: appText('环境变量', 'Environment Variables'),
        description: appText(
          '面向本地桥接工具的只读安全提供方。',
          'Read-only secure provider for local bridge tools.',
        ),
        status: StatusInfo(appText('可用', 'Available'), StatusTone.neutral),
        capabilities: ['Read env', 'Mask refs'],
      ),
      _ProviderCardData(
        name: appText('本地存储', 'Local Store'),
        description: appText(
          '使用系统安全存储保存本地密钥和令牌。',
          'OS-backed secure storage for local secrets and tokens.',
        ),
        status: StatusInfo(appText('已启用', 'Enabled'), StatusTone.success),
        capabilities: ['Local refs', 'Masking'],
      ),
      _ProviderCardData(
        name: appText('外部密钥管理器', 'External Secret Manager'),
        description: appText(
          '为外部密钥服务预留的适配器入口。',
          'Reserved adapter surface for external secret services.',
        ),
        status: StatusInfo(appText('预览', 'Preview'), StatusTone.accent),
        capabilities: ['Reserved', 'Extensible'],
      ),
    ];

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
          children: providers
              .map(
                (provider) => SizedBox(
                  width: width,
                  child: SurfaceCard(
                    onTap: () => onOpenDetail(
                      DetailPanelData(
                        title: provider.name,
                        subtitle: appText('密钥提供方', 'Secret Provider'),
                        icon: Icons.key_rounded,
                        status: provider.status,
                        description: provider.description,
                        meta: provider.capabilities,
                        actions: [
                          appText('连接', 'Connect'),
                          appText('配置', 'Configure'),
                        ],
                        sections: [
                          DetailSection(
                            title: appText('能力', 'Capabilities'),
                            items: provider.capabilities
                                .map(
                                  (item) => DetailItem(
                                    label: appText('能力项', 'Capability'),
                                    value: item,
                                  ),
                                )
                                .toList(),
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
                                provider.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            StatusBadge(status: provider.status, compact: true),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(provider.description),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: provider.capabilities
                              .map((item) => Chip(label: Text(item)))
                              .toList(),
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

class _AuditPanel extends StatelessWidget {
  const _AuditPanel({required this.controller, required this.onOpenDetail});

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final items = controller.secretAuditTrail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: '搜索审计',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            OutlinedButton(
              onPressed: () {},
              child: Text(appText('状态过滤', 'Filter Status')),
            ),
            OutlinedButton(
              onPressed: () {},
              child: Text(appText('时间过滤', 'Filter Time')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          SurfaceCard(
            child: Text(
              appText(
                '还没有安全审计条目。保存 Gateway、Vault 或 Ollama 密钥后会在这里出现记录。',
                'No audit entries yet. Records will appear after saving Gateway, Vault, or Ollama secrets.',
              ),
            ),
          )
        else
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: items.map((entry) {
                return InkWell(
                  onTap: () => onOpenDetail(
                    DetailPanelData(
                      title: entry.action,
                      subtitle: appText('审计记录', 'Audit Entry'),
                      icon: Icons.policy_outlined,
                      status: _statusForString(entry.status),
                      description: '${entry.provider} · ${entry.target}',
                      meta: [entry.timeLabel, entry.module],
                      actions: [appText('查看', 'View')],
                      sections: [
                        DetailSection(
                          title: appText('审计', 'Audit'),
                          items: [
                            DetailItem(
                              label: appText('提供方', 'Provider'),
                              value: entry.provider,
                            ),
                            DetailItem(
                              label: appText('目标', 'Target'),
                              value: entry.target,
                            ),
                            DetailItem(
                              label: appText('模块', 'Module'),
                              value: entry.module,
                            ),
                            DetailItem(
                              label: appText('状态', 'Status'),
                              value: _statusForString(entry.status).label,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text(entry.timeLabel)),
                        Expanded(flex: 2, child: Text(entry.action)),
                        Expanded(flex: 2, child: Text(entry.provider)),
                        Expanded(flex: 2, child: Text(entry.target)),
                        Expanded(flex: 2, child: Text(entry.module)),
                        StatusBadge(
                          status: _statusForString(entry.status),
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

class _SecretRefsTable extends StatelessWidget {
  const _SecretRefsTable({required this.entries, required this.onOpenDetail});

  final List<SecretReferenceEntry> entries;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return SurfaceCard(
        child: Text(
          appText('暂时还没有密钥引用。', 'No secret references available yet.'),
        ),
      );
    }
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: entries.map((reference) {
          return InkWell(
            onTap: () => onOpenDetail(
              DetailPanelData(
                title: reference.name,
                subtitle: appText('密钥引用', 'Secret Reference'),
                icon: Icons.key_rounded,
                status: _statusForString(reference.status),
                description: reference.maskedValue,
                meta: [reference.provider, reference.module],
                actions: [
                  appText('查看引用', 'Reveal Ref'),
                  appText('打开设置', 'Open Settings'),
                ],
                sections: [
                  DetailSection(
                    title: appText('引用', 'Reference'),
                    items: [
                      DetailItem(
                        label: appText('提供方', 'Provider'),
                        value: reference.provider,
                      ),
                      DetailItem(
                        label: appText('模块', 'Module'),
                        value: reference.module,
                      ),
                      DetailItem(
                        label: appText('脱敏值', 'Masked value'),
                        value: reference.maskedValue,
                      ),
                      DetailItem(
                        label: appText('状态', 'Status'),
                        value: _statusForString(reference.status).label,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      reference.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Expanded(flex: 2, child: Text(reference.provider)),
                  Expanded(flex: 2, child: Text(reference.module)),
                  Expanded(flex: 2, child: Text(reference.maskedValue)),
                  StatusBadge(
                    status: _statusForString(reference.status),
                    compact: true,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ProviderCardData {
  const _ProviderCardData({
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

StatusInfo _statusForString(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.contains('connected') ||
      value.contains('enabled') ||
      value.contains('success')) {
    return StatusInfo(appText('已连接', 'Connected'), StatusTone.success);
  }
  if (value.contains('fail') || value.contains('error')) {
    return StatusInfo(appText('错误', 'Error'), StatusTone.danger);
  }
  if (value.contains('preview') || value.contains('reachable')) {
    return StatusInfo(appText('预览', 'Preview'), StatusTone.accent);
  }
  return StatusInfo(appText('空闲', 'Idle'), StatusTone.neutral);
}
