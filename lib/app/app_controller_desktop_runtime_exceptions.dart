class AiGatewayChatExceptionInternal implements Exception {
  const AiGatewayChatExceptionInternal(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiGatewayAbortExceptionInternal implements Exception {
  const AiGatewayAbortExceptionInternal(this.partialText);

  final String partialText;
}
