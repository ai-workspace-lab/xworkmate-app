import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/mode_switcher.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

class _FakeGatewayRuntime extends ChangeNotifier implements GatewayRuntime {
  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial();
  final StreamController<GatewayPushEvent> _events =
      StreamController<GatewayPushEvent>.broadcast();

  @override
  bool get isConnected => _snapshot.status == RuntimeConnectionStatus.connected;

  @override
  GatewayConnectionSnapshot get snapshot => _snapshot;

  @override
  Stream<GatewayPushEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    _snapshot = GatewayConnectionSnapshot(
      profile: profile,
      status: RuntimeConnectionStatus.connected,
    );
  }

  @override
  Future<void> disconnect() async {
    _snapshot = GatewayConnectionSnapshot(
      profile: _snapshot.profile,
      status: RuntimeConnectionStatus.offline,
    );
  }

  @override
  Future<Map<String, dynamic>> request(
    String method, {
    Map<String, dynamic> params = const {},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return <String, dynamic>{};
  }

  @override
  void clearLogs() {}

  @override
  List<RuntimeLogEntry> get logs => const <RuntimeLogEntry>[];

  @override
  List<RuntimeLogEntry> get logsForTest => const <RuntimeLogEntry>[];

  @override
  void addRuntimeLogForTest({
    required String level,
    required String category,
    required String message,
  }) {}
}

class _FakeCodexRuntime extends CodexRuntime {
  bool findCalled = false;
  bool startCalled = false;
  String? findResult;

  @override
  Future<String?> findCodexBinary() async {
    findCalled = true;
    return findResult;
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
  }

  @override
  Future<void> stop() async {}
}

class _FakeModeSwitcher extends ModeSwitcher {
  _FakeModeSwitcher(super.gateway);

  GatewayMode mode = GatewayMode.offline;
  ModeCapabilities modeCapabilities = ModeCapabilities.offline;
  bool offlineSwitchCalled = false;

  @override
  GatewayMode get currentMode => mode;

  @override
  ModeCapabilities get capabilities => modeCapabilities;

  @override
  Future<ModeSwitchResult> switchToLocal({
    String host = '127.0.0.1',
    int port = 18789,
    String? token,
  }) async {
    mode = GatewayMode.local;
    modeCapabilities = ModeCapabilities.local;
    return ModeSwitchResult(success: true, mode: GatewayMode.local);
  }

  @override
  Future<ModeSwitchResult> switchToRemote({
    String host = 'openclaw.svc.plus',
    int port = 443,
    bool tls = true,
    String? token,
  }) async {
    mode = GatewayMode.remote;
    modeCapabilities = ModeCapabilities.remote;
    return ModeSwitchResult(success: true, mode: GatewayMode.remote);
  }

  @override
  Future<ModeSwitchResult> switchToOffline() async {
    offlineSwitchCalled = true;
    mode = GatewayMode.offline;
    modeCapabilities = ModeCapabilities.offline;
    return ModeSwitchResult(success: true, mode: GatewayMode.offline);
  }

  @override
  Future<ModeSwitchResult> autoSelect({bool preferRemote = true}) async {
    return preferRemote ? switchToRemote() : switchToLocal();
  }
}

void main() {
  group('RuntimeCoordinator runtime modes', () {
    late _FakeGatewayRuntime gateway;
    late _FakeCodexRuntime codex;
    late _FakeModeSwitcher modeSwitcher;
    late RuntimeCoordinator coordinator;

    setUp(() {
      gateway = _FakeGatewayRuntime();
      codex = _FakeCodexRuntime();
      modeSwitcher = _FakeModeSwitcher(gateway);
      coordinator = RuntimeCoordinator(
        gateway: gateway,
        codex: codex,
        modeSwitcher: modeSwitcher,
      );
    });

    test('built-in mode does not resolve or start external codex process', () async {
      codex.findResult = '/usr/local/bin/codex';

      await coordinator.initialize(
        preferredMode: GatewayMode.remote,
        runtimeMode: CodeAgentRuntimeMode.builtIn,
      );

      expect(coordinator.runtimeMode, CodeAgentRuntimeMode.builtIn);
      expect(codex.findCalled, isFalse);
      expect(codex.startCalled, isFalse);
      expect(coordinator.isReady, isTrue);
    });

    test('external mode resolves and starts codex process when binary exists', () async {
      codex.findResult = '/usr/local/bin/codex';

      await coordinator.initialize(
        preferredMode: GatewayMode.remote,
        runtimeMode: CodeAgentRuntimeMode.externalCli,
      );

      expect(coordinator.runtimeMode, CodeAgentRuntimeMode.externalCli);
      expect(codex.findCalled, isTrue);
      expect(codex.startCalled, isTrue);
      expect(modeSwitcher.currentMode, GatewayMode.remote);
    });

    test('external mode falls back to offline when codex binary missing', () async {
      codex.findResult = null;

      await coordinator.initialize(
        preferredMode: GatewayMode.remote,
        runtimeMode: CodeAgentRuntimeMode.externalCli,
      );

      expect(codex.findCalled, isTrue);
      expect(codex.startCalled, isFalse);
      expect(modeSwitcher.offlineSwitchCalled, isTrue);
      expect(modeSwitcher.currentMode, GatewayMode.offline);
    });
  });

  group('RuntimeCoordinator external provider registry', () {
    late RuntimeCoordinator coordinator;

    setUp(() {
      final gateway = _FakeGatewayRuntime();
      final codex = _FakeCodexRuntime();
      coordinator = RuntimeCoordinator(
        gateway: gateway,
        codex: codex,
        modeSwitcher: _FakeModeSwitcher(gateway),
      );
    });

    test('registers and unregisters external code agent providers', () {
      const provider = ExternalCodeAgentProvider(
        id: 'qwen-cli',
        name: 'Qwen CLI',
        command: 'qwen',
        defaultArgs: <String>['serve'],
        capabilities: <String>['chat', 'code-edit'],
      );

      coordinator.registerExternalCodeAgent(provider);

      expect(coordinator.hasExternalCodeAgent('qwen-cli'), isTrue);
      expect(coordinator.externalCodeAgents, hasLength(1));

      final removed = coordinator.unregisterExternalCodeAgent('qwen-cli');
      expect(removed, isTrue);
      expect(coordinator.externalCodeAgents, isEmpty);
    });
  });
}
