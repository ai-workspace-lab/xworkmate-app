import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../runtime/runtime_controllers.dart';
import 'workspace_management_i18n.dart';
import 'workspace_provision_controller.dart';
import 'workspace_provision_models.dart';

class WorkspaceManagementResult extends StatelessWidget {
  const WorkspaceManagementResult({
    super.key,
    required this.controller,
    required this.appController,
  });

  final WorkspaceProvisionController controller;
  final AppController appController;

  @override
  Widget build(BuildContext context) {
    if (controller.phase == ProvisionPhase.success) {
      return _success(context);
    }
    if (controller.phase == ProvisionPhase.failed) {
      return _failure(context);
    }
    return const SizedBox.shrink();
  }

  Widget _success(BuildContext context) {
    final theme = Theme.of(context);
    final result = controller.deploymentResult;
    final url = result?.url ?? '';
    final token = result?.bridgeToken ?? '';
    return Container(
      key: const Key('workspace-management-result-success'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                WorkspaceManagementText.ready,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (url.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(url),
            const SizedBox(height: 8),
            Text(
              appText('预生成 Bridge Token', 'Pre-generated bridge token'),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(token),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: url)),
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(WorkspaceManagementText.copyAddress),
                ),
                OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: token)),
                  icon: const Icon(Icons.key_outlined),
                  label: Text(appText('复制 Token', 'Copy token')),
                ),
                OutlinedButton.icon(
                  onPressed: result == null
                      ? null
                      : () => _saveAsDefault(result),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(appText('设为默认', 'Set as default')),
                ),
                OutlinedButton.icon(
                  onPressed: result == null ? null : () => _downloadResult(result),
                  icon: const Icon(Icons.download_outlined),
                  label: Text(appText('下载凭据', 'Download credentials')),
                ),
                FilledButton.tonalIcon(
                  onPressed: null,
                  icon: const Icon(Icons.settings_remote_outlined),
                  label: Text(WorkspaceManagementText.connectToWorkspace),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _downloadResult(WorkspaceDeploymentResult result) async {
    final location = await getSaveLocation(
      suggestedName: 'xworkmate-bridge-credentials.txt',
    );
    if (location == null) {
      return;
    }
    await File(location.path).writeAsString(result.downloadText);
  }

  Future<void> _saveAsDefault(WorkspaceDeploymentResult result) async {
    final settingsController = appController.settingsController;
    final currentSettings = appController.settings;
    final nextSettings = await settingsController.buildSavedAccountProfileSettings(
      settings: currentSettings,
      accountBaseUrl: currentSettings.accountBaseUrl,
      accountIdentifier: currentSettings.accountUsername,
      bridgeServerUrl: result.url,
      bridgeToken: result.bridgeToken,
      isManualBridge: true,
    );
    await appController.saveSettings(nextSettings, refreshAfterSave: true);
  }

  Widget _failure(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('workspace-management-result-failed'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  WorkspaceManagementText.failed,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  controller.errorMessage ??
                      appText('请查看日志。', 'Check logs.'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
