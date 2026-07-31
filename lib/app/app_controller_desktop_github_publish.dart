import '../features/settings/local_git_repository_connection.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_thread_sessions.dart';

extension AppControllerDesktopGitHubPublish on AppController {
  bool get canPublishCurrentConversationToGitHub =>
      settings.githubRepository.isConfigured && chatMessages.isNotEmpty;

  Future<GitHubApiResult> publishCurrentConversationToGitHub() async {
    final config = settings.githubRepository;
    if (!config.isConfigured) {
      return GitHubApiResult.failure(
        'Connect a GitHub repository in Settings first.',
      );
    }
    final token = await settingsController.loadSecretValueByRef(
      config.tokenRef,
    );
    if (token.isEmpty) {
      return GitHubApiResult.failure(
        'The GitHub token is missing. Reconnect the repository in Settings.',
      );
    }
    final messages = chatMessages
        .where((message) => !message.pending && message.text.trim().isNotEmpty)
        .map((message) => (role: message.role, text: message.text))
        .toList(growable: false);
    if (messages.isEmpty) {
      return GitHubApiResult.failure(
        'There is no completed conversation to publish.',
      );
    }
    final thread = taskThreadForSessionInternal(currentSessionKey);
    final title = thread?.title.trim().isNotEmpty == true
        ? thread!.title.trim()
        : 'XWorkmate conversation';
    final markdown = renderGitHubConversationMarkdown(
      title: title,
      messages: messages,
    );
    final path = buildGitHubConversationPath(
      directory: config.publishPath,
      title: title,
      timestamp: DateTime.now(),
    );
    return publishConversationToGitHub(
      repository: config.repository,
      token: token,
      branch: config.branch,
      path: path,
      markdown: markdown,
    );
  }
}
