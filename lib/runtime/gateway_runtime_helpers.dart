// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:web_socket_channel/io.dart';
import '../app/app_metadata.dart';
import 'device_identity_store.dart';
import 'platform_environment.dart';
import 'runtime_models.dart';
import 'secure_config_store.dart';
import 'gateway_runtime_protocol.dart';
import 'gateway_runtime_events.dart';
import 'gateway_runtime_errors.dart';
import 'gateway_runtime_core.dart';

String formatGatewayConnectAuthSummary({
  required String mode,
  required List<String> fields,
  required List<String> sources,
}) {
  final resolvedFields = fields.isEmpty ? 'none' : fields.join(', ');
  final resolvedSources = sources.isEmpty ? 'none' : sources.join(' · ');
  return '$mode | fields: $resolvedFields | sources: $resolvedSources';
}

mixin GatewayRuntimeHelpersInternal on ChangeNotifier {
  Future<RpcResponseInternal> requestRawInternal(
    GatewayRuntime runtime,
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final channel = runtime.channelInternal;
    if (channel == null) {
      throw GatewayRuntimeException('gateway not connected', code: 'OFFLINE');
    }
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${runtime.requestCounterInternal++}';
    final completer = Completer<RpcResponseInternal>();
    runtime.pendingInternal[id] = completer;
    final frame = <String, dynamic>{
      'type': 'req',
      'id': id,
      'method': method,
      ...?params == null ? null : <String, dynamic>{'params': params},
    };
    channel.sink.add(jsonEncode(frame));
    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw GatewayRuntimeException(
          '$method request timeout',
          code: 'RPC_TIMEOUT',
        ),
      );
    } finally {
      runtime.pendingInternal.remove(id);
    }
  }

  GatewayPendingDevice parsePendingDeviceInternal(Map<String, dynamic> map) {
    return GatewayPendingDevice(
      requestId: stringValue(map['requestId']) ?? randomIdInternal(),
      deviceId: stringValue(map['deviceId']) ?? 'unknown-device',
      displayName: stringValue(map['displayName']),
      role: stringValue(map['role']),
      scopes: stringList(map['scopes']),
      remoteIp: stringValue(map['remoteIp']),
      isRepair: boolValue(map['isRepair']) ?? false,
      requestedAtMs: intValue(map['ts']),
    );
  }

  GatewayPairedDevice parsePairedDeviceInternal(
    Map<String, dynamic> map, {
    String? currentDeviceId,
  }) {
    return GatewayPairedDevice(
      deviceId: stringValue(map['deviceId']) ?? 'unknown-device',
      displayName: stringValue(map['displayName']),
      roles: stringList(map['roles']),
      scopes: stringList(map['scopes']),
      remoteIp: stringValue(map['remoteIp']),
      tokens: asList(map['tokens'])
          .map((item) => parseTokenSummaryInternal(asMap(item)))
          .toList(growable: false),
      createdAtMs: intValue(map['createdAtMs']),
      approvedAtMs: intValue(map['approvedAtMs']),
      currentDevice:
          currentDeviceId != null &&
          currentDeviceId.isNotEmpty &&
          currentDeviceId == stringValue(map['deviceId']),
    );
  }

  GatewayDeviceTokenSummary parseTokenSummaryInternal(
    Map<String, dynamic> map,
  ) {
    return GatewayDeviceTokenSummary(
      role: stringValue(map['role']) ?? 'operator',
      scopes: stringList(map['scopes']),
      createdAtMs: intValue(map['createdAtMs']),
      rotatedAtMs: intValue(map['rotatedAtMs']),
      revokedAtMs: intValue(map['revokedAtMs']),
      lastUsedAtMs: intValue(map['lastUsedAtMs']),
    );
  }

  Future<Map<String, dynamic>> buildConnectParamsInternal(
    GatewayRuntime runtime, {
    required GatewayConnectionProfile profile,
    required LocalDeviceIdentity identity,
    required String nonce,
    required String authToken,
    required String authDeviceToken,
    required String authPassword,
  }) async {
    final clientId = resolveClientIdInternal();
    final clientMode = 'ui';
    final signedAtMs = DateTime.now().millisecondsSinceEpoch;
    final signaturePayload = runtime.identityStoreInternal
        .buildDeviceAuthPayloadV3(
          deviceId: identity.deviceId,
          clientId: clientId,
          clientMode: clientMode,
          role: 'operator',
          scopes: kDefaultOperatorConnectScopes,
          signedAtMs: signedAtMs,
          token: authToken,
          nonce: nonce,
          platform: runtime.deviceInfoInternal.platformLabel,
          deviceFamily: runtime.deviceInfoInternal.deviceFamily,
        );
    final signature = await runtime.identityStoreInternal.signPayload(
      identity: identity,
      payload: signaturePayload,
    );

    return <String, dynamic>{
      'minProtocol': kGatewayProtocolVersion,
      'maxProtocol': kGatewayProtocolVersion,
      'client': <String, dynamic>{
        'id': clientId,
        'displayName':
            '$kSystemAppName ${runtime.deviceInfoInternal.deviceFamily}',
        'version': runtime.packageInfoInternal.version,
        'platform': runtime.deviceInfoInternal.platformLabel,
        'deviceFamily': runtime.deviceInfoInternal.deviceFamily,
        'modelIdentifier': runtime.deviceInfoInternal.modelIdentifier,
        'mode': clientMode,
        'instanceId':
            '$clientId-${identity.deviceId.substring(0, min(8, identity.deviceId.length))}',
      },
      'caps': const <String>['tool-events'],
      'commands': const <String>[],
      'permissions': const <String, bool>{},
      'role': 'operator',
      'scopes': kDefaultOperatorConnectScopes,
      if (authToken.isNotEmpty ||
          authDeviceToken.isNotEmpty ||
          authPassword.isNotEmpty)
        'auth': <String, dynamic>{
          if (authToken.isNotEmpty) 'token': authToken,
          if (authDeviceToken.isNotEmpty) 'deviceToken': authDeviceToken,
          if (authPassword.isNotEmpty) 'password': authPassword,
        },
      'locale': Platform.localeName,
      'userAgent': '$kSystemAppName/${runtime.packageInfoInternal.version}',
      'device': <String, dynamic>{
        'id': identity.deviceId,
        'publicKey': identity.publicKeyBase64Url,
        'signature': signature,
        'signedAt': signedAtMs,
        'nonce': nonce,
      },
    };
  }

  (String, int, bool)? resolveEndpointInternal(
    GatewayConnectionProfile profile,
  ) {
    final payload = decodeGatewaySetupCode(profile.setupCode);
    if (profile.useSetupCode && payload != null) {
      return (payload.host, payload.port, payload.tls);
    }
    final host = profile.host.trim();
    if (host.isEmpty) {
      return null;
    }
    final normalized = parseGatewayEndpoint(
      host.contains('://')
          ? host
          : composeManualUrlInternal(host, profile.port, profile.tls),
    );
    return normalized ?? (host, profile.port, profile.tls);
  }

  void handleIncomingInternal(
    GatewayRuntime runtime,
    dynamic raw,
    Completer<String> challenge,
  ) {
    final text = raw is String ? raw : utf8.decode(raw as List<int>);
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    final type = stringValue(decoded['type']);
    if (type == 'event') {
      final event = stringValue(decoded['event']) ?? '';
      final payload = decoded['payload'];
      if (event == 'connect.challenge') {
        final nonce = stringValue(asMap(payload)['nonce']);
        if (nonce != null && !challenge.isCompleted) {
          challenge.complete(nonce);
        }
        appendLogInternal(runtime, 'debug', 'connect', 'challenge received');
        return;
      }
      if (event == 'health') {
        runtime.snapshotInternal = runtime.snapshotInternal.copyWith(
          healthPayload: asMap(payload),
        );
        appendLogInternal(runtime, 'debug', 'health', 'push health update');
        runtime.notifyListeners();
      } else if (event == 'device.pair.requested' ||
          event == 'device.pair.resolved') {
        final eventPayload = asMap(payload);
        appendLogInternal(
          runtime,
          'info',
          'pairing',
          '$event | request: ${stringValue(eventPayload['requestId']) ?? 'unknown'} | device: ${stringValue(eventPayload['deviceId']) ?? 'unknown'}',
        );
      } else if (event == 'seqGap') {
        appendLogInternal(runtime, 'warn', 'sync', 'sequence gap detected');
      }
      runtime.eventsInternal.add(
        GatewayPushEvent(
          event: event,
          payload: payload,
          sequence: intValue(decoded['seq']),
        ),
      );
      return;
    }
    if (type != 'res') {
      return;
    }
    final id = stringValue(decoded['id']);
    if (id == null) {
      return;
    }
    final completer = runtime.pendingInternal.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }
    final ok = boolValue(decoded['ok']) ?? false;
    final payload = decoded['payload'];
    final error = asMap(decoded['error']);
    if (!ok) {
      appendLogInternal(
        runtime,
        'error',
        'rpc',
        'request failed | code: ${stringValue(error['code']) ?? 'unknown'} | detail: ${stringValue(asMap(error['details'])['code']) ?? 'none'} | message: ${stringValue(error['message']) ?? 'gateway request failed'}',
      );
      if (!shouldAutoReconnectForCodesInternal(
        stringValue(error['code']),
        stringValue(asMap(error['details'])['code']),
      )) {
        runtime.suppressReconnectInternal = true;
      }
      completer.completeError(
        GatewayRuntimeException(
          stringValue(error['message']) ?? 'gateway request failed',
          code: stringValue(error['code']),
          details: error['details'],
        ),
      );
      return;
    }
    completer.complete(
      RpcResponseInternal(ok: ok, payload: payload, error: error),
    );
  }

  void handleSocketFailureInternal(GatewayRuntime runtime, String message) {
    failPendingInternal(
      runtime,
      GatewayRuntimeException(message, code: 'SOCKET_FAILURE'),
    );
    if (runtime.manualDisconnectInternal || runtime.suppressReconnectInternal) {
      appendLogInternal(
        runtime,
        'warn',
        'socket',
        'failure ignored for reconnect | manual: ${runtime.manualDisconnectInternal} | suppressed: ${runtime.suppressReconnectInternal} | message: $message',
      );
      return;
    }
    appendLogInternal(runtime, 'error', 'socket', 'failure | $message');
    runtime.snapshotInternal = runtime.snapshotInternal.copyWith(
      status: RuntimeConnectionStatus.error,
      statusText: 'Gateway error',
      lastError: message,
      lastErrorCode: 'SOCKET_FAILURE',
      lastErrorDetailCode: null,
    );
    runtime.notifyListeners();
    scheduleReconnectInternal(runtime);
  }

  void handleSocketClosedInternal(GatewayRuntime runtime) {
    failPendingInternal(
      runtime,
      GatewayRuntimeException('socket closed', code: 'SOCKET_CLOSED'),
    );
    if (runtime.manualDisconnectInternal || runtime.suppressReconnectInternal) {
      appendLogInternal(
        runtime,
        'warn',
        'socket',
        'closed without reconnect | manual: ${runtime.manualDisconnectInternal} | suppressed: ${runtime.suppressReconnectInternal}',
      );
      return;
    }
    appendLogInternal(runtime, 'warn', 'socket', 'closed by gateway');
    runtime.snapshotInternal = runtime.snapshotInternal.copyWith(
      status: RuntimeConnectionStatus.error,
      statusText: 'Disconnected',
      lastError: 'Gateway connection closed',
      lastErrorCode: 'SOCKET_CLOSED',
      lastErrorDetailCode: null,
    );
    runtime.notifyListeners();
    scheduleReconnectInternal(runtime);
  }

  String cronScheduleLabelInternal(Map<String, dynamic> schedule) {
    final kind = stringValue(schedule['kind']) ?? '';
    return switch (kind) {
      'at' => stringValue(schedule['at']) ?? 'at',
      'every' => '${intValue(schedule['everyMs']) ?? 0}ms',
      'cron' => stringValue(schedule['expr']) ?? 'cron',
      _ => 'unknown',
    };
  }

  void scheduleReconnectInternal(GatewayRuntime runtime) {
    final profile = runtime.desiredProfileInternal;
    if (runtime.manualDisconnectInternal ||
        runtime.suppressReconnectInternal ||
        profile == null) {
      return;
    }
    runtime.reconnectTimerInternal?.cancel();
    runtime.reconnectTimerInternal = Timer(const Duration(seconds: 2), () {
      appendLogInternal(
        runtime,
        'info',
        'socket',
        'reconnect firing | host: ${profile.host.trim().isEmpty ? 'setup-code' : profile.host.trim()} | port: ${profile.port}',
      );
      unawaited(runtime.connectProfile(profile));
    });
  }

  bool shouldAutoReconnectInternal(GatewayRuntimeException? error) {
    return shouldAutoReconnectForCodesInternal(error?.code, error?.detailCode);
  }

  bool shouldAutoReconnectForCodesInternal(String? code, String? detailCode) {
    final resolvedCode = code?.trim().toUpperCase();
    final resolvedDetailCode = detailCode?.trim().toUpperCase();
    const nonRetryableCodes = <String>{
      'INVALID_REQUEST',
      'UNAUTHORIZED',
      'NOT_PAIRED',
      'AUTH_REQUIRED',
    };
    const nonRetryableDetailCodes = <String>{
      'AUTH_REQUIRED',
      'AUTH_UNAUTHORIZED',
      'AUTH_TOKEN_MISSING',
      'AUTH_TOKEN_MISMATCH',
      'AUTH_PASSWORD_MISSING',
      'AUTH_PASSWORD_MISMATCH',
      'AUTH_DEVICE_TOKEN_MISMATCH',
      'PAIRING_REQUIRED',
      'DEVICE_IDENTITY_REQUIRED',
      'CONTROL_UI_DEVICE_IDENTITY_REQUIRED',
    };
    if (resolvedCode != null && nonRetryableCodes.contains(resolvedCode)) {
      return false;
    }
    if (resolvedDetailCode != null &&
        nonRetryableDetailCodes.contains(resolvedDetailCode)) {
      return false;
    }
    return true;
  }

  bool isPairingRequiredErrorInternal(String? code, String? detailCode) {
    final resolvedCode = code?.trim().toUpperCase();
    final resolvedDetailCode = detailCode?.trim().toUpperCase();
    return resolvedCode == 'NOT_PAIRED' ||
        resolvedDetailCode == 'PAIRING_REQUIRED';
  }

  Future<void> closeSocketInternal(GatewayRuntime runtime) async {
    runtime.reconnectTimerInternal?.cancel();
    final subscription = runtime.socketSubscriptionInternal;
    runtime.socketSubscriptionInternal = null;
    await subscription?.cancel();
    await runtime.channelInternal?.sink.close();
    runtime.channelInternal = null;
    failPendingInternal(
      runtime,
      GatewayRuntimeException('socket reset', code: 'SOCKET_RESET'),
    );
  }

  void appendLogInternal(
    GatewayRuntime runtime,
    String level,
    String category,
    String message,
  ) {
    runtime.logsInternal.add(
      RuntimeLogEntry(
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        level: level,
        category: category,
        message: message,
      ),
    );
    const maxLogEntries = 250;
    if (runtime.logsInternal.length > maxLogEntries) {
      runtime.logsInternal.removeRange(
        0,
        runtime.logsInternal.length - maxLogEntries,
      );
    }
    runtime.notifyListeners();
  }

  String connectAuthSummaryInternal({
    required String mode,
    required List<String> fields,
    required List<String> sources,
  }) {
    final resolvedFields = fields.isEmpty ? 'none' : fields.join(', ');
    final resolvedSources = sources.isEmpty ? 'none' : sources.join(' · ');
    return '$mode | fields: $resolvedFields | sources: $resolvedSources';
  }

  void failPendingInternal(GatewayRuntime runtime, Object error) {
    final values = runtime.pendingInternal.values.toList(growable: false);
    runtime.pendingInternal.clear();
    for (final completer in values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  String resolveClientIdInternal() {
    return resolveGatewayClientId();
  }

  Future<RuntimePackageInfo> loadPackageInfoInternal() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return RuntimePackageInfo(
        appName: info.appName,
        packageName: info.packageName,
        version: info.version,
        buildNumber: info.buildNumber,
      );
    } catch (_) {
      return const RuntimePackageInfo(
        appName: kSystemAppName,
        packageName: 'plus.svc.xworkmate',
        version: kAppVersion,
        buildNumber: kAppBuildNumber,
      );
    }
  }

  Future<RuntimeDeviceInfo> loadDeviceInfoInternal() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return RuntimeDeviceInfo(
          platform: 'ios',
          platformVersion: info.systemVersion,
          deviceFamily: info.model,
          modelIdentifier: info.utsname.machine,
        );
      }
      if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        return RuntimeDeviceInfo(
          platform: 'macos',
          platformVersion:
              '${info.majorVersion}.${info.minorVersion}.${info.patchVersion}',
          deviceFamily: 'Mac',
          modelIdentifier: info.model,
        );
      }
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return RuntimeDeviceInfo(
          platform: 'android',
          platformVersion: info.version.release,
          deviceFamily: info.model,
          modelIdentifier: info.id,
        );
      }
      if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        return RuntimeDeviceInfo(
          platform: 'windows',
          platformVersion: info.displayVersion,
          deviceFamily: 'Windows',
          modelIdentifier: info.computerName,
        );
      }
      if (Platform.isLinux) {
        final info = await plugin.linuxInfo;
        return RuntimeDeviceInfo(
          platform: 'linux',
          platformVersion: info.version ?? '',
          deviceFamily: 'Linux',
          modelIdentifier: info.machineId ?? 'linux',
        );
      }
    } catch (_) {
      // Fall through to generic info.
    }
    return RuntimeDeviceInfo(
      platform: Platform.operatingSystem,
      platformVersion: Platform.operatingSystemVersion,
      deviceFamily: Platform.operatingSystem,
      modelIdentifier: Platform.localHostname,
    );
  }
}

