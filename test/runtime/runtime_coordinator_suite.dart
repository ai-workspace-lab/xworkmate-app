@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/mode_switcher.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import '../test_support.dart';

class _FakeGatewayRuntime extends GatewayRuntime {
  factory _FakeGatewayRuntime() {
    final store = createIsolatedTestStore();
    return _FakeGatewayRuntime._(store);
  }

  _FakeGatewayRuntime._(SecureConfigStore store)
    : super(store: store, identityStore: DeviceIdentityStore(store));

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
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode).copyWith(
      status: RuntimeConnectionStatus.connected,
      statusText: 'Connected',
    );
    _events.add(
      const GatewayPushEvent(
        event: 'gateway/connected',
        payload: <String, dynamic>{},
      ),
    );
  }

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    _snapshot = _snapshot.copyWith(
      status: RuntimeConnectionStatus.offline,
      statusText: 'Offline',
    );
  }

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return <String, dynamic>{};
  }
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
  Future<ModeSwitchResult> autoSelect({
    bool preferRemote = true,
    String? localToken,
    String? remoteToken,
  }) async {
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

    test(
      'built-in mode does not resolve or start external codex process',
      () async {
        codex.findResult = '/usr/local/bin/codex';

        await coordinator.initialize(
          preferredMode: GatewayMode.remote,
          runtimeMode: CodeAgentRuntimeMode.builtIn,
        );

        expect(coordinator.runtimeMode, CodeAgentRuntimeMode.builtIn);
        expect(codex.findCalled, isFalse);
        expect(codex.startCalled, isFalse);
        expect(coordinator.isReady, isTrue);
      },
    );

    test(
      'external mode keeps gateway ready without starting local codex process',
      () async {
        codex.findResult = '/usr/local/bin/codex';

        await coordinator.initialize(
          preferredMode: GatewayMode.remote,
          runtimeMode: CodeAgentRuntimeMode.externalCli,
        );

        expect(coordinator.runtimeMode, CodeAgentRuntimeMode.externalCli);
        expect(codex.findCalled, isFalse);
        expect(codex.startCalled, isFalse);
        expect(modeSwitcher.currentMode, GatewayMode.remote);
      },
    );

    test(
      'external mode no longer forces offline when codex binary is missing',
      () async {
        codex.findResult = null;

        await coordinator.initialize(
          preferredMode: GatewayMode.remote,
          runtimeMode: CodeAgentRuntimeMode.externalCli,
        );

        expect(codex.findCalled, isFalse);
        expect(codex.startCalled, isFalse);
        expect(modeSwitcher.offlineSwitchCalled, isFalse);
        expect(modeSwitcher.currentMode, GatewayMode.remote);
      },
    );
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

    test('normalizes provider command and capabilities on register', () {
      const provider = ExternalCodeAgentProvider(
        id: 'codex',
        name: 'Codex CLI',
        command: '  codex  ',
        capabilities: <String>[' chat ', 'CODE-EDIT', 'chat', ''],
      );

      coordinator.registerExternalCodeAgent(provider);

      final stored = coordinator.externalCodeAgents.single;
      expect(stored.command, 'codex');
      expect(stored.capabilities, <String>['chat', 'code-edit']);
    });

    test('discovers providers by required capabilities', () {
      coordinator.registerExternalCodeAgent(
        const ExternalCodeAgentProvider(
          id: 'codex',
          name: 'Codex CLI',
          command: 'codex',
          capabilities: <String>['chat', 'code-edit', 'gateway-bridge'],
        ),
      );
      coordinator.registerExternalCodeAgent(
        const ExternalCodeAgentProvider(
          id: 'qwen-cli',
          name: 'Qwen CLI',
          command: 'qwen',
          capabilities: <String>['chat'],
        ),
      );
      coordinator.registerExternalCodeAgent(
        const ExternalCodeAgentProvider(
          id: 'llama-cli',
          name: 'Llama CLI',
          command: 'llama',
          capabilities: <String>['code-edit'],
        ),
      );

      final codeEditProviders = coordinator.discoverExternalCodeAgents(
        requiredCapabilities: const <String>['code-edit'],
      );
      expect(
        codeEditProviders.map((provider) => provider.id).toList(),
        <String>['codex', 'llama-cli'],
      );

      final bridgeProviders = coordinator.discoverExternalCodeAgents(
        requiredCapabilities: const <String>['chat', 'gateway-bridge'],
      );
      expect(bridgeProviders.map((provider) => provider.id).toList(), <String>[
        'codex',
      ]);
    });

    test(
      'selects provider by preferred id then falls back deterministically',
      () {
        coordinator.registerExternalCodeAgent(
          const ExternalCodeAgentProvider(
            id: 'codex',
            name: 'Codex CLI',
            command: 'codex',
            capabilities: <String>['chat', 'code-edit'],
          ),
        );
        coordinator.registerExternalCodeAgent(
          const ExternalCodeAgentProvider(
            id: 'qwen-cli',
            name: 'Qwen CLI',
            command: 'qwen',
            capabilities: <String>['chat'],
          ),
        );

        final preferred = coordinator.selectExternalCodeAgent(
          preferredProviderId: 'qwen-cli',
          requiredCapabilities: const <String>['chat'],
        );
        expect(preferred?.id, 'qwen-cli');

        final fallback = coordinator.selectExternalCodeAgent(
          preferredProviderId: 'qwen-cli',
          requiredCapabilities: const <String>['code-edit'],
        );
        expect(fallback?.id, 'codex');
      },
    );

    test('returns null when no provider satisfies required capabilities', () {
      coordinator.registerExternalCodeAgent(
        const ExternalCodeAgentProvider(
          id: 'qwen-cli',
          name: 'Qwen CLI',
          command: 'qwen',
          capabilities: <String>['chat'],
        ),
      );

      final selected = coordinator.selectExternalCodeAgent(
        requiredCapabilities: const <String>['memory-sync'],
      );
      expect(selected, isNull);
    });
  });
}
