@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/mode_switcher.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import '../test_support.dart';

// Mock GatewayRuntime for testing
class MockGatewayRuntime extends GatewayRuntime {
  factory MockGatewayRuntime() {
    final store = createIsolatedTestStore();
    return MockGatewayRuntime._(store);
  }

  MockGatewayRuntime._(SecureConfigStore store)
    : super(store: store, identityStore: DeviceIdentityStore(store));
  final StreamController<GatewayPushEvent> _eventsController =
      StreamController<GatewayPushEvent>.broadcast();
  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial();
  bool _isConnected = false;
  final List<Map<String, dynamic>> _requests = [];
  final Set<RuntimeConnectionMode> _failingModes = <RuntimeConnectionMode>{};

  void failNextConnectFor(RuntimeConnectionMode mode) {
    _failingModes.add(mode);
  }

  void setConnected(bool connected) {
    _isConnected = connected;
    _snapshot = _snapshot.copyWith(
      status: connected
          ? RuntimeConnectionStatus.connected
          : RuntimeConnectionStatus.offline,
      statusText: connected ? 'Connected' : 'Offline',
    );
    notifyListeners();

    // Emit connection event
    if (connected) {
      unawaited(
        Future<void>.delayed(Duration.zero, () {
          _eventsController.add(
            const GatewayPushEvent(
              event: 'gateway/connected',
              payload: <String, dynamic>{},
            ),
          );
        }),
      );
    }
  }

  @override
  bool get isConnected => _isConnected;

  @override
  GatewayConnectionSnapshot get snapshot => _snapshot;

  @override
  Stream<GatewayPushEvent> get events => _eventsController.stream;

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    _requests.add({'method': method, 'params': params ?? const {}});
    return {'success': true};
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    if (_failingModes.remove(profile.mode)) {
      throw StateError('Failed to connect ${profile.mode.name}');
    }
    _isConnected = true;
    _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode).copyWith(
      status: RuntimeConnectionStatus.connected,
      statusText: 'Connected',
    );
    notifyListeners();
    unawaited(
      Future<void>.delayed(Duration.zero, () {
        _eventsController.add(
          const GatewayPushEvent(
            event: 'gateway/connected',
            payload: <String, dynamic>{},
          ),
        );
      }),
    );
  }

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    _isConnected = false;
    _snapshot = GatewayConnectionSnapshot.initial(
      mode: _snapshot.mode,
    ).copyWith(statusText: 'Offline');
    notifyListeners();
  }

  @override
  void dispose() {
    _eventsController.close();
    super.dispose();
  }
}

