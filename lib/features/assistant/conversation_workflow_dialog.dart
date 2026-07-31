import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import '../connectors/conversation_publish_connector.dart';
import '../plugins/conversation_plugin.dart';
import '../plugins/harness_delivery_target.dart';
import '../settings/local_git_repository_connection.dart';

/// Asks the user to choose a conversation plugin and a publish connector,
/// independently, and confirms the combination before anything runs.
///
/// Returns null when the user cancels; no network request is made here.
Future<ConversationWorkflowRequest?> showConversationWorkflowDialog({
  required BuildContext context,
  required List<HarnessTarget> availableTargets,
  required GitHubRepositoryConnectorConfig github,
  VoidCallback? onOpenPluginSettings,
  VoidCallback? onOpenConnectorSettings,
}) {
  return showDialog<ConversationWorkflowRequest>(
    context: context,
    builder: (context) => ConversationWorkflowDialog(
      availableTargets: availableTargets,
      github: github,
      onOpenPluginSettings: onOpenPluginSettings,
      onOpenConnectorSettings: onOpenConnectorSettings,
    ),
  );
}

class ConversationWorkflowDialog extends StatefulWidget {
  const ConversationWorkflowDialog({
    super.key,
    required this.availableTargets,
    required this.github,
    this.onOpenPluginSettings,
    this.onOpenConnectorSettings,
  });

  final List<HarnessTarget> availableTargets;
  final GitHubRepositoryConnectorConfig github;
  final VoidCallback? onOpenPluginSettings;
  final VoidCallback? onOpenConnectorSettings;

  @override
  State<ConversationWorkflowDialog> createState() =>
      _ConversationWorkflowDialogState();
}

class _ConversationWorkflowDialogState
    extends State<ConversationWorkflowDialog> {
  ConversationPluginSelection _plugin = ConversationPluginSelection.none;
  ConversationPublishSelection _publisher = ConversationPublishSelection.none;

  List<HarnessTarget> get _validTargets => widget.availableTargets
      .where((target) => target.isValid)
      .toList(growable: false);

  ConversationWorkflowRequest get _request =>
      ConversationWorkflowRequest(plugin: _plugin, publisher: _publisher);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targets = _validTargets;
    final issues = _request.validationIssues(
      availableTargets: targets,
      github: widget.github,
    );
    final summary = _request.describe(
      availableTargets: targets,
      github: widget.github,
    );

    return AlertDialog(
      key: const Key('conversation-workflow-dialog'),
      title: Text(appText('运行对话工作流', 'Run conversation workflow')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SectionTitle(appText('对话插件', 'Conversation plugin')),
              RadioGroup<ConversationPluginId?>(
                groupValue: _plugin.pluginId,
                onChanged: (value) => setState(
                  () => _plugin = value == null
                      ? ConversationPluginSelection.none
                      : _plugin.copyWith(
                          pluginId: value,
                          harnessTargetId: _plugin.harnessTargetId.isEmpty
                              ? (targets.length == 1 ? targets.single.id : '')
                              : _plugin.harnessTargetId,
                        ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<ConversationPluginId?>(
                      key: const Key('conversation-workflow-plugin-none'),
                      value: null,
                      title: Text(appText('不使用插件', 'No plugin')),
                    ),
                    RadioListTile<ConversationPluginId?>(
                      key: const Key('conversation-workflow-plugin-harness'),
                      value: ConversationPluginId.harnessWorkflow,
                      title: Text(ConversationPluginId.harnessWorkflow.label),
                    ),
                  ],
                ),
              ),
              if (_plugin.pluginId == ConversationPluginId.harnessWorkflow)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: targets.isEmpty
                      ? _EmptyStateRow(
                          key: const Key(
                            'conversation-workflow-no-harness-target',
                          ),
                          message: appText(
                            '还没有可用的 Harness 交付目标。',
                            'No Harness delivery target is configured yet.',
                          ),
                          actionLabel: appText(
                            '前往设置 → 插件',
                            'Open Settings → Plugins',
                          ),
                          onAction: widget.onOpenPluginSettings,
                        )
                      : DropdownButtonFormField<String>(
                          key: const Key(
                            'conversation-workflow-harness-target',
                          ),
                          initialValue: _plugin.harnessTargetId.isEmpty
                              ? null
                              : _plugin.harnessTargetId,
                          decoration: InputDecoration(
                            labelText: appText('交付目标', 'Delivery target'),
                          ),
                          items: targets
                              .map(
                                (target) => DropdownMenuItem<String>(
                                  value: target.id,
                                  child: Text(target.label),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) => setState(
                            () => _plugin = _plugin.copyWith(
                              harnessTargetId: value ?? '',
                            ),
                          ),
                        ),
                ),
              const SizedBox(height: 12),
              _SectionTitle(appText('发布连接器', 'Publish connector')),
              RadioGroup<ConversationPublishConnectorId?>(
                groupValue: _publisher.connectorId,
                onChanged: (value) => setState(
                  () => _publisher = ConversationPublishSelection(
                    connectorId: value,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<ConversationPublishConnectorId?>(
                      key: const Key('conversation-workflow-publish-none'),
                      value: null,
                      title: Text(appText('不发布', 'Do not publish')),
                    ),
                    RadioListTile<ConversationPublishConnectorId?>(
                      key: const Key('conversation-workflow-publish-github'),
                      value: ConversationPublishConnectorId.githubApi,
                      enabled: widget.github.isConfigured,
                      title: Text(
                        ConversationPublishConnectorId.githubApi.label,
                      ),
                      subtitle: widget.github.isConfigured
                          ? Text(describeGitHubConnectorTarget(widget.github))
                          : null,
                    ),
                  ],
                ),
              ),
              if (!widget.github.isConfigured)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: _EmptyStateRow(
                    key: const Key('conversation-workflow-github-unconfigured'),
                    message: appText(
                      'GitHub 连接器尚未连接。',
                      'The GitHub connector is not connected yet.',
                    ),
                    actionLabel: appText(
                      '前往设置 → 连接器',
                      'Open Settings → Connectors',
                    ),
                    onAction: widget.onOpenConnectorSettings,
                  ),
                ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  key: const Key('conversation-workflow-summary'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(summary, style: theme.textTheme.bodySmall),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('conversation-workflow-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appText('取消', 'Cancel')),
        ),
        FilledButton(
          key: const Key('conversation-workflow-confirm'),
          onPressed: issues.isEmpty
              ? () => Navigator.of(context).pop(_request)
              : null,
          child: Text(_request.primaryActionLabel),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _EmptyStateRow extends StatelessWidget {
  const _EmptyStateRow({
    super.key,
    required this.message,
    required this.actionLabel,
    this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(message, style: Theme.of(context).textTheme.bodySmall),
      ),
      TextButton(onPressed: onAction, child: Text(actionLabel)),
    ],
  );
}
