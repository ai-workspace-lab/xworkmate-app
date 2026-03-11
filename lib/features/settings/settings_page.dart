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
  late final TextEditingController _apisixYamlController;
  late final TextEditingController _vaultTokenController;
  late final TextEditingController _ollamaApiKeyController;

  @override
  void initState() {
    super.initState();
    _apisixYamlController = TextEditingController(
      text: widget.controller.settings.apisix.inlineYaml,
    );
    _vaultTokenController = TextEditingController();
    _ollamaApiKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _apisixYamlController.dispose();
    _vaultTokenController.dispose();
    _ollamaApiKeyController.dispose();
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
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
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
      const SizedBox(height: 16),
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
      const SizedBox(height: 16),
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
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('网关连接', 'Gateway Connection'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              '${controller.connection.status.label} · ${controller.connection.remoteAddress ?? settings.gateway.host}:${settings.gateway.port}',
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
              appText('APISIX YAML', 'APISIX YAML'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _EditableField(
              label: appText('配置名称', 'Profile Name'),
              value: settings.apisix.name,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(
                  apisix: settings.apisix.copyWith(name: value),
                ),
              ),
            ),
            _EditableField(
              label: appText('来源类型', 'Source Type'),
              value: settings.apisix.sourceType,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(
                  apisix: settings.apisix.copyWith(sourceType: value),
                ),
              ),
            ),
            _EditableField(
              label: appText('文件路径', 'File Path'),
              value: settings.apisix.filePath,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(
                  apisix: settings.apisix.copyWith(filePath: value),
                ),
              ),
            ),
            TextField(
              controller: _apisixYamlController,
              minLines: 6,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: appText('内联 YAML', 'Inline YAML'),
                hintText: appText(
                  '粘贴 APISIX 路由或 upstream YAML 用于校验',
                  'Paste APISIX route / upstream YAML for validation',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonal(
                  onPressed: () => _saveSettings(
                    controller,
                    settings.copyWith(
                      apisix: settings.apisix.copyWith(
                        inlineYaml: _apisixYamlController.text,
                      ),
                    ),
                  ),
                  child: Text(appText('保存草稿', 'Save Draft')),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final updated = settings.apisix.copyWith(
                      inlineYaml: _apisixYamlController.text,
                    );
                    final result = await controller.validateApisixYaml(updated);
                    if (!mounted) {
                      return;
                    }
                    messenger.showSnackBar(
                      SnackBar(content: Text(result.validationMessage)),
                    );
                  },
                  child: Text(
                    '${appText('校验', 'Validate')} · ${settings.apisix.validationState}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              settings.apisix.validationMessage,
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
