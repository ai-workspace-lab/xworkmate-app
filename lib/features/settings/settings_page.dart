import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/ui_feature_manifest.dart';
import '../../app/workspace_navigation.dart';
import '../ai_gateway/ai_gateway_page.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/gateway_connect_dialog.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.initialTab = SettingsTab.general,
    this.initialDetail,
    this.navigationContext,
  });

  final AppController controller;
  final SettingsTab initialTab;
  final SettingsDetailPage? initialDetail;
  final SettingsNavigationContext? navigationContext;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _storedSecretMask = '****';

  late SettingsTab _tab;
  SettingsDetailPage? _detail;
  SettingsNavigationContext? _navigationContext;
  late final TextEditingController _aiGatewayNameController;
  late final TextEditingController _aiGatewayUrlController;
  late final TextEditingController _aiGatewayApiKeyRefController;
  late final TextEditingController _aiGatewayApiKeyController;
  late final TextEditingController _aiGatewayModelSearchController;
  late final TextEditingController _vaultTokenController;
  late final TextEditingController _ollamaApiKeyController;
  late final TextEditingController _runtimeLogFilterController;
  bool _aiGatewayTesting = false;
  bool _aiGatewaySyncing = false;
  String _aiGatewayTestState = 'idle';
  String _aiGatewayTestMessage = '';
  String _aiGatewayTestEndpoint = '';
  String _aiGatewayNameSyncedValue = '';
  String _aiGatewayUrlSyncedValue = '';
  String _aiGatewayApiKeyRefSyncedValue = '';
  _SecretFieldUiState _aiGatewayApiKeyState = const _SecretFieldUiState();
  _SecretFieldUiState _vaultTokenState = const _SecretFieldUiState();
  _SecretFieldUiState _ollamaApiKeyState = const _SecretFieldUiState();

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _detail = widget.initialDetail;
    _navigationContext = widget.navigationContext;
    _aiGatewayNameController = TextEditingController();
    _aiGatewayUrlController = TextEditingController();
    _aiGatewayApiKeyRefController = TextEditingController();
    _aiGatewayApiKeyController = TextEditingController();
    _aiGatewayModelSearchController = TextEditingController();
    _vaultTokenController = TextEditingController();
    _ollamaApiKeyController = TextEditingController();
    _runtimeLogFilterController = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != _tab) {
      _tab = widget.initialTab;
    }
    if (widget.initialDetail != _detail) {
      _detail = widget.initialDetail;
    }
    if (widget.navigationContext != _navigationContext) {
      _navigationContext = widget.navigationContext;
    }
  }

  @override
  void dispose() {
    _aiGatewayNameController.dispose();
    _aiGatewayUrlController.dispose();
    _aiGatewayApiKeyRefController.dispose();
    _aiGatewayApiKeyController.dispose();
    _aiGatewayModelSearchController.dispose();
    _vaultTokenController.dispose();
    _ollamaApiKeyController.dispose();
    _runtimeLogFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final featurePlatform = resolveUiFeaturePlatformFromContext(context);
        final uiFeatures = controller.featuresFor(featurePlatform);
        final availableTabs = uiFeatures.availableSettingsTabs;
        _tab = uiFeatures.sanitizeSettingsTab(controller.settingsTab);
        _detail = controller.settingsDetail;
        _navigationContext = controller.settingsNavigationContext;
        final settings = controller.settings;
        final showingDetail = _detail != null;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                breadcrumbs: buildSettingsBreadcrumbs(
                  controller,
                  tab: _tab,
                  detail: _detail,
                  navigationContext: _navigationContext,
                ),
                title: appText('设置', 'Settings'),
                subtitle: showingDetail
                    ? appText(
                        '当前正在编辑详细设置参数，保存后会回写到对应状态页。',
                        'You are editing detailed settings. Saved values flow back to the related status page.',
                      )
                    : appText(
                        '配置 $kProductBrandName 工作区、网关默认项、界面与诊断选项',
                        'Configure workspace, gateway defaults, appearance, and diagnostics for $kProductBrandName.',
                      ),
                trailing: SizedBox(
                  width: showingDetail ? 168 : 220,
                  child: showingDetail
                      ? OutlinedButton.icon(
                          onPressed: () {
                            controller.closeSettingsDetail();
                            setState(() {
                              _detail = null;
                              _navigationContext = null;
                            });
                          },
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: Text(appText('返回概览', 'Back to overview')),
                        )
                      : TextField(
                          decoration: InputDecoration(
                            hintText: appText('搜索设置', 'Search settings'),
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              if (!showingDetail) ...[
                SectionTabs(
                  items: availableTabs.map((item) => item.label).toList(),
                  value: _tab.label,
                  onChanged: (value) => setState(() {
                    _tab = availableTabs.firstWhere(
                      (item) => item.label == value,
                    );
                    _detail = null;
                    _navigationContext = null;
                    controller.setSettingsTab(_tab);
                  }),
                ),
                const SizedBox(height: 24),
              ],
              ..._buildContentForCurrentState(
                context,
                controller,
                settings,
                uiFeatures,
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildContentForCurrentState(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
  ) {
    if (_detail != null) {
      return _buildDetailContent(context, controller, settings, _detail!);
    }

    return switch (_tab) {
      SettingsTab.general => _buildGeneral(context, controller, settings),
      SettingsTab.workspace => _buildWorkspace(context, controller, settings),
      SettingsTab.gateway => _buildGateway(context, controller, settings),
      SettingsTab.agents => _buildAgents(context, controller, settings),
      SettingsTab.appearance => _buildAppearance(context, controller),
      SettingsTab.diagnostics => _buildDiagnostics(context, controller),
      SettingsTab.experimental => _buildExperimental(
        context,
        controller,
        settings,
        uiFeatures,
      ),
      SettingsTab.about => _buildAbout(context, controller),
    };
  }

  List<Widget> _buildDetailContent(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    SettingsDetailPage detail,
  ) {
    final gatewaySections = _buildGateway(context, controller, settings);
    final workspaceSections = _buildWorkspace(context, controller, settings);
    return switch (detail) {
      SettingsDetailPage.gatewayConnection => <Widget>[
        _buildDetailIntro(
          context,
          title: detail.label,
          description: appText(
            '集中编辑 Gateway 连接、设备配对和会话级连接入口。',
            'Edit gateway connection, device pairing, and session-level connection entry points in one place.',
          ),
        ),
        const SizedBox(height: 16),
        ...gatewaySections.take(3),
      ],
      SettingsDetailPage.aiGatewayIntegration => <Widget>[
        _buildDetailIntro(
          context,
          title: detail.label,
          description: appText(
            '统一管理 AI Gateway 地址、API Key、模型目录同步和默认选择。',
            'Manage AI Gateway endpoint, API key, model catalog sync, and default selections from one screen.',
          ),
        ),
        const SizedBox(height: 16),
        if (gatewaySections.isNotEmpty) gatewaySections.last,
      ],
      SettingsDetailPage.vaultProvider => <Widget>[
        _buildDetailIntro(
          context,
          title: detail.label,
          description: appText(
            '只在这里维护 Vault 地址、命名空间和安全 token 引用。',
            'Maintain Vault endpoint, namespace, and secure token references here.',
          ),
        ),
        const SizedBox(height: 16),
        if (gatewaySections.length > 4) gatewaySections[4],
      ],
      SettingsDetailPage.ollamaProvider => <Widget>[
        _buildDetailIntro(
          context,
          title: detail.label,
          description: appText(
            '本地与云端 Ollama 提供方参数统一放在这个 detail 页面中维护。',
            'Local and cloud Ollama provider settings live in this dedicated detail page.',
          ),
        ),
        const SizedBox(height: 16),
        ...workspaceSections.skip(1),
      ],
      SettingsDetailPage.externalAgents => <Widget>[
        _buildDetailIntro(
          context,
          title: detail.label,
          description: appText(
            '多 Agent 协作、角色编排和外部 CLI 工具的详细参数集中在这里。',
            'Detailed multi-agent collaboration, role orchestration, and external CLI settings are edited here.',
          ),
        ),
        const SizedBox(height: 16),
        ..._buildAgents(context, controller, settings),
        const SizedBox(height: 16),
        CodexIntegrationCard(controller: controller),
      ],
      SettingsDetailPage.diagnosticsAdvanced => <Widget>[
        _buildDetailIntro(
          context,
          title: detail.label,
          description: appText(
            '高级诊断集中展示网关诊断、运行日志和设备信息。',
            'Advanced diagnostics centralize gateway diagnostics, runtime logs, and device information.',
          ),
        ),
        const SizedBox(height: 16),
        ..._buildDiagnostics(context, controller),
      ],
    };
  }

  Widget _buildDetailIntro(
    BuildContext context, {
    required String title,
    required String description,
  }) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  List<Widget> _buildGeneral(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Application', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _SwitchRow(
              label: appText('启用工作台外壳', 'Active workspace shell'),
              value: settings.appActive,
              onChanged: (value) => _saveSettings(
                controller,
                settings.copyWith(appActive: value),
              ),
            ),
            _SwitchRow(
              label: appText('开机启动', 'Launch at login'),
              value: settings.launchAtLogin,
              onChanged: (value) => _saveSettings(
                controller,
                settings.copyWith(launchAtLogin: value),
              ),
            ),
            _SwitchRow(
              label: controller.supportsDesktopIntegration
                  ? appText('显示托盘图标', 'Show tray icon')
                  : appText('显示 Dock 图标', 'Show dock icon'),
              value: settings.showDockIcon,
              onChanged: (value) => _saveSettings(
                controller,
                settings.copyWith(showDockIcon: value),
              ),
            ),
            _SwitchRow(
              label: appText('账号本地模式', 'Account local mode'),
              value: settings.accountLocalMode,
              onChanged: (value) => _saveSettings(
                controller,
                settings.copyWith(accountLocalMode: value),
              ),
            ),
          ],
        ),
      ),
      if (controller.supportsDesktopIntegration)
        _buildLinuxDesktopIntegration(context, controller, settings),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('账号访问', 'Account Access'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _EditableField(
              label: appText('账号服务地址', 'Account Base URL'),
              value: settings.accountBaseUrl,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(accountBaseUrl: value),
              ),
            ),
            _EditableField(
              label: appText('账号用户名', 'Account Username'),
              value: settings.accountUsername,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(accountUsername: value),
              ),
            ),
            _EditableField(
              label: appText('工作区名称', 'Workspace Label'),
              value: settings.accountWorkspace,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(accountWorkspace: value),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildLinuxDesktopIntegration(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final desktop = controller.desktopIntegration;
    final config = settings.linuxDesktop;
    final theme = Theme.of(context);
    return SurfaceCard(
      key: const ValueKey('linux-desktop-integration-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appText('Linux 桌面集成', 'Linux Desktop Integration'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            appText(
              '统一管理 GNOME / KDE 的代理模式、隧道连接、托盘菜单与开机自启。',
              'Manage GNOME / KDE proxy mode, tunnel session, tray menu, and autostart from one surface.',
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _InfoRow(
            label: appText('桌面环境', 'Desktop'),
            value: desktop.environment.label,
          ),
          _InfoRow(
            label: 'NetworkManager',
            value: desktop.networkManagerAvailable
                ? appText('可用', 'Available')
                : appText('不可用', 'Unavailable'),
          ),
          _InfoRow(
            label: appText('当前模式', 'Current Mode'),
            value: desktop.mode.label,
          ),
          _InfoRow(
            label: appText('隧道状态', 'Tunnel'),
            value: desktop.tunnel.connected
                ? appText('已连接', 'Connected')
                : desktop.tunnel.available
                ? appText('可连接', 'Ready')
                : appText('未检测到配置', 'No profile detected'),
          ),
          _InfoRow(
            label: appText('系统代理', 'System Proxy'),
            value: desktop.systemProxy.enabled
                ? '${desktop.systemProxy.host}:${desktop.systemProxy.port}'
                : appText('未启用', 'Disabled'),
          ),
          _SwitchRow(
            label: appText('开机启动', 'Launch at login'),
            value: settings.launchAtLogin,
            onChanged: (value) => controller.setLaunchAtLogin(value),
          ),
          _SwitchRow(
            label: appText('托盘菜单', 'Tray menu'),
            value: config.trayEnabled,
            onChanged: (value) => controller.saveLinuxDesktopConfig(
              config.copyWith(trayEnabled: value),
            ),
          ),
          _EditableField(
            label: appText('隧道连接名称', 'Tunnel Connection Name'),
            value: config.vpnConnectionName,
            onSubmitted: (value) => controller.saveLinuxDesktopConfig(
              config.copyWith(vpnConnectionName: value.trim()),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _EditableField(
                  label: appText('代理主机', 'Proxy Host'),
                  value: config.proxyHost,
                  onSubmitted: (value) => controller.saveLinuxDesktopConfig(
                    config.copyWith(proxyHost: value.trim()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _EditableField(
                  label: appText('代理端口', 'Proxy Port'),
                  value: config.proxyPort.toString(),
                  onSubmitted: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed == null || parsed <= 0) {
                      return;
                    }
                    controller.saveLinuxDesktopConfig(
                      config.copyWith(proxyPort: parsed),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonal(
                onPressed: controller.desktopPlatformBusy
                    ? null
                    : () => controller.setDesktopVpnMode(VpnMode.proxy),
                child: Text(appText('切换到代理', 'Use Proxy')),
              ),
              FilledButton.tonal(
                onPressed: controller.desktopPlatformBusy
                    ? null
                    : () => controller.setDesktopVpnMode(VpnMode.tunnel),
                child: Text(appText('切换到隧道', 'Use Tunnel')),
              ),
              OutlinedButton(
                onPressed: controller.desktopPlatformBusy
                    ? null
                    : controller.connectDesktopTunnel,
                child: Text(appText('连接隧道', 'Connect Tunnel')),
              ),
              OutlinedButton(
                onPressed: controller.desktopPlatformBusy
                    ? null
                    : controller.disconnectDesktopTunnel,
                child: Text(appText('断开隧道', 'Disconnect Tunnel')),
              ),
              OutlinedButton(
                onPressed: controller.desktopPlatformBusy
                    ? null
                    : controller.refreshDesktopIntegration,
                child: Text(appText('刷新状态', 'Refresh Status')),
              ),
            ],
          ),
          if (desktop.statusMessage.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildNotice(
              context,
              tone: theme.colorScheme.surfaceContainerHighest,
              title: appText('桌面状态', 'Desktop Status'),
              message: desktop.statusMessage,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildWorkspace(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final hasStoredOllamaApiKey =
        controller.settingsController.secureRefs['ollama_cloud_api_key'] !=
        null;
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('工作区', 'Workspace'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _EditableField(
              label: appText('工作区路径', 'Workspace Path'),
              value: settings.workspacePath,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(workspacePath: value),
              ),
            ),
            _EditableField(
              label: appText('远程项目根目录', 'Remote Project Root'),
              value: settings.remoteProjectRoot,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(remoteProjectRoot: value),
              ),
            ),
            _EditableField(
              label: appText('CLI 路径', 'CLI Path'),
              value: settings.cliPath,
              onSubmitted: (value) =>
                  _saveSettings(controller, settings.copyWith(cliPath: value)),
            ),
            _EditableField(
              label: appText('默认模型', 'Default Model'),
              value: settings.defaultModel,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(defaultModel: value),
              ),
            ),
            _EditableField(
              label: appText('默认提供方', 'Default Provider'),
              value: settings.defaultProvider,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(defaultProvider: value),
              ),
            ),
          ],
        ),
      ),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('本地 Ollama', 'Ollama Local'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _EditableField(
              label: appText('服务地址', 'Endpoint'),
              value: settings.ollamaLocal.endpoint,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(
                  ollamaLocal: settings.ollamaLocal.copyWith(endpoint: value),
                ),
              ),
            ),
            _EditableField(
              label: appText('默认模型', 'Default Model'),
              value: settings.ollamaLocal.defaultModel,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(
                  ollamaLocal: settings.ollamaLocal.copyWith(
                    defaultModel: value,
                  ),
                ),
              ),
            ),
            _SwitchRow(
              label: appText('自动发现', 'Auto Discover'),
              value: settings.ollamaLocal.autoDiscover,
              onChanged: (value) => _saveSettings(
                controller,
                settings.copyWith(
                  ollamaLocal: settings.ollamaLocal.copyWith(
                    autoDiscover: value,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => controller.testOllamaConnection(cloud: false),
                child: Text(
                  '${appText('测试连接', 'Test Connection')} · ${controller.settingsController.ollamaStatus}',
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('Ollama Cloud', 'Ollama Cloud'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _EditableField(
              label: appText('基础地址', 'Base URL'),
              value: settings.ollamaCloud.baseUrl,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(
                  ollamaCloud: settings.ollamaCloud.copyWith(baseUrl: value),
                ),
              ),
            ),
            _EditableField(
              label: appText('工作区 / 组织', 'Workspace / Org'),
              value:
                  '${settings.ollamaCloud.organization} / ${settings.ollamaCloud.workspace}',
              onSubmitted: (value) {
                final parts = value.split('/');
                _saveSettings(
                  controller,
                  settings.copyWith(
                    ollamaCloud: settings.ollamaCloud.copyWith(
                      organization: parts.isNotEmpty ? parts.first.trim() : '',
                      workspace: parts.length > 1 ? parts[1].trim() : '',
                    ),
                  ),
                );
              },
            ),
            _EditableField(
              label: appText('默认模型', 'Default Model'),
              value: settings.ollamaCloud.defaultModel,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(
                  ollamaCloud: settings.ollamaCloud.copyWith(
                    defaultModel: value,
                  ),
                ),
              ),
            ),
            _buildSecureField(
              controller: _ollamaApiKeyController,
              label:
                  '${appText('API Key', 'API Key')} (${settings.ollamaCloud.apiKeyRef})',
              hasStoredValue: hasStoredOllamaApiKey,
              fieldState: _ollamaApiKeyState,
              onStateChanged: (value) =>
                  setState(() => _ollamaApiKeyState = value),
              loadValue: controller.settingsController.loadOllamaCloudApiKey,
              onSubmitted: controller.settingsController.saveOllamaCloudApiKey,
              storedHelperText: appText(
                '已安全保存，默认以 **** 显示，点击查看后读取真实值。',
                'Stored securely. Shows as **** until you reveal it.',
              ),
              emptyHelperText: appText(
                '输入后会安全保存到本机密钥存储。',
                'Saving writes to secure local key storage.',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () async {
                  await _persistOllamaApiKeyIfNeeded(
                    controller,
                    hasStoredValue: hasStoredOllamaApiKey,
                  );
                  await controller.testOllamaConnection(cloud: true);
                },
                child: Text(
                  '${appText('测试云端', 'Test Cloud')} · ${controller.settingsController.ollamaStatus}',
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildGateway(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    _syncDraftControllerValue(
      _aiGatewayNameController,
      settings.aiGateway.name,
      syncedValue: _aiGatewayNameSyncedValue,
      onSyncedValueChanged: (value) => _aiGatewayNameSyncedValue = value,
    );
    _syncDraftControllerValue(
      _aiGatewayUrlController,
      settings.aiGateway.baseUrl,
      syncedValue: _aiGatewayUrlSyncedValue,
      onSyncedValueChanged: (value) => _aiGatewayUrlSyncedValue = value,
    );
    _syncDraftControllerValue(
      _aiGatewayApiKeyRefController,
      settings.aiGateway.apiKeyRef,
      syncedValue: _aiGatewayApiKeyRefSyncedValue,
      onSyncedValueChanged: (value) => _aiGatewayApiKeyRefSyncedValue = value,
    );
    final selectedModels = settings.aiGateway.selectedModels.isNotEmpty
        ? settings.aiGateway.selectedModels
        : settings.aiGateway.availableModels.take(5).toList(growable: false);
    final filteredModels = _filterAiGatewayModels(
      settings.aiGateway.availableModels,
    );
    final hasStoredAiGatewayApiKey =
        controller.settingsController.secureRefs['ai_gateway_api_key'] != null;
    final hasStoredVaultToken =
        controller.settingsController.secureRefs['vault_token'] != null;
    final statusTheme = _aiGatewayFeedbackTheme(
      context,
      _aiGatewayTestMessage.isEmpty
          ? settings.aiGateway.syncState
          : _aiGatewayTestState,
    );
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OpenClaw Gateway',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              '${controller.connection.status.label} · ${controller.connection.remoteAddress ?? '${settings.gateway.host}:${settings.gateway.port}'}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonal(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => GatewayConnectDialog(
                      controller: controller,
                      onDone: () => Navigator.of(context).pop(),
                    ),
                  ),
                  child: Text(appText('打开连接面板', 'Open Connect Panel')),
                ),
                OutlinedButton(
                  onPressed: controller.refreshGatewayHealth,
                  child: Text(appText('刷新健康状态', 'Refresh Health')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: controller.selectedAgentId.isEmpty
                  ? ''
                  : controller.selectedAgentId,
              decoration: InputDecoration(
                labelText: appText('当前代理', 'Selected Agent'),
              ),
              items: [
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(appText('主代理', 'Main')),
                ),
                ...controller.agents.map(
                  (agent) => DropdownMenuItem<String>(
                    value: agent.id,
                    child: Text(agent.name),
                  ),
                ),
              ],
              onChanged: controller.selectAgent,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _buildDeviceSecurityCard(context, controller),
      const SizedBox(height: 16),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('Vault 服务', 'Vault Server'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _EditableField(
              label: appText('地址', 'Address'),
              value: settings.vault.address,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(
                  vault: settings.vault.copyWith(address: value),
                ),
              ),
            ),
            _EditableField(
              label: appText('命名空间', 'Namespace'),
              value: settings.vault.namespace,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(
                  vault: settings.vault.copyWith(namespace: value),
                ),
              ),
            ),
            _EditableField(
              label: appText('认证模式', 'Auth Mode'),
              value: settings.vault.authMode,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(
                  vault: settings.vault.copyWith(authMode: value),
                ),
              ),
            ),
            _EditableField(
              label: appText('Token 引用', 'Token Ref'),
              value: settings.vault.tokenRef,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(
                  vault: settings.vault.copyWith(tokenRef: value),
                ),
              ),
            ),
            _buildSecureField(
              controller: _vaultTokenController,
              label:
                  '${appText('Vault Token', 'Vault Token')} (${settings.vault.tokenRef})',
              hasStoredValue: hasStoredVaultToken,
              fieldState: _vaultTokenState,
              onStateChanged: (value) =>
                  setState(() => _vaultTokenState = value),
              loadValue: controller.settingsController.loadVaultToken,
              onSubmitted: controller.settingsController.saveVaultToken,
              storedHelperText: appText(
                '已安全保存，默认以 **** 显示，点击查看后读取真实值。',
                'Stored securely. Shows as **** until you reveal it.',
              ),
              emptyHelperText: appText(
                '输入后会安全保存到本机密钥存储。',
                'Saving writes to secure local key storage.',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () async {
                  await _persistVaultTokenIfNeeded(
                    controller,
                    hasStoredValue: hasStoredVaultToken,
                  );
                  await controller.testVaultConnection();
                },
                child: Text(
                  '${appText('测试 Vault', 'Test Vault')} · ${controller.settingsController.vaultStatus}',
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('AI Gateway', 'AI Gateway'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('ai-gateway-name-field'),
              controller: _aiGatewayNameController,
              decoration: InputDecoration(
                labelText: appText('配置名称', 'Profile Name'),
              ),
              onSubmitted: (_) => _saveAiGatewayDraft(controller, settings),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('ai-gateway-url-field'),
              controller: _aiGatewayUrlController,
              decoration: InputDecoration(
                labelText: appText('Gateway URL', 'Gateway URL'),
              ),
              onSubmitted: (_) => _saveAiGatewayDraft(controller, settings),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('ai-gateway-api-key-ref-field'),
              controller: _aiGatewayApiKeyRefController,
              decoration: InputDecoration(
                labelText: appText('API Key 引用', 'API Key Ref'),
              ),
              onSubmitted: (_) => _saveAiGatewayDraft(controller, settings),
            ),
            _buildSecureField(
              fieldKey: const ValueKey('ai-gateway-api-key-field'),
              controller: _aiGatewayApiKeyController,
              label:
                  '${appText('API Key', 'API Key')} (${_aiGatewayApiKeyRefController.text.trim().isEmpty ? settings.aiGateway.apiKeyRef : _aiGatewayApiKeyRefController.text.trim()})',
              hasStoredValue: hasStoredAiGatewayApiKey,
              fieldState: _aiGatewayApiKeyState,
              onStateChanged: (value) =>
                  setState(() => _aiGatewayApiKeyState = value),
              loadValue: controller.settingsController.loadAiGatewayApiKey,
              onSubmitted: controller.settingsController.saveAiGatewayApiKey,
              storedHelperText: appText(
                '已安全保存，默认以 **** 显示；可直接测试或保存/应用，也可点击查看。',
                'Stored securely. Test or save/apply directly, or reveal it on demand.',
              ),
              emptyHelperText: appText(
                '输入后点击测试连接或保存/应用。',
                'Test or save/apply to persist securely.',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton(
                  key: const ValueKey('ai-gateway-test-button'),
                  onPressed: _aiGatewayTesting || _aiGatewaySyncing
                      ? null
                      : () => _testAiGatewayConnection(controller, settings),
                  child: Text(
                    _aiGatewayTesting
                        ? appText('测试中...', 'Testing...')
                        : appText('测试连接', 'Test Connection'),
                  ),
                ),
                FilledButton.tonal(
                  key: const ValueKey('ai-gateway-apply-button'),
                  onPressed: _aiGatewayTesting || _aiGatewaySyncing
                      ? null
                      : () => _applyAiGatewaySettings(controller, settings),
                  child: Text(
                    _aiGatewaySyncing
                        ? appText('应用中...', 'Applying...')
                        : appText('保存/应用', 'Save / Apply'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              settings.aiGateway.syncMessage,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_aiGatewayTestMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                key: const ValueKey('ai-gateway-test-feedback'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusTheme.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _aiGatewayTestMessage,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: statusTheme.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_aiGatewayTestEndpoint.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _aiGatewayTestEndpoint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: statusTheme.foreground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (settings.aiGateway.availableModels.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('ai-gateway-model-search'),
                controller: _aiGatewayModelSearchController,
                decoration: InputDecoration(
                  labelText: appText('搜索模型', 'Search models'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon:
                      _aiGatewayModelSearchController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: appText('清空搜索', 'Clear search'),
                          onPressed: () {
                            _aiGatewayModelSearchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    appText(
                      '已选 ${selectedModels.length} / ${settings.aiGateway.availableModels.length}',
                      'Selected ${selectedModels.length} / ${settings.aiGateway.availableModels.length}',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  OutlinedButton(
                    key: const ValueKey('ai-gateway-select-filtered'),
                    onPressed: filteredModels.isEmpty
                        ? null
                        : () async {
                            await controller.updateAiGatewaySelection(
                              <String>{
                                ...selectedModels,
                                ...filteredModels,
                              }.toList(growable: false),
                            );
                          },
                    child: Text(appText('选择筛选结果', 'Select filtered')),
                  ),
                  OutlinedButton(
                    key: const ValueKey('ai-gateway-reset-default'),
                    onPressed: () async {
                      await controller.updateAiGatewaySelection(
                        settings.aiGateway.availableModels
                            .take(5)
                            .toList(growable: false),
                      );
                    },
                    child: Text(appText('恢复默认 5 个', 'Reset default 5')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (filteredModels.isEmpty)
                Text(
                  appText('没有匹配的模型。', 'No matching models.'),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: filteredModels
                      .map((modelId) {
                        final selected = selectedModels.contains(modelId);
                        return FilterChip(
                          label: Text(modelId),
                          selected: selected,
                          onSelected: (_) async {
                            final nextSelection = selected
                                ? selectedModels
                                      .where((item) => item != modelId)
                                      .toList(growable: true)
                                : <String>[...selectedModels, modelId];
                            await controller.updateAiGatewaySelection(
                              nextSelection,
                            );
                          },
                        );
                      })
                      .toList(growable: false),
                ),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildAppearance(
    BuildContext context,
    AppController controller,
  ) {
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('主题', 'Theme'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ChoiceChip(
                  label: Text(appText('浅色', 'Light')),
                  selected: controller.themeMode == ThemeMode.light,
                  onSelected: (_) => controller.setThemeMode(ThemeMode.light),
                ),
                ChoiceChip(
                  label: Text(appText('深色', 'Dark')),
                  selected: controller.themeMode == ThemeMode.dark,
                  onSelected: (_) => controller.setThemeMode(ThemeMode.dark),
                ),
                ChoiceChip(
                  label: Text(appText('跟随系统', 'System')),
                  selected: controller.themeMode == ThemeMode.system,
                  onSelected: (_) => controller.setThemeMode(ThemeMode.system),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildDiagnostics(
    BuildContext context,
    AppController controller,
  ) {
    final runtimeLogs = controller.runtimeLogs
        .where(_matchesRuntimeLogFilter)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('网关诊断', 'Gateway Diagnostics'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: appText('连接', 'Connection'),
              value: controller.connection.status.label,
            ),
            _InfoRow(
              label: appText('地址', 'Address'),
              value:
                  controller.connection.remoteAddress ??
                  appText('离线', 'Offline'),
            ),
            _InfoRow(
              label: appText('代理', 'Agent'),
              value: controller.activeAgentName,
            ),
            _InfoRow(
              label: appText('认证模式', 'Auth Mode'),
              value:
                  controller.connection.connectAuthMode ??
                  appText('未发起', 'Not attempted'),
            ),
            _InfoRow(
              label: appText('认证诊断', 'Auth Diagnostics'),
              value: controller.connection.connectAuthSummary,
            ),
            _InfoRow(
              label: appText('健康负载', 'Health Payload'),
              value: controller.connection.healthPayload == null
                  ? appText('不可用', 'Unavailable')
                  : encodePrettyJson(controller.connection.healthPayload!),
            ),
            _InfoRow(
              label: appText('状态负载', 'Status Payload'),
              value: controller.connection.statusPayload == null
                  ? appText('不可用', 'Unavailable')
                  : encodePrettyJson(controller.connection.statusPayload!),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        key: const ValueKey('runtime-log-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appText('运行日志', 'Runtime Logs'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        appText(
                          '只记录本机运行期的连接、鉴权、配对和 socket 诊断，不写入密钥明文。',
                          'Shows local runtime diagnostics for connection, auth, pairing, and socket events without logging secret values.',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: runtimeLogs.isEmpty
                      ? null
                      : () => controller.clearRuntimeLogs(),
                  child: Text(appText('清空', 'Clear')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('runtime-log-filter'),
              controller: _runtimeLogFilterController,
              decoration: InputDecoration(
                labelText: appText('筛选日志', 'Filter Logs'),
                hintText: appText(
                  '按级别、分类或关键字过滤',
                  'Filter by level, category, or keyword',
                ),
                prefixIcon: const Icon(Icons.manage_search_rounded),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            if (runtimeLogs.isEmpty)
              Text(
                appText('当前没有运行日志。', 'No runtime logs yet.'),
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 320),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SelectionArea(
                  child: ListView.separated(
                    itemCount: runtimeLogs.length,
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      final entry = runtimeLogs[index];
                      return SelectableText(
                        entry.line,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      );
                    },
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        key: const ValueKey('assistant-local-state-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('本地数据清理', 'Local Data Cleanup'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              appText(
                '删除本机保存的 Assistant 任务线程会话、本地设置快照和恢复备份，不会删除已保存密钥，也不会触碰外部 Codex 全局目录。',
                'Deletes locally saved Assistant threads, settings snapshots, and recovery backups. Stored secrets and the external Codex home stay untouched.',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const ValueKey('assistant-local-state-clear-button'),
                onPressed: () =>
                    _showClearAssistantLocalStateDialog(context, controller),
                icon: const Icon(Icons.delete_forever_rounded),
                label: Text(
                  appText('清理任务线程与本地配置', 'Clear threads and local config'),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('设备', 'Device'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: appText('平台', 'Platform'),
              value: controller.runtime.deviceInfo.platformLabel,
            ),
            _InfoRow(
              label: appText('设备类型', 'Device Family'),
              value: controller.runtime.deviceInfo.deviceFamily,
            ),
            _InfoRow(
              label: appText('型号标识', 'Model Identifier'),
              value: controller.runtime.deviceInfo.modelIdentifier,
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildAgents(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final orchestrator = controller.multiAgentOrchestrator;
    final config = settings.multiAgent;
    final theme = Theme.of(context);
    final mountTargets = List<ManagedMountTargetState>.from(config.mountTargets)
      ..sort(
        (left, right) =>
            left.label.toLowerCase().compareTo(right.label.toLowerCase()),
      );
    final managedSkillCount = config.managedSkills
        .where((item) => item.selected)
        .length;
    final managedMcpCount = config.managedMcpServers
        .where((item) => item.enabled)
        .length;

    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final info = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appText('多 Agent 协作', 'Multi-Agent Collaboration'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appText(
                        '限定在多 Agent 协作：Architect 负责调度/文档，Lead Engineer 负责主程，Worker/Review 负责并行 worker 与复审；第一批外部桥接走 ollama launch。',
                        'Multi-agent only: Architect handles orchestration/docs, Lead Engineer owns the critical path, Worker/Review handles parallel workers and review; first-batch external bridges run through ollama launch.',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                );
                final toggle = _InlineSwitchField(
                  label: appText('启用协作模式', 'Enable Collaboration'),
                  value: config.enabled,
                  onChanged: (value) => _saveMultiAgentConfig(
                    controller,
                    config.copyWith(enabled: value),
                  ),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [info, const SizedBox(height: 16), toggle],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 20),
                    Flexible(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: toggle,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('multi-agent-framework-${config.framework.name}'),
              initialValue: config.framework.name,
              decoration: InputDecoration(
                labelText: appText('协作框架', 'Framework'),
              ),
              items: MultiAgentFramework.values
                  .map(
                    (framework) => DropdownMenuItem<String>(
                      value: framework.name,
                      child: Text(framework.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                final framework = MultiAgentFrameworkCopy.fromJsonValue(value);
                _saveMultiAgentConfig(
                  controller,
                  config.copyWith(
                    framework: framework,
                    arisEnabled: framework == MultiAgentFramework.aris,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'Ollama', value: config.ollamaEndpoint),
            _InfoRow(
              label: appText('文档 Lane', 'Doc Lane'),
              value:
                  '${config.architect.cliTool} · ${config.architect.model.isEmpty ? '—' : config.architect.model}',
            ),
            _InfoRow(
              label: appText('主程 Lane', 'Lead Lane'),
              value:
                  '${config.engineer.cliTool} · ${config.engineer.model.isEmpty ? '—' : config.engineer.model}',
            ),
            _InfoRow(
              label: appText('Worker Lane', 'Worker Lane'),
              value:
                  '${config.tester.cliTool} · ${config.tester.model.isEmpty ? '—' : config.tester.model}',
            ),
            _InfoRow(
              label: appText('超时时间', 'Timeout'),
              value: '${config.timeoutSeconds}s',
            ),
            _InfoRow(
              label: 'ARIS',
              value: config.usesAris
                  ? [
                      config.arisCompatStatus,
                      if (config.arisBundleVersion.trim().isNotEmpty)
                        config.arisBundleVersion.trim(),
                    ].join(' · ')
                  : appText('未启用', 'Disabled'),
            ),
            _InfoRow(
              label: appText('运行状态', 'Runtime'),
              value: orchestrator.isRunning
                  ? appText('协作执行中', 'Collaboration running')
                  : config.enabled
                  ? appText('已启用', 'Enabled')
                  : appText('已停用', 'Disabled'),
            ),
          ],
        ),
      ),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('角色配置', 'Role Configuration'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _AgentRoleCard(
              title:
                  '🧭 ${appText('Architect（调度/文档）', 'Architect (Docs / Scheduler)')}',
              description: appText(
                '负责 requirements -> acceptance evidence、架构选项排序、文档与调度。',
                'Owns requirements -> acceptance evidence, option ranking, docs, and orchestration.',
              ),
              cliTool: config.architect.cliTool,
              model: config.architect.model,
              enabled: config.architect.enabled,
              cliOptions: _mergeOptions(config.architect.cliTool, const [
                'claude',
                'codex',
                'opencode',
                'gemini',
              ]),
              modelOptions: _getArchitectModelOptions(settings, config),
              onCliChanged: (tool) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  architect: config.architect.copyWith(cliTool: tool),
                ),
              ),
              onModelChanged: (model) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  architect: config.architect.copyWith(model: model),
                ),
              ),
              onEnabledChanged: (enabled) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  architect: config.architect.copyWith(enabled: enabled),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _AgentRoleCard(
              title: '🔧 ${appText('Lead Engineer（主程）', 'Lead Engineer')}',
              description: appText(
                '负责关键实现、重构、集成收口，默认走 codex + minimax-m2.7:cloud。',
                'Owns critical implementation, refactors, and integration. Defaults to codex + minimax-m2.7:cloud.',
              ),
              cliTool: config.engineer.cliTool,
              model: config.engineer.model,
              enabled: config.engineer.enabled,
              cliOptions: _mergeOptions(config.engineer.cliTool, const [
                'codex',
                'claude',
                'opencode',
                'gemini',
              ]),
              modelOptions: _getLeadModelOptions(settings, config),
              onCliChanged: (tool) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  engineer: config.engineer.copyWith(cliTool: tool),
                ),
              ),
              onModelChanged: (model) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  engineer: config.engineer.copyWith(model: model),
                ),
              ),
              onEnabledChanged: (enabled) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  engineer: config.engineer.copyWith(enabled: enabled),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _AgentRoleCard(
              title:
                  '🧪 ${appText('Worker/Review（Worker 池）', 'Worker/Review Pool')}',
              description: appText(
                '负责 glm/qwen worker lane、回归审阅和补充建议。',
                'Owns glm/qwen worker lanes, review, regression checks, and follow-up notes.',
              ),
              cliTool: config.tester.cliTool,
              model: config.tester.model,
              enabled: config.tester.enabled,
              cliOptions: _mergeOptions(config.tester.cliTool, const [
                'opencode',
                'codex',
                'claude',
                'gemini',
              ]),
              modelOptions: _getWorkerModelOptions(settings, config),
              onCliChanged: (tool) => _saveMultiAgentConfig(
                controller,
                config.copyWith(tester: config.tester.copyWith(cliTool: tool)),
              ),
              onModelChanged: (model) => _saveMultiAgentConfig(
                controller,
                config.copyWith(tester: config.tester.copyWith(model: model)),
              ),
              onEnabledChanged: (enabled) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  tester: config.tester.copyWith(enabled: enabled),
                ),
              ),
            ),
          ],
        ),
      ),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('审阅策略', 'Review Strategy'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _EditableField(
                    label: appText('最大迭代次数', 'Max Iterations'),
                    value: config.maxIterations.toString(),
                    onSubmitted: (value) {
                      final parsed = int.tryParse(value.trim());
                      if (parsed != null && parsed > 0) {
                        _saveMultiAgentConfig(
                          controller,
                          config.copyWith(maxIterations: parsed),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _EditableField(
                    label: appText('最低达标分数', 'Min Acceptable Score'),
                    value: config.minAcceptableScore.toString(),
                    onSubmitted: (value) {
                      final parsed = int.tryParse(value.trim());
                      if (parsed != null && parsed >= 1 && parsed <= 10) {
                        _saveMultiAgentConfig(
                          controller,
                          config.copyWith(minAcceptableScore: parsed),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              appText(
                '当 Worker/Review 评分低于最低分数时，将进入迭代审阅循环。最多迭代指定次数。',
                'When the Worker/Review score is below minimum, the iteration loop runs until max iterations or the score passes.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final info = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appText('发现与分发', 'Discovery & Distribution'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appText(
                        'App 作为统一发现与分发中心，维护托管 skills、MCP server list 和 AI Gateway 默认注入，但不会覆盖用户原有 CLI 配置。',
                        'The app acts as the discovery and distribution center for managed skills, MCP server lists, and AI Gateway defaults without overwriting existing CLI config.',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                );
                final refreshButton = OutlinedButton(
                  onPressed: () =>
                      controller.refreshMultiAgentMounts(sync: config.autoSync),
                  child: Text(appText('刷新挂载', 'Refresh Mounts')),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [info, const SizedBox(height: 12), refreshButton],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 16),
                    refreshButton,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _SwitchRow(
              label: appText('自动同步托管配置', 'Auto-sync managed config'),
              value: config.autoSync,
              onChanged: (value) => _saveMultiAgentConfig(
                controller,
                config.copyWith(autoSync: value),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'multi-agent-injection-${config.aiGatewayInjectionPolicy.name}',
              ),
              initialValue: config.aiGatewayInjectionPolicy.name,
              decoration: InputDecoration(
                labelText: appText('AI Gateway 注入策略', 'AI Gateway Injection'),
              ),
              items: AiGatewayInjectionPolicy.values
                  .map(
                    (policy) => DropdownMenuItem<String>(
                      value: policy.name,
                      child: Text(policy.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                _saveMultiAgentConfig(
                  controller,
                  config.copyWith(
                    aiGatewayInjectionPolicy:
                        AiGatewayInjectionPolicyCopy.fromJsonValue(value),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: appText('托管 Skills', 'Managed Skills'),
              value: '$managedSkillCount',
            ),
            _InfoRow(
              label: appText('托管 MCP', 'Managed MCP'),
              value: '$managedMcpCount',
            ),
            if (config.usesAris) ...[
              const SizedBox(height: 4),
              Text(
                appText(
                  'ARIS 模式会把内嵌 skills 与 Go bridge reviewer 作为本地 Ollama 协作增强层，不会覆盖你原有的 CLI 全局配置。',
                  'ARIS mode injects embedded skills and the Go bridge reviewer for local Ollama collaboration without overwriting your existing CLI global config.',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            ...mountTargets.map(
              (target) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MountTargetCard(target: target),
              ),
            ),
          ],
        ),
      ),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('协作流程概览', 'Workflow Overview'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _WorkflowStep(
              label: '1',
              emoji: '🧭',
              title: appText(
                'Architect（调度/文档）',
                'Architect (Docs / Scheduler)',
              ),
              desc: appText(
                '收敛 requirements -> acceptance evidence，并冻结里程碑。',
                'Freeze requirements -> acceptance evidence and milestones.',
              ),
            ),
            _WorkflowStep(
              label: '2',
              emoji: '🔧',
              title: appText('Lead Engineer（主程）', 'Lead Engineer'),
              desc: appText(
                '主程执行关键路径与集成收口。',
                'Lead engineer executes the critical path and integration.',
              ),
            ),
            _WorkflowStep(
              label: '3',
              emoji: '🧪',
              title: appText('Worker/Review（Worker 池）', 'Worker/Review Pool'),
              desc: appText(
                '并行 worker 补切片，review lane 给出复审与回归建议。',
                'Parallel workers handle bounded slices while the review lane returns critique and regression guidance.',
              ),
            ),
            _WorkflowStep(
              label: '↻',
              emoji: '🔄',
              title: appText('迭代（如需要）', 'Iterate (if needed)'),
              desc: appText(
                '主程修复 -> Worker/Review 重新审阅',
                'Lead engineer fixes -> Worker/Review re-reviews',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appText(
                '首批支持的外部启动模式：`ollama launch claude --model kimi-k2.5:cloud --yes -- -p ...`、`ollama launch codex --model minimax-m2.7:cloud -- exec ...`、`ollama launch opencode --model glm-5:cloud -- run ...`。',
                'First-batch launch bridges: `ollama launch claude --model kimi-k2.5:cloud --yes -- -p ...`, `ollama launch codex --model minimax-m2.7:cloud -- exec ...`, and `ollama launch opencode --model glm-5:cloud -- run ...`.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ];
  }

  List<String> _getLocalModelOptions(SettingsSnapshot settings) {
    return <String>[
          settings.ollamaLocal.defaultModel,
          'qwen3.5',
          'glm-4.7-flash',
        ]
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  List<String> _mergeOptions(String current, List<String> defaults) {
    return <String>[current.trim(), ...defaults]
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  List<String> _getArchitectModelOptions(
    SettingsSnapshot settings,
    MultiAgentConfig config,
  ) {
    return _mergeOptions(config.architect.model, <String>[
      'kimi-k2.5:cloud',
      'qwen3.5:cloud',
      'glm-5:cloud',
      ..._getLocalModelOptions(settings),
    ]);
  }

  List<String> _getLeadModelOptions(
    SettingsSnapshot settings,
    MultiAgentConfig config,
  ) {
    return _mergeOptions(config.engineer.model, <String>[
      'minimax-m2.7:cloud',
      'qwen3.5:cloud',
      'glm-5:cloud',
      ..._getLocalModelOptions(settings),
    ]);
  }

  List<String> _getWorkerModelOptions(
    SettingsSnapshot settings,
    MultiAgentConfig config,
  ) {
    return _mergeOptions(config.tester.model, <String>[
      'glm-5:cloud',
      'qwen3.5:cloud',
      'glm-4.7-flash',
      'qwen3.5',
      ..._getLocalModelOptions(settings),
    ]);
  }

  List<Widget> _buildExperimental(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
  ) {
    final toggles = <Widget>[
      if (uiFeatures.allowsExperimentalSetting(
        UiFeatureKeys.settingsExperimentalCanvas,
      ))
        _SwitchRow(
          label: appText('Canvas 宿主', 'Canvas host'),
          value: settings.experimentalCanvas,
          onChanged: (value) => _saveSettings(
            controller,
            settings.copyWith(experimentalCanvas: value),
          ),
        ),
      if (uiFeatures.allowsExperimentalSetting(
        UiFeatureKeys.settingsExperimentalBridge,
      ))
        _SwitchRow(
          label: appText('桥接模式', 'Bridge mode'),
          value: settings.experimentalBridge,
          onChanged: (value) => _saveSettings(
            controller,
            settings.copyWith(experimentalBridge: value),
          ),
        ),
      if (uiFeatures.allowsExperimentalSetting(
        UiFeatureKeys.settingsExperimentalDebug,
      ))
        _SwitchRow(
          label: appText('调试运行时', 'Debug runtime'),
          value: settings.experimentalDebug,
          onChanged: (value) => _saveSettings(
            controller,
            settings.copyWith(experimentalDebug: value),
          ),
        ),
    ];

    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('实验特性', 'Experimental'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (toggles.isEmpty)
              Text(
                appText(
                  '当前发布配置未开放额外实验开关。',
                  'This build does not expose additional experimental toggles.',
                ),
              ),
            ...toggles,
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildAbout(BuildContext context, AppController controller) {
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('关于', 'About'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _InfoRow(label: appText('应用', 'App'), value: kSystemAppName),
            _InfoRow(
              label: appText('版本', 'Version'),
              value: controller.runtime.packageInfo.version,
            ),
            _InfoRow(
              label: appText('构建号', 'Build'),
              value: controller.runtime.packageInfo.buildNumber,
            ),
            _InfoRow(
              label: appText('包名', 'Package'),
              value: controller.runtime.packageInfo.packageName,
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _saveSettings(
    AppController controller,
    SettingsSnapshot snapshot,
  ) {
    return controller.saveSettings(snapshot);
  }

  Future<void> _saveMultiAgentConfig(
    AppController controller,
    MultiAgentConfig config,
  ) {
    return controller.saveMultiAgentConfig(config);
  }

  AiGatewayProfile _buildAiGatewayDraft(SettingsSnapshot settings) {
    final draftName = _aiGatewayNameController.text.trim();
    final draftBaseUrl = _aiGatewayUrlController.text.trim();
    final draftApiKeyRef = _aiGatewayApiKeyRefController.text.trim();
    final current = settings.aiGateway;
    final defaults = AiGatewayProfile.defaults();
    final connectionChanged =
        draftBaseUrl != current.baseUrl || draftApiKeyRef != current.apiKeyRef;
    return current.copyWith(
      name: draftName,
      baseUrl: draftBaseUrl,
      apiKeyRef: draftApiKeyRef,
      availableModels: connectionChanged
          ? defaults.availableModels
          : current.availableModels,
      selectedModels: connectionChanged
          ? defaults.selectedModels
          : current.selectedModels,
      syncState: connectionChanged ? defaults.syncState : current.syncState,
      syncMessage: connectionChanged
          ? defaults.syncMessage
          : current.syncMessage,
    );
  }

  Future<void> _saveAiGatewayDraft(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final draft = _buildAiGatewayDraft(settings);
    final hasStoredAiGatewayApiKey =
        controller.settingsController.secureRefs['ai_gateway_api_key'] != null;
    await _saveSettings(controller, settings.copyWith(aiGateway: draft));
    unawaited(
      _persistAiGatewayApiKeyIfNeeded(
        controller,
        hasStoredValue: hasStoredAiGatewayApiKey,
      ).catchError((_) {}),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _aiGatewayNameSyncedValue = draft.name;
      _aiGatewayUrlSyncedValue = draft.baseUrl;
      _aiGatewayApiKeyRefSyncedValue = draft.apiKeyRef;
      _aiGatewayTestState = draft.syncState;
      _aiGatewayTestMessage = '';
      _aiGatewayTestEndpoint = '';
    });
  }

  Future<void> _applyAiGatewaySettings(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final draft = _buildAiGatewayDraft(settings);
    final apiKey = _secretOverride(
      _aiGatewayApiKeyController,
      _aiGatewayApiKeyState,
    );
    final hasStoredAiGatewayApiKey =
        controller.settingsController.secureRefs['ai_gateway_api_key'] != null;
    setState(() => _aiGatewaySyncing = true);
    try {
      await _saveSettings(controller, settings.copyWith(aiGateway: draft));
      await _persistAiGatewayApiKeyIfNeeded(
        controller,
        hasStoredValue: hasStoredAiGatewayApiKey,
      );
      if (!mounted) {
        return;
      }
      _aiGatewayNameSyncedValue = draft.name;
      _aiGatewayUrlSyncedValue = draft.baseUrl;
      _aiGatewayApiKeyRefSyncedValue = draft.apiKeyRef;
      if (_aiGatewayTestState != 'ready') {
        setState(() {
          _aiGatewayTestState = draft.syncState;
          _aiGatewayTestMessage = '';
          _aiGatewayTestEndpoint = '';
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(appText('AI Gateway 已保存', 'AI Gateway saved')),
          ),
        );
        return;
      }
      final result = await controller.syncAiGatewayCatalog(
        draft,
        apiKeyOverride: apiKey,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _aiGatewayTestState = result.syncState;
        _aiGatewayTestMessage = result.syncState == 'ready'
            ? 'Catalog synced · ${result.availableModels.length} model(s) ready'
            : result.syncMessage;
        _aiGatewayTestEndpoint = result.syncState == 'ready'
            ? _previewAiGatewayEndpoint(draft.baseUrl)
            : '';
      });
      messenger.showSnackBar(SnackBar(content: Text(result.syncMessage)));
    } finally {
      if (mounted) {
        setState(() => _aiGatewaySyncing = false);
      }
    }
  }

  Future<void> _testAiGatewayConnection(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final draft = _buildAiGatewayDraft(settings);
    final apiKey = _secretOverride(
      _aiGatewayApiKeyController,
      _aiGatewayApiKeyState,
    );
    setState(() => _aiGatewayTesting = true);
    try {
      final result = await controller.settingsController
          .testAiGatewayConnection(draft, apiKeyOverride: apiKey);
      if (!mounted) {
        return;
      }
      setState(() {
        _aiGatewayTestState = result.state;
        _aiGatewayTestMessage = result.message;
        _aiGatewayTestEndpoint = result.endpoint;
      });
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) {
        setState(() => _aiGatewayTesting = false);
      }
    }
  }

  List<String> _filterAiGatewayModels(List<String> models) {
    final query = _aiGatewayModelSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return models;
    }
    return models
        .where((modelId) => modelId.toLowerCase().contains(query))
        .toList(growable: false);
  }

  String _previewAiGatewayEndpoint(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.trim().isEmpty) {
      return '';
    }
    final pathSegments = uri.pathSegments
        .where((item) => item.isNotEmpty)
        .toList(growable: true);
    if (pathSegments.isEmpty) {
      pathSegments.add('v1');
    }
    if (pathSegments.last != 'models') {
      pathSegments.add('models');
    }
    return uri
        .replace(pathSegments: pathSegments, query: null, fragment: null)
        .toString();
  }

  Widget _buildSecureField({
    Key? fieldKey,
    required TextEditingController controller,
    required String label,
    required bool hasStoredValue,
    required _SecretFieldUiState fieldState,
    required ValueChanged<_SecretFieldUiState> onStateChanged,
    required Future<String> Function() loadValue,
    required Future<void> Function(String) onSubmitted,
    required String storedHelperText,
    required String emptyHelperText,
  }) {
    _primeSecureFieldController(
      controller,
      hasStoredValue: hasStoredValue,
      fieldState: fieldState,
    );
    final showMaskedPlaceholder =
        hasStoredValue && !fieldState.showPlaintext && !fieldState.hasDraft;
    return TextField(
      key: fieldKey,
      controller: controller,
      obscureText: !fieldState.showPlaintext && fieldState.hasDraft,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        helperText: hasStoredValue ? storedHelperText : emptyHelperText,
        suffixIcon: fieldState.loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                tooltip: fieldState.showPlaintext
                    ? appText('隐藏', 'Hide')
                    : appText('查看', 'Reveal'),
                onPressed: () => _toggleSecureFieldVisibility(
                  controller: controller,
                  hasStoredValue: hasStoredValue,
                  fieldState: fieldState,
                  onStateChanged: onStateChanged,
                  loadValue: loadValue,
                ),
                icon: Icon(
                  fieldState.showPlaintext
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
              ),
      ),
      onTap: () {
        if (!showMaskedPlaceholder) {
          return;
        }
        controller.clear();
        onStateChanged(fieldState.copyWith(hasDraft: true));
      },
      onChanged: (value) {
        if (value == _storedSecretMask) {
          return;
        }
        final nextHasDraft = value.trim().isNotEmpty;
        if (nextHasDraft == fieldState.hasDraft) {
          return;
        }
        onStateChanged(fieldState.copyWith(hasDraft: nextHasDraft));
      },
      onSubmitted: (_) => _persistSecureFieldIfNeeded(
        controller: controller,
        hasStoredValue: hasStoredValue,
        fieldState: fieldState,
        onStateChanged: onStateChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }

  Future<void> _toggleSecureFieldVisibility({
    required TextEditingController controller,
    required bool hasStoredValue,
    required _SecretFieldUiState fieldState,
    required ValueChanged<_SecretFieldUiState> onStateChanged,
    required Future<String> Function() loadValue,
  }) async {
    if (fieldState.showPlaintext) {
      if (fieldState.hasDraft) {
        onStateChanged(fieldState.copyWith(showPlaintext: false));
        return;
      }
      if (hasStoredValue) {
        _syncControllerValue(controller, _storedSecretMask);
      } else {
        controller.clear();
      }
      onStateChanged(const _SecretFieldUiState());
      return;
    }
    if (fieldState.hasDraft || !hasStoredValue) {
      onStateChanged(fieldState.copyWith(showPlaintext: true, loading: false));
      return;
    }
    onStateChanged(fieldState.copyWith(loading: true));
    final value = (await loadValue()).trim();
    if (!mounted) {
      return;
    }
    if (value.isNotEmpty) {
      _syncControllerValue(controller, value);
    } else {
      controller.clear();
    }
    onStateChanged(
      const _SecretFieldUiState(showPlaintext: true, hasDraft: false),
    );
  }

  Future<void> _persistSecureFieldIfNeeded({
    required TextEditingController controller,
    required bool hasStoredValue,
    required _SecretFieldUiState fieldState,
    required ValueChanged<_SecretFieldUiState> onStateChanged,
    required Future<void> Function(String) onSubmitted,
  }) async {
    final value = _normalizeSecretValue(controller.text);
    if (value.isEmpty) {
      return;
    }
    if (!fieldState.hasDraft && hasStoredValue) {
      return;
    }
    await onSubmitted(value);
    if (!mounted) {
      return;
    }
    _syncControllerValue(controller, _storedSecretMask);
    onStateChanged(const _SecretFieldUiState());
  }

  Future<void> _persistAiGatewayApiKeyIfNeeded(
    AppController controller, {
    required bool hasStoredValue,
  }) {
    return _persistSecureFieldIfNeeded(
      controller: _aiGatewayApiKeyController,
      hasStoredValue: hasStoredValue,
      fieldState: _aiGatewayApiKeyState,
      onStateChanged: (value) => setState(() => _aiGatewayApiKeyState = value),
      onSubmitted: controller.settingsController.saveAiGatewayApiKey,
    );
  }

  Future<void> _persistVaultTokenIfNeeded(
    AppController controller, {
    required bool hasStoredValue,
  }) {
    return _persistSecureFieldIfNeeded(
      controller: _vaultTokenController,
      hasStoredValue: hasStoredValue,
      fieldState: _vaultTokenState,
      onStateChanged: (value) => setState(() => _vaultTokenState = value),
      onSubmitted: controller.settingsController.saveVaultToken,
    );
  }

  Future<void> _persistOllamaApiKeyIfNeeded(
    AppController controller, {
    required bool hasStoredValue,
  }) {
    return _persistSecureFieldIfNeeded(
      controller: _ollamaApiKeyController,
      hasStoredValue: hasStoredValue,
      fieldState: _ollamaApiKeyState,
      onStateChanged: (value) => setState(() => _ollamaApiKeyState = value),
      onSubmitted: controller.settingsController.saveOllamaCloudApiKey,
    );
  }

  void _primeSecureFieldController(
    TextEditingController controller, {
    required bool hasStoredValue,
    required _SecretFieldUiState fieldState,
  }) {
    if (fieldState.showPlaintext || fieldState.hasDraft) {
      return;
    }
    final nextValue = hasStoredValue ? _storedSecretMask : '';
    if (controller.text == nextValue) {
      return;
    }
    _syncControllerValue(controller, nextValue);
  }

  String _secretOverride(
    TextEditingController controller,
    _SecretFieldUiState fieldState,
  ) {
    if (!fieldState.showPlaintext && !fieldState.hasDraft) {
      return '';
    }
    return _normalizeSecretValue(controller.text);
  }

  String _normalizeSecretValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == _storedSecretMask) {
      return '';
    }
    return trimmed;
  }

  _AiGatewayFeedbackTheme _aiGatewayFeedbackTheme(
    BuildContext context,
    String state,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (state) {
      'ready' => _AiGatewayFeedbackTheme(
        background: colorScheme.primaryContainer,
        border: colorScheme.primary,
        foreground: colorScheme.onPrimaryContainer,
      ),
      'empty' => _AiGatewayFeedbackTheme(
        background: colorScheme.secondaryContainer,
        border: colorScheme.secondary,
        foreground: colorScheme.onSecondaryContainer,
      ),
      'error' || 'invalid' => _AiGatewayFeedbackTheme(
        background: colorScheme.errorContainer,
        border: colorScheme.error,
        foreground: colorScheme.onErrorContainer,
      ),
      _ => _AiGatewayFeedbackTheme(
        background: colorScheme.surfaceContainerHighest,
        border: colorScheme.outlineVariant,
        foreground: colorScheme.onSurfaceVariant,
      ),
    };
  }

  void _syncControllerValue(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = controller.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
  }

  void _syncDraftControllerValue(
    TextEditingController controller,
    String value, {
    required String syncedValue,
    required ValueChanged<String> onSyncedValueChanged,
  }) {
    final hasLocalDraft = controller.text != syncedValue;
    if (hasLocalDraft && controller.text != value) {
      return;
    }
    _syncControllerValue(controller, value);
    if (syncedValue != value) {
      onSyncedValueChanged(value);
    }
  }

  bool _matchesRuntimeLogFilter(RuntimeLogEntry entry) {
    final query = _runtimeLogFilterController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final haystack = '${entry.level} ${entry.category} ${entry.message}'
        .toLowerCase();
    return haystack.contains(query);
  }

  Widget _buildDeviceSecurityCard(
    BuildContext context,
    AppController controller,
  ) {
    final theme = Theme.of(context);
    final connection = controller.connection;
    final devices = controller.devices;
    final pending = devices.pending;
    final paired = devices.paired;
    final authScopes = connection.authScopes.isEmpty
        ? appText('未协商', 'Not negotiated')
        : connection.authScopes.join(', ');
    return SurfaceCard(
      key: const ValueKey('gateway-device-security-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appText('设备配对与角色令牌', 'Device Pairing & Role Tokens'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      appText(
                        '对齐 OpenClaw 的 Devices 安全机制，处理 pairing requests 和按角色下发的 device token。',
                        'Match OpenClaw device security: pairing requests and per-role device tokens.',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: controller.runtime.isConnected
                    ? () => controller.refreshDevices()
                    : null,
                child: Text(appText('刷新', 'Refresh')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoRow(
            label: appText('本机 Device ID', 'Local Device ID'),
            value: connection.deviceId ?? appText('未初始化', 'Not initialized'),
          ),
          _InfoRow(
            label: appText('当前角色', 'Current Role'),
            value: connection.authRole ?? 'operator',
          ),
          _InfoRow(label: appText('授权范围', 'Granted Scopes'), value: authScopes),
          if (connection.pairingRequired) ...[
            const SizedBox(height: 8),
            _buildNotice(
              context,
              tone: theme.colorScheme.tertiaryContainer,
              title: appText('需要设备审批', 'Pairing Required'),
              message: appText(
                '当前设备已经向 Gateway 发起配对。请在已授权的 operator 设备上审批该请求，然后重新连接。',
                'This device has requested pairing. Approve it from an authorized operator device, then reconnect.',
              ),
            ),
          ] else if (connection.gatewayTokenMissing) ...[
            const SizedBox(height: 8),
            _buildNotice(
              context,
              tone: theme.colorScheme.errorContainer,
              title: appText('缺少共享 Token', 'Shared Token Missing'),
              message: appText(
                '当前连接没有通过共享 token 或已配对 device token 完成鉴权。先输入共享 Token 建立首次配对，后续可切换为 device token。',
                'The current connection is missing shared-token or paired device-token auth. Use a shared token for the first pairing, then continue with the device token.',
              ),
            ),
          ],
          if ((controller.devicesController.error ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildNotice(
              context,
              tone: theme.colorScheme.errorContainer,
              title: appText('设备列表错误', 'Devices Error'),
              message: controller.devicesController.error!,
            ),
          ],
          const SizedBox(height: 16),
          if (!controller.runtime.isConnected) ...[
            Text(
              appText(
                '连接 Gateway 后，这里会显示待审批设备、已配对设备和角色令牌。',
                'Connect the gateway to load pending devices, paired devices, and role tokens.',
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ] else ...[
            Text(
              appText('待审批请求', 'Pending Requests'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (pending.isEmpty)
              Text(
                appText('当前没有待审批设备。', 'No pending pairing requests.'),
                style: theme.textTheme.bodyMedium,
              )
            else
              ...pending.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildPendingDeviceCard(context, controller, item),
                ),
              ),
            const SizedBox(height: 20),
            Text(
              appText('已配对设备', 'Paired Devices'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (paired.isEmpty)
              Text(
                appText('当前没有已配对设备。', 'No paired devices yet.'),
                style: theme.textTheme.bodyMedium,
              )
            else
              ...paired.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildPairedDeviceCard(context, controller, item),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingDeviceCard(
    BuildContext context,
    AppController controller,
    GatewayPendingDevice item,
  ) {
    final theme = Theme.of(context);
    final metadata = <String>[
      if ((item.role ?? '').isNotEmpty) 'role: ${item.role}',
      if (item.scopes.isNotEmpty) item.scopes.join(', '),
      if ((item.remoteIp ?? '').isNotEmpty) item.remoteIp!,
      _relativeTime(item.requestedAtMs),
      if (item.isRepair) appText('修复请求', 'repair'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  SelectableText(
                    item.deviceId,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(metadata.join(' · '), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () =>
                      controller.approveDevicePairing(item.requestId),
                  child: Text(appText('批准', 'Approve')),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final confirmed = await _confirmDeviceAction(
                      context,
                      title: appText('拒绝配对请求', 'Reject Pairing Request'),
                      message: appText(
                        '确定拒绝 ${item.label} 的配对请求吗？',
                        'Reject the pairing request from ${item.label}?',
                      ),
                    );
                    if (confirmed == true) {
                      await controller.rejectDevicePairing(item.requestId);
                    }
                  },
                  child: Text(appText('拒绝', 'Reject')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPairedDeviceCard(
    BuildContext context,
    AppController controller,
    GatewayPairedDevice item,
  ) {
    final theme = Theme.of(context);
    final meta = <String>[
      if (item.roles.isNotEmpty) 'roles: ${item.roles.join(', ')}',
      if (item.scopes.isNotEmpty) 'scopes: ${item.scopes.join(', ')}',
      if ((item.remoteIp ?? '').isNotEmpty) item.remoteIp!,
      if (item.currentDevice) appText('当前设备', 'current device'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      SelectableText(
                        item.deviceId,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(meta.join(' · '), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () async {
                    final confirmed = await _confirmDeviceAction(
                      context,
                      title: appText('移除已配对设备', 'Remove Paired Device'),
                      message: appText(
                        '确定移除 ${item.label} 吗？这会使该设备需要重新配对。',
                        'Remove ${item.label}? The device will need pairing again.',
                      ),
                    );
                    if (confirmed == true) {
                      await controller.removePairedDevice(item.deviceId);
                    }
                  },
                  child: Text(appText('移除', 'Remove')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (item.tokens.isEmpty)
              Text(
                appText('当前没有角色令牌。', 'No role tokens.'),
                style: theme.textTheme.bodySmall,
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _buildTokenRow(
                  context,
                  controller,
                  item,
                  _latestDeviceToken(item.tokens),
                ),
              ),
          ],
        ),
      ),
    );
  }

  GatewayDeviceTokenSummary _latestDeviceToken(
    List<GatewayDeviceTokenSummary> tokens,
  ) {
    final sorted = List<GatewayDeviceTokenSummary>.from(tokens)
      ..sort((left, right) {
        final rightTime = _deviceTokenStatusTime(right);
        final leftTime = _deviceTokenStatusTime(left);
        return rightTime.compareTo(leftTime);
      });
    return sorted.first;
  }

  int _deviceTokenStatusTime(GatewayDeviceTokenSummary token) {
    return token.lastUsedAtMs ??
        token.rotatedAtMs ??
        token.revokedAtMs ??
        token.createdAtMs ??
        0;
  }

  Widget _buildTokenRow(
    BuildContext context,
    AppController controller,
    GatewayPairedDevice device,
    GatewayDeviceTokenSummary token,
  ) {
    final theme = Theme.of(context);
    final details = <String>[
      token.revoked ? appText('已撤销', 'revoked') : appText('有效', 'active'),
      if (token.scopes.isNotEmpty) token.scopes.join(', '),
      _relativeTime(_deviceTokenStatusTime(token)),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(token.role, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(details.join(' · '), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () async {
                    final nextToken = await controller.rotateDeviceRoleToken(
                      deviceId: device.deviceId,
                      role: token.role,
                      scopes: token.scopes,
                    );
                    if (!context.mounted ||
                        nextToken == null ||
                        nextToken.isEmpty) {
                      return;
                    }
                    await _showRotatedTokenDialog(
                      context,
                      device: device,
                      role: token.role,
                      token: nextToken,
                    );
                  },
                  child: Text(appText('轮换', 'Rotate')),
                ),
                if (!token.revoked)
                  OutlinedButton(
                    onPressed: () async {
                      final confirmed = await _confirmDeviceAction(
                        context,
                        title: appText('撤销角色令牌', 'Revoke Role Token'),
                        message: appText(
                          '确定撤销 ${device.label} 的 ${token.role} 令牌吗？',
                          'Revoke the ${token.role} token for ${device.label}?',
                        ),
                      );
                      if (confirmed == true) {
                        await controller.revokeDeviceRoleToken(
                          deviceId: device.deviceId,
                          role: token.role,
                        );
                      }
                    },
                    child: Text(appText('撤销', 'Revoke')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotice(
    BuildContext context, {
    required Color tone,
    required String title,
    required String message,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          SelectableText(message, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Future<bool?> _confirmDeviceAction(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appText('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(appText('确认', 'Confirm')),
          ),
        ],
      ),
    );
  }

  Future<void> _showClearAssistantLocalStateDialog(
    BuildContext context,
    AppController controller,
  ) {
    var confirmed = false;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(appText('清理本地数据', 'Clear Local Data')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appText(
                  '该操作会删除本机保存的 Assistant 任务线程会话、本地设置快照和恢复备份，且无法撤销。',
                  'This deletes locally stored Assistant threads, settings snapshots, and recovery backups. This cannot be undone.',
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const ValueKey('assistant-local-state-clear-confirm'),
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                onChanged: (value) {
                  setDialogState(() {
                    confirmed = value ?? false;
                  });
                },
                title: Text(
                  appText(
                    '我确认删除本机任务线程会话和本地配置',
                    'I confirm deleting local threads and settings',
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(appText('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: !confirmed
                  ? null
                  : () async {
                      await controller.clearAssistantLocalState();
                      if (!dialogContext.mounted) {
                        return;
                      }
                      Navigator.of(dialogContext).pop();
                    },
              child: Text(appText('确认清理', 'Confirm Clear')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRotatedTokenDialog(
    BuildContext context, {
    required GatewayPairedDevice device,
    required String role,
    required String token,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText('新的角色令牌', 'New Role Token')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText(
                '${device.label} 的 $role 令牌已轮换，请立即安全保存。',
                'Rotated the $role token for ${device.label}. Store it securely now.',
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(token),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appText('关闭', 'Close')),
          ),
        ],
      ),
    );
  }

  String _relativeTime(int? timestampMs) {
    if (timestampMs == null || timestampMs <= 0) {
      return appText('时间未知', 'time unknown');
    }
    final delta = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
    if (delta.inMinutes < 1) {
      return appText('刚刚', 'just now');
    }
    if (delta.inHours < 1) {
      return appText('${delta.inMinutes} 分钟前', '${delta.inMinutes}m ago');
    }
    if (delta.inDays < 1) {
      return appText('${delta.inHours} 小时前', '${delta.inHours}h ago');
    }
    return appText('${delta.inDays} 天前', '${delta.inDays}d ago');
  }
}

class _EditableField extends StatelessWidget {
  const _EditableField({
    required this.label,
    required this.value,
    required this.onSubmitted,
  });

  final String label;
  final String value;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        key: ValueKey('$label:$value'),
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        onFieldSubmitted: onSubmitted,
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _MountTargetCard extends StatelessWidget {
  const _MountTargetCard({required this.target});

  final ManagedMountTargetState target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = target.available
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    final summary = <String>[
      '${appText('发现', 'Discovery')}: ${target.discoveryState}',
      '${appText('同步', 'Sync')}: ${target.syncState}',
      if (target.supportsSkills)
        '${appText('技能', 'Skills')}: ${target.discoveredSkillCount}',
      if (target.supportsMcp)
        '${appText('MCP', 'MCP')}: ${target.discoveredMcpCount}',
      if (target.supportsMcp)
        '${appText('托管', 'Managed')}: ${target.managedMcpCount}',
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(target.label, style: theme.textTheme.titleMedium),
                ),
                Text(
                  target.available
                      ? appText('可用', 'Available')
                      : appText('未安装', 'Missing'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(summary.join(' · '), style: theme.textTheme.bodySmall),
            if (target.detail.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(target.detail, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _InlineSwitchField extends StatelessWidget {
  const _InlineSwitchField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelLarge,
                softWrap: true,
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

class _AiGatewayFeedbackTheme {
  const _AiGatewayFeedbackTheme({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;
}

class _SecretFieldUiState {
  const _SecretFieldUiState({
    this.showPlaintext = false,
    this.hasDraft = false,
    this.loading = false,
  });

  final bool showPlaintext;
  final bool hasDraft;
  final bool loading;

  _SecretFieldUiState copyWith({
    bool? showPlaintext,
    bool? hasDraft,
    bool? loading,
  }) {
    return _SecretFieldUiState(
      showPlaintext: showPlaintext ?? this.showPlaintext,
      hasDraft: hasDraft ?? this.hasDraft,
      loading: loading ?? this.loading,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(width: 16),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

/// Agent 角色配置卡片
class _AgentRoleCard extends StatelessWidget {
  const _AgentRoleCard({
    required this.title,
    required this.description,
    required this.cliTool,
    required this.model,
    required this.enabled,
    required this.cliOptions,
    required this.modelOptions,
    required this.onCliChanged,
    required this.onModelChanged,
    required this.onEnabledChanged,
  });

  final String title;
  final String description;
  final String cliTool;
  final String model;
  final bool enabled;
  final List<String> cliOptions;
  final List<String> modelOptions;
  final ValueChanged<String> onCliChanged;
  final ValueChanged<String> onModelChanged;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(description, style: theme.textTheme.bodySmall),
                ],
              );
              final toggle = _InlineSwitchField(
                label: appText('启用', 'Enabled'),
                value: enabled,
                onChanged: onEnabledChanged,
              );
              if (cliOptions.length <= 1) {
                return info;
              }
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [info, const SizedBox(height: 12), toggle],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Align(alignment: Alignment.topRight, child: toggle),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final cliField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CLI', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: cliOptions.contains(cliTool)
                        ? cliTool
                        : cliOptions.first,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: cliOptions
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onCliChanged(v);
                    },
                  ),
                ],
              );
              final modelField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appText('模型', 'Model'),
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: modelOptions.contains(model)
                        ? model
                        : modelOptions.first,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: modelOptions
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(m, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onModelChanged(v);
                    },
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [cliField, const SizedBox(height: 12), modelField],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cliField),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: modelField),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 工作流步骤展示
class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({
    required this.label,
    required this.emoji,
    required this.title,
    required this.desc,
  });

  final String label;
  final String emoji;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primaryContainer,
            ),
            child: Text(label, style: theme.textTheme.labelSmall),
          ),
          const SizedBox(width: 12),
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                Text(desc, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
