import 'direct_single_agent_app_server_client.dart';
import 'multi_agent_orchestrator.dart';
import 'runtime_models.dart';

class SingleAgentProviderResolution {
  const SingleAgentProviderResolution({
    required this.selection,
    required this.resolvedProvider,
    required this.fallbackReason,
  });

  final SingleAgentProvider selection;
  final SingleAgentProvider? resolvedProvider;
  final String? fallbackReason;
}

class SingleAgentRunRequest {
  const SingleAgentRunRequest({
    required this.sessionId,
    required this.provider,
    required this.prompt,
    required this.model,
    required this.workingDirectory,
    required this.gatewayToken,
    required this.attachments,
    required this.selectedSkills,
    required this.aiGatewayBaseUrl,
    required this.aiGatewayApiKey,
    required this.config,
    this.onOutput,
    this.configuredCodexCliPath = '',
  });

  final String sessionId;
  final SingleAgentProvider provider;
  final String prompt;
  final String model;
  final String workingDirectory;
  final String gatewayToken;
  final List<CollaborationAttachment> attachments;
  final List<AssistantThreadSkillEntry> selectedSkills;
  final String aiGatewayBaseUrl;
  final String aiGatewayApiKey;
  final MultiAgentConfig config;
  final void Function(String text)? onOutput;
  final String configuredCodexCliPath;
}

class SingleAgentRunResult {
  const SingleAgentRunResult({
    required this.provider,
    required this.output,
    required this.success,
    required this.errorMessage,
    required this.shouldFallbackToAiChat,
    this.aborted = false,
    this.fallbackReason,
    this.resolvedModel = '',
  });

  final SingleAgentProvider provider;
  final String output;
  final bool success;
  final String errorMessage;
  final bool shouldFallbackToAiChat;
  final bool aborted;
  final String? fallbackReason;
  final String resolvedModel;
}

abstract class SingleAgentRunner {
  Future<SingleAgentProviderResolution> resolveProvider({
    required SingleAgentProvider selection,
    required String configuredCodexCliPath,
    required String gatewayToken,
  });

  Future<SingleAgentRunResult> run(SingleAgentRunRequest request);

  Future<void> abort(String sessionId);
}

class DefaultSingleAgentRunner implements SingleAgentRunner {
  DefaultSingleAgentRunner({
    required DirectSingleAgentAppServerClient appServerClient,
  }) : _appServerClient = appServerClient;

  final DirectSingleAgentAppServerClient _appServerClient;

  @override
  Future<SingleAgentProviderResolution> resolveProvider({
    required SingleAgentProvider selection,
    required String configuredCodexCliPath,
    required String gatewayToken,
  }) async {
    try {
      if (selection != SingleAgentProvider.auto) {
        final capabilities = await _appServerClient.loadCapabilities(
          provider: selection,
          gatewayToken: gatewayToken,
        );
        if (!capabilities.available ||
            !capabilities.supportsProvider(selection)) {
          return SingleAgentProviderResolution(
            selection: selection,
            resolvedProvider: null,
            fallbackReason:
                capabilities.errorMessage ??
                '${selection.label} endpoint is unavailable.',
          );
        }
        return SingleAgentProviderResolution(
          selection: selection,
          resolvedProvider: selection,
          fallbackReason: null,
        );
      }

      String? fallbackReason;
      for (final provider in kBuiltinExternalAcpProviders) {
        final capabilities = await _appServerClient.loadCapabilities(
          provider: provider,
          gatewayToken: gatewayToken,
        );
        if (capabilities.available && capabilities.supportsProvider(provider)) {
          return SingleAgentProviderResolution(
            selection: selection,
            resolvedProvider: provider,
            fallbackReason: null,
          );
        }
        fallbackReason ??= capabilities.errorMessage;
      }
      return SingleAgentProviderResolution(
        selection: selection,
        resolvedProvider: null,
        fallbackReason:
            fallbackReason ??
            'No external ACP endpoint is currently available.',
      );
    } catch (error) {
      return SingleAgentProviderResolution(
        selection: selection,
        resolvedProvider: null,
        fallbackReason: 'Single-agent app-server negotiation failed: $error',
      );
    }
  }

  @override
  Future<SingleAgentRunResult> run(SingleAgentRunRequest request) async {
    try {
      final result = await _appServerClient.run(
        DirectSingleAgentRunRequest(
          sessionId: request.sessionId,
          provider: request.provider,
          prompt: _augmentPrompt(request),
          model: request.model,
          workingDirectory: request.workingDirectory,
          gatewayToken: request.gatewayToken,
          selectedSkills: request.selectedSkills,
          onOutput: request.onOutput,
        ),
      );
      return SingleAgentRunResult(
        provider: request.provider,
        output: result.output,
        success: result.success,
        errorMessage: result.errorMessage,
        shouldFallbackToAiChat: !result.success && result.output.isEmpty,
        aborted: result.aborted,
        resolvedModel: result.resolvedModel,
        fallbackReason: !result.success
            ? 'Single-agent app-server run failed: ${result.errorMessage}'
            : null,
      );
    } catch (error) {
      final shouldFallback = _shouldFallbackToAiChat(error.toString());
      return SingleAgentRunResult(
        provider: request.provider,
        output: '',
        success: false,
        errorMessage: error.toString(),
        shouldFallbackToAiChat: shouldFallback,
        resolvedModel: '',
        fallbackReason: shouldFallback
            ? '${request.provider.label} provider is unavailable from the direct app-server endpoint.'
            : null,
      );
    }
  }

  @override
  Future<void> abort(String sessionId) async {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return;
    }
    await _appServerClient.abort(normalized);
  }

  bool _shouldFallbackToAiChat(String message) {
    final normalizedMessage = message.toLowerCase();
    return normalizedMessage.contains('timeout') ||
        normalizedMessage.contains('unavailable') ||
        normalizedMessage.contains('missing') ||
        normalizedMessage.contains('closed') ||
        normalizedMessage.contains('connect');
  }

  String _augmentPrompt(SingleAgentRunRequest request) {
    if (request.attachments.isEmpty) {
      return request.prompt;
    }
    final attachmentLines = request.attachments
        .map((item) => '- ${item.name}: ${item.path}')
        .join('\n');
    return 'User-selected local attachments:\n$attachmentLines\n\n${request.prompt}';
  }
}
