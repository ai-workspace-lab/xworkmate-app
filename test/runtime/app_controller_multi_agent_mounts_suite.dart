@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/multi_agent_mount_resolver.dart';
import 'package:xworkmate/runtime/multi_agent_mounts.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

import '../test_support.dart';

void main() {
  test(
    'AppController refreshMultiAgentMounts persists reconciled mount state',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppController(
        store: createIsolatedTestStore(enableSecureStorage: false),
        multiAgentMountManager: MultiAgentMountManager(
          resolver: _FakeMountResolver(
            config: MultiAgentConfig.defaults().copyWith(
              arisBundleVersion: 'batch3',
              arisCompatStatus: 'ready',
              mountTargets: const <ManagedMountTargetState>[
                ManagedMountTargetState(
                  targetId: 'opencode',
                  label: 'OpenCode',
                  available: true,
                  supportsSkills: true,
                  supportsMcp: true,
                  supportsAiGatewayInjection: true,
                  discoveryState: 'ready',
                  syncState: 'ready',
                  discoveredSkillCount: 0,
                  discoveredMcpCount: 3,
                  managedMcpCount: 1,
                  detail: 'resolver result',
                ),
              ],
            ),
          ),
        ),
      );
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);
      await controller.refreshMultiAgentMounts(sync: true);

      expect(controller.settings.multiAgent.arisBundleVersion, 'batch3');
      expect(controller.settings.multiAgent.arisCompatStatus, 'ready');
      expect(controller.settings.multiAgent.mountTargets, hasLength(1));
      expect(
        controller.settings.multiAgent.mountTargets.single.targetId,
        'opencode',
      );
      expect(
        controller.multiAgentOrchestrator.config.mountTargets.single.detail,
        'resolver result',
      );
    },
  );
}

class _FakeMountResolver implements MultiAgentMountResolver {
  _FakeMountResolver({required this.config});

  final MultiAgentConfig config;

  @override
  Future<MultiAgentConfig?> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
    String configuredCodexCliPath = '',
    required String codexHome,
    required String opencodeHome,
    required ArisMountProbe arisProbe,
  }) async => this.config;

  @override
  Future<void> dispose() async {}
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
