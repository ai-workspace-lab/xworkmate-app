part of 'gateway_runtime.dart';

class GatewayRuntimeException implements Exception {
  GatewayRuntimeException(this.message, {this.code, this.details});

  final String message;
  final String? code;
  final Object? details;

  String? get detailCode => stringValue(asMap(details)['code']);

  @override
  String toString() => code == null ? message : '$code: $message';
}
