import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/runtime/account_runtime_client.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/runtime/desktop_platform_service.dart';

SecureConfigStore createIsolatedTestStore({bool enableSecureStorage = true}) {
  final testRoot = Directory.systemTemp.createTempSync('xworkmate-store-test-');
  addTearDown(() async {
    if (await testRoot.exists()) {
      await _deleteDirectoryWithRetry(testRoot);
    }
  });
  return SecureConfigStore(
    enableSecureStorage: enableSecureStorage,
    databasePathResolver: () async =>
        '${testRoot.path}/${SettingsStore.databaseFileName}',
    fallbackDirectoryPathResolver: () async => testRoot.path,
  );
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 5; attempt += 1) {
    if (!await directory.exists()) {
      return;
    }
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 4) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 80 * (attempt + 1)));
    }
  }
}

Future<AppController> createTestController(
  WidgetTester tester, {
  DesktopPlatformService? desktopPlatformService,
  UiFeatureManifest? uiFeatureManifest,
  AccountRuntimeClient Function(String baseUrl)? accountClientFactory,
  SettingsSnapshot? initialSettingsSnapshot,
  List<SingleAgentProvider>? availableSingleAgentProvidersOverride,
  GoTaskServiceClient? goTaskServiceClient,
  List<String>? singleAgentSharedSkillScanRootOverrides,
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final testRoot =
      '${Directory.systemTemp.path}/xworkmate-widget-tests-${DateTime.now().microsecondsSinceEpoch}';
  final store = SecureConfigStore(
    enableSecureStorage: false,
    databasePathResolver: () async => '$testRoot/settings.sqlite3',
    fallbackDirectoryPathResolver: () async => testRoot,
  );
  if (initialSettingsSnapshot != null) {
    await Directory(testRoot).create(recursive: true);
    await store.initialize();
    await store.saveSettingsSnapshot(initialSettingsSnapshot);
  }
  final controller = AppController(
    store: store,
    runtimeCoordinator: RuntimeCoordinator(
      gateway: _TestFakeGatewayRuntime(store: store),
      codex: _TestFakeCodexRuntime(),
    ),
    desktopPlatformService: desktopPlatformService,
    uiFeatureManifest: uiFeatureManifest,
    accountClientFactory: accountClientFactory,
    availableSingleAgentProvidersOverride:
        availableSingleAgentProvidersOverride,
    goTaskServiceClient: goTaskServiceClient,
    singleAgentSharedSkillScanRootOverrides:
        singleAgentSharedSkillScanRootOverrides,
  );
  addTearDown(controller.dispose);
  await tester.pump(const Duration(milliseconds: 100));
  if (settle) {
    await tester.pumpAndSettle();
  }
  return controller;
}

class _TestFakeGatewayRuntime extends GatewayRuntime {
  _TestFakeGatewayRuntime({required super.store})
    : super(identityStore: DeviceIdentityStore(store));

  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial();
  GatewayDevicePairingList _pairingList = const GatewayDevicePairingList(
    pending: <GatewayPendingDevice>[],
    paired: <GatewayPairedDevice>[],
  );

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
    _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode).copyWith(
      status: RuntimeConnectionStatus.connected,
      statusText: 'Connected',
      remoteAddress: '${profile.host}:${profile.port}',
      connectAuthMode: 'none',
    );
    notifyListeners();
  }

  void setSnapshotForTest(GatewayConnectionSnapshot snapshot) {
    _snapshot = snapshot.normalizedForConnectedState();
    notifyListeners();
  }

  void setDevicePairingForTest(GatewayDevicePairingList pairingList) {
    _pairingList = pairingList;
    notifyListeners();
  }

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    _snapshot = _snapshot.copyWith(
      status: RuntimeConnectionStatus.offline,
      statusText: 'Offline',
      remoteAddress: null,
      clearLastError: true,
      clearLastErrorCode: true,
      clearLastErrorDetailCode: true,
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
          'pending': _pairingList.pending
              .map(
                (item) => <String, dynamic>{
                  'requestId': item.requestId,
                  'deviceId': item.deviceId,
                  'label': item.label,
                  'role': item.role,
                  'scopes': item.scopes,
                  'remoteIp': item.remoteIp,
                  'requestedAtMs': item.requestedAtMs,
                  'repair': item.isRepair,
                },
              )
              .toList(growable: false),
          'paired': _pairingList.paired
              .map(
                (item) => <String, dynamic>{
                  'deviceId': item.deviceId,
                  'displayName': item.displayName,
                  'roles': item.roles,
                  'scopes': item.scopes,
                  'remoteIp': item.remoteIp,
                  'tokens': item.tokens
                      .map(
                        (token) => <String, dynamic>{
                          'role': token.role,
                          'scopes': token.scopes,
                          'createdAtMs': token.createdAtMs,
                          'rotatedAtMs': token.rotatedAtMs,
                          'revokedAtMs': token.revokedAtMs,
                          'lastUsedAtMs': token.lastUsedAtMs,
                        },
                      )
                      .toList(growable: false),
                  'createdAtMs': item.createdAtMs,
                  'approvedAtMs': item.approvedAtMs,
                  'currentDevice': item.currentDevice,
                },
              )
              .toList(growable: false),
        };
      case 'system-presence':
        return const <Object>[];
      default:
        return <String, dynamic>{};
    }
  }
}

void setGatewaySnapshotForTest(
  AppController controller,
  GatewayConnectionSnapshot snapshot,
) {
  final runtime = controller.runtime;
  if (runtime is! _TestFakeGatewayRuntime) {
    throw StateError(
      'createTestController() runtime does not support mutation',
    );
  }
  runtime.setSnapshotForTest(snapshot);
}

void setGatewayPairingListForTest(
  AppController controller,
  GatewayDevicePairingList pairingList,
) {
  final runtime = controller.runtime;
  if (runtime is! _TestFakeGatewayRuntime) {
    throw StateError(
      'createTestController() runtime does not support mutation',
    );
  }
  runtime.setDevicePairingForTest(pairingList);
}

class _TestFakeCodexRuntime extends CodexRuntime {
  @override
  Future<String?> findCodexBinary() async => null;

  @override
  Future<void> stop() async {}
}

Future<void> pumpPage(
  WidgetTester tester, {
  required Widget child,
  Size size = const Size(1600, 4000),
  TargetPlatform? platform,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: platform == null
          ? AppTheme.light()
          : AppTheme.light(platform: platform),
      darkTheme: platform == null
          ? AppTheme.dark()
          : AppTheme.dark(platform: platform),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}
