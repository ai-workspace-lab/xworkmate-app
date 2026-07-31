import '../features/connectors/conversation_publish_connector.dart';
import '../features/plugins/harness_delivery_target.dart';
import '../features/settings/local_git_repository_connection.dart';
import '../i18n/app_language.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_github_publish.dart';
import 'app_controller_desktop_thread_sessions.dart';

class ConversationWorkflowOutcome {
  const ConversationWorkflowOutcome({
    required this.success,
    required this.message,
    this.publishPending = false,
  });

  final bool success;
  final String message;

  /// The plugin ran and a GitHub publish was requested, but the publish is
  /// deliberately left to an explicit second step — the app cannot yet observe
  /// plugin completion, and guessing it with a timer would publish a partial
  /// conversation.
  final bool publishPending;
}

extension AppControllerDesktopConversationWorkflow on AppController {
  /// There is a conversation to act on and at least one capability configured
  /// to act on it with.
  bool get canRunConversationWorkflow =>
      chatMessages.isNotEmpty &&
      (settings.githubRepository.isConfigured ||
          settings.harnessTargets.any((target) => target.isValid));

  /// Runs one user-confirmed [ConversationWorkflowRequest]. A request that
  /// selects no publish connector never reads the GitHub token and never
  /// issues a GitHub request.
  Future<ConversationWorkflowOutcome> runConversationWorkflow(
    ConversationWorkflowRequest request, {
    GitHubWriteRequest? put,
  }) async {
    final targets = settings.harnessTargets;
    final issues = request.validationIssues(
      availableTargets: targets,
      github: settings.githubRepository,
    );
    if (issues.isNotEmpty) {
      return ConversationWorkflowOutcome(
        success: false,
        message: issues.join('\n'),
      );
    }

    if (request.plugin.runsPlugin) {
      final target = request.plugin.resolveHarnessTarget(targets)!;
      try {
        await sendChatMessage(_harnessPluginPrompt(target));
      } catch (error) {
        return ConversationWorkflowOutcome(
          success: false,
          message: appText(
            'Harness Workflow 启动失败：$error',
            'Harness Workflow could not start: $error',
          ),
        );
      }
      // Harness failure must not auto-publish, so the publish step is never
      // chained onto this run.
      return ConversationWorkflowOutcome(
        success: true,
        message: request.publisher.publishes
            ? appText(
                'Harness Workflow 已启动。完成后再发布最新结果。',
                'Harness Workflow started. Publish the latest result once it finishes.',
              )
            : appText('Harness Workflow 已启动。', 'Harness Workflow started.'),
        publishPending: request.publisher.publishes,
      );
    }

    final result = await publishCurrentConversationToGitHub(put: put);
    return ConversationWorkflowOutcome(
      success: result.success,
      message: result.success
          ? appText('对话已发布到 GitHub。', 'Conversation published to GitHub.')
          : result.message,
    );
  }

  String _harnessPluginPrompt(HarnessTarget target) {
    final buffer = StringBuffer()
      ..writeln(renderHarnessDeliveryContextBlock(target))
      ..writeln()
      ..write(
        appText(
          '请在上述交付目标范围内继续处理当前对话。',
          'Continue the current conversation within the delivery target above.',
        ),
      );
    return buffer.toString();
  }
}
