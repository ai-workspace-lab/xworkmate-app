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

const String _manualCodexBridgeSkipReason =
    'Disabled by default: reserved for manual validation with a dedicated Codex environment only.';

class _FakeGatewayRuntime extends GatewayRuntime {
  _FakeGatewayRuntime({required bool connected})
    : super(
        store: SecureConfigStore(),
        identityStore: DeviceIdentityStore(SecureConfigStore()),
      ) {
    setConnected(connected);
  }

  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial();

  void setConnected(bool connected) {
    _snapshot =
        GatewayConnectionSnapshot.initial(
          mode: GatewayConnectionProfile.defaults().mode,
        ).copyWith(
          status: connected
              ? RuntimeConnectionStatus.connected
              : RuntimeConnectionStatus.offline,
          statusText: connected ? 'Connected' : 'Offline',
        );
  }

  @override
  bool get isConnected => _snapshot.status == RuntimeConnectionStatus.connected;

  @override
  GatewayConnectionSnapshot get snapshot => _snapshot;

  @override
  Stream<GatewayPushEvent> get events => const Stream<GatewayPushEvent>.empty();

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    setConnected(true);
  }

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    setConnected(false);
  }

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final resolvedParams = params ?? const <String, dynamic>{};
    requests.add(<String, dynamic>{'method': method, 'params': resolvedParams});
    if (method == 'agent/register') {
      return <String, dynamic>{
        'agentId': 'bridge-1',
        'agentType': resolvedParams['agentType'],
        'name': resolvedParams['name'],
        'version': resolvedParams['version'],
        'token': 'registration-token',
        'registeredAt': '2026-03-14T10:00:00Z',
      };
    }
    return <String, dynamic>{};
  }
}

class _FakeCodexRuntime extends CodexRuntime {
  _FakeCodexRuntime();

  bool startCalled = false;
  bool stopCalled = false;
  bool findCalled = false;
  String? startedCodexPath;
  String? startedCwd;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<String?> findCodexBinary() async {
    findCalled = true;
    return null;
  }

  @override
  Future<void> startStdio({
    required String codexPath,
    String? cwd,
    CodexSandboxMode sandbox = CodexSandboxMode.workspaceWrite,
    CodexApprovalPolicy approval = CodexApprovalPolicy.suggest,
    List<String> extraArgs = const <String>[],
  }) async {
    startCalled = true;
    startedCodexPath = codexPath;
    startedCwd = cwd;
    _connected = true;
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
    _connected = false;
  }
}

