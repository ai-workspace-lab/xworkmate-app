import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/surface_card.dart';
import 'workspace_management_form.dart';
import 'workspace_management_i18n.dart';
import 'workspace_management_result.dart';
import 'workspace_management_steps.dart';
import 'workspace_provision_controller.dart';

class WorkspaceManagementPanel extends StatefulWidget {
  const WorkspaceManagementPanel({
    super.key,
    required this.appController,
    WorkspaceProvisionController? provisionController,
  }) : _provisionController = provisionController;

  final AppController appController;
  final WorkspaceProvisionController? _provisionController;

  static Future<void> show(BuildContext context, AppController controller) {
    return showDialog<void>(
      context: context,
      builder: (_) => WorkspaceManagementPanel(appController: controller),
    );
  }

  @override
  State<WorkspaceManagementPanel> createState() =>
      _WorkspaceManagementPanelState();
}

class _WorkspaceManagementPanelState extends State<WorkspaceManagementPanel> {
  late final WorkspaceProvisionController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget._provisionController == null;
    _controller =
        widget._provisionController ??
        WorkspaceProvisionController(
          initialWorkspaceDomain: _initialWorkspaceDomain(),
        );
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  String _initialWorkspaceDomain() {
    final connection = widget.appController.connection;
    if (connection.status == RuntimeConnectionStatus.connected) {
      final remote = connection.remoteAddress?.trim() ?? '';
      final parsed = Uri.tryParse(remote.contains('://') ? remote : 'https://$remote');
      if (parsed != null && parsed.host.trim().isNotEmpty) {
        return parsed.host.trim();
      }
    }
    return widget.appController.settings.primaryGatewayProfile.host.trim();
  }

  Future<void> _confirmCreate() async {
    if (!_controller.canSubmit) {
      await _controller.createWorkspace();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText('确认创建工作空间', 'Confirm workspace creation')),
        content: Text(
          appText(
            '即将在 ${_controller.serverAddress} 上创建 AI 工作空间。\n\n'
                '域名: ${_controller.workspaceDomain}\n'
                'SSH 用户: ${_controller.sshUsername}\n\n'
                '该操作会安装系统依赖、配置服务和启动 systemd 服务，请确认这是你自己的服务器。',
            'XWorkmate will create an AI Workspace on ${_controller.serverAddress}.\n\n'
                'Domain: ${_controller.workspaceDomain}\n'
                'SSH user: ${_controller.sshUsername}\n\n'
                'This installs system dependencies, configures services, and starts systemd services. Confirm this is your own server.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appText('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(appText('确认创建', 'Create')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      unawaited(_controller.createWorkspace(installMissingPrerequisites: true));
    }
  }

  Future<void> _exportConfig() async {
    final yaml = _controller.exportYaml();
    await Clipboard.setData(ClipboardData(text: yaml));
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText('YAML 已导出', 'YAML exported')),
        content: SingleChildScrollView(child: SelectableText(yaml)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appText('关闭', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _importConfig() async {
    final yamlController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(appText('导入 YAML', 'Import YAML')),
          content: SizedBox(
            width: 720,
            child: TextField(
              controller: yamlController,
              minLines: 12,
              maxLines: 18,
              decoration: InputDecoration(
                hintText: appText('粘贴 YAML 配置', 'Paste YAML configuration'),
                alignLabelWithHint: true,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(appText('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(appText('导入', 'Import')),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        _controller.importYaml(yamlController.text);
      }
    } finally {
      yamlController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 820),
        child: SurfaceCard(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 14, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.dns_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            WorkspaceManagementText.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _controller.isBusy
                              ? null
                              : () => unawaited(_exportConfig()),
                          icon: const Icon(Icons.upload_outlined),
                          label: Text(appText('导出 YAML', 'Export YAML')),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: _controller.isBusy
                              ? null
                              : () => unawaited(_importConfig()),
                          icon: const Icon(Icons.download_outlined),
                          label: Text(appText('导入 YAML', 'Import YAML')),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _controller.isBusy
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          tooltip: appText('关闭', 'Close'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          WorkspaceManagementForm(
                            controller: _controller,
                            onDetect: () => unawaited(_controller.detectServer()),
                            onCreate: () => unawaited(_confirmCreate()),
                          ),
                          const SizedBox(height: 20),
                          WorkspaceManagementSteps(steps: _controller.steps),
                          const SizedBox(height: 12),
                          _LogPanel(controller: _controller),
                          const SizedBox(height: 12),
                          WorkspaceManagementResult(controller: _controller),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.controller});

  final WorkspaceProvisionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton.icon(
              key: const Key('workspace-management-log-toggle'),
              onPressed: () => controller.updateForm(
                logsExpanded: !controller.logsExpanded,
              ),
              icon: Icon(
                controller.logsExpanded ? Icons.expand_less : Icons.expand_more,
              ),
              label: Text(WorkspaceManagementText.logs),
            ),
            const Spacer(),
            if (controller.logsExpanded)
              IconButton(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: controller.logBuffer.text),
                ),
                icon: const Icon(Icons.copy_outlined),
                tooltip: WorkspaceManagementText.copyLogs,
              ),
          ],
        ),
        if (controller.logsExpanded)
          Container(
            key: const Key('workspace-management-log-content'),
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                controller.logBuffer.text.isEmpty
                    ? appText('暂无日志', 'No logs yet')
                    : controller.logBuffer.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
      ],
    );
  }
}
