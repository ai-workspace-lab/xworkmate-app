enum ExternalAgentTransport { subprocess, websocketJsonRpc }

extension ExternalAgentTransportCopy on ExternalAgentTransport {
  static ExternalAgentTransport fromJsonValue(String? value) {
    return ExternalAgentTransport.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ExternalAgentTransport.subprocess,
    );
  }
}

class ExternalCodeAgentProvider {
  const ExternalCodeAgentProvider({
    required this.id,
    required this.name,
    required this.command,
    this.transport = ExternalAgentTransport.subprocess,
    this.endpoint = '',
    this.defaultArgs = const <String>[],
    this.capabilities = const <String>[],
  });

  final String id;
  final String name;
  final String command;
  final ExternalAgentTransport transport;
  final String endpoint;
  final List<String> defaultArgs;
  final List<String> capabilities;
}
