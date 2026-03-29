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
import 'gateway_runtime_session_client.dart';
import 'platform_environment.dart';
import 'runtime_models.dart';
import 'secure_config_store.dart';
import 'gateway_runtime_protocol.dart';
import 'gateway_runtime_events.dart';
import 'gateway_runtime_errors.dart';
import 'gateway_runtime_helpers.dart';

part 'gateway_runtime_api.dart';

class GatewayRuntime extends ChangeNotifier with GatewayRuntimeHelpersInternal {
  GatewayRuntime({
    required SecureConfigStore store,
    required DeviceIdentityStore identityStore,
    GatewayRuntimeSessionClient? sessionClient,
    bool allowDirectSocketFallbackOnSessionClientFailure = false,
    String runtimeId = '',
  }) : storeInternal = store,
       identityStoreInternal = identityStore,
       sessionClientInternal = sessionClient,
       allowDirectSocketFallbackOnSessionClientFailureInternal =
           allowDirectSocketFallbackOnSessionClientFailure,
       runtimeIdInternal = runtimeId.trim().isNotEmpty
           ? runtimeId.trim()
           : randomIdInternal();

  final SecureConfigStore storeInternal;
  final DeviceIdentityStore identityStoreInternal;
  final GatewayRuntimeSessionClient? sessionClientInternal;
  final bool allowDirectSocketFallbackOnSessionClientFailureInternal;
  final String runtimeIdInternal;
  final StreamController<GatewayPushEvent> eventsInternal =
      StreamController<GatewayPushEvent>.broadcast();
  final Map<String, Completer<RpcResponseInternal>> pendingInternal =
      <String, Completer<RpcResponseInternal>>{};
  final List<RuntimeLogEntry> logsInternal = <RuntimeLogEntry>[];

  IOWebSocketChannel? channelInternal;
  StreamSubscription<dynamic>? socketSubscriptionInternal;
  StreamSubscription<GatewayRuntimeSessionUpdate>? sessionUpdatesInternal;
  Timer? reconnectTimerInternal;
  GatewayConnectionProfile? desiredProfileInternal;
  bool manualDisconnectInternal = false;
  bool suppressReconnectInternal = false;
  int requestCounterInternal = 0;

  GatewayConnectionSnapshot snapshotInternal =
      GatewayConnectionSnapshot.initial(
        mode: GatewayConnectionProfile.defaults().mode,
      );
  RuntimePackageInfo packageInfoInternal = const RuntimePackageInfo(
    appName: kSystemAppName,
    packageName: 'plus.svc.xworkmate',
    version: kAppVersion,
    buildNumber: kAppBuildNumber,
  );
  RuntimeDeviceInfo deviceInfoInternal = RuntimeDeviceInfo(
    platform: Platform.operatingSystem,
    platformVersion: '',
    deviceFamily: 'Desktop',
    modelIdentifier: 'unknown',
  );

  GatewayConnectionSnapshot get snapshot => snapshotInternal;
  RuntimePackageInfo get packageInfo => packageInfoInternal;
  RuntimeDeviceInfo get deviceInfo => deviceInfoInternal;
  Stream<GatewayPushEvent> get events => eventsInternal.stream;
  List<RuntimeLogEntry> get logs =>
      List<RuntimeLogEntry>.unmodifiable(logsInternal);
  bool get isConnected =>
      snapshotInternal.status == RuntimeConnectionStatus.connected;

  void clearLogs() {
    if (logsInternal.isEmpty) {
      return;
    }
    logsInternal.clear();
    notifyListeners();
  }

  @visibleForTesting
  void addRuntimeLogForTest({
    required String level,
    required String category,
    required String message,
  }) {
    appendLogInternal(this, level, category, message);
  }

  Future<void> initialize() async {
    sessionUpdatesInternal ??= sessionClientInternal?.updates.listen(
      _handleSessionUpdateInternal,
    );
    await storeInternal.initialize();
    packageInfoInternal = await loadPackageInfoInternal();
    deviceInfoInternal = await loadDeviceInfoInternal();
    notifyListeners();
  }

  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    desiredProfileInternal = profile;
    manualDisconnectInternal = false;
    suppressReconnectInternal = false;
    await closeSocketInternal(this);

