import 'gateway_runtime_errors.dart';
import 'gateway_runtime_events.dart';
import 'gateway_runtime_helpers.dart';
import 'runtime_models.dart';

class GatewayRuntimeSessionConnectRequest {
  const GatewayRuntimeSessionConnectRequest({
    required this.runtimeId,
    required this.mode,
    required this.clientId,
    required this.locale,
    required this.userAgent,
    required this.host,
    required this.port,
    required this.tls,
    required this.connectAuthMode,
    required this.connectAuthFields,
    required this.connectAuthSources,
    required this.hasSharedAuth,
    required this.hasDeviceToken,
    required this.packageInfo,
    required this.deviceInfo,
    required this.identity,
    required this.authToken,
    required this.authDeviceToken,
    required this.authPassword,
  });

  final String runtimeId;
  final RuntimeConnectionMode mode;
  final String clientId;
  final String locale;
  final String userAgent;
  final String host;
  final int port;
  final bool tls;
  final String connectAuthMode;
  final List<String> connectAuthFields;
  final List<String> connectAuthSources;
  final bool hasSharedAuth;
  final bool hasDeviceToken;
  final RuntimePackageInfo packageInfo;
  final RuntimeDeviceInfo deviceInfo;
  final LocalDeviceIdentity identity;
  final String authToken;
  final String authDeviceToken;
  final String authPassword;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'runtimeId': runtimeId,
      'mode': mode.name,
      'clientId': clientId,
      'locale': locale,
      'userAgent': userAgent,
      'endpoint': <String, dynamic>{'host': host, 'port': port, 'tls': tls},
      'connectAuthMode': connectAuthMode,
      'connectAuthFields': connectAuthFields,
      'connectAuthSources': connectAuthSources,
      'hasSharedAuth': hasSharedAuth,
      'hasDeviceToken': hasDeviceToken,
      'packageInfo': <String, dynamic>{
        'appName': packageInfo.appName,
        'packageName': packageInfo.packageName,
        'version': packageInfo.version,
        'buildNumber': packageInfo.buildNumber,
      },
      'deviceInfo': <String, dynamic>{
        'platform': deviceInfo.platform,
        'platformVersion': deviceInfo.platformVersion,
        'deviceFamily': deviceInfo.deviceFamily,
        'modelIdentifier': deviceInfo.modelIdentifier,
      },
      'identity': <String, dynamic>{
        'deviceId': identity.deviceId,
        'publicKeyBase64Url': identity.publicKeyBase64Url,
        'privateKeyBase64Url': identity.privateKeyBase64Url,
      },
      'auth': <String, dynamic>{
        if (authToken.trim().isNotEmpty) 'token': authToken.trim(),
        if (authDeviceToken.trim().isNotEmpty)
          'deviceToken': authDeviceToken.trim(),
        if (authPassword.trim().isNotEmpty) 'password': authPassword.trim(),
      },
    };
  }
}

class GatewayRuntimeSessionConnectResult {
  const GatewayRuntimeSessionConnectResult({
    required this.snapshot,
    required this.auth,
    required this.returnedDeviceToken,
    required this.raw,
  });

  final GatewayConnectionSnapshot snapshot;
  final Map<String, dynamic> auth;
  final String returnedDeviceToken;
  final Map<String, dynamic> raw;

  factory GatewayRuntimeSessionConnectResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return GatewayRuntimeSessionConnectResult(
      snapshot: gatewayConnectionSnapshotFromJson(_castMap(json['snapshot'])),
      auth: _castMap(json['auth']),
      returnedDeviceToken: json['returnedDeviceToken']?.toString().trim() ?? '',
      raw: json,
    );
  }
}

enum GatewayRuntimeSessionUpdateType { snapshot, log, push }

class GatewayRuntimeSessionUpdate {
  const GatewayRuntimeSessionUpdate({
    required this.runtimeId,
    required this.type,
    this.snapshot,
    this.log,
    this.push,
    this.raw = const <String, dynamic>{},
  });

  final String runtimeId;
  final GatewayRuntimeSessionUpdateType type;
  final GatewayConnectionSnapshot? snapshot;
  final RuntimeLogEntry? log;
  final GatewayPushEvent? push;
  final Map<String, dynamic> raw;

