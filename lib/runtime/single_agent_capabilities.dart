import 'runtime_models.dart';

class SingleAgentCapabilities {
  const SingleAgentCapabilities({
    required this.available,
    required this.supportedProviders,
    required this.endpoint,
    this.errorMessage,
  });

  const SingleAgentCapabilities.unavailable({
    required this.endpoint,
    this.errorMessage,
  }) : available = false,
       supportedProviders = const <SingleAgentProvider>[];

  final bool available;
  final List<SingleAgentProvider> supportedProviders;
  final String endpoint;
  final String? errorMessage;

  bool get supportsCodex => supportsProvider(SingleAgentProvider.codex);

  bool supportsProvider(SingleAgentProvider provider) =>
      supportedProviders.contains(provider);
}