class GatewaySetupPayload {
  const GatewaySetupPayload({
    required this.host,
    required this.port,
    required this.tls,
    required this.token,
    required this.password,
  });

  final String host;
  final int port;
  final bool tls;
  final String token;
  final String password;
}

GatewaySetupPayload? decodeGatewaySetupCode(String rawInput) {
  final trimmed = rawInput.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final candidate = resolveSetupCodeCandidateInternal(trimmed);
  final direct = decodeSetupPayloadJsonInternal(candidate);
  if (direct != null) {
    return direct;
  }
  try {
    final normalized = candidate.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized + '=' * ((4 - normalized.length % 4) % 4);
    final decoded = utf8.decode(base64.decode(padded));
    return decodeSetupPayloadJsonInternal(decoded);
  } catch (_) {
    return null;
  }
}

GatewaySetupPayload? decodeSetupPayloadJsonInternal(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final url = stringValue(json['url']);
    final host = stringValue(json['host']);
    final port = intValue(json['port']);
    final tls = boolValue(json['tls']);
    final resolved = parseGatewayEndpoint(
      url ?? composeManualUrlInternal(host, port, tls),
    );
    if (resolved == null) {
      return null;
    }
    return GatewaySetupPayload(
      host: resolved.$1,
      port: resolved.$2,
      tls: resolved.$3,
      token: stringValue(json['token']) ?? '',
      password: stringValue(json['password']) ?? '',
    );
  } catch (_) {
    return null;
  }
}

