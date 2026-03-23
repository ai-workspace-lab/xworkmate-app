import 'gateway_acp_client.dart';
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
  final List<CollaborationAttachment> attachments;
  final List<String> selectedSkills;
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
  });

  final SingleAgentProvider provider;
  final String output;
  final bool success;
  final String errorMessage;
  final bool shouldFallbackToAiChat;
  final bool aborted;
  final String? fallbackReason;
}

abstract class SingleAgentRunner {
  Future<SingleAgentProviderResolution> resolveProvider({
    required SingleAgentProvider selection,
    required String configuredCodexCliPath,
  });

  Future<SingleAgentRunResult> run(SingleAgentRunRequest request);

  Future<void> abort(String sessionId);
}

class DefaultSingleAgentRunner implements SingleAgentRunner {
  DefaultSingleAgentRunner({required GatewayAcpClient acpClient})
    : _acpClient = acpClient;

  static const List<SingleAgentProvider> _autoOrder = <SingleAgentProvider>[
    SingleAgentProvider.codex,
    SingleAgentProvider.opencode,
    SingleAgentProvider.claude,
    SingleAgentProvider.gemini,
  ];

  final GatewayAcpClient _acpClient;

  @override
  Future<SingleAgentProviderResolution> resolveProvider({
    required SingleAgentProvider selection,
    required String configuredCodexCliPath,
  }) async {
    try {
      final capabilities = await _acpClient.loadCapabilities();
      if (!capabilities.singleAgent) {
        return SingleAgentProviderResolution(
          selection: selection,
          resolvedProvider: null,
          fallbackReason: 'ACP single-agent capability is unavailable.',
        );
      }
      if (selection != SingleAgentProvider.auto) {
        final available = capabilities.providers.contains(selection);
        return SingleAgentProviderResolution(
          selection: selection,
          resolvedProvider: available ? selection : null,
          fallbackReason: available
              ? null
              : '${selection.label} provider is unavailable from ACP adapter.',
        );
      }

      for (final provider in _autoOrder) {
        if (capabilities.providers.contains(provider)) {
          return SingleAgentProviderResolution(
            selection: selection,
            resolvedProvider: provider,
            fallbackReason: null,
          );
        }
      }
      return const SingleAgentProviderResolution(
        selection: SingleAgentProvider.auto,
        resolvedProvider: null,
        fallbackReason: 'No ACP single-agent provider is currently available.',
      );
    } catch (error) {
      return SingleAgentProviderResolution(
        selection: selection,
        resolvedProvider: null,
        fallbackReason: 'ACP capability negotiation failed: $error',
      );
    }
  }

  @override
  Future<SingleAgentRunResult> run(SingleAgentRunRequest request) async {
    try {
      final result = await _acpClient.runSingleAgent(
        GatewayAcpSingleAgentRequest(
          sessionId: request.sessionId,
          threadId: request.sessionId,
          provider: request.provider,
          prompt: _augmentPrompt(request),
          model: request.model,
          workingDirectory: request.workingDirectory,
          attachments: request.attachments,
          selectedSkills: request.selectedSkills,
          aiGatewayBaseUrl: request.aiGatewayBaseUrl,
          aiGatewayApiKey: request.aiGatewayApiKey,
          resumeSession: true,
        ),
        onUpdate: (update) {
          if (update.textDelta.isNotEmpty) {
            request.onOutput?.call(update.textDelta);
          }
        },
      );
      return SingleAgentRunResult(
        provider: request.provider,
        output: result.output,
        success: result.success,
        errorMessage: result.errorMessage,
        shouldFallbackToAiChat: !result.success && result.output.isEmpty,
        fallbackReason: !result.success
            ? 'ACP single-agent run failed: ${result.errorMessage}'
            : null,
      );
    } on GatewayAcpException catch (error) {
      final shouldFallback = _shouldFallbackToAiChat(error.code, error.message);
      return SingleAgentRunResult(
        provider: request.provider,
        output: '',
        success: false,
        errorMessage: error.toString(),
        shouldFallbackToAiChat: shouldFallback,
        fallbackReason: shouldFallback
            ? '${request.provider.label} provider is unavailable from ACP adapter.'
            : null,
      );
    } catch (error) {
      return SingleAgentRunResult(
        provider: request.provider,
        output: '',
        success: false,
        errorMessage: error.toString(),
        shouldFallbackToAiChat: true,
        fallbackReason:
            '${request.provider.label} provider run failed before completion.',
      );
    }
  }

  @override
  Future<void> abort(String sessionId) async {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return;
    }
    try {
      await _acpClient.cancelSession(
        sessionId: normalized,
        threadId: normalized,
      );
    } catch (_) {
      // Best effort only.
    }
  }

  bool _shouldFallbackToAiChat(String? code, String message) {
    final normalizedCode = code?.trim().toUpperCase() ?? '';
    if (normalizedCode == 'ACP_ENDPOINT_MISSING' ||
        normalizedCode == 'ACP_HTTP_ENDPOINT_MISSING' ||
        normalizedCode == 'ACP_WS_CONNECT_TIMEOUT' ||
        normalizedCode == 'ACP_WS_RUNTIME_ERROR' ||
        normalizedCode == 'ACP_WS_EARLY_CLOSE') {
      return true;
    }
    final normalizedMessage = message.toLowerCase();
    return normalizedMessage.contains('timeout') ||
        normalizedMessage.contains('unavailable') ||
        normalizedMessage.contains('missing');
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
