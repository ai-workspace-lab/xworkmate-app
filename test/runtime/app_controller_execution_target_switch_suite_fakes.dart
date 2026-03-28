// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'app_controller_execution_target_switch_suite_core.dart';
import 'app_controller_execution_target_switch_suite_connection.dart';
import 'app_controller_execution_target_switch_suite_thread.dart';
import 'app_controller_execution_target_switch_suite_fixtures.dart';

class FakeGatewayRuntimeInternal extends GatewayRuntime {
  FakeGatewayRuntimeInternal({required super.store})
    : super(identityStore: DeviceIdentityStore(store));

  final List<GatewayConnectionProfile> connectedProfiles =
      <GatewayConnectionProfile>[];
  final Set<RuntimeConnectionMode> failingModesInternal =
      <RuntimeConnectionMode>{};
  Completer<void>? connectGateInternal;
  Completer<void>? disconnectGateInternal;
  int disconnectCount = 0;
  GatewayConnectionSnapshot fakeSnapshotInternal =
      GatewayConnectionSnapshot.initial();

  @override
  bool get isConnected =>
      fakeSnapshotInternal.status == RuntimeConnectionStatus.connected;

  @override
  GatewayConnectionSnapshot get snapshot => fakeSnapshotInternal;

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
    final connectGate = connectGateInternal;
    connectGateInternal = null;
    if (connectGate != null && !connectGate.isCompleted) {
      await connectGate.future;
    }
    if (failingModesInternal.remove(profile.mode)) {
      fakeSnapshotInternal =
          GatewayConnectionSnapshot.initial(mode: profile.mode).copyWith(
            status: RuntimeConnectionStatus.error,
            statusText: 'Error',
            remoteAddress: '${profile.host}:${profile.port}',
            lastError: 'Failed to connect ${profile.mode.name}',
          );
      notifyListeners();
      throw StateError('Failed to connect ${profile.mode.name}');
    }
    fakeSnapshotInternal = GatewayConnectionSnapshot.initial(mode: profile.mode)
        .copyWith(
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
    final disconnectGate = disconnectGateInternal;
    disconnectGateInternal = null;
    if (disconnectGate != null && !disconnectGate.isCompleted) {
      await disconnectGate.future;
    }
    fakeSnapshotInternal = fakeSnapshotInternal.copyWith(
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
    failingModesInternal.add(mode);
  }

  void holdNextConnect(Completer<void> gate) {
    connectGateInternal = gate;
  }

  void holdNextDisconnect(Completer<void> gate) {
    disconnectGateInternal = gate;
  }
}

class FakeCodexRuntimeInternal extends CodexRuntime {
  @override
  Future<String?> findCodexBinary() async => null;

  @override
  Future<void> stop() async {}
}

Future<void> deleteDirectoryWithRetryInternal(Directory directory) async {
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
