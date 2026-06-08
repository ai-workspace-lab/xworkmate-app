import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import 'workspace_provision_controller.dart';
import 'workspace_provision_models.dart';

class WorkspaceManagementForm extends StatefulWidget {
  const WorkspaceManagementForm({
    super.key,
    required this.controller,
    required this.onDetect,
    required this.onCreate,
  });

  final WorkspaceProvisionController controller;
  final VoidCallback onDetect;
  final VoidCallback onCreate;

  @override
  State<WorkspaceManagementForm> createState() =>
      _WorkspaceManagementFormState();
}

class _WorkspaceManagementFormState extends State<WorkspaceManagementForm> {
  late final TextEditingController _serverController;
  late final TextEditingController _domainController;
  late final TextEditingController _userController;
  late final TextEditingController _passwordController;
  late final TextEditingController _keyController;
  late final TextEditingController _keyPathController;
  late final TextEditingController _portController;
  late final TextEditingController _sudoController;
  late final TextEditingController _installPathController;
  late final TextEditingController _deepseekKeyController;
  late final TextEditingController _nvidiaKeyController;
  late final TextEditingController _ollamaKeyController;
  late final TextEditingController _openclawTokenController;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _serverController = TextEditingController(text: c.serverAddress);
    _domainController = TextEditingController(text: c.workspaceDomain);
    _userController = TextEditingController(text: c.sshUsername);
    _passwordController = TextEditingController(text: c.sshPassword ?? '');
    _keyController = TextEditingController(text: c.sshKeyContent ?? '');
    _keyPathController = TextEditingController(text: c.sshKeyPath ?? '');
    _portController = TextEditingController(text: c.sshPort.toString());
    _sudoController = TextEditingController(text: c.sudoPassword ?? '');
    _installPathController = TextEditingController(text: c.installPath);
    _deepseekKeyController = TextEditingController(text: c.deepseekApiKey ?? '');
    _nvidiaKeyController = TextEditingController(text: c.nvidiaApiKey ?? '');
    _ollamaKeyController = TextEditingController(text: c.ollamaApiKey ?? '');
    _openclawTokenController =
        TextEditingController(text: c.openclawGatewayToken ?? '');
  }

  @override
  void dispose() {
    _serverController.dispose();
    _domainController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _keyController.dispose();
    _keyPathController.dispose();
    _portController.dispose();
    _sudoController.dispose();
    _installPathController.dispose();
    _deepseekKeyController.dispose();
    _nvidiaKeyController.dispose();
    _ollamaKeyController.dispose();
    _openclawTokenController.dispose();
    super.dispose();
  }

  void _sync() {
    widget.controller.updateForm(
      serverAddress: _serverController.text.trim(),
      workspaceDomain: _domainController.text.trim(),
      sshUsername: _userController.text.trim(),
      sshPassword: _passwordController.text,
      sshKeyContent: _keyController.text,
      sshKeyPath: _keyPathController.text.trim(),
      sshPort: int.tryParse(_portController.text.trim()) ?? 22,
      sudoPassword: _sudoController.text,
      installPath: _installPathController.text.trim().isEmpty
          ? '/opt/xworkspace/playbooks'
          : _installPathController.text.trim(),
      deepseekApiKey: _deepseekKeyController.text,
      nvidiaApiKey: _nvidiaKeyController.text,
      ollamaApiKey: _ollamaKeyController.text,
      openclawGatewayToken: _openclawTokenController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final disabled = controller.isBusy;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 760 ? 2 : 1;
                final itemWidth =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _field(
                      width: itemWidth,
                      controller: _serverController,
                      enabled: !disabled,
                      label: appText('服务器地址 *', 'Server address *'),
                      icon: Icons.dns_outlined,
                    ),
                    _field(
                      width: itemWidth,
                      controller: _domainController,
                      enabled: !disabled,
                      label: appText('Workspace 域名 *', 'Workspace domain *'),
                      icon: Icons.public_outlined,
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 14, top: 2),
                        child: Text(
                          appText(
                            '将检测桥接域名：${controller.bridgeDomain}',
                            'Bridge domain will be checked: ${controller.bridgeDomain}',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    _field(
                      width: itemWidth,
                      controller: _userController,
                      enabled: !disabled,
                      label: appText('SSH 用户名 *', 'SSH username *'),
                      icon: Icons.person_outline,
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: SegmentedButton<AuthMethod>(
                        segments: [
                          ButtonSegment(
                            value: AuthMethod.sshKey,
                            icon: const Icon(Icons.key_outlined),
                            label: Text(appText('SSH Key', 'SSH Key')),
                          ),
                          ButtonSegment(
                            value: AuthMethod.password,
                            icon: const Icon(Icons.password_outlined),
                            label: Text(appText('密码', 'Password')),
                          ),
                        ],
                        selected: {controller.authMethod},
                        onSelectionChanged: disabled
                            ? null
                            : (value) => controller.updateForm(
                                authMethod: value.single,
                              ),
                      ),
                    ),
                    if (controller.authMethod == AuthMethod.password)
                      _field(
                        width: itemWidth,
                        controller: _passwordController,
                        enabled: !disabled,
                        label: appText('SSH 密码 *', 'SSH password *'),
                        icon: Icons.lock_outline,
                        obscureText: true,
                      )
                    else ...[
                      _field(
                        width: itemWidth,
                        controller: _keyPathController,
                        enabled: !disabled,
                        label: appText('SSH Key 文件路径', 'SSH key file path'),
                        icon: Icons.folder_outlined,
                      ),
                      _field(
                        width: constraints.maxWidth,
                        controller: _keyController,
                        enabled: !disabled,
                        label: appText('SSH Key 内容', 'SSH key content'),
                        icon: Icons.article_outlined,
                        minLines: 3,
                        maxLines: 5,
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: disabled
                    ? null
                    : () => controller.updateForm(
                        showAdvanced: !controller.showAdvanced,
                      ),
                icon: Icon(
                  controller.showAdvanced
                      ? Icons.expand_less
                      : Icons.expand_more,
                ),
                label: Text(appText('高级选项', 'Advanced options')),
              ),
            ),
            if (controller.showAdvanced) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _field(
                    width: 140,
                    controller: _portController,
                    enabled: !disabled,
                    label: appText('SSH 端口', 'SSH port'),
                    icon: Icons.numbers_outlined,
                    keyboardType: TextInputType.number,
                  ),
                  _field(
                    width: 220,
                    controller: _sudoController,
                    enabled: !disabled,
                    label: appText('sudo 密码', 'sudo password'),
                    icon: Icons.admin_panel_settings_outlined,
                    obscureText: true,
                  ),
                  _field(
                    width: 320,
                    controller: _installPathController,
                    enabled: !disabled,
                    label: appText('安装路径', 'Install path'),
                    icon: Icons.storage_outlined,
                  ),
                  _field(
                    width: 320,
                    controller: _deepseekKeyController,
                    enabled: !disabled,
                    label: 'DEEPSEEK_API_KEY',
                    icon: Icons.key_outlined,
                    obscureText: true,
                  ),
                  _field(
                    width: 320,
                    controller: _nvidiaKeyController,
                    enabled: !disabled,
                    label: 'NVIDIA_API_KEY',
                    icon: Icons.key_outlined,
                    obscureText: true,
                  ),
                  _field(
                    width: 320,
                    controller: _ollamaKeyController,
                    enabled: !disabled,
                    label: 'OLLAMA_API_KEY',
                    icon: Icons.key_outlined,
                    obscureText: true,
                  ),
                  _field(
                    width: 320,
                    controller: _openclawTokenController,
                    enabled: !disabled,
                    label: 'OPENCLAW_GATEWAY_TOKEN',
                    icon: Icons.key_outlined,
                    obscureText: true,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('workspace-management-detect-button'),
                  onPressed: disabled
                      ? null
                      : () {
                          _sync();
                          widget.onDetect();
                        },
                  icon: const Icon(Icons.health_and_safety_outlined),
                  label: Text(appText('检测服务器', 'Detect server')),
                ),
                FilledButton.icon(
                  key: const Key('workspace-management-create-button'),
                  onPressed: disabled
                      ? null
                      : () {
                          _sync();
                          widget.onCreate();
                        },
                  icon: const Icon(Icons.rocket_launch_outlined),
                  label: Text(appText('创建工作空间', 'Create workspace')),
                ),
                Tooltip(
                  message: appText(
                    '等待 playbooks 仓库提供 upgrade-ai-workspace.yml 后启用',
                    'Enabled after playbooks provides upgrade-ai-workspace.yml',
                  ),
                  child: FilledButton.tonalIcon(
                    key: const Key('workspace-management-upgrade-button'),
                    onPressed: null,
                    icon: const Icon(Icons.system_update_alt_outlined),
                    label: Text(appText('升级工作空间', 'Upgrade workspace')),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _field({
    required double width,
    required TextEditingController controller,
    required bool enabled,
    required String label,
    required IconData icon,
    bool obscureText = false,
    int minLines = 1,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        minLines: minLines,
        maxLines: obscureText ? 1 : maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
        ),
      ),
    );
  }
}
