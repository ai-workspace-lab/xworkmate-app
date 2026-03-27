@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/modules/modules_page.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

import '../test_support.dart';

void main() {
  testWidgets(
    'Modules gateway shortcut routes to Settings center and modules page excludes the old gateway tab',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);
      controller.openModules(tab: ModulesTab.gateway);

      expect(controller.destination, WorkspaceDestination.settings);
      expect(controller.settingsTab, SettingsTab.gateway);

      await pumpPage(
        tester,
        child: SettingsPage(
          controller: controller,
          initialTab: controller.settingsTab,
          initialDetail: controller.settingsDetail,
          navigationContext: controller.settingsNavigationContext,
        ),
      );

      expect(find.text('OpenClaw Gateway'), findsWidgets);

      controller.navigateTo(WorkspaceDestination.nodes);
      await pumpPage(
        tester,
        child: ModulesPage(controller: controller, onOpenDetail: (_) {}),
      );

      expect(find.text('ClawHub'), findsNothing);
      expect(find.text('连接器'), findsNothing);

      await tester.tap(find.text('打开设置中心'));
      await tester.pumpAndSettle();
      expect(controller.destination, WorkspaceDestination.settings);
      expect(controller.settingsTab, SettingsTab.gateway);
      expect(controller.settingsDetail, isNull);
    },
  );

  testWidgets('ModulesPage skill tab shows three execution mode cards', (
    WidgetTester tester,
  ) async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'xworkmate-modules-page-skills-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    await _writeSkill(
      Directory('${tempDirectory.path}/custom-skills'),
      'browser-automation',
      skillName: 'Browser Automation',
      description: 'Automate browser tasks',
    );

    final store = SecureConfigStore(
      enableSecureStorage: false,
      databasePathResolver: () async => '${tempDirectory.path}/settings.db',
      fallbackDirectoryPathResolver: () async => tempDirectory.path,
      defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
    );
    final controller = AppController(
      store: store,
      runtimeCoordinator: RuntimeCoordinator(
        gateway: _FakeGatewayRuntime(store: store),
        codex: _FakeCodexRuntime(),
      ),
      singleAgentSharedSkillScanRootOverrides: <String>[
        '${tempDirectory.path}/custom-skills',
      ],
    );
    addTearDown(controller.dispose);
    final stopwatch = Stopwatch()..start();
    while (controller.initializing) {
      if (stopwatch.elapsed > const Duration(seconds: 10)) {
        fail('controller did not finish initializing before timeout');
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    await controller.setAssistantExecutionTarget(
      AssistantExecutionTarget.singleAgent,
    );
    await tester.pumpAndSettle();

    controller.openModules(tab: ModulesTab.skills);
    await pumpPage(
      tester,
      child: ModulesPage(
        controller: controller,
        onOpenDetail: (_) {},
        initialTab: ModulesTab.skills,
      ),
    );

    expect(find.text('技能模式'), findsOneWidget);
    expect(find.text('单机智能体'), findsOneWidget);
    expect(find.text('本地 Gateway'), findsOneWidget);
    expect(find.text('远程 Gateway'), findsOneWidget);
    expect(find.text('Browser Automation'), findsWidgets);
  }, skip: true);
}

Future<void> _writeSkill(
  Directory root,
  String name, {
  required String skillName,
  required String description,
}) async {
  final directory = Directory('${root.path}/$name');
  await directory.create(recursive: true);
  await File('${directory.path}/SKILL.md').writeAsString('''
---
name: $skillName
description: $description
---
''');
}

class _FakeGatewayRuntime extends GatewayRuntime {
  _FakeGatewayRuntime({required super.store})
    : super(identityStore: DeviceIdentityStore(store));

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
          'pending': const <Object>[],
          'paired': const <Object>[],
        };
      case 'system-presence':
        return const <Object>[];
      default:
        return <String, dynamic>{};
    }
  }
}

class _FakeCodexRuntime extends CodexRuntime {
  @override
  Future<String?> findCodexBinary() async => null;

  @override
  Future<void> stop() async {}
}
