part of 'app_controller_execution_target_switch_suite.dart';

class _FakeGatewayRuntime extends GatewayRuntime {
  _FakeGatewayRuntime({required super.store})
    : super(identityStore: DeviceIdentityStore(store));

  final List<GatewayConnectionProfile> connectedProfiles =
      <GatewayConnectionProfile>[];
  final Set<RuntimeConnectionMode> _failingModes = <RuntimeConnectionMode>{};
  Completer<void>? _connectGate;
  Completer<void>? _disconnectGate;
  int disconnectCount = 0;
  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial();

  @override
  bool get isConnected => _snapshot.status == RuntimeConnectionStatus.connected;

  @override
  GatewayConnectionSnapshot get snapshot => _snapshot;

  @override
  Stream<GatewayPushEvent> get events => const Stream<GatewayPushEvent>.empty();

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    connectedProfiles.add(profile);
    final connectGate = _connectGate;
    _connectGate = null;
    if (connectGate != null && !connectGate.isCompleted) {
      await connectGate.future;
    }
    if (_failingModes.remove(profile.mode)) {
      _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode)
          .copyWith(
            status: RuntimeConnectionStatus.error,
            statusText: 'Error',
            remoteAddress: '${profile.host}:${profile.port}',
            lastError: 'Failed to connect ${profile.mode.name}',
          );
      notifyListeners();
      throw StateError('Failed to connect ${profile.mode.name}');
    }
    _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode).copyWith(
      status: RuntimeConnectionStatus.connected,
      statusText: 'Connected',
      remoteAddress: '${profile.host}:${profile.port}',
      connectAuthMode: 'none',
    );
    notifyListeners();
  }

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    disconnectCount += 1;
    final disconnectGate = _disconnectGate;
    _disconnectGate = null;
    if (disconnectGate != null && !disconnectGate.isCompleted) {
      await disconnectGate.future;
    }
    _snapshot = _snapshot.copyWith(
      status: RuntimeConnectionStatus.offline,
      statusText: 'Offline',
    );
    notifyListeners();
  }

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    switch (method) {
      case 'health':
      case 'status':
        return <String, dynamic>{'ok': true};
      case 'agents.list':
        return <String, dynamic>{'agents': const <Object>[], 'mainKey': 'main'};
      case 'sessions.list':
        return <String, dynamic>{'sessions': const <Object>[]};
      case 'chat.history':
        return <String, dynamic>{'messages': const <Object>[]};
      case 'skills.status':
        return <String, dynamic>{'skills': const <Object>[]};
      case 'channels.status':
        return <String, dynamic>{
          'channelMeta': const <Object>[],
          'channelLabels': const <String, dynamic>{},
          'channelDetailLabels': const <String, dynamic>{},
          'channelAccounts': const <String, dynamic>{},
          'channelOrder': const <Object>[],
        };
      case 'models.list':
        return <String, dynamic>{'models': const <Object>[]};
      case 'cron.list':
        return <String, dynamic>{'jobs': const <Object>[]};
      case 'device.pair.list':
        return <String, dynamic>{
          'pending': const <Object>[],
          'paired': const <Object>[],
        };
      case 'system-presence':
        return const <Object>[];
      default:
        return <String, dynamic>{};
    }
  }

  void failNextConnect(RuntimeConnectionMode mode) {
    _failingModes.add(mode);
  }

  void holdNextConnect(Completer<void> gate) {
    _connectGate = gate;
  }

  void holdNextDisconnect(Completer<void> gate) {
    _disconnectGate = gate;
  }
}

class _FakeCodexRuntime extends CodexRuntime {
  @override
  Future<String?> findCodexBinary() async => null;

  @override
  Future<void> stop() async {}
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  if (!await directory.exists()) {
    return;
  }
  for (var attempt = 0; attempt < 3; attempt += 1) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 2) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