void main() {
  group(
    'Manual Codex bridge validation',
    () {
      test(
        'AppController enables external Codex bridge and registers to gateway',
        () async {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final store = SecureConfigStore();
          final gateway = _FakeGatewayRuntime(connected: true);
          final codex = _FakeCodexRuntime();
          final coordinator = RuntimeCoordinator(
            gateway: gateway,
            codex: codex,
          );
          final controller = AppController(
            store: store,
            runtimeCoordinator: coordinator,
          );
          addTearDown(controller.dispose);

          await _waitFor(() => !controller.initializing);

          final tempDir = await Directory.systemTemp.createTemp('codex-bridge-');
          addTearDown(() async {
            if (await tempDir.exists()) {
              await tempDir.delete(recursive: true);
            }
          });
          final codexBinary = File('${tempDir.path}/codex');
          await codexBinary.writeAsString('#!/bin/sh\nexit 0\n');

          await controller.settingsController.saveAiGatewayApiKey(
            'bridge-secret',
          );
          await controller.saveSettings(
            controller.settings.copyWith(
              workspacePath: tempDir.path,
              codeAgentRuntimeMode: CodeAgentRuntimeMode.externalCli,
              codexCliPath: codexBinary.path,
              aiGateway: controller.settings.aiGateway.copyWith(
                baseUrl: 'https://gateway.example.com',
              ),
            ),
          );

          await controller.enableCodexBridge();

          expect(controller.isCodexBridgeEnabled, isTrue);
          expect(
            controller.codexCooperationState,
            CodexCooperationState.registered,
          );
          expect(codex.startCalled, isTrue);
          expect(codex.startedCodexPath, codexBinary.path);
          expect(codex.startedCwd, tempDir.path);

          final registrationCall = gateway.requests.firstWhere(
            (request) => request['method'] == 'agent/register',
          );
          final params = registrationCall['params'] as Map<String, dynamic>;
          expect(params['transport'], 'stdio-bridge');
          expect(params['metadata'], containsPair('providerId', 'codex'));
          expect(params['metadata'], containsPair('runtimeMode', 'externalCli'));
          expect(
            (params['metadata']['node'] as Map<String, dynamic>)['kind'],
            'app-mediated-cooperative-node',
          );
        },
      );

      test(
        'AppController keeps bridge running when gateway registration is unavailable',
        () async {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final store = SecureConfigStore();
          final gateway = _FakeGatewayRuntime(connected: false);
          final codex = _FakeCodexRuntime();
          final coordinator = RuntimeCoordinator(
            gateway: gateway,
            codex: codex,
          );
          final controller = AppController(
            store: store,
            runtimeCoordinator: coordinator,
          );
          addTearDown(controller.dispose);

          await _waitFor(() => !controller.initializing);

          final tempDir = await Directory.systemTemp.createTemp(
            'codex-bridge-offline-',
          );
          addTearDown(() async {
            if (await tempDir.exists()) {
              await tempDir.delete(recursive: true);
            }
          });
          final codexBinary = File('${tempDir.path}/codex');
          await codexBinary.writeAsString('#!/bin/sh\nexit 0\n');

          await controller.saveSettings(
            controller.settings.copyWith(
              codeAgentRuntimeMode: CodeAgentRuntimeMode.externalCli,
              codexCliPath: codexBinary.path,
              aiGateway: controller.settings.aiGateway.copyWith(
                baseUrl: 'https://gateway.example.com',
              ),
            ),
          );

          await controller.enableCodexBridge();

          expect(controller.isCodexBridgeEnabled, isTrue);
          expect(
            controller.codexCooperationState,
            CodexCooperationState.bridgeOnly,
          );
          expect(codex.startCalled, isTrue);
          expect(
            gateway.requests.where(
              (request) => request['method'] == 'agent/register',
            ),
            isEmpty,
          );
        },
      );

      test(
        'AppController preserves built-in mode and does not require external codex binary',
        () async {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final store = SecureConfigStore();
          final gateway = _FakeGatewayRuntime(connected: false);
          final codex = _FakeCodexRuntime();
          final coordinator = RuntimeCoordinator(
            gateway: gateway,
            codex: codex,
          );
          final controller = AppController(
            store: store,
            runtimeCoordinator: coordinator,
          );
          addTearDown(controller.dispose);

          await _waitFor(() => !controller.initializing);

          await controller.saveSettings(
            controller.settings.copyWith(
              codeAgentRuntimeMode: CodeAgentRuntimeMode.builtIn,
              aiGateway: controller.settings.aiGateway.copyWith(
                baseUrl: 'https://gateway.example.com',
              ),
            ),
          );

          expect(
            controller.settings.codeAgentRuntimeMode,
            CodeAgentRuntimeMode.builtIn,
          );
          expect(controller.codexRuntimeWarning, isNotNull);

          await controller.enableCodexBridge();

          expect(controller.isCodexBridgeEnabled, isTrue);
          expect(
            controller.codexCooperationState,
            CodexCooperationState.bridgeOnly,
          );
          expect(codex.startCalled, isFalse);
          expect(coordinator.runtimeMode, CodeAgentRuntimeMode.builtIn);
        },
      );
    },
    skip: _manualCodexBridgeSkipReason,
  );
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
