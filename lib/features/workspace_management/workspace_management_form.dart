import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import 'playbook_runner.dart';
import 'workspace_provision_controller.dart';
import 'workspace_provision_models.dart';

class WorkspaceManagementForm extends StatefulWidget {
  const WorkspaceManagementForm({
    super.key,
    required this.controller,
    required this.onDetect,
    required this.onCreate,
    required this.onUpgrade,
  });

  final WorkspaceProvisionController controller;
  final VoidCallback onDetect;
  final VoidCallback onCreate;
  final VoidCallback onUpgrade;

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
  final List<_ExtraRowControllers> _extraRows = <_ExtraRowControllers>[];
  bool _syncingFromController = false;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    widget.controller.addListener(_handleControllerUpdate);
    _serverController = TextEditingController(text: c.serverAddress);
    _domainController = TextEditingController(text: c.workspaceDomain);
    _userController = TextEditingController(text: c.sshUsername);
    _passwordController = TextEditingController(text: c.sshPassword ?? '');
    _keyController = TextEditingController(text: c.sshKeyContent ?? '');
    _keyPathController = TextEditingController(text: c.sshKeyPath ?? '');
    _portController = TextEditingController(text: c.sshPort.toString());
    _sudoController = TextEditingController(text: c.sudoPassword ?? '');
    _installPathController = TextEditingController(
      text: PlaybookRunner.setupScriptUrl,
    );
    for (final row in c.extraConfigs) {
      _extraRows.add(
        _ExtraRowControllers(
          keyController: TextEditingController(text: row.key),
          valueController: TextEditingController(text: row.value),
          noteController: TextEditingController(text: row.note),
        ),
      );
    }
  }

  void _handleControllerUpdate() {
    if (!mounted || _syncingFromController) {
      return;
    }
    _syncingFromController = true;
    try {
      _syncText(_serverController, widget.controller.serverAddress);
      _syncText(_domainController, widget.controller.workspaceDomain);
      _syncText(_userController, widget.controller.sshUsername);
      _syncText(_passwordController, widget.controller.sshPassword ?? '');
      _syncText(_keyController, widget.controller.sshKeyContent ?? '');
      _syncText(_keyPathController, widget.controller.sshKeyPath ?? '');
      _syncText(_portController, widget.controller.sshPort.toString());
      _syncText(_sudoController, widget.controller.sudoPassword ?? '');
      _syncText(_installPathController, PlaybookRunner.setupScriptUrl);
      _syncExtraRows(widget.controller.extraConfigs);
    } finally {
      _syncingFromController = false;
    }
  }

  void _syncText(TextEditingController controller, String value) {
    if (controller.text != value) {
      controller.value = controller.value.copyWith(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
        composing: TextRange.empty,
      );
    }
  }

  void _syncExtraRows(List<WorkspaceExtraConfig> configs) {
    if (_extraRows.length != configs.length) {
      for (final row in _extraRows) {
        row.dispose();
      }
      _extraRows
        ..clear()
        ..addAll(
          configs.map(
            (row) => _ExtraRowControllers(
              keyController: TextEditingController(text: row.key),
              valueController: TextEditingController(text: row.value),
              noteController: TextEditingController(text: row.note),
            ),
          ),
        );
      return;
    }
    for (var i = 0; i < configs.length; i++) {
      final source = configs[i];
      final row = _extraRows[i];
      _syncText(row.keyController, source.key);
      _syncText(row.valueController, source.value);
      _syncText(row.noteController, source.note);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerUpdate);
    _serverController.dispose();
    _domainController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _keyController.dispose();
    _keyPathController.dispose();
    _portController.dispose();
    _sudoController.dispose();
    _installPathController.dispose();
    for (final row in _extraRows) {
      row.dispose();
    }
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
      installPath: '',
      extraConfigs: _extraRows
          .map(
            (row) => WorkspaceExtraConfig(
              key: row.keyController.text.trim(),
              value: row.valueController.text,
              note: row.noteController.text.trim(),
            ),
          )
          .where((row) => row.key.trim().isNotEmpty)
          .toList(),
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
                            '将按当前输入检测桥接域名：${controller.bridgeDomain}',
                            'Bridge domain will be checked from the current input: ${controller.bridgeDomain}',
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
                    enabled: false,
                    label: appText('执行脚本', 'Setup script'),
                    icon: Icons.storage_outlined,
                  ),
                  _ExtraConfigEditor(
                    rows: _extraRows,
                    enabled: !disabled,
                    onAdd: () {
                      setState(() {
                        _extraRows.add(
                          _ExtraRowControllers(
                            keyController: TextEditingController(),
                            valueController: TextEditingController(),
                            noteController: TextEditingController(),
                          ),
                        );
                      });
                    },
                    onRemove: (index) {
                      setState(() {
                        final row = _extraRows.removeAt(index);
                        row.dispose();
                      });
                    },
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
                FilledButton.tonalIcon(
                  key: const Key('workspace-management-upgrade-button'),
                  onPressed: disabled
                      ? null
                      : () {
                          _sync();
                          widget.onUpgrade();
                        },
                  icon: const Icon(Icons.system_update_alt_outlined),
                  label: Text(appText('升级工作空间', 'Upgrade workspace')),
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

class _ExtraConfigEditor extends StatelessWidget {
  const _ExtraConfigEditor({
    required this.rows,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_ExtraRowControllers> rows;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              appText('脚本参数', 'Script parameters'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.add),
              label: Text(appText('添加行', 'Add row')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(rows.length, (index) {
          final row = rows[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ExtraConfigRow(
              index: index,
              row: row,
              enabled: enabled,
              onRemove: () => onRemove(index),
            ),
          );
        }),
      ],
    );
  }
}

class _ExtraConfigRow extends StatelessWidget {
  const _ExtraConfigRow({
    required this.index,
    required this.row,
    required this.enabled,
    required this.onRemove,
  });

  final int index;
  final _ExtraRowControllers row;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 820 ? 3 : 1;
        final itemWidth = columns == 3
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: itemWidth,
              child: TextField(
                controller: row.keyController,
                enabled: enabled,
                decoration: InputDecoration(
                  labelText: appText('KEY', 'KEY'),
                  prefixIcon: const Icon(Icons.key_outlined, size: 18),
                ),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: TextField(
                controller: row.valueController,
                enabled: enabled,
                obscureText: row.isSensitiveKey,
                decoration: InputDecoration(
                  labelText: appText('VALUE', 'VALUE'),
                  prefixIcon: const Icon(Icons.data_object_outlined, size: 18),
                ),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: TextField(
                controller: row.noteController,
                enabled: enabled,
                maxLength: 20,
                decoration: InputDecoration(
                  labelText: appText('备注(20字内)', 'Note (<=20 chars)'),
                  prefixIcon: const Icon(Icons.note_outlined, size: 18),
                  counterText: '',
                ),
              ),
            ),
            if (columns == 1)
              SizedBox(
                width: constraints.maxWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: enabled ? onRemove : null,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: appText('删除', 'Delete'),
                  ),
                ),
              )
            else
              IconButton(
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.delete_outline),
                tooltip: appText('删除', 'Delete'),
              ),
          ],
        );
      },
    );
  }
}

class _ExtraRowControllers {
  _ExtraRowControllers({
    required this.keyController,
    required this.valueController,
    required this.noteController,
  });

  final TextEditingController keyController;
  final TextEditingController valueController;
  final TextEditingController noteController;

  bool get isSensitiveKey {
    final key = keyController.text.trim().toUpperCase();
    return key.contains('KEY') ||
        key.contains('TOKEN') ||
        key.contains('SECRET');
  }

  void dispose() {
    keyController.dispose();
    valueController.dispose();
    noteController.dispose();
  }
}
