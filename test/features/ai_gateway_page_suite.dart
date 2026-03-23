@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/theme/app_theme.dart';

import '../test_support.dart';

class _FakeGatewayRuntime extends GatewayRuntime {
  factory _FakeGatewayRuntime() {
    final store = createIsolatedTestStore();
    return _FakeGatewayRuntime._(store);
  }

  _FakeGatewayRuntime._(SecureConfigStore store)
    : super(store: store, identityStore: DeviceIdentityStore(store));

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {}

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {}

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
  @override
  Future<String?> findCodexBinary() async => null;

  @override
  Future<void> stop() async {}
}

class _AiGatewaySettingsShortcutTestController extends AppController {
  _AiGatewaySettingsShortcutTestController({
    required super.store,
    required super.runtimeCoordinator,
    super.uiFeatureManifest,
  });

  @override
  Future<void> refreshMultiAgentMounts({bool sync = false}) async {}
}

void main() {
  testWidgets('LLM API shortcut routes to Settings center', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    controller.navigateTo(WorkspaceDestination.aiGateway);

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

    expect(find.text('OpenClaw Gateway'), findsOneWidget);
    expect(find.text('LLM API'), findsWidgets);
  });

  testWidgets(
    'Settings external agents detail keeps Codex bridge runtime states',
    (WidgetTester tester) async {
      late AppController controller;
      late Directory testRoot;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        testRoot = await Directory.systemTemp.createTemp(
          'xworkmate-ai-gateway-shortcut-',
        );
        final store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => '${testRoot.path}/settings.sqlite3',
          fallbackDirectoryPathResolver: () async => testRoot.path,
        );
        final manifest = UiFeatureManifest.fallback().copyWithFeature(
          platform: UiFeaturePlatform.desktop,
          module: 'settings',
          feature: 'agents',
          enabled: true,
          releaseTier: UiFeatureReleaseTier.stable,
        );
        controller = _AiGatewaySettingsShortcutTestController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: _FakeGatewayRuntime(),
            codex: _FakeCodexRuntime(),
          ),
          uiFeatureManifest: manifest,
        );
        await _waitFor(() => !controller.initializing);
      });
      addTearDown(() => controller.dispose());
      addTearDown(() async {
        if (await testRoot.exists()) {
          await testRoot.delete(recursive: true);
        }
      });

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1000);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      controller.openSettings(
        detail: SettingsDetailPage.externalAgents,
        navigationContext: SettingsNavigationContext(
          rootLabel: '设置',
          destination: WorkspaceDestination.settings,
          sectionLabel: SettingsTab.agents.label,
          settingsTab: SettingsTab.agents,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: Scaffold(
            body: SettingsPage(
              controller: controller,
              initialTab: controller.settingsTab,
              initialDetail: controller.settingsDetail,
              navigationContext: controller.settingsNavigationContext,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('External Codex CLI'), findsOneWidget);
      expect(find.text('Built-in Codex (Experimental)'), findsOneWidget);
      expect(find.text('未检测到'), findsOneWidget);

      final builtInChip = find.widgetWithText(
        ChoiceChip,
        'Built-in Codex (Experimental)',
      );
      await tester.ensureVisible(builtInChip);
      await tester.tap(builtInChip);
      await tester.pumpAndSettle();
      expect(
        controller.settings.codeAgentRuntimeMode,
        CodeAgentRuntimeMode.builtIn,
      );

      late Directory tempDir;
      late File codexBinary;
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'codex-ai-gateway-shortcut-',
        );
        codexBinary = File('${tempDir.path}/codex');
        await codexBinary.writeAsString('#!/bin/sh\nexit 0\n');
        await controller.saveSettings(
          controller.settings.copyWith(
            codeAgentRuntimeMode: CodeAgentRuntimeMode.externalCli,
            codexCliPath: codexBinary.path,
          ),
        );
      });
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('已就绪'), findsOneWidget);
      expect(find.text(codexBinary.path), findsAtLeastNWidgets(1));
    },
  );
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
