import 'dart:async';

import 'gateway_runtime_errors.dart';
import 'gateway_runtime_session_client.dart';
import 'go_acp_stdio_bridge.dart';

class GoGatewayRuntimeDesktopClient implements GatewayRuntimeSessionClient {
  GoGatewayRuntimeDesktopClient({GoAcpStdioBridge? bridge})
    : _bridge = bridge ?? GoAcpStdioBridge() {
    _notificationsSubscription = _bridge.notifications.listen(
      _handleNotification,
      onError: (Object error, StackTrace stackTrace) {
        _updatesController.addError(error, stackTrace);
      },
    );
  }

  final GoAcpStdioBridge _bridge;
  late final StreamSubscription<Map<String, dynamic>> _notificationsSubscription;
  final StreamController<GatewayRuntimeSessionUpdate> _updatesController =
      StreamController<GatewayRuntimeSessionUpdate>.broadcast();

  @override
  Stream<GatewayRuntimeSessionUpdate> get updates => _updatesController.stream;

  @override
  Future<GatewayRuntimeSessionConnectResult> connect(
    GatewayRuntimeSessionConnectRequest request,
  ) async {
    final result = await _request(
      method: 'xworkmate.gateway.connect',
      params: request.toJson(),
    );
    if (_boolValue(result['ok']) != true) {
      throw _gatewayErrorFromResult(
        result,
        fallbackMessage: 'Gateway connect failed',
      );
    }
    return GatewayRuntimeSessionConnectResult.fromJson(result);
  }

  @override
  Future<dynamic> request({
    required String runtimeId,
    required String method,
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final result = await _request(
      method: 'xworkmate.gateway.request',
      params: <String, dynamic>{
        'runtimeId': runtimeId,
        'method': method,
        if (params != null && params.isNotEmpty) 'params': params,
        'timeoutMs': timeout.inMilliseconds,
      },
    );
    if (_boolValue(result['ok']) != true) {
      throw _gatewayErrorFromResult(
        result,
        fallbackMessage: '$method request failed',
      );
    }
    return result['payload'];
  }

  @override
  Future<void> disconnect({required String runtimeId}) async {
    if (!_bridge.isStarted) {
      return;
    }
    await _request(
      method: 'xworkmate.gateway.disconnect',
      params: <String, dynamic>{'runtimeId': runtimeId},
    );
  }

  @override
  Future<void> dispose() async {
    await _notificationsSubscription.cancel();
    await _bridge.dispose();
    await _updatesController.close();
  }

  Future<Map<String, dynamic>> _request({
    required String method,
    required Map<String, dynamic> params,
  }) async {
    final response = await _bridge.request(method: method, params: params);
    return _castMap(response['result']);
  }

  void _handleNotification(Map<String, dynamic> notification) {
    final method = notification['method']?.toString().trim() ?? '';
    if (method.isEmpty) {
      return;
    }
    try {
      _updatesController.add(
        GatewayRuntimeSessionUpdate.fromNotification(notification),
      );
    } catch (_) {
      // Ignore unrelated ACP notifications.
    }
  }

  GatewayRuntimeException _gatewayErrorFromResult(
    Map<String, dynamic> result, {
    required String fallbackMessage,
  }) {
    final error = _castMap(result['error']);
    return GatewayRuntimeException(
      error['message']?.toString() ?? fallbackMessage,
      code: error['code']?.toString(),
      details: error['details'],
    );
  }

  Map<String, dynamic> _castMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  bool? _boolValue(Object? raw) {
    if (raw is bool) {
      return raw;
    }
    if (raw is num) {
      return raw != 0;
    }
    final text = raw?.toString().trim().toLowerCase();
    if (text == null || text.isEmpty) {
      return null;
    }
    if (text == 'true' || text == '1' || text == 'yes') {
      return true;
    }
    if (text == 'false' || text == '0' || text == 'no') {
      return false;
    }
    return null;
  }
}
