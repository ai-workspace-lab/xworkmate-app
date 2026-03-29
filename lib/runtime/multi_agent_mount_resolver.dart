import 'runtime_models.dart';

class ArisMountProbe {
  const ArisMountProbe({
    required this.available,
    required this.bundleVersion,
    required this.llmChatServerPath,
    required this.skillCount,
    required this.bridgeAvailable,
    this.error = '',
  });

  const ArisMountProbe.unavailable({this.error = ''})
    : available = false,
      bundleVersion = '',
      llmChatServerPath = '',
      skillCount = 0,
      bridgeAvailable = false;

  final bool available;
  final String bundleVersion;
  final String llmChatServerPath;
  final int skillCount;
  final bool bridgeAvailable;
  final String error;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'available': available,
      'bundleVersion': bundleVersion,
      'llmChatServerPath': llmChatServerPath,
      'skillCount': skillCount,
      'bridgeAvailable': bridgeAvailable,
      'error': error,
    };
  }
}

abstract class MultiAgentMountResolver {
  Future<MultiAgentConfig?> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
    String configuredCodexCliPath = '',
    required String codexHome,
    required String opencodeHome,
    required ArisMountProbe arisProbe,
  });

  Future<void> dispose();
}
