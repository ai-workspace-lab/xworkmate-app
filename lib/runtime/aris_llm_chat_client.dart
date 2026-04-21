import 'dart:async';

class ArisLlmChatClient {
  ArisLlmChatClient({
    Duration rpcTimeout = const Duration(minutes: 2),
  }) : _rpcTimeout = rpcTimeout;

  final Duration _rpcTimeout;

  Future<String> chat({
    required String endpoint,
    required String apiKey,
    required String model,
    required String prompt,
    String systemPrompt = '',
  }) {
    return _callTool(
      toolName: 'chat',
      environment: <String, String>{},
      arguments: <String, dynamic>{},
    );
  }

  Future<String> claudeReview({
    required String prompt,
    String model = '',
    String systemPrompt = '',
    String tools = '',
  }) {
    return _callTool(
      toolName: 'claude_review',
      environment: <String, String>{},
      arguments: <String, dynamic>{},
    );
  }

  Future<String> _callTool({
    required String toolName,
    required Map<String, String> environment,
    required Map<String, dynamic> arguments,
  }) async {
    // Local Go core execution is deprecated in favor of bridge-mediated execution.
    throw UnsupportedError(
      'Local Go core execution is disabled. Use bridge endpoints like /acp-server/hermes instead.',
    );
  }
}