    final endpoint = resolveEndpointInternal(profile);
    final setupPayload = decodeGatewaySetupCode(profile.setupCode);
    final storedToken =
        (await storeInternal.loadGatewayToken(
          profileIndex: profileIndex,
        ))?.trim() ??
        '';
    final storedPassword =
        (await storeInternal.loadGatewayPassword(
          profileIndex: profileIndex,
        ))?.trim() ??
        '';
    final explicitToken = authTokenOverride.trim();
    final explicitPassword = authPasswordOverride.trim();
    final sharedTokenSource = explicitToken.isNotEmpty
        ? 'shared:form'
        : storedToken.isNotEmpty
        ? 'shared:store'
        : (setupPayload?.token.trim().isNotEmpty ?? false)
        ? 'shared:setup-code'
        : null;
    final sharedToken = explicitToken.isNotEmpty
        ? explicitToken
        : storedToken.isNotEmpty
        ? storedToken
        : (setupPayload?.token.trim() ?? '');
    final passwordSource = explicitPassword.isNotEmpty
        ? 'password:form'
        : storedPassword.isNotEmpty
        ? 'password:store'
        : (setupPayload?.password.trim().isNotEmpty ?? false)
        ? 'password:setup-code'
        : null;
    final password = explicitPassword.isNotEmpty
        ? explicitPassword
        : storedPassword.isNotEmpty
        ? storedPassword
        : (setupPayload?.password.trim() ?? '');
    final identity = await identityStoreInternal.loadOrCreate();
    final storedDeviceToken =
        (await storeInternal.loadDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
        ))?.trim() ??
        '';
    final explicitDeviceToken = '';
    final deviceTokenSource = explicitDeviceToken.isNotEmpty
        ? 'device:form'
        : sharedToken.isEmpty && storedDeviceToken.isNotEmpty
        ? 'device:store'
        : null;
    final deviceToken = explicitDeviceToken.isNotEmpty
        ? explicitDeviceToken
        : sharedToken.isEmpty
        ? storedDeviceToken
        : '';
    final authToken = sharedToken.isNotEmpty ? sharedToken : deviceToken;
    final connectAuthMode = sharedToken.isNotEmpty
        ? 'shared-token'
        : deviceToken.isNotEmpty
        ? 'device-token'
        : password.isNotEmpty
        ? 'password'
        : 'none';
    final connectAuthFields = <String>[
      if (authToken.isNotEmpty) 'token',
      if (deviceToken.isNotEmpty) 'deviceToken',
      if (password.isNotEmpty) 'password',
    ];
    final connectAuthSources = <String>[
      ...?sharedTokenSource == null ? null : <String>[sharedTokenSource],
      ...?deviceTokenSource == null ? null : <String>[deviceTokenSource],
      ...?passwordSource == null ? null : <String>[passwordSource],
    ];
    final connectAuthSummary = connectAuthSummaryInternal(
      mode: connectAuthMode,
      fields: connectAuthFields,
      sources: connectAuthSources,
    );
    final usedStoredDeviceTokenOnly =
        sharedToken.isEmpty && deviceToken.isNotEmpty;

    if (endpoint == null) {
      appendLogInternal(
        this,
        'warn',
        'connect',
        'missing endpoint | auth: $connectAuthSummary',
      );
      snapshotInternal = GatewayConnectionSnapshot.initial(mode: profile.mode)
          .copyWith(
            statusText: 'Missing gateway endpoint',
            lastError: 'Configure setup code or manual host / port first.',
            lastErrorCode: 'MISSING_ENDPOINT',
            deviceId: identity.deviceId,
            connectAuthMode: connectAuthMode,
            connectAuthFields: connectAuthFields,
            connectAuthSources: connectAuthSources,
          );
      notifyListeners();
      return;
    }

    appendLogInternal(
      this,
      'info',
      'connect',
      'attempt ${endpoint.$1}:${endpoint.$2} tls:${endpoint.$3} | auth: $connectAuthSummary',
    );

    snapshotInternal = GatewayConnectionSnapshot.initial(mode: profile.mode)
        .copyWith(
          status: RuntimeConnectionStatus.connecting,
          statusText: 'Connecting…',
          remoteAddress: '${endpoint.$1}:${endpoint.$2}',
          deviceId: identity.deviceId,
          authRole: 'operator',
          authScopes: kDefaultOperatorConnectScopes,
          connectAuthMode: connectAuthMode,
          connectAuthFields: connectAuthFields,
          connectAuthSources: connectAuthSources,
          hasSharedAuth: sharedToken.isNotEmpty || password.isNotEmpty,
          hasDeviceToken: deviceToken.isNotEmpty,
          clearLastError: true,
          clearLastErrorCode: true,
          clearLastErrorDetailCode: true,
        );
    notifyListeners();

    final sessionClient = sessionClientInternal;
    if (sessionClient != null) {
      try {
        final connectResult = await sessionClient.connect(
          GatewayRuntimeSessionConnectRequest(
            runtimeId: runtimeIdInternal,
            mode: profile.mode,
            clientId: resolveClientIdInternal(),
            locale: Platform.localeName,
            userAgent: '$kSystemAppName/${packageInfoInternal.version}',
            host: endpoint.$1,
            port: endpoint.$2,
            tls: endpoint.$3,
            connectAuthMode: connectAuthMode,
            connectAuthFields: connectAuthFields,
            connectAuthSources: connectAuthSources,
            hasSharedAuth: sharedToken.isNotEmpty || password.isNotEmpty,
            hasDeviceToken: deviceToken.isNotEmpty,
            packageInfo: packageInfoInternal,
            deviceInfo: deviceInfoInternal,
            identity: identity,
            authToken: sharedToken,
            authDeviceToken: deviceToken,
            authPassword: password,
          ),
        );
        if (connectResult.returnedDeviceToken.trim().isNotEmpty) {
          await storeInternal.saveDeviceToken(
            deviceId: identity.deviceId,
            role:
                connectResult.auth['role']?.toString().trim().isNotEmpty == true
                ? connectResult.auth['role'].toString().trim()
                : 'operator',
            token: connectResult.returnedDeviceToken.trim(),
          );
          appendLogInternal(
            this,
            'info',
            'auth',
            'stored device token for role ${connectResult.auth['role']?.toString().trim().isNotEmpty == true ? connectResult.auth['role'].toString().trim() : 'operator'}',
          );
        }
        snapshotInternal = connectResult.snapshot;
        notifyListeners();
        return;
      } on GatewayRuntimeException catch (error) {
        if (allowDirectSocketFallbackOnSessionClientFailureInternal &&
            _shouldFallbackToDirectRuntimeInternal(error)) {
          appendLogInternal(
            this,
            'warn',
            'connect',
            'go-core runtime unavailable, falling back to direct websocket | code: ${error.code ?? 'unknown'}',
          );
        } else {
          if (error.detailCode == 'AUTH_DEVICE_TOKEN_MISMATCH' &&
              deviceToken.isNotEmpty &&
              sharedToken.isEmpty) {
            await storeInternal.clearDeviceToken(
              deviceId: identity.deviceId,
              role: 'operator',
            );
          } else if (usedStoredDeviceTokenOnly &&
              isPairingRequiredErrorInternal(error.code, error.detailCode)) {
            await storeInternal.clearDeviceToken(
              deviceId: identity.deviceId,
              role: 'operator',
            );
            appendLogInternal(
              this,
              'warn',
              'auth',
              'cleared stale device token after pairing-required response',
            );
          }
          snapshotInternal = snapshotInternal.copyWith(
            status: RuntimeConnectionStatus.error,
            statusText: 'Connection failed',
            lastError: error.toString(),
            lastErrorCode: error.code,
            lastErrorDetailCode: error.detailCode,
            connectAuthMode: connectAuthMode,
            connectAuthFields: connectAuthFields,
            connectAuthSources: connectAuthSources,
            hasSharedAuth: sharedToken.isNotEmpty || password.isNotEmpty,
            hasDeviceToken: deviceToken.isNotEmpty,
          );
          notifyListeners();
          rethrow;
        }
      }
    }

    try {
      final scheme = endpoint.$3 ? 'wss' : 'ws';
      channelInternal = IOWebSocketChannel.connect(
        Uri.parse('$scheme://${endpoint.$1}:${endpoint.$2}'),
        pingInterval: const Duration(seconds: 30),
        connectTimeout: const Duration(seconds: 10),
      );
      final challenge = Completer<String>();
      socketSubscriptionInternal = channelInternal!.stream.listen(
        (dynamic raw) => handleIncomingInternal(this, raw, challenge),
        onError: (Object error, StackTrace stackTrace) {
          handleSocketFailureInternal(this, error.toString());
        },
        onDone: () {
          handleSocketClosedInternal(this);
        },
        cancelOnError: true,
      );

      final nonce = await challenge.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw GatewayRuntimeException(
          'connect challenge timeout',
          code: 'CONNECT_CHALLENGE_TIMEOUT',
        ),
      );
      final connectResult = await requestRawInternal(
        this,
        'connect',
        params: await buildConnectParamsInternal(
          this,
          profile: profile,
          identity: identity,
          nonce: nonce,
          authToken: authToken,
          authDeviceToken: deviceToken,
          authPassword: password,
        ),
        timeout: const Duration(seconds: 12),
      );

      final payload = asMap(connectResult.payload);
      final auth = asMap(payload['auth']);
      final snapshot = asMap(payload['snapshot']);
      final sessionDefaults = asMap(snapshot['sessionDefaults']);
      final server = asMap(payload['server']);
      final returnedDeviceToken = stringValue(auth['deviceToken']);
      if (returnedDeviceToken != null && returnedDeviceToken.isNotEmpty) {
        await storeInternal.saveDeviceToken(
          deviceId: identity.deviceId,
          role: stringValue(auth['role']) ?? 'operator',
          token: returnedDeviceToken,
        );
        appendLogInternal(
          this,
          'info',
          'auth',
          'stored device token for role ${stringValue(auth['role']) ?? 'operator'}',
        );
      }
      final negotiatedRole = stringValue(auth['role']) ?? 'operator';
      final negotiatedScopes = stringList(auth['scopes']);
      snapshotInternal = snapshotInternal.copyWith(
        status: RuntimeConnectionStatus.connected,
        statusText: 'Connected',
        serverName: stringValue(server['host']),
        remoteAddress: '${endpoint.$1}:${endpoint.$2}',
        mainSessionKey:
            stringValue(sessionDefaults['mainSessionKey']) ?? 'main',
        lastConnectedAtMs: DateTime.now().millisecondsSinceEpoch,
        authRole: negotiatedRole,
        authScopes: negotiatedScopes,
        connectAuthMode: connectAuthMode,
        connectAuthFields: connectAuthFields,
        connectAuthSources: connectAuthSources,
        hasSharedAuth: sharedToken.isNotEmpty || password.isNotEmpty,
        hasDeviceToken:
            (returnedDeviceToken != null && returnedDeviceToken.isNotEmpty) ||
            deviceToken.isNotEmpty,
        clearLastError: true,
        clearLastErrorCode: true,
        clearLastErrorDetailCode: true,
      );
      appendLogInternal(
        this,
        'info',
        'connect',
        'connected ${endpoint.$1}:${endpoint.$2} | role: $negotiatedRole | scopes: ${negotiatedScopes.length}',
      );
      notifyListeners();
    } catch (error) {
      final runtimeError = error is GatewayRuntimeException ? error : null;
      if (runtimeError?.detailCode == 'AUTH_DEVICE_TOKEN_MISMATCH' &&
          deviceToken.isNotEmpty &&
          sharedToken.isEmpty) {
        await storeInternal.clearDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
        );
      } else if (usedStoredDeviceTokenOnly &&
          isPairingRequiredErrorInternal(
            runtimeError?.code,
            runtimeError?.detailCode,
          )) {
        await storeInternal.clearDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
        );
        appendLogInternal(
          this,
          'warn',
          'auth',
          'cleared stale device token after pairing-required response',
        );
      }
      if (!shouldAutoReconnectInternal(runtimeError)) {
        suppressReconnectInternal = true;
        appendLogInternal(
          this,
          'warn',
          'socket',
          'auto reconnect suppressed | code: ${runtimeError?.code ?? 'unknown'} | detail: ${runtimeError?.detailCode ?? 'none'}',
        );
      }
      await closeSocketInternal(this);
      appendLogInternal(
        this,
        'error',
        'connect',
        'failed ${endpoint.$1}:${endpoint.$2} | code: ${runtimeError?.code ?? 'unknown'} | detail: ${runtimeError?.detailCode ?? 'none'} | message: ${error.toString()}',
      );
      snapshotInternal = snapshotInternal.copyWith(
        status: RuntimeConnectionStatus.error,
        statusText: 'Connection failed',
        lastError: error.toString(),
        lastErrorCode: runtimeError?.code,
        lastErrorDetailCode: runtimeError?.detailCode,
        connectAuthMode: connectAuthMode,
        connectAuthFields: connectAuthFields,
        connectAuthSources: connectAuthSources,
        hasSharedAuth: sharedToken.isNotEmpty || password.isNotEmpty,
        hasDeviceToken: deviceToken.isNotEmpty,
      );
      notifyListeners();
      if (shouldAutoReconnectInternal(runtimeError)) {
        appendLogInternal(
          this,
          'warn',
          'socket',
          'scheduling reconnect in 2s | code: ${runtimeError?.code ?? 'unknown'}',
        );
        scheduleReconnectInternal(this);
      }
      rethrow;
    }
  }

  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    manualDisconnectInternal = true;
    appendLogInternal(this, 'info', 'connect', 'manual disconnect');
    if (clearDesiredProfile) {
      desiredProfileInternal = null;
    }
    reconnectTimerInternal?.cancel();
    if (sessionClientInternal != null) {
      await sessionClientInternal!.disconnect(runtimeId: runtimeIdInternal);
      snapshotInternal =
          GatewayConnectionSnapshot.initial(
            mode: snapshotInternal.mode,
          ).copyWith(
            statusText: 'Offline',
            deviceId: snapshotInternal.deviceId,
            authRole: snapshotInternal.authRole,
            authScopes: snapshotInternal.authScopes,
            hasSharedAuth: snapshotInternal.hasSharedAuth,
            hasDeviceToken: snapshotInternal.hasDeviceToken,
          );
      notifyListeners();
      return;
    }
    await closeSocketInternal(this);
    snapshotInternal =
        GatewayConnectionSnapshot.initial(mode: snapshotInternal.mode).copyWith(
          statusText: 'Offline',
          deviceId: snapshotInternal.deviceId,
          authRole: snapshotInternal.authRole,
          authScopes: snapshotInternal.authScopes,
          hasSharedAuth: snapshotInternal.hasSharedAuth,
          hasDeviceToken: snapshotInternal.hasDeviceToken,
        );
    notifyListeners();
  }

  bool _shouldFallbackToDirectRuntimeInternal(GatewayRuntimeException error) {
    switch (error.code) {
      case 'GO_GATEWAY_RUNTIME_ENDPOINT_MISSING':
      case 'GO_GATEWAY_RUNTIME_TRANSPORT_UNAVAILABLE':
      case 'GO_GATEWAY_RUNTIME_WS_CONNECT_TIMEOUT':
      case 'GO_GATEWAY_RUNTIME_WS_CLOSED':
      case 'GO_GATEWAY_RUNTIME_WS_ERROR':
        return true;
      default:
        return false;
    }
  }

  Future<Map<String, dynamic>> health() => _healthInternal();

  Future<Map<String, dynamic>> status() => _statusInternal();

  Future<List<GatewayAgentSummary>> listAgents() => _listAgentsInternal();

  Future<List<GatewaySessionSummary>> listSessions({
    String? agentId,
    int limit = 24,
  }) => _listSessionsInternal(agentId: agentId, limit: limit);

  Future<List<GatewayChatMessage>> loadHistory(
    String sessionKey, {
    int limit = 120,
  }) => _loadHistoryInternal(sessionKey, limit: limit);

  Future<String> sendChat({
    required String sessionKey,
    required String message,
    required String thinking,
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    String? agentId,
    Map<String, dynamic>? metadata,
  }) => _sendChatInternal(
    sessionKey: sessionKey,
    message: message,
    thinking: thinking,
    attachments: attachments,
    agentId: agentId,
    metadata: metadata,
  );

  Future<void> abortChat({required String sessionKey, required String runId}) =>
      _abortChatInternal(sessionKey: sessionKey, runId: runId);

  Future<List<GatewayInstanceSummary>> listInstances() =>
      _listInstancesInternal();

  Future<List<GatewaySkillSummary>> listSkills({String? agentId}) =>
      _listSkillsInternal(agentId: agentId);

  Future<List<GatewayConnectorSummary>> listConnectors() =>
      _listConnectorsInternal();

  Future<List<GatewayModelSummary>> listModels() => _listModelsInternal();

  Future<List<GatewayCronJobSummary>> listCronJobs() => _listCronJobsInternal();

  Future<GatewayDevicePairingList> listDevicePairing() =>
      _listDevicePairingInternal();

  Future<GatewayPairedDevice?> approveDevicePairing(String requestId) =>
      _approveDevicePairingInternal(requestId);

  Future<void> rejectDevicePairing(String requestId) =>
      _rejectDevicePairingInternal(requestId);

  Future<void> removePairedDevice(String deviceId) =>
      _removePairedDeviceInternal(deviceId);

  Future<String> rotateDeviceToken({
    required String deviceId,
    required String role,
    List<String> scopes = const <String>[],
  }) => _rotateDeviceTokenInternal(
    deviceId: deviceId,
    role: role,
    scopes: scopes,
  );

  Future<void> revokeDeviceToken({
    required String deviceId,
    required String role,
  }) => _revokeDeviceTokenInternal(deviceId: deviceId, role: role);

  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) => _requestInternal(method, params: params, timeout: timeout);

  void _notifyRuntimeChangedInternal() {
    notifyListeners();
  }

  void _handleSessionUpdateInternal(GatewayRuntimeSessionUpdate update) {
    if (update.runtimeId != runtimeIdInternal) {
      return;
    }
    switch (update.type) {
      case GatewayRuntimeSessionUpdateType.snapshot:
        if (update.snapshot != null) {
          snapshotInternal = update.snapshot!;
          notifyListeners();
        }
        return;
      case GatewayRuntimeSessionUpdateType.log:
        final entry = update.log;
        if (entry == null) {
          return;
        }
        logsInternal.add(entry);
        const maxLogEntries = 250;
        if (logsInternal.length > maxLogEntries) {
          logsInternal.removeRange(0, logsInternal.length - maxLogEntries);
        }
        notifyListeners();
        return;
      case GatewayRuntimeSessionUpdateType.push:
        final push = update.push;
        if (push != null) {
          eventsInternal.add(push);
        }
        return;
    }
  }

  @override
  void dispose() {
    sessionUpdatesInternal?.cancel();
    unawaited(sessionClientInternal?.dispose() ?? Future<void>.value());
    eventsInternal.close();
    reconnectTimerInternal?.cancel();
    unawaited(closeSocketInternal(this));
    super.dispose();
  }
}