String resolveSetupCodeCandidateInternal(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return stringValue(decoded['setupCode']) ?? raw;
    }
  } catch (_) {
    // Leave raw as-is.
  }
  return raw;
}

(String, int, bool)? parseGatewayEndpoint(String? rawInput) {
  final raw = rawInput?.trim() ?? '';
  if (raw.isEmpty) {
    return null;
  }
  final normalized = raw.contains('://') ? raw : 'https://$raw';
  final uri = Uri.tryParse(normalized);
  final host = uri?.host.trim() ?? '';
  if (host.isEmpty) {
    return null;
  }
  final scheme = uri?.scheme.trim().toLowerCase() ?? 'https';
  final tls = switch (scheme) {
    'ws' || 'http' => false,
    _ => true,
  };
  final parsedPort = uri?.port;
  final port = parsedPort != null && parsedPort >= 1 && parsedPort <= 65535
      ? parsedPort
      : (tls ? 443 : 18789);
  return (host, port, tls);
}

String? composeManualUrlInternal(String? host, int? port, bool? tls) {
  final trimmedHost = host?.trim() ?? '';
  if (trimmedHost.isEmpty) {
    return null;
  }
  final resolvedPort = port ?? 18789;
  final scheme = tls == false ? 'http' : 'https';
  return '$scheme://$trimmedHost:$resolvedPort';
}

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

