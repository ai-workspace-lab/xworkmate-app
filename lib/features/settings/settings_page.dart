import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/app_store_policy.dart';
import '../../app/ui_feature_manifest.dart';
import '../../app/workspace_navigation.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/gateway_runtime.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import 'codex_integration_card.dart';
import 'skill_directory_authorization_card.dart';
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
  late final TextEditingController _gatewaySetupCodeController;
  late final TextEditingController _gatewayHostController;
  late final TextEditingController _gatewayPortController;
  late final List<TextEditingController> _gatewayTokenControllers;
  late final List<TextEditingController> _gatewayPasswordControllers;
  late final TextEditingController _vaultTokenController;
  late final TextEditingController _ollamaApiKeyController;
  late final TextEditingController _runtimeLogFilterController;
  bool _gatewayTesting = false;
  String _gatewayTestState = 'idle';
  String _gatewayTestMessage = '';
  String _gatewayTestEndpoint = '';
  bool _openClawGatewayExpanded = true;
  bool _vaultServerExpanded = true;
  bool _aiGatewayExpanded = true;
  int _selectedGatewayProfileIndex = kGatewayLocalProfileIndex;
  String _gatewaySetupCodeSyncedValue = '';
  String _gatewayHostSyncedValue = '';
  String _gatewayPortSyncedValue = '';
  late final List<_SecretFieldUiState> _gatewayTokenStates;
  late final List<_SecretFieldUiState> _gatewayPasswordStates;
  bool _aiGatewayTesting = false;
  String _aiGatewayTestState = 'idle';
  String _aiGatewayTestMessage = '';
  String _aiGatewayTestEndpoint = '';
  _GatewayIntegrationSubTab _integrationSubTab =
      _GatewayIntegrationSubTab.gateway;
  int _llmEndpointSlotLimit = 1;
  int _selectedLlmEndpointIndex = 0;
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
    _gatewaySetupCodeController = TextEditingController();
    _gatewayHostController = TextEditingController();
    _gatewayPortController = TextEditingController();
    _gatewayTokenControllers = List<TextEditingController>.generate(
      kGatewayProfileListLength,
      (_) => TextEditingController(),
      growable: false,
    );
    _gatewayPasswordControllers = List<TextEditingController>.generate(
      kGatewayProfileListLength,
      (_) => TextEditingController(),
      growable: false,
    );
    _gatewayTokenStates = List<_SecretFieldUiState>.filled(
      kGatewayProfileListLength,
      const _SecretFieldUiState(),
      growable: false,
    );
    _gatewayPasswordStates = List<_SecretFieldUiState>.filled(
      kGatewayProfileListLength,
      const _SecretFieldUiState(),
      growable: false,
    );
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
    _applyGatewayNavigationHints();
  }

  void _applyGatewayNavigationHints() {
    final detail = _detail;
    final navigationContext = _navigationContext;
    if (detail != SettingsDetailPage.gatewayConnection ||
        navigationContext == null) {
      return;
    }
    final gatewayProfileIndex = navigationContext.gatewayProfileIndex;
    if (gatewayProfileIndex == null) {
      return;
    }
    _selectedGatewayProfileIndex = gatewayProfileIndex.clamp(
      0,
      kGatewayProfileListLength - 1,
    );
  }

  bool _prefersGatewaySetupCodeForCurrentContext(BuildContext context) {
    return resolveUiFeaturePlatformFromContext(context) ==
            UiFeaturePlatform.mobile &&
        _detail == SettingsDetailPage.gatewayConnection &&
        _navigationContext?.prefersGatewaySetupCode == true &&
        _selectedGatewayProfileIndex != kGatewayLocalProfileIndex;
  }

  @override
  void dispose() {
    _aiGatewayNameController.dispose();
    _aiGatewayUrlController.dispose();
    _aiGatewayApiKeyRefController.dispose();
    _aiGatewayApiKeyController.dispose();
    _aiGatewayModelSearchController.dispose();
    _gatewaySetupCodeController.dispose();
    _gatewayHostController.dispose();
    _gatewayPortController.dispose();
    for (final controller in _gatewayTokenControllers) {
      controller.dispose();
    }
    for (final controller in _gatewayPasswordControllers) {
      controller.dispose();
    }
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
        _applyGatewayNavigationHints();
        final settings = controller.settingsDraft;
        final showingDetail = _detail != null;
        final showGlobalApplyBar =
            _tab != SettingsTab.gateway ||
            _integrationSubTab == _GatewayIntegrationSubTab.acp;
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
              if (showGlobalApplyBar) ...[
                _buildGlobalApplyBar(context, controller),
                const SizedBox(height: 16),
              ],
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
      return _buildDetailContent(
        context,
        controller,
        settings,
        uiFeatures,
        _detail!,
      );
    }

    return switch (_tab) {
      SettingsTab.general => _buildGeneral(
        context,
        controller,
        settings,
        uiFeatures,
      ),
      SettingsTab.workspace => _buildWorkspace(context, controller, settings),
      SettingsTab.gateway => _buildGateway(
        context,
        controller,
        settings,
        uiFeatures,
      ),
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
    UiFeatureAccess uiFeatures,
    SettingsDetailPage detail,
  ) {
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
        _buildOpenClawGatewayCard(context, controller, settings),
        if (uiFeatures.supportsVaultServer) ...[
          const SizedBox(height: 16),
          _buildVaultProviderCard(context, controller, settings),
        ],
        const SizedBox(height: 16),
        _buildLlmEndpointManager(context, controller, settings),
      ],
      SettingsDetailPage.aiGatewayIntegration => <Widget>[
        _buildDetailIntro(
          context,
          title: detail.label,
          description: appText(
            '把主 LLM API 与可选兼容端点统一收口成接入点列表。默认先显示主接入点，需要时可通过 + 扩展更多端点。',
            'Manage the primary LLM API and optional compatible endpoints from one endpoint list. Start with the primary entry and expand more endpoints with + when needed.',
          ),
        ),
        const SizedBox(height: 16),
        _buildLlmEndpointManager(context, controller, settings),
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
        if (uiFeatures.supportsVaultServer)
          _buildVaultProviderCard(context, controller, settings)
        else
          SurfaceCard(
            child: Text(
              appText(
                '当前发布配置未开放 Vault Server 参数。',
                'Vault Server settings are disabled in this release configuration.',
              ),
            ),
          ),
      ],
      SettingsDetailPage.externalAgents => <Widget>[
        _buildDetailIntro(
          context,
          title: detail.label,
          description: appText(
            '多 Agent 协作、角色编排和外部 Agent / ACP 连接的详细参数集中在这里。',
            'Detailed multi-agent collaboration, role orchestration, and external Agent / ACP connection settings are edited here.',
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

  Widget _buildGlobalApplyBar(BuildContext context, AppController controller) {
    final theme = Theme.of(context);
    final hasDraft = controller.hasSettingsDraftChanges;
    final hasPendingApply = controller.hasPendingSettingsApply;
    final message = controller.settingsDraftStatusMessage;
    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appText('设置提交流程', 'Settings Submission'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  message.isNotEmpty
                      ? message
                      : hasDraft
                      ? appText(
                          '当前存在未保存草稿。保存：仅保存配置，不立即生效。',
                          'There are unsaved drafts. Save persists configuration only and does not apply it immediately.',
                        )
                      : hasPendingApply
                      ? appText(
                          '当前存在已保存但未应用的更改。应用：立即按当前配置生效。',
                          'There are saved changes waiting to be applied. Apply makes the current configuration take effect immediately.',
                        )
                      : (message.isEmpty
                            ? appText(
                                '当前没有待提交更改。',
                                'There are no pending settings changes.',
                              )
                            : message),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton(
                key: const ValueKey('settings-global-save-button'),
                onPressed: hasDraft
                    ? () => _handleTopLevelSave(controller)
                    : null,
                child: Text(appText('保存', 'Save')),
              ),
              FilledButton.tonal(
                key: const ValueKey('settings-global-apply-button'),
                onPressed: (!hasDraft && !hasPendingApply)
                    ? null
                    : () => _handleTopLevelApply(controller),
                child: Text(appText('应用', 'Apply')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGeneral(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
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
            if (uiFeatures.supportsAccountAccess)
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
      if (uiFeatures.supportsAccountAccess)
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
            onChanged: (value) => _saveSettings(
              controller,
              settings.copyWith(launchAtLogin: value),
            ),
          ),
          _SwitchRow(
            label: appText('托盘菜单', 'Tray menu'),
            value: config.trayEnabled,
            onChanged: (value) => _saveSettings(
              controller,
              settings.copyWith(
                linuxDesktop: config.copyWith(trayEnabled: value),
              ),
            ),
          ),
          _EditableField(
            label: appText('隧道连接名称', 'Tunnel Connection Name'),
            value: config.vpnConnectionName,
            onSubmitted: (value) => _saveSettings(
              controller,
              settings.copyWith(
                linuxDesktop: config.copyWith(vpnConnectionName: value.trim()),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _EditableField(
                  label: appText('代理主机', 'Proxy Host'),
                  value: config.proxyHost,
                  onSubmitted: (value) => _saveSettings(
                    controller,
                    settings.copyWith(
                      linuxDesktop: config.copyWith(proxyHost: value.trim()),
                    ),
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
                    _saveSettings(
                      controller,
                      settings.copyWith(
                        linuxDesktop: config.copyWith(proxyPort: parsed),
                      ),
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
    ];
  }

  List<Widget> _buildGateway(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
  ) {
    final tabLabel = switch (_integrationSubTab) {
      _GatewayIntegrationSubTab.gateway => 'OpenClaw Gateway',
      _GatewayIntegrationSubTab.llm => appText('LLM 接入点', 'LLM Endpoints'),
      _GatewayIntegrationSubTab.acp => appText('ACP 外部接入', 'External ACP'),
      _GatewayIntegrationSubTab.skills => appText(
        'SKILLS 目录授权',
        'SKILLS Directory Authorization',
      ),
    };
    return [
      SectionTabs(
        items: <String>[
          'OpenClaw Gateway',
          appText('LLM 接入点', 'LLM Endpoints'),
          appText('ACP 外部接入', 'External ACP'),
          appText('SKILLS 目录授权', 'SKILLS Directory Authorization'),
        ],
        value: tabLabel,
        onChanged: (value) => setState(() {
          _integrationSubTab = switch (value) {
            'OpenClaw Gateway' => _GatewayIntegrationSubTab.gateway,
            _ when value == appText('LLM 接入点', 'LLM Endpoints') =>
              _GatewayIntegrationSubTab.llm,
            _ when value == appText('ACP 外部接入', 'External ACP') =>
              _GatewayIntegrationSubTab.acp,
            _ => _GatewayIntegrationSubTab.skills,
          };
        }),
      ),
      const SizedBox(height: 16),
      ...switch (_integrationSubTab) {
        _GatewayIntegrationSubTab.gateway => <Widget>[
          _buildCollapsibleGatewaySection(
            context: context,
            title: 'OpenClaw Gateway',
            expanded: _openClawGatewayExpanded,
            onChanged: (value) => setState(() {
              _openClawGatewayExpanded = value;
            }),
            child: _buildOpenClawGatewayCard(context, controller, settings),
          ),
          if (uiFeatures.supportsVaultServer) ...[
            const SizedBox(height: 16),
            _buildCollapsibleGatewaySection(
              context: context,
              title: appText('Vault Server', 'Vault Server'),
              expanded: _vaultServerExpanded,
              onChanged: (value) => setState(() {
                _vaultServerExpanded = value;
              }),
              child: _buildVaultProviderCard(context, controller, settings),
            ),
          ],
        ],
        _GatewayIntegrationSubTab.llm => <Widget>[
          _buildCollapsibleGatewaySection(
            context: context,
            title: appText('LLM 接入点', 'LLM Endpoints'),
            expanded: _aiGatewayExpanded,
            onChanged: (value) => setState(() {
              _aiGatewayExpanded = value;
            }),
            child: _buildLlmEndpointManager(context, controller, settings),
          ),
        ],
        _GatewayIntegrationSubTab.acp => <Widget>[
          _buildExternalAcpEndpointManager(context, controller, settings),
        ],
        _GatewayIntegrationSubTab.skills => <Widget>[
          SkillDirectoryAuthorizationCard(controller: controller),
        ],
      },
    ];
  }

  Widget _buildExternalAcpEndpointManager(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appText('外部 ACP Server Endpoint', 'External ACP Server Endpoints'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            appText(
              '这里仅保留 Codex、OpenCode 预设接入。历史上的 Claude / Gemini 预配置会迁移为自定义 ACP Server Endpoint。你可以继续添加多个自定义 Endpoint，协议支持 ws / wss / http / https。',
              'Only Codex and OpenCode stay as preset integrations here. Legacy Claude and Gemini entries are migrated into custom ACP server endpoints. You can add multiple custom endpoints with ws / wss / http / https.',
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const ValueKey('external-acp-provider-add-button'),
              onPressed: () => _saveSettings(
                controller,
                _appendExternalAcpProvider(settings),
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                appText(
                  '添加自定义 ACP Server Endpoint',
                  'Add custom ACP server endpoint',
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...settings.externalAcpEndpoints.map(
            (profile) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildExternalAcpProviderCard(
                context,
                controller,
                settings,
                profile,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExternalAcpProviderCard(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    ExternalAcpEndpointProfile profile,
  ) {
    final provider = profile.toProvider();
    final endpoint = profile.endpoint.trim();
    final configured = endpoint.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  provider.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (!profile.isPreset) ...[
                IconButton(
                  tooltip: appText('删除 Provider', 'Remove provider'),
                  onPressed: () => _saveSettings(
                    controller,
                    settings.copyWith(
                      externalAcpEndpoints: settings.externalAcpEndpoints
                          .where(
                            (item) => item.providerKey != profile.providerKey,
                          )
                          .toList(growable: false),
                    ),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                const SizedBox(width: 4),
              ],
              _StatusChip(
                label: configured
                    ? appText('已配置', 'Configured')
                    : appText('未配置', 'Empty'),
                tone: configured ? _StatusChipTone.ready : _StatusChipTone.idle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _EditableField(
            label: appText('显示名称', 'Display name'),
            value: profile.label,
            onSubmitted: (value) => _saveSettings(
              controller,
              settings.copyWithExternalAcpEndpointForProvider(
                provider,
                profile.copyWith(label: value),
              ),
            ),
          ),
          _EditableField(
            label: appText('ACP Server Endpoint', 'ACP Server Endpoint'),
            value: endpoint,
            onSubmitted: (value) => _saveSettings(
              controller,
              settings.copyWithExternalAcpEndpointForProvider(
                provider,
                profile.copyWith(endpoint: value),
              ),
            ),
          ),
          Text(
            appText(
              '示例：ws://127.0.0.1:9001、wss://acp.example.com/rpc、http://127.0.0.1:8080、https://agent.example.com',
              'Examples: ws://127.0.0.1:9001, wss://acp.example.com/rpc, http://127.0.0.1:8080, https://agent.example.com',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  SettingsSnapshot _appendExternalAcpProvider(SettingsSnapshot settings) {
    var suffix = settings.externalAcpEndpoints.length + 1;
    String providerKey() => 'custom-agent-$suffix';
    final existingKeys = settings.externalAcpEndpoints
        .map((item) => item.providerKey)
        .toSet();
    while (existingKeys.contains(providerKey())) {
      suffix += 1;
    }
    return settings.copyWith(
      externalAcpEndpoints: <ExternalAcpEndpointProfile>[
        ...settings.externalAcpEndpoints,
        ExternalAcpEndpointProfile(
          providerKey: providerKey(),
          label: appText(
            '自定义 ACP Endpoint $suffix',
            'Custom ACP Endpoint $suffix',
          ),
          badge: '',
          endpoint: '',
          enabled: true,
        ),
      ],
    );
  }

  Widget _buildLlmEndpointManager(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final visibleCount = _resolvedVisibleLlmEndpointCount(controller, settings);
    if (_selectedLlmEndpointIndex >= visibleCount) {
      _selectedLlmEndpointIndex = visibleCount - 1;
    }
    final activeSlot = _llmEndpointSlots[_selectedLlmEndpointIndex];
    final canExpand = visibleCount < _llmEndpointSlots.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List<Widget>.generate(visibleCount, (index) {
            return ChoiceChip(
              key: ValueKey('llm-endpoint-chip-$index'),
              selected: index == _selectedLlmEndpointIndex,
              avatar: const Icon(Icons.link_rounded, size: 18),
              label: Text(_llmEndpointChipLabel(controller, settings, index)),
              onSelected: (_) => setState(() {
                _selectedLlmEndpointIndex = index;
              }),
            );
          }),
        ),
        if (canExpand) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const ValueKey('llm-endpoint-add-button'),
              onPressed: () => setState(() {
                final nextCount = (_llmEndpointSlotLimit + 1).clamp(
                  1,
                  _llmEndpointSlots.length,
                );
                _llmEndpointSlotLimit = nextCount;
                _selectedLlmEndpointIndex = nextCount - 1;
              }),
              icon: const Icon(Icons.add_rounded),
              label: Text(appText('添加连接源', 'Add source')),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SurfaceCard(
          key: ValueKey('llm-endpoint-panel-${activeSlot.name}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appText('连接源详情', 'Source details'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _buildLlmEndpointBody(
                context,
                controller,
                settings,
                slot: activeSlot,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _llmEndpointChipLabel(
    AppController controller,
    SettingsSnapshot settings,
    int index,
  ) {
    final slot = _llmEndpointSlots[index];
    final configured = _isLlmEndpointSlotConfigured(controller, settings, slot);
    final label = switch (slot) {
      _LlmEndpointSlot.aiGateway => appText('主 LLM API', 'Primary LLM API'),
      _LlmEndpointSlot.ollamaLocal => appText('Ollama 本地', 'Ollama Local'),
      _LlmEndpointSlot.ollamaCloud => appText('Ollama Cloud', 'Ollama Cloud'),
    };
    return appText(
      configured ? label : '$label（空）',
      configured ? label : '$label (empty)',
    );
  }

  Widget _buildLlmEndpointBody(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings, {
    required _LlmEndpointSlot slot,
  }) {
    return switch (slot) {
      _LlmEndpointSlot.aiGateway => _buildAiGatewayCardBody(
        context,
        controller,
        settings,
      ),
      _LlmEndpointSlot.ollamaLocal => _buildOllamaLocalEndpointBody(
        context,
        controller,
        settings,
      ),
      _LlmEndpointSlot.ollamaCloud => _buildOllamaCloudEndpointBody(
        context,
        controller,
        settings,
      ),
    };
  }

  Widget _buildCollapsibleGatewaySection({
    required BuildContext context,
    required String title,
    required bool expanded,
    required ValueChanged<bool> onChanged,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onChanged(!expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: expanded
                        ? appText('折叠', 'Collapse')
                        : appText('展开', 'Expand'),
                    onPressed: () => onChanged(!expanded),
                    icon: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: const Icon(Icons.expand_more_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: expanded ? child : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildOpenClawGatewayCard(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    return SurfaceCard(
      child: _buildOpenClawGatewayCardBody(context, controller, settings),
    );
  }

  Widget _buildOpenClawGatewayCardBody(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    _syncGatewayDraftControllers(settings);
    final theme = Theme.of(context);
    final gatewayProfiles = settings.gatewayProfiles;
    final selectedProfileIndex = _selectedGatewayProfileIndex.clamp(
      0,
      gatewayProfiles.length - 1,
    );
    final gatewayProfile = gatewayProfiles[selectedProfileIndex];
    final gatewayMode = _gatewayProfileModeForSlot(
      selectedProfileIndex,
      gatewayProfile,
    );
    final gatewayTokenController =
        _gatewayTokenControllers[selectedProfileIndex];
    final gatewayPasswordController =
        _gatewayPasswordControllers[selectedProfileIndex];
    final gatewayTokenState = _gatewayTokenStates[selectedProfileIndex];
    final gatewayPasswordState = _gatewayPasswordStates[selectedProfileIndex];
    final uiFeatures = controller.featuresFor(
      resolveUiFeaturePlatformFromContext(context),
    );
    final setupCodeFeatureEnabled = uiFeatures.supportsGatewaySetupCode;
    final forceSetupCodeMode = _prefersGatewaySetupCodeForCurrentContext(
      context,
    );
    final useSetupCode = selectedProfileIndex == kGatewayLocalProfileIndex
        ? false
        : forceSetupCodeMode ||
              (setupCodeFeatureEnabled && gatewayProfile.useSetupCode);
    final gatewayTls = gatewayMode == RuntimeConnectionMode.local
        ? false
        : gatewayProfile.tls;
    final hasStoredGatewayToken = controller.hasStoredGatewayTokenForProfile(
      selectedProfileIndex,
    );
    final hasStoredGatewayPassword = controller
        .hasStoredGatewayPasswordForProfile(selectedProfileIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appText(
            '这里维护外部 Gateway / ACP endpoint 连接源 profile。工作模式在会话区单独切换：single-agent 通过标准 ACP 协议直连外部 Agent；local/remote 继续走 Gateway。保存：仅保存配置，不立即生效。应用：立即按当前配置生效。',
            'This card edits external Gateway / ACP endpoint profiles. Work mode is switched in the session UI: single-agent connects to an external Agent over the standard ACP protocol, while local/remote continue through Gateway. Save persists configuration only, while Apply makes it take effect immediately.',
          ),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List<Widget>.generate(gatewayProfiles.length, (index) {
            final profile = gatewayProfiles[index];
            final configured =
                profile.setupCode.trim().isNotEmpty ||
                profile.host.trim().isNotEmpty;
            return ChoiceChip(
              key: ValueKey('gateway-profile-chip-$index'),
              selected: index == selectedProfileIndex,
              avatar: Icon(switch (index) {
                kGatewayLocalProfileIndex => Icons.computer_rounded,
                kGatewayRemoteProfileIndex => Icons.cloud_outlined,
                _ => Icons.link_rounded,
              }, size: 18),
              label: Text(
                _gatewayProfileChipLabel(index, configured: configured),
              ),
              onSelected: (_) {
                setState(() {
                  _selectedGatewayProfileIndex = index;
                  _gatewayTestState = 'idle';
                  _gatewayTestMessage = '';
                  _gatewayTestEndpoint = '';
                });
              },
            );
          }),
        ),
        const SizedBox(height: 12),
        Text(
          _gatewayProfileSlotDescription(selectedProfileIndex),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (selectedProfileIndex != kGatewayLocalProfileIndex &&
            !forceSetupCodeMode &&
            setupCodeFeatureEnabled) ...[
          SectionTabs(
            items: [appText('配置码', 'Setup Code'), appText('手动配置', 'Manual')],
            value: useSetupCode
                ? appText('配置码', 'Setup Code')
                : appText('手动配置', 'Manual'),
            size: SectionTabsSize.small,
            onChanged: (value) {
              final nextUseSetupCode = value == appText('配置码', 'Setup Code');
              unawaited(
                _saveGatewayProfile(
                  controller,
                  settings,
                  gatewayProfile.copyWith(useSetupCode: nextUseSetupCode),
                ).catchError((_) {}),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        if (selectedProfileIndex != kGatewayLocalProfileIndex &&
            useSetupCode) ...[
          TextField(
            key: const ValueKey('gateway-setup-code-field'),
            controller: _gatewaySetupCodeController,
            autofocus: forceSetupCodeMode,
            minLines: 4,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: appText('配置码', 'Setup Code'),
              hintText: appText(
                '粘贴 Gateway 配置码或 JSON 负载',
                'Paste gateway setup code or JSON payload',
              ),
            ),
            onChanged: (_) => unawaited(
              _saveGatewayDraft(controller, settings).catchError((_) {}),
            ),
            onSubmitted: (_) => _saveGatewayDraft(controller, settings),
          ),
        ] else ...[
          TextField(
            key: const ValueKey('gateway-host-field'),
            controller: _gatewayHostController,
            decoration: InputDecoration(labelText: appText('主机', 'Host')),
            onChanged: (_) => unawaited(
              _saveGatewayDraft(controller, settings).catchError((_) {}),
            ),
            onSubmitted: (_) => _saveGatewayDraft(controller, settings),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: const ValueKey('gateway-port-field'),
                  controller: _gatewayPortController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: appText('端口', 'Port')),
                  onChanged: (_) => unawaited(
                    _saveGatewayDraft(controller, settings).catchError((_) {}),
                  ),
                  onSubmitted: (_) => _saveGatewayDraft(controller, settings),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Opacity(
                  opacity: gatewayMode == RuntimeConnectionMode.local ? 0.6 : 1,
                  child: _InlineSwitchField(
                    label: 'TLS',
                    value: gatewayTls,
                    onChanged: (value) {
                      if (gatewayMode == RuntimeConnectionMode.local) {
                        return;
                      }
                      unawaited(
                        _saveGatewayProfile(
                          controller,
                          settings,
                          gatewayProfile.copyWith(tls: value),
                        ).catchError((_) {}),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _buildSecureField(
          fieldKey: const ValueKey('gateway-shared-token-field'),
          controller: gatewayTokenController,
          label: appText('共享 Token', 'Shared Token'),
          hasStoredValue: hasStoredGatewayToken,
          fieldState: gatewayTokenState,
          onStateChanged: (value) =>
              setState(() => _gatewayTokenStates[selectedProfileIndex] = value),
          loadValue: () => controller.settingsController.loadGatewayToken(
            profileIndex: selectedProfileIndex,
          ),
          onSubmitted: (value) async => controller.saveGatewayTokenDraft(
            value,
            profileIndex: selectedProfileIndex,
          ),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示；可直接测试，也可通过本区保存/应用提交。',
            'Stored securely. Test directly or submit with local Save / Apply actions.',
          ),
          emptyHelperText: appText(
            '输入后先进入草稿；通过本区保存/应用提交。',
            'Values stage into draft first; submit with local Save / Apply actions.',
          ),
        ),
        const SizedBox(height: 12),
        _buildSecureField(
          fieldKey: const ValueKey('gateway-password-field'),
          controller: gatewayPasswordController,
          label: appText('密码', 'Password'),
          hasStoredValue: hasStoredGatewayPassword,
          fieldState: gatewayPasswordState,
          onStateChanged: (value) => setState(
            () => _gatewayPasswordStates[selectedProfileIndex] = value,
          ),
          loadValue: () => controller.settingsController.loadGatewayPassword(
            profileIndex: selectedProfileIndex,
          ),
          onSubmitted: (value) async => controller.saveGatewayPasswordDraft(
            value,
            profileIndex: selectedProfileIndex,
          ),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示；可直接测试，也可通过本区保存/应用提交。',
            'Stored securely. Test directly or submit with local Save / Apply actions.',
          ),
          emptyHelperText: appText(
            '输入后先进入草稿；通过本区保存/应用提交。',
            'Values stage into draft first; submit with local Save / Apply actions.',
          ),
        ),
        const SizedBox(height: 16),
        _buildSettingsSectionActions(
          controller: controller,
          testKey: const ValueKey('gateway-test-button'),
          saveKey: const ValueKey('gateway-save-button'),
          applyKey: const ValueKey('gateway-apply-button'),
          testing: _gatewayTesting,
          onTest: () => _testGatewayConnection(controller, settings),
          onSave: () => _saveGatewayAndPersist(controller, settings),
          onApply: () => _saveGatewayAndApply(controller, settings),
        ),
        const SizedBox(height: 16),
        _buildDeviceSecurityCard(context, controller),
        if (_gatewayTestMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildNotice(
            context,
            tone: _gatewayTestState == 'success'
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.errorContainer,
            title: appText('测试连接', 'Test Connection'),
            message: _gatewayTestEndpoint.isEmpty
                ? _gatewayTestMessage
                : '$_gatewayTestMessage\n$_gatewayTestEndpoint',
          ),
        ],
      ],
    );
  }

  Widget _buildVaultProviderCard(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    return SurfaceCard(
      child: _buildVaultProviderCardBody(context, controller, settings),
    );
  }

  Widget _buildVaultProviderCardBody(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final hasStoredVaultToken =
        controller.settingsController.secureRefs['vault_token'] != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditableField(
          label: appText('地址', 'Address'),
          value: settings.vault.address,
          onSubmitted: (value) => _saveSettings(
            controller,
            settings.copyWith(vault: settings.vault.copyWith(address: value)),
          ),
        ),
        _EditableField(
          label: appText('命名空间', 'Namespace'),
          value: settings.vault.namespace,
          onSubmitted: (value) => _saveSettings(
            controller,
            settings.copyWith(vault: settings.vault.copyWith(namespace: value)),
          ),
        ),
        _EditableField(
          label: appText('认证模式', 'Auth Mode'),
          value: settings.vault.authMode,
          onSubmitted: (value) => _saveSettings(
            controller,
            settings.copyWith(vault: settings.vault.copyWith(authMode: value)),
          ),
        ),
        _EditableField(
          label: appText('Token 引用', 'Token Ref'),
          value: settings.vault.tokenRef,
          onSubmitted: (value) => _saveSettings(
            controller,
            settings.copyWith(vault: settings.vault.copyWith(tokenRef: value)),
          ),
        ),
        _buildSecureField(
          controller: _vaultTokenController,
          label:
              '${appText('Vault Token', 'Vault Token')} (${settings.vault.tokenRef})',
          hasStoredValue: hasStoredVaultToken,
          fieldState: _vaultTokenState,
          onStateChanged: (value) => setState(() => _vaultTokenState = value),
          loadValue: controller.settingsController.loadVaultToken,
          onSubmitted: (value) async => controller.saveVaultTokenDraft(value),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示，点击查看后读取真实值。',
            'Stored securely. Shows as **** until you reveal it.',
          ),
          emptyHelperText: appText(
            '输入后先进入草稿；保存后才会写入安全存储。',
            'Values stage into draft first and only persist to secure storage after Save.',
          ),
        ),
        const SizedBox(height: 12),
        _buildSettingsSectionActions(
          controller: controller,
          testKey: const ValueKey('vault-test-button'),
          saveKey: const ValueKey('vault-save-button'),
          applyKey: const ValueKey('vault-apply-button'),
          onTest: () => _testVaultConnection(controller, settings),
          onSave: () => _handleTopLevelSave(controller),
          onApply: () => _handleTopLevelApply(controller),
          testLabel:
              '${appText('测试连接', 'Test Connection')} · ${controller.settingsController.vaultStatus}',
        ),
      ],
    );
  }

  Widget _buildAiGatewayCardBody(
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
    final statusTheme = _aiGatewayFeedbackTheme(
      context,
      _aiGatewayTestMessage.isEmpty
          ? settings.aiGateway.syncState
          : _aiGatewayTestState,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('ai-gateway-name-field'),
          controller: _aiGatewayNameController,
          decoration: InputDecoration(
            labelText: appText('配置名称', 'Profile Name'),
          ),
          onChanged: (_) => unawaited(
            _saveAiGatewayDraft(controller, settings).catchError((_) {}),
          ),
          onSubmitted: (_) => _saveAiGatewayDraft(controller, settings),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('ai-gateway-url-field'),
          controller: _aiGatewayUrlController,
          decoration: InputDecoration(
            labelText: appText('LLM API Endpoint', 'LLM API Endpoint'),
          ),
          onChanged: (_) => unawaited(
            _saveAiGatewayDraft(controller, settings).catchError((_) {}),
          ),
          onSubmitted: (_) => _saveAiGatewayDraft(controller, settings),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('ai-gateway-api-key-ref-field'),
          controller: _aiGatewayApiKeyRefController,
          decoration: InputDecoration(
            labelText: appText('LLM API Token 引用', 'LLM API Token Ref'),
          ),
          onChanged: (_) => unawaited(
            _saveAiGatewayDraft(controller, settings).catchError((_) {}),
          ),
          onSubmitted: (_) => _saveAiGatewayDraft(controller, settings),
        ),
        _buildSecureField(
          fieldKey: const ValueKey('ai-gateway-api-key-field'),
          controller: _aiGatewayApiKeyController,
          label:
              '${appText('LLM API Token', 'LLM API Token')} (${_aiGatewayApiKeyRefController.text.trim().isEmpty ? settings.aiGateway.apiKeyRef : _aiGatewayApiKeyRefController.text.trim()})',
          hasStoredValue: hasStoredAiGatewayApiKey,
          fieldState: _aiGatewayApiKeyState,
          onStateChanged: (value) =>
              setState(() => _aiGatewayApiKeyState = value),
          loadValue: controller.settingsController.loadAiGatewayApiKey,
          onSubmitted: (value) async =>
              controller.saveAiGatewayApiKeyDraft(value),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示；可直接测试，也可通过本区保存/应用提交。',
            'Stored securely. Test directly or submit it with the local Save / Apply actions.',
          ),
          emptyHelperText: appText(
            '输入后可直接测试，也可通过本区保存/应用提交。',
            'Test it now, or submit it with the local Save / Apply actions.',
          ),
        ),
        const SizedBox(height: 12),
        _buildSettingsSectionActions(
          controller: controller,
          testKey: const ValueKey('ai-gateway-test-button'),
          saveKey: const ValueKey('ai-gateway-save-button'),
          applyKey: const ValueKey('ai-gateway-apply-button'),
          testing: _aiGatewayTesting,
          onTest: () => _testAiGatewayConnection(controller, settings),
          onSave: () => _saveAiGatewayAndPersist(controller, settings),
          onApply: () => _saveAiGatewayAndApply(controller, settings),
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
              suffixIcon: _aiGatewayModelSearchController.text.trim().isEmpty
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
    );
  }

  Widget _buildOllamaLocalEndpointBody(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              ollamaLocal: settings.ollamaLocal.copyWith(defaultModel: value),
            ),
          ),
        ),
        _SwitchRow(
          label: appText('自动发现', 'Auto Discover'),
          value: settings.ollamaLocal.autoDiscover,
          onChanged: (value) => _saveSettings(
            controller,
            settings.copyWith(
              ollamaLocal: settings.ollamaLocal.copyWith(autoDiscover: value),
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
    );
  }

  Widget _buildOllamaCloudEndpointBody(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final hasStoredOllamaApiKey =
        controller.settingsController.secureRefs['ollama_cloud_api_key'] !=
        null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              ollamaCloud: settings.ollamaCloud.copyWith(defaultModel: value),
            ),
          ),
        ),
        _buildSecureField(
          controller: _ollamaApiKeyController,
          label:
              '${appText('API Key', 'API Key')} (${settings.ollamaCloud.apiKeyRef})',
          hasStoredValue: hasStoredOllamaApiKey,
          fieldState: _ollamaApiKeyState,
          onStateChanged: (value) => setState(() => _ollamaApiKeyState = value),
          loadValue: controller.settingsController.loadOllamaCloudApiKey,
          onSubmitted: (value) async =>
              controller.saveOllamaCloudApiKeyDraft(value),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示；可直接测试，也可通过本区保存/应用提交。',
            'Stored securely. Test directly or submit it with the local Save / Apply actions.',
          ),
          emptyHelperText: appText(
            '输入后可直接测试，也可通过本区保存/应用提交。',
            'Test it now, or submit it with the local Save / Apply actions.',
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => controller.testOllamaConnection(cloud: true),
            child: Text(
              '${appText('测试云端', 'Test Cloud')} · ${controller.settingsController.ollamaStatus}',
            ),
          ),
        ),
      ],
    );
  }

  int _resolvedVisibleLlmEndpointCount(
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final requiredCount = _requiredLlmEndpointSlotCount(controller, settings);
    return requiredCount > _llmEndpointSlotLimit
        ? requiredCount
        : _llmEndpointSlotLimit;
  }

  int _requiredLlmEndpointSlotCount(
    AppController controller,
    SettingsSnapshot settings,
  ) {
    var requiredCount = 1;
    if (_isOllamaLocalEndpointConfigured(settings)) {
      requiredCount = 2;
    }
    if (_isOllamaCloudEndpointConfigured(controller, settings)) {
      requiredCount = 3;
    }
    return requiredCount;
  }

  bool _isLlmEndpointSlotConfigured(
    AppController controller,
    SettingsSnapshot settings,
    _LlmEndpointSlot slot,
  ) {
    return switch (slot) {
      _LlmEndpointSlot.aiGateway => _isAiGatewayEndpointConfigured(
        controller,
        settings,
      ),
      _LlmEndpointSlot.ollamaLocal => _isOllamaLocalEndpointConfigured(
        settings,
      ),
      _LlmEndpointSlot.ollamaCloud => _isOllamaCloudEndpointConfigured(
        controller,
        settings,
      ),
    };
  }

  bool _isAiGatewayEndpointConfigured(
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final defaults = AiGatewayProfile.defaults();
    final config = settings.aiGateway;
    return config.name.trim() != defaults.name ||
        config.baseUrl.trim().isNotEmpty ||
        config.apiKeyRef.trim() != defaults.apiKeyRef ||
        config.availableModels.isNotEmpty ||
        config.selectedModels.isNotEmpty ||
        controller.settingsController.secureRefs['ai_gateway_api_key'] != null;
  }

  bool _isOllamaLocalEndpointConfigured(SettingsSnapshot settings) {
    final defaults = OllamaLocalConfig.defaults();
    final config = settings.ollamaLocal;
    return config.endpoint.trim() != defaults.endpoint ||
        config.defaultModel.trim() != defaults.defaultModel ||
        config.autoDiscover != defaults.autoDiscover;
  }

  bool _isOllamaCloudEndpointConfigured(
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final defaults = OllamaCloudConfig.defaults();
    final config = settings.ollamaCloud;
    return config.baseUrl.trim() != defaults.baseUrl ||
        config.organization.trim().isNotEmpty ||
        config.workspace.trim().isNotEmpty ||
        config.defaultModel.trim() != defaults.defaultModel ||
        config.apiKeyRef.trim() != defaults.apiKeyRef ||
        controller.settingsController.secureRefs['ollama_cloud_api_key'] !=
            null;
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
                        'App 作为统一发现与分发中心，维护托管 skills、MCP server list 和 LLM API 默认注入，但不会覆盖用户原有 CLI 配置。',
                        'The app acts as the discovery and distribution center for managed skills, MCP server lists, and LLM API defaults without overwriting existing CLI config.',
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
                labelText: appText('LLM API 注入策略', 'LLM API Injection'),
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
                  'ARIS 模式会把内嵌 skills 与 Go core reviewer 作为本地 Ollama 协作增强层，不会覆盖你原有的 CLI 全局配置。',
                  'ARIS mode injects embedded skills and the Go core reviewer for local Ollama collaboration without overwriting your existing CLI global config.',
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
            if (kAppStoreDistribution) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  appText(
                    '当前构建启用了 App Store 分发策略：Apple 渠道会隐藏实验入口，并禁用外部 CLI / 本地 Runtime 能力。',
                    'This build enables the App Store distribution policy: Apple storefront builds hide experimental surfaces and disable external CLI / local runtime capabilities.',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('隐私政策', 'Privacy Policy'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              appText(
                '说明本应用会保存哪些本地设置、哪些用户数据会按你的操作发送到外部网关或 LLM 端点，以及如何清除本地数据。',
                'Explains which settings stay on-device, which user data is sent to your configured gateway or LLM endpoints, and how to clear local data.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              key: const ValueKey('settings-open-privacy-policy'),
              onPressed: () => _showPrivacyPolicyDialog(context),
              icon: const Icon(Icons.privacy_tip_outlined),
              label: Text(appText('查看隐私政策', 'View Privacy Policy')),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _showPrivacyPolicyDialog(BuildContext context) {
    final theme = Theme.of(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(appText('隐私政策', 'Privacy Policy')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Text(
                appText(_privacyPolicyZh, _privacyPolicyEn),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(appText('关闭', 'Close')),
            ),
          ],
        );
      },
    );
  }

  static const String _privacyPolicyZh = '''
XWorkmate 隐私政策

1. 本地保存
- 应用会在本机保存你主动配置的工作区设置、界面偏好、线程草稿和诊断状态。
- 共享 Token、密码、API Key 等敏感信息使用系统安全存储；不会写入普通 SharedPreferences。

2. 发送到外部服务的数据
- 只有在你主动发起连接、发送消息、上传附件或测试连接时，应用才会把当前输入内容发送到你配置的 OpenClaw Gateway 或 LLM API Endpoint。
- 发送内容可能包括：提示词、会话上下文、你明确选择的附件路径与文件内容、以及完成请求所需的认证头。

3. 不会做的事情
- 不会接入广告 SDK，不会做跨应用追踪，不会在未操作时自动读取工作区文件。
- 不会把你的网关密码、共享 Token 或 LLM API Token 上传到本项目默认的开发者服务。

4. 第三方处理
- 你配置的 OpenClaw Gateway、LLM API Endpoint、对象存储或其它外部服务，将按你自己的服务条款处理收到的数据。
- 你需要确认这些外部服务具备你要求的合规能力。

5. 删除与撤回
- 你可以在“设置 -> 诊断/集成”中清除本地线程、移除本地配置，并删除已保存的安全凭据。
- 如果你希望删除已经发送到外部服务的数据，需要在对应外部服务侧执行删除或撤回。
''';

  static const String _privacyPolicyEn = '''
XWorkmate Privacy Policy

1. Local storage
- The app stores the settings, UI preferences, draft threads, and diagnostic state that you explicitly save on this device.
- Shared tokens, passwords, and API keys are stored in platform secure storage instead of plain SharedPreferences.

2. Data sent to external services
- Data is only sent when you explicitly connect, send a message, attach a file, or run a connection test against your configured OpenClaw Gateway or LLM API endpoint.
- Sent data can include prompts, conversation context, user-selected attachment paths and file contents, and the authentication headers required to complete the request.

3. What the app does not do
- It does not include advertising SDKs, cross-app tracking, or automatic workspace file reads without a user action.
- It does not upload your gateway passwords, shared tokens, or LLM API tokens to developer-operated services by default.

4. Third-party processing
- Your configured OpenClaw Gateway, LLM API endpoint, object storage, or other external services process the data you send under their own terms.
- You are responsible for confirming that those external services meet your compliance requirements.

5. Deletion and withdrawal
- You can clear local threads, remove local settings, and delete stored secrets from Settings.
- If you need data removed from an external service, you must request deletion from that external service directly.
''';

  Future<void> _saveSettings(
    AppController controller,
    SettingsSnapshot snapshot,
  ) {
    return controller.saveSettingsDraft(snapshot);
  }

  Future<void> _handleTopLevelSave(AppController controller) async {
    await _captureVisibleSecretDrafts(controller);
    await controller.persistSettingsDraft();
    if (!mounted) {
      return;
    }
    setState(() {
      _resetSecureFieldUiAfterPersist(controller);
    });
  }

  Future<void> _handleTopLevelApply(AppController controller) async {
    await _captureVisibleSecretDrafts(controller);
    await controller.applySettingsDraft();
    if (!mounted) {
      return;
    }
    setState(() {
      _resetSecureFieldUiAfterPersist(controller);
    });
  }

  Future<void> _captureVisibleSecretDrafts(AppController controller) async {
    for (var index = 0; index < kGatewayProfileListLength; index += 1) {
      final gatewayToken = _secretOverride(
        _gatewayTokenControllers[index],
        _gatewayTokenStates[index],
      );
      if (gatewayToken.isNotEmpty) {
        controller.saveGatewayTokenDraft(gatewayToken, profileIndex: index);
      }
      final gatewayPassword = _secretOverride(
        _gatewayPasswordControllers[index],
        _gatewayPasswordStates[index],
      );
      if (gatewayPassword.isNotEmpty) {
        controller.saveGatewayPasswordDraft(
          gatewayPassword,
          profileIndex: index,
        );
      }
    }
    final aiGatewayApiKey = _secretOverride(
      _aiGatewayApiKeyController,
      _aiGatewayApiKeyState,
    );
    if (aiGatewayApiKey.isNotEmpty) {
      controller.saveAiGatewayApiKeyDraft(aiGatewayApiKey);
    }
    final vaultToken = _secretOverride(_vaultTokenController, _vaultTokenState);
    if (vaultToken.isNotEmpty) {
      controller.saveVaultTokenDraft(vaultToken);
    }
    final ollamaApiKey = _secretOverride(
      _ollamaApiKeyController,
      _ollamaApiKeyState,
    );
    if (ollamaApiKey.isNotEmpty) {
      controller.saveOllamaCloudApiKeyDraft(ollamaApiKey);
    }
  }

  void _resetSecureFieldUiAfterPersist(AppController controller) {
    final hasStoredAiGatewayApiKey =
        controller.settingsController.secureRefs['ai_gateway_api_key'] != null;
    final hasStoredVaultToken =
        controller.settingsController.secureRefs['vault_token'] != null;
    final hasStoredOllamaApiKey =
        controller.settingsController.secureRefs['ollama_cloud_api_key'] !=
        null;
    for (var index = 0; index < kGatewayProfileListLength; index += 1) {
      _gatewayTokenStates[index] = const _SecretFieldUiState();
      _gatewayPasswordStates[index] = const _SecretFieldUiState();
      _primeSecureFieldController(
        _gatewayTokenControllers[index],
        hasStoredValue: controller.hasStoredGatewayTokenForProfile(index),
        fieldState: _gatewayTokenStates[index],
      );
      _primeSecureFieldController(
        _gatewayPasswordControllers[index],
        hasStoredValue: controller.hasStoredGatewayPasswordForProfile(index),
        fieldState: _gatewayPasswordStates[index],
      );
    }
    _aiGatewayApiKeyState = const _SecretFieldUiState();
    _vaultTokenState = const _SecretFieldUiState();
    _ollamaApiKeyState = const _SecretFieldUiState();
    _primeSecureFieldController(
      _aiGatewayApiKeyController,
      hasStoredValue: hasStoredAiGatewayApiKey,
      fieldState: _aiGatewayApiKeyState,
    );
    _primeSecureFieldController(
      _vaultTokenController,
      hasStoredValue: hasStoredVaultToken,
      fieldState: _vaultTokenState,
    );
    _primeSecureFieldController(
      _ollamaApiKeyController,
      hasStoredValue: hasStoredOllamaApiKey,
      fieldState: _ollamaApiKeyState,
    );
  }

  void _syncGatewayDraftControllers(SettingsSnapshot settings) {
    final current = _selectedGatewayProfile(settings);
    _syncDraftControllerValue(
      _gatewaySetupCodeController,
      current.setupCode,
      syncedValue: _gatewaySetupCodeSyncedValue,
      onSyncedValueChanged: (value) => _gatewaySetupCodeSyncedValue = value,
    );
    _syncDraftControllerValue(
      _gatewayHostController,
      current.host,
      syncedValue: _gatewayHostSyncedValue,
      onSyncedValueChanged: (value) => _gatewayHostSyncedValue = value,
    );
    _syncDraftControllerValue(
      _gatewayPortController,
      '${current.port}',
      syncedValue: _gatewayPortSyncedValue,
      onSyncedValueChanged: (value) => _gatewayPortSyncedValue = value,
    );
  }

  GatewayConnectionProfile _selectedGatewayProfile(SettingsSnapshot settings) {
    final profiles = settings.gatewayProfiles;
    final index = _selectedGatewayProfileIndex.clamp(0, profiles.length - 1);
    return profiles[index];
  }

  RuntimeConnectionMode _gatewayProfileModeForSlot(
    int index,
    GatewayConnectionProfile profile,
  ) {
    if (index == kGatewayLocalProfileIndex) {
      return RuntimeConnectionMode.local;
    }
    if (index == kGatewayRemoteProfileIndex) {
      return RuntimeConnectionMode.remote;
    }
    return switch (profile.mode) {
      RuntimeConnectionMode.local => RuntimeConnectionMode.local,
      RuntimeConnectionMode.remote => RuntimeConnectionMode.remote,
      RuntimeConnectionMode.unconfigured =>
        profile.host.trim().isNotEmpty || profile.setupCode.trim().isNotEmpty
            ? RuntimeConnectionMode.remote
            : RuntimeConnectionMode.unconfigured,
    };
  }

  String _gatewayProfileSlotLabel(int index) {
    return switch (index) {
      kGatewayLocalProfileIndex => appText(
        '本地 OpenClaw Gateway',
        'Local OpenClaw Gateway',
      ),
      kGatewayRemoteProfileIndex => appText(
        '远程 OpenClaw Gateway',
        'Remote OpenClaw Gateway',
      ),
      _ => appText(
        '自定义连接源 ${index - kGatewayCustomProfileStartIndex + 1}',
        'Custom source ${index - kGatewayCustomProfileStartIndex + 1}',
      ),
    };
  }

  String _gatewayProfileChipLabel(int index, {required bool configured}) {
    final label = switch (index) {
      kGatewayLocalProfileIndex => _gatewayProfileSlotLabel(index),
      kGatewayRemoteProfileIndex => _gatewayProfileSlotLabel(index),
      _ => appText(
        '连接源 ${index - kGatewayCustomProfileStartIndex + 1}',
        'Source ${index - kGatewayCustomProfileStartIndex + 1}',
      ),
    };
    return appText(
      configured ? label : '$label（空）',
      configured ? label : '$label (empty)',
    );
  }

  String _gatewayProfileSlotDescription(int index) {
    return switch (index) {
      kGatewayLocalProfileIndex => appText(
        '固定本地连接源，默认 127.0.0.1:18789。这里只维护本地源参数，不切换当前工作模式。',
        'Fixed local source with default 127.0.0.1:18789. This card edits the local source only and does not switch the current work mode.',
      ),
      kGatewayRemoteProfileIndex => appText(
        '固定远程连接源，默认 openclaw.svc.plus:443。这里只维护远程源参数，不切换当前工作模式。',
        'Fixed remote source with default openclaw.svc.plus:443. This card edits the remote source only and does not switch the current work mode.',
      ),
      _ => appText(
        '预留自定义 OpenClaw 连接源槽位。当前版本先做配置存储，不绑定固定工作模式。',
        'Reserved custom OpenClaw source slot. In this build it stores connection settings only and is not bound to a fixed work mode.',
      ),
    };
  }

  GatewayConnectionProfile _buildGatewayDraftProfile(
    SettingsSnapshot settings,
  ) {
    final current = _selectedGatewayProfile(settings);
    final mode = _gatewayProfileModeForSlot(
      _selectedGatewayProfileIndex,
      current,
    );
    final forceSetupCodeMode =
        _navigationContext?.prefersGatewaySetupCode == true &&
        _detail == SettingsDetailPage.gatewayConnection &&
        _selectedGatewayProfileIndex != kGatewayLocalProfileIndex;
    final useSetupCode = mode == RuntimeConnectionMode.local
        ? false
        : forceSetupCodeMode || current.useSetupCode;
    final tls = mode == RuntimeConnectionMode.local ? false : current.tls;
    final parsedPort = int.tryParse(_gatewayPortController.text.trim());
    final decoded = useSetupCode
        ? decodeGatewaySetupCode(_gatewaySetupCodeController.text)
        : null;
    final fallbackPort = switch (mode) {
      RuntimeConnectionMode.local => 18789,
      RuntimeConnectionMode.remote => tls ? 443 : current.port,
      RuntimeConnectionMode.unconfigured => 443,
    };
    return current.copyWith(
      mode: mode,
      useSetupCode: useSetupCode,
      setupCode: useSetupCode ? _gatewaySetupCodeController.text.trim() : '',
      host: useSetupCode
          ? (decoded?.host ?? current.host)
          : _gatewayHostController.text.trim(),
      port: useSetupCode
          ? (decoded?.port ?? current.port)
          : (parsedPort ?? fallbackPort),
      tls: useSetupCode ? (decoded?.tls ?? tls) : tls,
    );
  }

  Future<void> _saveGatewayProfile(
    AppController controller,
    SettingsSnapshot settings,
    GatewayConnectionProfile profile,
  ) async {
    final nextSettings = settings.copyWithGatewayProfileAt(
      _selectedGatewayProfileIndex,
      profile,
    );
    await _saveSettings(controller, nextSettings);
    if (!mounted) {
      return;
    }
    setState(() {
      _gatewaySetupCodeSyncedValue = profile.setupCode;
      _gatewayHostSyncedValue = profile.host;
      _gatewayPortSyncedValue = '${profile.port}';
      _gatewayTestState = 'idle';
      _gatewayTestMessage = '';
      _gatewayTestEndpoint = '';
    });
  }

  Future<void> _saveGatewayDraft(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final profile = _buildGatewayDraftProfile(settings);
    await _saveGatewayProfile(controller, settings, profile);
  }

  Future<void> _saveGatewayAndPersist(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    await _saveGatewayDraft(controller, settings);
    await _handleTopLevelSave(controller);
  }

  Future<void> _saveGatewayAndApply(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    await _saveGatewayDraft(controller, settings);
    await _handleTopLevelApply(controller);
  }

  Future<void> _saveAiGatewayAndPersist(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    await _saveAiGatewayDraft(controller, settings);
    await _handleTopLevelSave(controller);
  }

  Future<void> _saveAiGatewayAndApply(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    await _saveAiGatewayDraft(controller, settings);
    await _handleTopLevelApply(controller);
  }

  Future<void> _saveMultiAgentConfig(
    AppController controller,
    MultiAgentConfig config,
  ) {
    return controller.saveSettingsDraft(
      controller.settingsDraft.copyWith(multiAgent: config),
    );
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
    await _saveSettings(controller, settings.copyWith(aiGateway: draft));
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

  Future<void> _testVaultConnection(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final token = _secretOverride(_vaultTokenController, _vaultTokenState);
    final message = await controller.testVaultConnectionDraft(
      snapshot: settings,
      tokenOverride: token,
    );
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _testGatewayConnection(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final gatewayDraft = _buildGatewayDraftProfile(settings);
    final selectedProfileIndex = _selectedGatewayProfileIndex.clamp(
      0,
      settings.gatewayProfiles.length - 1,
    );
    final gatewayTokenController =
        _gatewayTokenControllers[selectedProfileIndex];
    final gatewayPasswordController =
        _gatewayPasswordControllers[selectedProfileIndex];
    final gatewayTokenState = _gatewayTokenStates[selectedProfileIndex];
    final gatewayPasswordState = _gatewayPasswordStates[selectedProfileIndex];
    final executionTarget = switch (gatewayDraft.mode) {
      RuntimeConnectionMode.local => AssistantExecutionTarget.local,
      RuntimeConnectionMode.remote => AssistantExecutionTarget.remote,
      RuntimeConnectionMode.unconfigured => AssistantExecutionTarget.remote,
    };
    var token = _secretOverride(gatewayTokenController, gatewayTokenState);
    var password = _secretOverride(
      gatewayPasswordController,
      gatewayPasswordState,
    );
    if (token.isEmpty) {
      token = await controller.settingsController.loadGatewayToken(
        profileIndex: selectedProfileIndex,
      );
    }
    if (password.isEmpty) {
      password = await controller.settingsController.loadGatewayPassword(
        profileIndex: selectedProfileIndex,
      );
    }
    setState(() => _gatewayTesting = true);
    try {
      final result = await controller.testGatewayConnectionDraft(
        profile: gatewayDraft,
        executionTarget: executionTarget,
        tokenOverride: token,
        passwordOverride: password,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _gatewayTestState = result.state;
        _gatewayTestMessage = result.message;
        _gatewayTestEndpoint = result.endpoint;
      });
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) {
        setState(() => _gatewayTesting = false);
      }
    }
  }

  Widget _buildSettingsSectionActions({
    required AppController controller,
    required Key testKey,
    required Key saveKey,
    required Key applyKey,
    required Future<void> Function() onTest,
    required Future<void> Function() onSave,
    required Future<void> Function() onApply,
    bool testing = false,
    String? testLabel,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton(
          key: testKey,
          onPressed: testing ? null : () => onTest(),
          child: Text(
            testing
                ? appText('测试中...', 'Testing...')
                : (testLabel ?? appText('测试连接', 'Test Connection')),
          ),
        ),
        OutlinedButton(
          key: saveKey,
          onPressed: () => onSave(),
          child: Text(appText('保存', 'Save')),
        ),
        FilledButton.tonal(
          key: applyKey,
          onPressed: () => onApply(),
          child: Text(appText('应用', 'Apply')),
        ),
      ],
    );
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

class _EditableField extends StatefulWidget {
  const _EditableField({
    required this.label,
    required this.value,
    required this.onSubmitted,
  });

  final String label;
  final String value;
  final ValueChanged<String> onSubmitted;

  @override
  State<_EditableField> createState() => _EditableFieldState();
}

class _EditableFieldState extends State<_EditableField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _EditableField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _controller.text) {
      return;
    }
    _controller.value = _controller.value.copyWith(
      text: widget.value,
      selection: TextSelection.collapsed(offset: widget.value.length),
      composing: TextRange.empty,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        key: ValueKey('${widget.label}:${widget.value}'),
        controller: _controller,
        decoration: InputDecoration(labelText: widget.label),
        onChanged: widget.onSubmitted,
        onFieldSubmitted: widget.onSubmitted,
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

enum _GatewayIntegrationSubTab { gateway, llm, acp, skills }

enum _LlmEndpointSlot { aiGateway, ollamaLocal, ollamaCloud }

const List<_LlmEndpointSlot> _llmEndpointSlots = <_LlmEndpointSlot>[
  _LlmEndpointSlot.aiGateway,
  _LlmEndpointSlot.ollamaLocal,
  _LlmEndpointSlot.ollamaCloud,
];

enum _StatusChipTone { idle, ready }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final _StatusChipTone tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      _StatusChipTone.ready => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      _StatusChipTone.idle => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: foreground),
      ),
    );
  }
}
