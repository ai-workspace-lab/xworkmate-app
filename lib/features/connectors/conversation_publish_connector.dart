import 'package:flutter/foundation.dart';

import '../../i18n/app_language.dart';
import '../plugins/conversation_plugin.dart';
import '../plugins/harness_delivery_target.dart';
import '../settings/local_git_repository_connection.dart';

/// A publish connector decides *where* a conversation is published. It is
/// chosen independently of the conversation plugin.
enum ConversationPublishConnectorId { githubApi }

extension ConversationPublishConnectorIdCopy on ConversationPublishConnectorId {
  String get label => switch (this) {
    ConversationPublishConnectorId.githubApi => appText(
      'GitHub API',
      'GitHub API',
    ),
  };
}

@immutable
class ConversationPublishSelection {
  const ConversationPublishSelection({this.connectorId});

  /// null means "do not publish" — no connector request is ever made.
  final ConversationPublishConnectorId? connectorId;

  static const ConversationPublishSelection none =
      ConversationPublishSelection();

  bool get publishes => connectorId != null;

  bool get usesGitHub => connectorId == ConversationPublishConnectorId.githubApi;

  List<String> validationIssues(GitHubRepositoryConnectorConfig github) {
    if (connectorId == null) return const <String>[];
    if (!github.isConfigured) {
      return <String>[
        appText(
          '请先在设置 → 连接器中连接 GitHub 仓库。',
          'Connect a GitHub repository in Settings → Connectors first.',
        ),
      ];
    }
    return const <String>[];
  }

  @override
  bool operator ==(Object other) =>
      other is ConversationPublishSelection && other.connectorId == connectorId;

  @override
  int get hashCode => connectorId.hashCode;
}

/// One user-confirmed run of the conversation workflow. Memory-only: it
/// records a choice, never a credential.
@immutable
class ConversationWorkflowRequest {
  const ConversationWorkflowRequest({
    this.plugin = ConversationPluginSelection.none,
    this.publisher = ConversationPublishSelection.none,
  });

  final ConversationPluginSelection plugin;
  final ConversationPublishSelection publisher;

  /// Both "no plugin" and "no publish" leaves nothing to do.
  bool get isEmpty => !plugin.runsPlugin && !publisher.publishes;

  List<String> validationIssues({
    required List<HarnessTarget> availableTargets,
    required GitHubRepositoryConnectorConfig github,
  }) {
    if (isEmpty) {
      return <String>[
        appText(
          '请至少选择一个插件或发布连接器。',
          'Select at least a plugin or a publish connector.',
        ),
      ];
    }
    return <String>[
      ...plugin.validationIssues(availableTargets),
      ...publisher.validationIssues(github),
    ];
  }

  /// The primary button label for this combination.
  String get primaryActionLabel {
    if (plugin.runsPlugin && publisher.publishes) {
      return appText('运行并发布', 'Run and publish');
    }
    if (plugin.runsPlugin) return appText('运行', 'Run');
    if (publisher.publishes) return appText('发布', 'Publish');
    return appText('运行', 'Run');
  }

  /// A plain-language summary shown above the primary button so the network
  /// side effect is visible before it happens.
  String describe({
    required List<HarnessTarget> availableTargets,
    required GitHubRepositoryConnectorConfig github,
  }) {
    final parts = <String>[];
    final target = plugin.resolveHarnessTarget(availableTargets);
    if (plugin.runsPlugin && target != null) {
      parts.add(
        appText(
          '将使用 ${plugin.pluginId!.label} 处理当前对话，交付目标 ${target.label}。',
          'Process this conversation with ${plugin.pluginId!.label} against ${target.label}.',
        ),
      );
    }
    if (publisher.usesGitHub && github.isConfigured) {
      final where = describeGitHubConnectorTarget(github);
      parts.add(
        plugin.runsPlugin
            ? appText(
                '完成后通过 GitHub API 发布到 $where。',
                'When it finishes, publish through the GitHub API to $where.',
              )
            : appText(
                '通过 GitHub API 发布当前对话到 $where。',
                'Publish this conversation through the GitHub API to $where.',
              ),
      );
    }
    return parts.join('\n');
  }
}