void main() {
  group('GatewayMode', () {
    test('has all expected modes', () {
      expect(GatewayMode.values, hasLength(3));
      expect(GatewayMode.values, contains(GatewayMode.local));
      expect(GatewayMode.values, contains(GatewayMode.remote));
      expect(GatewayMode.values, contains(GatewayMode.offline));
    });
  });

  group('ModeSwitcherState', () {
    test('has all expected states', () {
      expect(ModeSwitcherState.values, hasLength(6));
      expect(
        ModeSwitcherState.values,
        contains(ModeSwitcherState.disconnected),
      );
      expect(ModeSwitcherState.values, contains(ModeSwitcherState.connecting));
      expect(
        ModeSwitcherState.values,
        contains(ModeSwitcherState.connectedLocal),
      );
      expect(
        ModeSwitcherState.values,
        contains(ModeSwitcherState.connectedRemote),
      );
      expect(ModeSwitcherState.values, contains(ModeSwitcherState.offline));
      expect(ModeSwitcherState.values, contains(ModeSwitcherState.error));
    });
  });

  group('ModeCapabilities', () {
    test('local mode has correct capabilities', () {
      expect(ModeCapabilities.local.hasCloudMemory, isFalse);
      expect(ModeCapabilities.local.hasTaskQueue, isFalse);
      expect(ModeCapabilities.local.hasMultiAgent, isFalse);
      expect(ModeCapabilities.local.hasLocalModels, isTrue);
      expect(ModeCapabilities.local.hasCodeAgent, isTrue);
    });

    test('remote mode has correct capabilities', () {
      expect(ModeCapabilities.remote.hasCloudMemory, isTrue);
      expect(ModeCapabilities.remote.hasTaskQueue, isTrue);
      expect(ModeCapabilities.remote.hasMultiAgent, isTrue);
      expect(ModeCapabilities.remote.hasLocalModels, isTrue);
      expect(ModeCapabilities.remote.hasCodeAgent, isTrue);
    });

    test('offline mode has correct capabilities', () {
      expect(ModeCapabilities.offline.hasCloudMemory, isFalse);
      expect(ModeCapabilities.offline.hasTaskQueue, isFalse);
      expect(ModeCapabilities.offline.hasMultiAgent, isFalse);
      expect(ModeCapabilities.offline.hasLocalModels, isFalse);
      expect(ModeCapabilities.offline.hasCodeAgent, isTrue);
    });

    test('toMap returns correct values', () {
      final map = ModeCapabilities.remote.toMap();
      expect(map['hasCloudMemory'], isTrue);
      expect(map['hasTaskQueue'], isTrue);
      expect(map['hasMultiAgent'], isTrue);
      expect(map['hasLocalModels'], isTrue);
      expect(map['hasCodeAgent'], isTrue);
    });
  });

  group('ModeSwitchResult', () {
    test('success result is created correctly', () {
      final result = ModeSwitchResult(
        success: true,
        mode: GatewayMode.remote,
        capabilities: ModeCapabilities.remote.toMap(),
      );

      expect(result.success, isTrue);
      expect(result.mode, equals(GatewayMode.remote));
      expect(result.error, isNull);
      expect(result.capabilities, isNotNull);
    });

    test('failure result is created correctly', () {
      final result = ModeSwitchResult(
        success: false,
        mode: GatewayMode.local,
        error: 'Connection failed',
      );

      expect(result.success, isFalse);
      expect(result.mode, equals(GatewayMode.local));
      expect(result.error, equals('Connection failed'));
      expect(result.capabilities, isNull);
    });
  });

  group('ModeSwitcher', () {
    late MockGatewayRuntime mockGateway;
    late ModeSwitcher modeSwitcher;

    setUp(() {
      mockGateway = MockGatewayRuntime();
      modeSwitcher = ModeSwitcher(mockGateway);
    });

    test('initial state is disconnected', () {
      expect(modeSwitcher.state, equals(ModeSwitcherState.disconnected));
      expect(modeSwitcher.currentMode, equals(GatewayMode.offline));
      expect(modeSwitcher.lastError, isNull);
    });

    test('switchToLocal succeeds when gateway connects', () async {
      mockGateway.setConnected(true);

      final result = await modeSwitcher.switchToLocal();

      expect(result.success, isTrue);
      expect(result.mode, equals(GatewayMode.local));
      expect(modeSwitcher.state, equals(ModeSwitcherState.connectedLocal));
      expect(modeSwitcher.capabilities.hasLocalModels, isTrue);
    });

    test('switchToRemote succeeds when gateway connects', () async {
      mockGateway.setConnected(true);

      final result = await modeSwitcher.switchToRemote();

      expect(result.success, isTrue);
      expect(result.mode, equals(GatewayMode.remote));
      expect(modeSwitcher.state, equals(ModeSwitcherState.connectedRemote));
      expect(modeSwitcher.capabilities.hasCloudMemory, isTrue);
    });

    test('switchToOffline succeeds', () async {
      final result = await modeSwitcher.switchToOffline();

      expect(result.success, isTrue);
      expect(result.mode, equals(GatewayMode.offline));
      expect(modeSwitcher.state, equals(ModeSwitcherState.offline));
      expect(modeSwitcher.capabilities.hasCloudMemory, isFalse);
    });

    test('stateDescription returns correct values', () {
      expect(modeSwitcher.stateDescription, equals('Disconnected'));

      modeSwitcher.switchToLocal();
      // Check after async completes
      Future.delayed(Duration(milliseconds: 100), () {
        expect(
          modeSwitcher.stateDescription,
          anyOf(equals('Connected (Local)'), equals('Connecting...')),
        );
      });
    });

    test('modeDescription returns correct values', () {
      expect(
        modeSwitcher.modeDescription,
        equals('Offline Mode (Local Codex Only)'),
      );
    });

    test('autoSelect prefers remote by default', () async {
      mockGateway.setConnected(true);

      final result = await modeSwitcher.autoSelect();

      expect(result.success, isTrue);
      expect(result.mode, equals(GatewayMode.remote));
    });

    test('autoSelect falls back to local when remote fails', () async {
      mockGateway.failNextConnectFor(RuntimeConnectionMode.remote);

      final result = await modeSwitcher.autoSelect();

      expect(result.success, isTrue);
      expect(result.mode, equals(GatewayMode.local));
      expect(modeSwitcher.currentMode, equals(GatewayMode.local));
    });

    test(
      'autoSelect falls back to offline when remote and local fail',
      () async {
        mockGateway
          ..failNextConnectFor(RuntimeConnectionMode.remote)
          ..failNextConnectFor(RuntimeConnectionMode.local);

        final result = await modeSwitcher.autoSelect();

        expect(result.success, isTrue);
        expect(result.mode, equals(GatewayMode.offline));
        expect(modeSwitcher.currentMode, equals(GatewayMode.offline));
      },
    );
  });
}