List<dynamic> asList(Object? value) {
  if (value is List<dynamic>) {
    return value;
  }
  if (value is List) {
    return value.cast<dynamic>();
  }
  return const <dynamic>[];
}

String? stringValue(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

bool? boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
        return true;
      case 'false':
        return false;
    }
  }
  return null;
}

int? intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

double? doubleValue(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

List<String> stringList(Object? value) {
  return asList(
    value,
  ).map(stringValue).whereType<String>().toList(growable: false);
}

String extractMessageText(Map<String, dynamic> message) {
  final directContent = message['content'];
  if (directContent is String) {
    return directContent;
  }
  final parts = <String>[];
  for (final part in asList(directContent)) {
    final map = asMap(part);
    final text = stringValue(map['text']) ?? stringValue(map['thinking']);
    if (text != null && text.isNotEmpty) {
      parts.add(text);
      continue;
    }
    final nestedContent = map['content'];
    if (nestedContent is String && nestedContent.trim().isNotEmpty) {
      parts.add(nestedContent.trim());
    }
  }
  return parts.join('\n').trim();
}

String randomIdInternal() {
  final random = Random.secure();
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final suffix = List<int>.generate(
    6,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return '$timestamp-$suffix';
}

class RpcResponseInternal {
  const RpcResponseInternal({
    required this.ok,
    required this.payload,
    required this.error,
  });

  final bool ok;
  final dynamic payload;
  final Map<String, dynamic> error;
}
