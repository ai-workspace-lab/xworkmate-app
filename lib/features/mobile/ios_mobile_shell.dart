import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/gateway_connect_dialog.dart';
import '../../widgets/section_tabs.dart';

enum IosMobileTab { home, overview, tasks, account, settings }

extension on IosMobileTab {
  String get label => switch (this) {
    IosMobileTab.home => '首页',
    IosMobileTab.overview => '总览',
    IosMobileTab.tasks => '任务',
    IosMobileTab.account => '账号登录',
    IosMobileTab.settings => '设置',
  };

  IconData get icon => switch (this) {
    IosMobileTab.home => Icons.home_rounded,
    IosMobileTab.overview => Icons.monitor_heart_outlined,
    IosMobileTab.tasks => Icons.layers_rounded,
    IosMobileTab.account => Icons.account_circle_outlined,
    IosMobileTab.settings => Icons.settings_rounded,
  };
}

const _background = Color(0xFFF3EFF6);
const _surface = Colors.white;
const _surfaceSoft = Color(0xFFF7F4FB);
const _stroke = Color(0xFFE3DDEE);
const _textPrimary = Color(0xFF101113);
const _textSecondary = Color(0xFF8A8694);
const _accentStart = Color(0xFF7C88F8);
const _accentEnd = Color(0xFF6757EF);
const _accentSoft = Color(0xFFD9D5FA);
const _blueSoft = Color(0xFFDCE4F1);
const _blueLine = Color(0xFF6285A6);
const _greenSoft = Color(0xFFDCEFE2);
const _greenLine = Color(0xFF62C56A);
const _orangeSoft = Color(0xFFF5E7D9);
const _orangeLine = Color(0xFFE1913E);

class IosMobileShell extends StatefulWidget {
  const IosMobileShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<IosMobileShell> createState() => _IosMobileShellState();
}