  factory GatewayRuntimeSessionUpdate.fromNotification(
    Map<String, dynamic> notification,
  ) {
    final method = notification['method']?.toString().trim() ?? '';
    final params = _castMap(notification['params']);
    final runtimeId = params['runtimeId']?.toString().trim() ?? '';
    switch (method) {
      case 'xworkmate.gateway.snapshot':
        return GatewayRuntimeSessionUpdate(
          runtimeId: runtimeId,
          type: GatewayRuntimeSessionUpdateType.snapshot,
          snapshot: gatewayConnectionSnapshotFromJson(
            _castMap(params['snapshot']),
          ),
          raw: params,
        );
      case 'xworkmate.gateway.log':
        return GatewayRuntimeSessionUpdate(
          runtimeId: runtimeId,
          type: GatewayRuntimeSessionUpdateType.log,
          log: runtimeLogEntryFromJson(_castMap(params['log'])),
          raw: params,
        );
      case 'xworkmate.gateway.push':
        final event = _castMap(params['event']);
        return GatewayRuntimeSessionUpdate(
          runtimeId: runtimeId,
          type: GatewayRuntimeSessionUpdateType.push,
          push: GatewayPushEvent(
            event: event['event']?.toString().trim() ?? '',
            payload: event['payload'],
            sequence: intValue(event['sequence']),
          ),
          raw: params,
        );
      default:
        throw GatewayRuntimeException(
          'Unsupported gateway notification: $method',
          code: 'GO_GATEWAY_RUNTIME_NOTIFICATION_UNSUPPORTED',
        );
    }
  }
}

abstract class GatewayRuntimeSessionClient {
  Stream<GatewayRuntimeSessionUpdate> get updates;

  Future<GatewayRuntimeSessionConnectResult> connect(
    GatewayRuntimeSessionConnectRequest request,
  );

  Future<dynamic> request({
    required String runtimeId,
    required String method,
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  });

  Future<void> disconnect({required String runtimeId});

  Future<void> dispose();
}

GatewayConnectionSnapshot gatewayConnectionSnapshotFromJson(
  Map<String, dynamic> json,
) {
  return GatewayConnectionSnapshot(
    status: _statusFromJson(json['status']?.toString()),
    mode: RuntimeConnectionModeCopy.fromJsonValue(json['mode']?.toString()),
    statusText: json['statusText']?.toString() ?? 'Offline',
    serverName: json['serverName']?.toString(),
    remoteAddress: json['remoteAddress']?.toString(),
    mainSessionKey: json['mainSessionKey']?.toString(),
    lastError: json['lastError']?.toString(),
    lastErrorCode: json['lastErrorCode']?.toString(),
    lastErrorDetailCode: json['lastErrorDetailCode']?.toString(),
    lastConnectedAtMs: intValue(json['lastConnectedAtMs']),
    deviceId: json['deviceId']?.toString(),
    authRole: json['authRole']?.toString(),
    authScopes: stringList(json['authScopes']),
    connectAuthMode: json['connectAuthMode']?.toString(),
    connectAuthFields: stringList(json['connectAuthFields']),
    connectAuthSources: stringList(json['connectAuthSources']),
    hasSharedAuth: boolValue(json['hasSharedAuth']) ?? false,
    hasDeviceToken: boolValue(json['hasDeviceToken']) ?? false,
    healthPayload: _castNullableMap(json['healthPayload']),
    statusPayload: _castNullableMap(json['statusPayload']),
  );
}

RuntimeLogEntry runtimeLogEntryFromJson(Map<String, dynamic> json) {
  return RuntimeLogEntry(
    timestampMs:
        intValue(json['timestampMs']) ?? DateTime.now().millisecondsSinceEpoch,
    level: json['level']?.toString() ?? 'info',
    category: json['category']?.toString() ?? 'runtime',
    message: json['message']?.toString() ?? '',
  );
}

RuntimeConnectionStatus _statusFromJson(String? value) {
  switch (value?.trim()) {
    case 'connecting':
      return RuntimeConnectionStatus.connecting;
    case 'connected':
      return RuntimeConnectionStatus.connected;
    case 'error':
      return RuntimeConnectionStatus.error;
    default:
      return RuntimeConnectionStatus.offline;
  }
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

Map<String, dynamic>? _castNullableMap(Object? value) {
  final resolved = _castMap(value);
  return resolved.isEmpty ? null : resolved;
}
