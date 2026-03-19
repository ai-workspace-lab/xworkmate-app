import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/runtime/desktop_platform_service.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

import '../test_support.dart';

class _DesktopServiceStub implements DesktopPlatformService {
  @override
  DesktopIntegrationState get state =>
      DesktopIntegrationState.fromJson(const <String, dynamic>{
        'isSupported': true,
        'environment': 'kde',
        'mode': 'proxy',
        'trayAvailable': true,
        'trayEnabled': true,
        'autostartEnabled': false,
        'networkManagerAvailable': true,
        'systemProxy': {
          'enabled': true,
          'host': '127.0.0.1',
          'port': 7890,
          'backend': 'kioslaverc',
          'lastAppliedMode': 'proxy',
        },
        'tunnel': {
          'available': true,
          'connected': false,
          'connectionName': 'XWorkmate Tunnel',
          'backend': 'nmcli',
          'lastError': '',
        },
        'statusMessage': '',
      });

  @override
  bool get isSupported => state.isSupported;

  @override
  Future<void> initialize(LinuxDesktopConfig config) async {}

  @override
  Future<void> syncConfig(LinuxDesktopConfig config) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> setMode(VpnMode mode) async {}

  @override
  Future<void> connectTunnel() async {}

  @override
  Future<void> disconnectTunnel() async {}

  @override
  Future<void> setLaunchAtLogin(bool enabled) async {}

  @override
  void dispose() {}
}

void main() {
  testWidgets('SettingsPage theme chips update controller theme mode', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(tester, child: SettingsPage(controller: controller));

    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.dark);

    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(controller.themeMode, ThemeMode.light);
  });

  testWidgets('SettingsPage gateway tab exposes device pairing controls', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(tester, child: SettingsPage(controller: controller));

    await tester.tap(find.text('集成'));
    await tester.pumpAndSettle();

    expect(find.text('打开连接面板'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gateway-device-security-card')),
      findsOneWidget,
    );
  });

  testWidgets('SettingsPage shows Linux desktop integration controls', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(
      tester,
      desktopPlatformService: _DesktopServiceStub(),
    );

    await pumpPage(tester, child: SettingsPage(controller: controller));

    expect(
      find.byKey(const ValueKey('linux-desktop-integration-card')),
      findsOneWidget,
    );
    expect(find.text('Linux 桌面集成'), findsOneWidget);
    expect(find.text('切换到代理'), findsOneWidget);
    expect(find.text('连接隧道'), findsOneWidget);
  });

  testWidgets('SettingsPage multi-agent tab keeps header readable', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: const SizedBox(width: 1100, height: 900, child: Placeholder()),
    );
    await pumpPage(
      tester,
      child: SizedBox(
        width: 1100,
        height: 900,
        child: SettingsPage(controller: controller),
      ),
    );

    await tester.tap(find.text('多 Agent'));
    await tester.pumpAndSettle();

    final titleFinder = find.text('多 Agent 协作');
    expect(titleFinder, findsOneWidget);
    expect(tester.getSize(titleFinder).width, greaterThan(80));
    expect(find.text('启用协作模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SettingsPage diagnostics tab filters and clears runtime logs', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.runtime.addRuntimeLogForTest(
      level: 'info',
      category: 'connect',
      message: 'connected remote gateway',
    );
    controller.runtime.addRuntimeLogForTest(
      level: 'warn',
      category: 'pairing',
      message: 'pairing required',
    );

    await pumpPage(tester, child: SettingsPage(controller: controller));

    await tester.tap(find.text('诊断'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('runtime-log-card')), findsOneWidget);
    expect(find.textContaining('connected remote gateway'), findsOneWidget);
    expect(find.textContaining('pairing required'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('runtime-log-filter')),
      'pairing',
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('connected remote gateway'), findsNothing);
    expect(find.textContaining('pairing required'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.runtimeLogs, isEmpty);
  });
}
