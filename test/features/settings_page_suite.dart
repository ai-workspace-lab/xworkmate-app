@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/models/app_models.dart';
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

    await pumpPage(
      tester,
      child: SettingsPage(controller: controller),
      platform: TargetPlatform.macOS,
    );

    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.dark);

    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(controller.themeMode, ThemeMode.light);
  });

  testWidgets('SettingsPage integration tab exposes unified gateway controls', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: SettingsPage(controller: controller),
      platform: TargetPlatform.macOS,
    );

    await tester.tap(find.text('集成'));
    await tester.pumpAndSettle();

    expect(find.text('OpenClaw Gateway'), findsOneWidget);
    expect(find.text('Vault Server'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-gateway-url-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('gateway-mode-field')), findsNothing);
    expect(find.text('认证诊断'), findsNothing);
    expect(find.byKey(const ValueKey('gateway-test-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('gateway-save-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('gateway-apply-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gateway-profile-chip-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gateway-profile-chip-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gateway-profile-chip-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gateway-profile-chip-3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gateway-profile-chip-4')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gateway-device-security-card')),
      findsOneWidget,
    );
  });

  testWidgets('SettingsPage gateway sections can collapse individually', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: SettingsPage(controller: controller),
      platform: TargetPlatform.macOS,
    );

    await tester.tap(find.text('集成'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OpenClaw Gateway'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('gateway-host-field')), findsNothing);
    expect(find.byKey(const ValueKey('gateway-test-button')), findsNothing);
    expect(
      find.byKey(const ValueKey('gateway-device-security-card')),
      findsNothing,
    );

    await tester.tap(find.text('OpenClaw Gateway'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('gateway-host-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('gateway-test-button')), findsOneWidget);
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

    await pumpPage(
      tester,
      child: SettingsPage(controller: controller),
      platform: TargetPlatform.macOS,
    );

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
    final manifest = UiFeatureManifest.fallback().copyWithFeature(
      platform: UiFeaturePlatform.desktop,
      module: 'settings',
      feature: 'agents',
      enabled: true,
      releaseTier: UiFeatureReleaseTier.stable,
    );
    final controller = await createTestController(
      tester,
      uiFeatureManifest: manifest,
    );

    await pumpPage(
      tester,
      child: const SizedBox(width: 1100, height: 900, child: Placeholder()),
      platform: TargetPlatform.macOS,
    );
    await pumpPage(
      tester,
      child: SizedBox(
        width: 1100,
        height: 900,
        child: SettingsPage(controller: controller),
      ),
      platform: TargetPlatform.macOS,
    );

    await tester.tap(find.text('多 Agent'));
    await tester.pumpAndSettle();

    final titleFinder = find.text('多 Agent 协作');
    expect(titleFinder, findsOneWidget);
    expect(tester.getSize(titleFinder).width, greaterThan(80));
    expect(find.text('启用协作模式'), findsOneWidget);
    expect(find.text('协作框架'), findsOneWidget);
    expect(find.textContaining('Lead Engineer'), findsWidgets);
    expect(find.textContaining('ollama launch codex'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SettingsPage hides gateway setup code editor by default', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: SettingsPage(controller: controller),
      platform: TargetPlatform.macOS,
    );

    await tester.tap(find.text('集成'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gateway-profile-chip-1')));
    await tester.pumpAndSettle();

    expect(find.text('配置码'), findsNothing);
    expect(
      find.byKey(const ValueKey('gateway-setup-code-field')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('gateway-host-field')), findsOneWidget);
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

  testWidgets('SettingsPage hides tabs disabled by feature manifest', (
    WidgetTester tester,
  ) async {
    final manifest = UiFeatureManifest.fallback()
        .copyWithFeature(
          platform: UiFeaturePlatform.desktop,
          module: 'settings',
          feature: 'diagnostics',
          enabled: false,
        )
        .copyWithFeature(
          platform: UiFeaturePlatform.desktop,
          module: 'settings',
          feature: 'experimental',
          enabled: false,
        );
    final controller = await createTestController(
      tester,
      uiFeatureManifest: manifest,
    );

    await pumpPage(
      tester,
      child: SettingsPage(controller: controller),
      platform: TargetPlatform.macOS,
    );

    expect(find.text('诊断'), findsNothing);
    expect(find.text('实验特性'), findsNothing);
  });

  testWidgets(
    'SettingsPage clears local assistant state with double confirmation',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await pumpPage(tester, child: SettingsPage(controller: controller));

      await tester.tap(find.text('诊断'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('assistant-local-state-card')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('assistant-local-state-clear-button')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final confirmButtonFinder = find.widgetWithText(FilledButton, '确认清理');
      final confirmButtonBefore = tester.widget<FilledButton>(
        confirmButtonFinder,
      );
      expect(confirmButtonBefore.onPressed, isNull);

      await tester.tap(
        find.byKey(const ValueKey('assistant-local-state-clear-confirm')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final confirmButtonAfter = tester.widget<FilledButton>(
        confirmButtonFinder,
      );
      expect(confirmButtonAfter.onPressed, isNotNull);
    },
  );

  testWidgets('SettingsPage detail mode returns to overview', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.openSettings(
      detail: SettingsDetailPage.gatewayConnection,
      navigationContext: SettingsNavigationContext(
        rootLabel: '设置',
        destination: WorkspaceDestination.settings,
        sectionLabel: SettingsTab.gateway.label,
        settingsTab: SettingsTab.gateway,
      ),
    );

    await pumpPage(
      tester,
      child: SettingsPage(
        controller: controller,
        initialTab: controller.settingsTab,
        initialDetail: controller.settingsDetail,
        navigationContext: controller.settingsNavigationContext,
      ),
    );

    expect(find.text('Gateway 连接参数'), findsWidgets);
    expect(find.text('返回概览'), findsOneWidget);

    await tester.tap(find.text('返回概览'));
    await tester.pumpAndSettle();

    expect(controller.settingsDetail, isNull);
    expect(find.text('搜索设置'), findsOneWidget);
  });
}