class _IosMobileShellState extends State<IosMobileShell> {
  IosMobileTab _tab = IosMobileTab.home;
  String _taskTab = 'Running';
  bool _deviceInfoExpanded = false;
  late final TextEditingController _accountBaseUrlController;
  late final TextEditingController _accountUsernameController;
  final TextEditingController _accountPasswordController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _accountBaseUrlController = TextEditingController(
      text: settings.accountBaseUrl,
    );
    _accountUsernameController = TextEditingController(
      text: settings.accountUsername,
    );
  }

  @override
  void dispose() {
    _accountBaseUrlController.dispose();
    _accountUsernameController.dispose();
    _accountPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          const Positioned(
            top: 100,
            left: -80,
            child: _GlowOrb(size: 220, color: Color(0x1A8C89FF)),
          ),
          const Positioned(
            right: -90,
            bottom: 220,
            child: _GlowOrb(size: 260, color: Color(0x143AB08F)),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: AnimatedBuilder(
                    animation: widget.controller,
                    builder: (context, _) {
                      return _MobilePageFrame(
                        child: switch (_tab) {
                          IosMobileTab.home => _buildHomePage(),
                          IosMobileTab.overview => _buildOverviewPage(),
                          IosMobileTab.tasks => _buildTasksPage(),
                          IosMobileTab.account => _buildAccountPage(),
                          IosMobileTab.settings => _buildSettingsPage(),
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  child: _BottomPillNav(
                    currentTab: _tab,
                    onChanged: (tab) => setState(() => _tab = tab),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomePage() {
    final controller = widget.controller;
    final connection = controller.connection;
    final title = connection.remoteAddress ?? 'xworkmate.svc.plus';
    final hero = _HeroCardData(
      badge: connection.status == RuntimeConnectionStatus.connected
          ? '会话已就绪'
          : '等待接入',
      badgeColor: connection.status == RuntimeConnectionStatus.connected
          ? _blueLine
          : _textSecondary,
      icon: Icons.forum_outlined,
      iconTint: _blueLine,
      iconBackground: _blueSoft,
      title: title,
      subtitle: connection.status == RuntimeConnectionStatus.connected
          ? controller.currentSessionKey
          : 'Connect OpenClaw gateway to start',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MobileHeader(
          breadcrumb: const ['首页'],
          title: title,
          secondaryIcon: Icons.list_rounded,
          onPrimaryPressed: _showConnectSheet,
          onSecondaryPressed: () =>
              setState(() => _tab = IosMobileTab.settings),
        ),
        const SizedBox(height: 22),
        _HeroCard(data: hero),
        const SizedBox(height: 18),
        GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          shrinkWrap: true,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.76,
          children: [
            _ShortcutCard(
              icon: Icons.chat_bubble_outline_rounded,
              iconColor: _blueLine,
              iconBackground: _blueSoft,
              title: '进入对话',
              subtitle: '继续当前会话',
              onTap: _openChatSheet,
            ),
            _ShortcutCard(
              icon: Icons.monitor_heart_outlined,
              iconColor: const Color(0xFF5CC9B7),
              iconBackground: const Color(0xFFDDF3EF),
              title: '状态总览',
              subtitle: '查看监控和使用状态',
              onTap: () => setState(() => _tab = IosMobileTab.overview),
            ),
            _ShortcutCard(
              icon: Icons.layers_outlined,
              iconColor: const Color(0xFF6B5CF2),
              iconBackground: _accentSoft,
              title: '任务查看',
              subtitle: '查看 queue 与历史',
              onTap: () => setState(() => _tab = IosMobileTab.tasks),
            ),
            _ShortcutCard(
              icon: Icons.account_circle_outlined,
              iconColor: _orangeLine,
              iconBackground: _orangeSoft,
              title: '账号登录',
              subtitle: '统一账户入口',
              onTap: () => setState(() => _tab = IosMobileTab.account),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionTitle('当前状态'),
        const SizedBox(height: 14),
        _StatusCard(
          title: controller.activeAgentName,
          value: connection.status.label,
          subtitle: connection.remoteAddress ?? 'No gateway target',
          trailing: controller.currentSessionKey,
        ),
      ],
    );
  }

  Widget _buildOverviewPage() {
    final controller = widget.controller;
    final connection = controller.connection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MobileHeader(
          breadcrumb: const ['首页', '总览'],
          title: connection.remoteAddress ?? 'Gateway',
          secondaryIcon: Icons.settings_outlined,
          onPrimaryPressed: _showConnectSheet,
          onSecondaryPressed: () =>
              setState(() => _tab = IosMobileTab.settings),
        ),
        const SizedBox(height: 22),
        _HeroCard(
          data: _HeroCardData(
            badge: connection.status == RuntimeConnectionStatus.connected
                ? '运行状态'
                : '等待接入',
            badgeColor: connection.status == RuntimeConnectionStatus.connected
                ? _greenLine
                : _textSecondary,
            icon: Icons.monitor_heart_outlined,
            iconTint: _greenLine,
            iconBackground: _greenSoft,
            title: connection.remoteAddress ?? 'No gateway target',
            subtitle: controller.activeAgentName,
          ),
        ),
        const SizedBox(height: 22),
        const _SectionTitle('监控概览'),
        const SizedBox(height: 14),
        _InfoPanel(
          items: [
            ('网关状态', connection.status.label),
            ('当前地址', connection.remoteAddress ?? 'Offline'),
            ('可用代理', '${controller.agents.length}'),
            ('会话数量', '${controller.sessions.length}'),
            ('运行任务', '${controller.tasksController.running.length}'),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionTitle('快速操作'),
        const SizedBox(height: 14),
        _ActionPanel(
          primaryLabel: '重新拉取状态',
          secondaryLabel: '打开连接设置',
          onPrimaryPressed: () async {
            await controller.refreshGatewayHealth();
            await controller.refreshAgents();
            await controller.refreshSessions();
          },
          onSecondaryPressed: _showConnectSheet,
        ),
      ],
    );
  }

  Widget _buildTasksPage() {
    final controller = widget.controller;
    final items = controller.taskItemsForTab(_taskTab);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MobileHeader(
          breadcrumb: const ['首页', '任务'],
          title: '任务',
          secondaryIcon: Icons.refresh_rounded,
          onPrimaryPressed: _openChatSheet,
          onSecondaryPressed: controller.refreshSessions,
        ),
        const SizedBox(height: 22),
        SectionTabs(
          items: const ['Queue', 'Running', 'History', 'Failed', 'Scheduled'],
          value: _taskTab,
          size: SectionTabsSize.small,
          onChanged: (value) => setState(() => _taskTab = value),
        ),
        const SizedBox(height: 18),
        _StatGrid(
          items: [
            _MiniStat('Total', '${controller.tasksController.totalCount}'),
            _MiniStat(
              'Running',
              '${controller.tasksController.running.length}',
            ),
            _MiniStat('Failed', '${controller.tasksController.failed.length}'),
            _MiniStat('Sessions', '${controller.sessions.length}'),
          ],
        ),
        const SizedBox(height: 20),
        if (_taskTab == 'Scheduled' && items.isEmpty)
          const _MessageCard(
            text: 'Scheduled 任务将在自动化管理包接入后展示，本轮只显示 Gateway 派生任务。',
          )
        else if (items.isEmpty)
          const _MessageCard(text: '当前没有匹配的任务项。')
        else
          ...items.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TaskCard(task: task),
            ),
          ),
      ],
    );
  }

  Widget _buildAccountPage() {
    final controller = widget.controller;
    final settings = controller.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MobileHeader(
          breadcrumb: const ['首页', '账号登录'],
          title: '账号',
          secondaryIcon: Icons.list_rounded,
          onPrimaryPressed: _showConnectSheet,
          onSecondaryPressed: () => setState(() => _tab = IosMobileTab.home),
        ),
        const SizedBox(height: 18),
        Center(
          child: Column(
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.cloud_outlined, size: 132, color: _accentEnd),
              const SizedBox(height: 24),
              const Text(
                '账号登录',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                settings.accountLocalMode ? '保存账号入口信息' : '统一账户地址已配置',
                style: const TextStyle(fontSize: 22, color: _textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 34),
        const _FieldLabel('服务地址'),
        const SizedBox(height: 12),
        _RoundedTextField(
          controller: _accountBaseUrlController,
          icon: Icons.dns_outlined,
          onSubmitted: (value) =>
              controller.saveSettings(settings.copyWith(accountBaseUrl: value)),
        ),
        const SizedBox(height: 22),
        const _FieldLabel('邮箱或账号'),
        const SizedBox(height: 12),
        _RoundedTextField(
          controller: _accountUsernameController,
          icon: Icons.person_outline_rounded,
          onSubmitted: (value) => controller.saveSettings(
            settings.copyWith(accountUsername: value),
          ),
        ),
        const SizedBox(height: 22),
        const _FieldLabel('密码'),
        const SizedBox(height: 12),
        TextField(
          controller: _accountPasswordController,
          obscureText: true,
          decoration: _roundedInputDecoration(
            hintText: '',
            icon: Icons.lock_outline_rounded,
          ),
        ),
        const SizedBox(height: 26),
        _PrimaryWideButton(
          label: settings.accountLocalMode ? '保存本地入口' : '登录',
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            FocusScope.of(context).unfocus();
            await controller.saveSettings(
              settings.copyWith(
                accountBaseUrl: _accountBaseUrlController.text.trim(),
                accountUsername: _accountUsernameController.text.trim(),
                accountLocalMode: true,
              ),
            );
            if (!context.mounted) {
              return;
            }
            messenger.showSnackBar(const SnackBar(content: Text('账号入口配置已保存。')));
          },
        ),
      ],
    );
  }

  Widget _buildSettingsPage() {
    final controller = widget.controller;
    final settings = controller.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MobileHeader(
          breadcrumb: const ['首页', '设置'],
          title: '设置',
          secondaryIcon: Icons.close_rounded,
          onPrimaryPressed: _showConnectSheet,
          onSecondaryPressed: () => setState(() => _tab = IosMobileTab.home),
        ),
        const SizedBox(height: 18),
        _HeroCard(
          data: _HeroCardData(
            badge: '偏好、连接与设备能力',
            badgeColor: _textSecondary,
            icon: Icons.settings_outlined,
            iconTint: _accentEnd,
            iconBackground: _accentSoft,
            title: connectionTitle(controller),
            subtitle:
                controller.connection.remoteAddress ?? 'xworkmate.svc.plus',
          ),
          compact: true,
        ),
        const SizedBox(height: 22),
        const _SectionTitle('连接与网关'),
        const SizedBox(height: 14),
        _GroupCard(
          children: [
            _GroupedRow(
              title: 'Gateway',
              subtitle:
                  controller.connection.remoteAddress ?? settings.gateway.host,
              leadingDotColor:
                  controller.connection.status ==
                      RuntimeConnectionStatus.connected
                  ? Colors.green
                  : _textSecondary,
              onTap: _showConnectSheet,
            ),
            _DividerLine(),
            _GroupedRow(
              title: 'Selected Agent',
              subtitle: controller.activeAgentName,
              onTap: _openAgentPicker,
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionTitle('模型与模块 Provider'),
        const SizedBox(height: 14),
        _GroupCard(
          children: [
            _GroupedRow(
              title: 'Ollama Local',
              subtitle: settings.ollamaLocal.endpoint,
              onTap: () => _openSettingsEditor(
                title: 'Ollama Local',
                child: _MobileSettingsEditor(
                  title: 'Ollama Local',
                  fields: [
                    _EditorFieldData(
                      label: 'Endpoint',
                      initialValue: settings.ollamaLocal.endpoint,
                      onSubmitted: (value) => controller.saveSettings(
                        settings.copyWith(
                          ollamaLocal: settings.ollamaLocal.copyWith(
                            endpoint: value,
                          ),
                        ),
                      ),
                    ),
                    _EditorFieldData(
                      label: 'Default Model',
                      initialValue: settings.ollamaLocal.defaultModel,
                      onSubmitted: (value) => controller.saveSettings(
                        settings.copyWith(
                          ollamaLocal: settings.ollamaLocal.copyWith(
                            defaultModel: value,
                          ),
                        ),
                      ),
                    ),
                  ],
                  footer: OutlinedButton(
                    onPressed: () =>
                        controller.testOllamaConnection(cloud: false),
                    child: Text(
                      'Test · ${controller.settingsController.ollamaStatus}',
                    ),
                  ),
                ),
              ),
            ),
            _DividerLine(),
            _GroupedRow(
              title: 'Ollama Cloud',
              subtitle: settings.ollamaCloud.baseUrl,
              onTap: () => _openSettingsEditor(
                title: 'Ollama Cloud',
                child: _MobileSettingsEditor(
                  title: 'Ollama Cloud',
                  fields: [
                    _EditorFieldData(
                      label: 'Base URL',
                      initialValue: settings.ollamaCloud.baseUrl,
                      onSubmitted: (value) => controller.saveSettings(
                        settings.copyWith(
                          ollamaCloud: settings.ollamaCloud.copyWith(
                            baseUrl: value,
                          ),
                        ),
                      ),
                    ),
                    _EditorFieldData(
                      label: 'Default Model',
                      initialValue: settings.ollamaCloud.defaultModel,
                      onSubmitted: (value) => controller.saveSettings(
                        settings.copyWith(
                          ollamaCloud: settings.ollamaCloud.copyWith(
                            defaultModel: value,
                          ),
                        ),
                      ),
                    ),
                  ],
                  footer: OutlinedButton(
                    onPressed: () =>
                        controller.testOllamaConnection(cloud: true),
                    child: Text(
                      'Test · ${controller.settingsController.ollamaStatus}',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionTitle('Secret / Vault'),
        const SizedBox(height: 14),
        _GroupCard(
          children: [
            _GroupedRow(
              title: 'Vault Server',
              subtitle: settings.vault.address,
              onTap: () => _openSettingsEditor(
                title: 'Vault Server',
                child: _MobileSettingsEditor(
                  title: 'Vault Server',
                  fields: [
                    _EditorFieldData(
                      label: 'Address',
                      initialValue: settings.vault.address,
                      onSubmitted: (value) => controller.saveSettings(
                        settings.copyWith(
                          vault: settings.vault.copyWith(address: value),
                        ),
                      ),
                    ),
                    _EditorFieldData(
                      label: 'Namespace',
                      initialValue: settings.vault.namespace,
                      onSubmitted: (value) => controller.saveSettings(
                        settings.copyWith(
                          vault: settings.vault.copyWith(namespace: value),
                        ),
                      ),
                    ),
                    _EditorFieldData(
                      label: 'Token Ref',
                      initialValue: settings.vault.tokenRef,
                      onSubmitted: (value) => controller.saveSettings(
                        settings.copyWith(
                          vault: settings.vault.copyWith(tokenRef: value),
                        ),
                      ),
                    ),
                  ],
                  footer: OutlinedButton(
                    onPressed: controller.testVaultConnection,
                    child: Text(
                      'Test · ${controller.settingsController.vaultStatus}',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionTitle('APISIX YAML'),
        const SizedBox(height: 14),
        _GroupCard(
          children: [
            _GroupedRow(
              title: settings.apisix.name,
              subtitle:
                  '${settings.apisix.filePath} · ${settings.apisix.validationState}',
              onTap: () => _openSettingsEditor(
                title: 'APISIX YAML',
                child: _ApisixEditor(
                  controller: controller,
                  profile: settings.apisix,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionTitle('设备与诊断'),
        const SizedBox(height: 14),
        _GroupCard(
          children: [
            const _GroupedRow(
              title: 'Features',
              subtitle: 'Gateway / Chat / Tasks / Modules',
            ),
            _DividerLine(),
            _GroupedExpandableRow(
              title: 'Device Info',
              expanded: _deviceInfoExpanded,
              onToggle: () =>
                  setState(() => _deviceInfoExpanded = !_deviceInfoExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(
                  children: [
                    _DeviceInfoLine(
                      label: 'Device',
                      value: widget.controller.runtime.deviceInfo.deviceFamily,
                    ),
                    _DeviceInfoLine(
                      label: 'Platform',
                      value: widget.controller.runtime.deviceInfo.platformLabel,
                    ),
                    _DeviceInfoLine(
                      label: 'XWorkmate',
                      value:
                          '${widget.controller.runtime.packageInfo.version} (${widget.controller.runtime.packageInfo.buildNumber})',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String connectionTitle(AppController controller) {
    return controller.connection.remoteAddress ?? 'xworkmate.svc.plus';
  }

  void _showConnectSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.94,
        child: Container(
          decoration: const BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
          ),
          child: SafeArea(
            top: false,
            child: GatewayConnectDialog(
              controller: widget.controller,
              compact: true,
              onDone: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }

  void _openChatSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.96,
        child: _MobileChatSheet(controller: widget.controller),
      ),
    );
  }

  void _openAgentPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Agent',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: const Text('Main'),
                  trailing: widget.controller.selectedAgentId.isEmpty
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    await widget.controller.selectAgent('');
                    navigator.pop();
                  },
                ),
                ...widget.controller.agents.map(
                  (agent) => ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: Text(agent.name),
                    subtitle: Text(agent.id),
                    trailing: widget.controller.selectedAgentId == agent.id
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () async {
                      final navigator = Navigator.of(context);
                      await widget.controller.selectAgent(agent.id);
                      navigator.pop();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSettingsEditor({required String title, required Widget child}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: Container(
          decoration: const BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ),
      ),
    );
  }
}

class _MobileChatSheet extends StatefulWidget {
  const _MobileChatSheet({required this.controller});

  final AppController controller;

  @override
  State<_MobileChatSheet> createState() => _MobileChatSheetState();
}

class _MobileChatSheetState extends State<_MobileChatSheet> {
  late final TextEditingController _inputController;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final controller = widget.controller;
            final connected =
                controller.connection.status ==
                RuntimeConnectionStatus.connected;
            final messages = controller.chatMessages;
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '对话',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              controller.currentSessionKey,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: _textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (controller.sessions.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: controller.currentSessionKey,
                      decoration: const InputDecoration(labelText: 'Session'),
                      items: controller.sessions
                          .map(
                            (session) => DropdownMenuItem<String>(
                              value: session.key,
                              child: Text(session.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          controller.switchSession(value);
                        }
                      },
                    ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _surfaceSoft,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: _stroke),
                      ),
                      child: !connected
                          ? const Center(
                              child: Text(
                                'Connect a gateway first to enter the chat.',
                              ),
                            )
                          : messages.isEmpty
                          ? const Center(
                              child: Text('当前 session 还没有消息，发送第一条指令即可开始。'),
                            )
                          : ListView.separated(
                              itemCount: messages.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final message = messages[index];
                                final isUser = message.role == 'user';
                                return Align(
                                  alignment: isUser
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 320,
                                    ),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: isUser
                                          ? const Color(0xFFE8E1FF)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(color: _stroke),
                                    ),
                                    child: Text(
                                      message.text.isEmpty
                                          ? 'Pending'
                                          : message.text,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _inputController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: _roundedInputDecoration(
                      hintText: connected
                          ? 'Ask XWorkmate anything…'
                          : 'Connect a gateway first…',
                      icon: Icons.edit_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _PrimaryWideButton(
                          label: controller.chatController.hasPendingRun
                              ? '停止'
                              : '发送',
                          onPressed: connected
                              ? () async {
                                  if (controller.chatController.hasPendingRun) {
                                    await controller.abortRun();
                                    return;
                                  }
                                  final text = _inputController.text;
                                  await controller.sendChatMessage(text);
                                  if (mounted && text.trim().isNotEmpty) {
                                    _inputController.clear();
                                  }
                                }
                              : () {},
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ApisixEditor extends StatefulWidget {
  const _ApisixEditor({required this.controller, required this.profile});

  final AppController controller;
  final ApisixYamlProfile profile;

  @override
  State<_ApisixEditor> createState() => _ApisixEditorState();
}

class _ApisixEditorState extends State<_ApisixEditor> {
  late final TextEditingController _pathController;
  late final TextEditingController _yamlController;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.profile.filePath);
    _yamlController = TextEditingController(text: widget.profile.inlineYaml);
  }

  @override
  void dispose() {
    _pathController.dispose();
    _yamlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('APISIX YAML', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        _RoundedTextField(
          initialValue: widget.profile.name,
          icon: Icons.tag_rounded,
          hintText: 'Profile Name',
          onSubmitted: (value) => widget.controller.saveSettings(
            widget.controller.settings.copyWith(
              apisix: widget.controller.settings.apisix.copyWith(name: value),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pathController,
          decoration: _roundedInputDecoration(
            hintText: widget.profile.filePath,
            icon: Icons.folder_outlined,
          ),
          onSubmitted: (value) => widget.controller.saveSettings(
            widget.controller.settings.copyWith(
              apisix: widget.controller.settings.apisix.copyWith(
                filePath: value,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _yamlController,
          minLines: 8,
          maxLines: 12,
          decoration: _roundedInputDecoration(
            hintText: 'Inline YAML',
            icon: Icons.code_rounded,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => widget.controller.saveSettings(
                  widget.controller.settings.copyWith(
                    apisix: widget.controller.settings.apisix.copyWith(
                      inlineYaml: _yamlController.text,
                    ),
                  ),
                ),
                child: const Text('保存草稿'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonal(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final result = await widget.controller.validateApisixYaml(
                    widget.controller.settings.apisix.copyWith(
                      filePath: _pathController.text,
                      inlineYaml: _yamlController.text,
                    ),
                  );
                  if (!mounted) {
                    return;
                  }
                  messenger.showSnackBar(
                    SnackBar(content: Text(result.validationMessage)),
                  );
                },
                child: Text(widget.profile.validationState),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          widget.profile.validationMessage,
          style: const TextStyle(color: _textSecondary),
        ),
      ],
    );
  }
}

class _MobileSettingsEditor extends StatelessWidget {
  const _MobileSettingsEditor({
    required this.title,
    required this.fields,
    this.footer,
  });

  final String title;
  final List<_EditorFieldData> fields;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        ...fields.expand(
          (field) => [
            _RoundedTextField(
              initialValue: field.initialValue,
              icon: Icons.edit_outlined,
              hintText: field.label,
              onSubmitted: field.onSubmitted,
            ),
            const SizedBox(height: 12),
          ],
        ),
        ...?footer == null ? null : <Widget>[footer!],
      ],
    );
  }
}

class _EditorFieldData {
  const _EditorFieldData({
    required this.label,
    required this.initialValue,
    required this.onSubmitted,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onSubmitted;
}

class _MobilePageFrame extends StatelessWidget {
  const _MobilePageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: child,
    );
  }
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.breadcrumb,
    required this.title,
    required this.secondaryIcon,
    required this.onPrimaryPressed,
    required this.onSecondaryPressed,
  });

  final List<String> breadcrumb;
  final String title;
  final IconData secondaryIcon;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                breadcrumb.join('  ›  '),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_accentStart, _accentEnd]),
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              IconButton(
                onPressed: onPrimaryPressed,
                icon: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onSecondaryPressed,
                icon: Icon(secondaryIcon, color: Colors.white, size: 30),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroCardData {
  const _HeroCardData({
    required this.badge,
    required this.badgeColor,
    required this.icon,
    required this.iconTint,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
  });

  final String badge;
  final Color badgeColor;
  final IconData icon;
  final Color iconTint;
  final Color iconBackground;
  final String title;
  final String subtitle;
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.data, this.compact = false});

  final _HeroCardData data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 24 : 26),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: _stroke, width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 78 : 100,
            height: compact ? 78 : 100,
            decoration: BoxDecoration(
              color: data.iconBackground,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Icon(
              data.icon,
              color: data.iconTint,
              size: compact ? 38 : 46,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.badge,
                  style: TextStyle(
                    fontSize: compact ? 18 : 20,
                    fontWeight: FontWeight.w700,
                    color: data.badgeColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 26 : 32,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  data.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, color: _textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(34),
        child: Ink(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: _stroke, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Icon(icon, color: iconColor, size: 38),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 18, color: _textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: _textPrimary,
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: _stroke, width: 1.2),
      ),
      child: Column(
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.$1,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        item.$2,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimaryPressed,
    required this.onSecondaryPressed,
  });

  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: _stroke, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PrimaryWideButton(label: primaryLabel, onPressed: onPrimaryPressed),
          const SizedBox(height: 14),
          TextButton(
            onPressed: onSecondaryPressed,
            child: Text(
              secondaryLabel,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String value;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: _stroke, width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, color: _textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(subtitle, style: const TextStyle(color: _textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Text(
            trailing,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomPillNav extends StatelessWidget {
  const _BottomPillNav({required this.currentTab, required this.onChanged});

  final IosMobileTab currentTab;
  final ValueChanged<IosMobileTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xF8FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _stroke),
      ),
      child: Row(
        children: IosMobileTab.values
            .map(
              (tab) => Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(tab),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: currentTab == tab
                          ? _surfaceSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tab.icon,
                          size: 32,
                          color: currentTab == tab ? _blueLine : _textPrimary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: currentTab == tab ? _blueLine : _textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _RoundedTextField extends StatelessWidget {
  const _RoundedTextField({
    this.initialValue,
    this.controller,
    required this.icon,
    this.hintText = '',
    this.onSubmitted,
  }) : assert(
         initialValue == null || controller == null,
         'Use either initialValue or controller.',
       );

  final String? initialValue;
  final TextEditingController? controller;
  final IconData icon;
  final String hintText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      controller: controller,
      decoration: _roundedInputDecoration(hintText: hintText, icon: icon),
      onFieldSubmitted: onSubmitted,
    );
  }
}

InputDecoration _roundedInputDecoration({
  required String hintText,
  required IconData icon,
}) {
  return InputDecoration(
    hintText: hintText,
    prefixIcon: Icon(icon, color: _textSecondary, size: 30),
    filled: true,
    fillColor: _surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(32),
      borderSide: const BorderSide(color: _stroke, width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(32),
      borderSide: const BorderSide(color: _stroke, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(32),
      borderSide: const BorderSide(color: _accentEnd, width: 1.8),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: _textSecondary,
      ),
    );
  }
}

class _PrimaryWideButton extends StatelessWidget {
  const _PrimaryWideButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: _accentEnd,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: _stroke, width: 1.2),
      ),
      child: Column(children: children),
    );
  }
}

class _GroupedRow extends StatelessWidget {
  const _GroupedRow({
    required this.title,
    required this.subtitle,
    this.leadingDotColor,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Color? leadingDotColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: Row(
        children: [
          if (leadingDotColor != null) ...[
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: leadingDotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, color: _textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(
            Icons.chevron_right_rounded,
            size: 32,
            color: _textPrimary,
          ),
        ],
      ),
    );
    if (onTap == null) {
      return row;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(32),
      onTap: onTap,
      child: row,
    );
  }
}

class _GroupedExpandableRow extends StatelessWidget {
  const _GroupedExpandableRow({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Device Info',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 32,
                  color: _textPrimary,
                ),
              ],
            ),
          ),
        ),
        if (expanded) child,
      ],
    );
  }
}

class _DividerLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Divider(height: 1, color: _stroke),
    );
  }
}

class _DeviceInfoLine extends StatelessWidget {
  const _DeviceInfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 20, color: _textSecondary),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _stroke),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, color: _textPrimary),
      ),
    );
  }
}

class _MiniStat {
  const _MiniStat(this.label, this.value);

  final String label;
  final String value;
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.items});

  final List<_MiniStat> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items
          .map(
            (item) => Container(
              width: 160,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: _stroke),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(color: _textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final DerivedTaskItem task;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
              ),
              Text(
                task.status,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(task.summary, style: const TextStyle(color: _textSecondary)),
          const SizedBox(height: 10),
          Text(
            '${task.owner} · ${task.startedAtLabel}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
