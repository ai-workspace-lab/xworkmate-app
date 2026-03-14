import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/gateway_connect_dialog.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsTab _tab = SettingsTab.general;
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

  @override
  void initState() {
    super.initState();
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
        final settings = controller.settings;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                title: appText('设置', 'Settings'),
                subtitle: appText(
                  '配置 $kProductBrandName 工作区、网关默认项、界面与诊断选项',
                  'Configure workspace, gateway defaults, appearance, and diagnostics for $kProductBrandName.',
                ),
                trailing: SizedBox(
                  width: 220,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: appText('搜索设置', 'Search settings'),
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SectionTabs(
                items: SettingsTab.values.map((item) => item.label).toList(),
                value: _tab.label,
                onChanged: (value) => setState(
                  () => _tab = SettingsTab.values.firstWhere(
                    (item) => item.label == value,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ...switch (_tab) {
                SettingsTab.general => _buildGeneral(
                  context,
                  controller,
                  settings,
                ),
                SettingsTab.workspace => _buildWorkspace(
                  context,
                  controller,
                  settings,
                ),
                SettingsTab.gateway => _buildGateway(
                  context,
                  controller,
                  settings,
                ),
                SettingsTab.appearance => _buildAppearance(context, controller),
                SettingsTab.diagnostics => _buildDiagnostics(
                  context,
                  controller,
                ),
                SettingsTab.experimental => _buildExperimental(
                  context,
                  controller,
                  settings,
                ),
                SettingsTab.about => _buildAbout(context, controller),
              },
            ],
          ),
        );
      },
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
              label: appText('显示 Dock 图标', 'Show dock icon'),
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
              appText('云端 Ollama', 'Ollama Cloud'),
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
            TextField(
              controller: _ollamaApiKeyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText:
                    '${appText('API Key', 'API Key')} (${settings.ollamaCloud.apiKeyRef})',
              ),
              onSubmitted: controller.settingsController.saveOllamaCloudApiKey,
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
        ),
      ),
    ];
  }

  List<Widget> _buildGateway(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    _syncControllerValue(_aiGatewayNameController, settings.aiGateway.name);
    _syncControllerValue(_aiGatewayUrlController, settings.aiGateway.baseUrl);
    _syncControllerValue(
      _aiGatewayApiKeyRefController,
      settings.aiGateway.apiKeyRef,
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
            TextField(
              controller: _vaultTokenController,
              obscureText: true,
              decoration: InputDecoration(
                labelText:
                    '${appText('Vault Token', 'Vault Token')} (${settings.vault.tokenRef})',
              ),
              onSubmitted: controller.settingsController.saveVaultToken,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: controller.testVaultConnection,
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
              controller: _aiGatewayNameController,
              decoration: InputDecoration(
                labelText: appText('配置名称', 'Profile Name'),
              ),
              onSubmitted: (_) => _saveAiGatewayDraft(controller, settings),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _aiGatewayUrlController,
              decoration: InputDecoration(
                labelText: appText('Gateway URL', 'Gateway URL'),
              ),
              onSubmitted: (_) => _saveAiGatewayDraft(controller, settings),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _aiGatewayApiKeyRefController,
              decoration: InputDecoration(
                labelText: appText('API Key 引用', 'API Key Ref'),
              ),
              onSubmitted: (_) => _saveAiGatewayDraft(controller, settings),
            ),
            TextField(
              controller: _aiGatewayApiKeyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText:
                    '${appText('API Key', 'API Key')} (${_aiGatewayApiKeyRefController.text.trim().isEmpty ? settings.aiGateway.apiKeyRef : _aiGatewayApiKeyRefController.text.trim()})',
                helperText: hasStoredAiGatewayApiKey
                    ? appText(
                        '已安全保存，可直接同步模型。',
                        'Stored securely and ready to sync.',
                      )
                    : appText(
                        '输入后点击保存或同步模型。',
                        'Save or sync to persist securely.',
                      ),
              ),
              onSubmitted: controller.settingsController.saveAiGatewayApiKey,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonal(
                  onPressed: _aiGatewayTesting || _aiGatewaySyncing
                      ? null
                      : () => _saveAiGatewayDraft(controller, settings),
                  child: Text(appText('保存草稿', 'Save Draft')),
                ),
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
                OutlinedButton(
                  key: const ValueKey('ai-gateway-sync-button'),
                  onPressed: () async {
                    if (_aiGatewayTesting || _aiGatewaySyncing) {
                      return;
                    }
                    final messenger = ScaffoldMessenger.of(context);
                    final draft = _buildAiGatewayDraft(settings);
                    final apiKey = _aiGatewayApiKeyController.text.trim();
                    setState(() => _aiGatewaySyncing = true);
                    try {
                      if (apiKey.isNotEmpty) {
                        await controller.settingsController.saveAiGatewayApiKey(
                          apiKey,
                        );
                      }
                      await _saveSettings(
                        controller,
                        settings.copyWith(aiGateway: draft),
                      );
                      final result = await controller.syncAiGatewayCatalog(
                        draft,
                        apiKeyOverride: apiKey,
                      );
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _aiGatewayTestState = result.syncState;
                        _aiGatewayTestMessage =
                            'Catalog synced · ${result.availableModels.length} model(s) ready';
                        _aiGatewayTestEndpoint = _previewAiGatewayEndpoint(
                          draft.baseUrl,
                        );
                      });
                      messenger.showSnackBar(
                        SnackBar(content: Text(result.syncMessage)),
                      );
                    } finally {
                      if (mounted) {
                        setState(() => _aiGatewaySyncing = false);
                      }
                    }
                  },
                  child: Text(
                    _aiGatewaySyncing
                        ? appText('同步中...', 'Syncing...')
                        : '${appText('同步模型', 'Sync Models')} · ${settings.aiGateway.syncState}',
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

  List<Widget> _buildExperimental(
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
              appText('实验特性', 'Experimental'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _SwitchRow(
              label: appText('Canvas 宿主', 'Canvas host'),
              value: settings.experimentalCanvas,
              onChanged: (value) => _saveSettings(
                controller,
                settings.copyWith(experimentalCanvas: value),
              ),
            ),
            _SwitchRow(
              label: appText('桥接模式', 'Bridge mode'),
              value: settings.experimentalBridge,
              onChanged: (value) => _saveSettings(
                controller,
                settings.copyWith(experimentalBridge: value),
              ),
            ),
            _SwitchRow(
              label: appText('调试运行时', 'Debug runtime'),
              value: settings.experimentalDebug,
              onChanged: (value) => _saveSettings(
                controller,
                settings.copyWith(experimentalDebug: value),
              ),
            ),
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

  AiGatewayProfile _buildAiGatewayDraft(SettingsSnapshot settings) {
    return settings.aiGateway.copyWith(
      name: _aiGatewayNameController.text.trim(),
      baseUrl: _aiGatewayUrlController.text.trim(),
      apiKeyRef: _aiGatewayApiKeyRefController.text.trim(),
    );
  }

  Future<void> _saveAiGatewayDraft(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final apiKey = _aiGatewayApiKeyController.text.trim();
    if (apiKey.isNotEmpty) {
      await controller.settingsController.saveAiGatewayApiKey(apiKey);
    }
    await _saveSettings(
      controller,
      settings.copyWith(aiGateway: _buildAiGatewayDraft(settings)),
    );
  }

  Future<void> _testAiGatewayConnection(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final draft = _buildAiGatewayDraft(settings);
    final apiKey = _aiGatewayApiKeyController.text.trim();
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
