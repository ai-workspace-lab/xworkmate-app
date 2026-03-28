part of 'gateway_runtime.dart';

class GatewayPushEvent {
  const GatewayPushEvent({
    required this.event,
    required this.payload,
    this.sequence,
  });

  final String event;
  final dynamic payload;
  final int? sequence;
}
