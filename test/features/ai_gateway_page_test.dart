import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/ai_gateway/ai_gateway_page.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/theme/app_theme.dart';

class _FakeGatewayRuntime extends GatewayRuntime {
  _FakeGatewayRuntime()
    : super(
        store: SecureConfigStore(),
        identityStore: DeviceIdentityStore(SecureConfigStore()),
      );

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
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

void main() {
  testWidgets('AiGatewayPage shows Codex bridge runtime states', (
    WidgetTester tester,
  ) async {
    late AppController controller;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SecureConfigStore();
      controller = AppController(
        store: store,
        runtimeCoordinator: RuntimeCoordinator(
          gateway: _FakeGatewayRuntime(),
          codex: _FakeCodexRuntime(),
        ),
      );
      await _waitFor(() => !controller.initializing);
    });
    addTearDown(() => controller.dispose());

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: Scaffold(
          body: AiGatewayPage(controller: controller, onOpenDetail: (_) {}),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('工具'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('External Codex CLI'), findsOneWidget);
    expect(find.text('Built-in Codex (Experimental)'), findsOneWidget);
    expect(find.text('未检测到'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(ChoiceChip, 'Built-in Codex (Experimental)'),
    );
    await tester.pumpAndSettle();
    expect(
      controller.settings.codeAgentRuntimeMode,
      CodeAgentRuntimeMode.builtIn,
    );

    late Directory tempDir;
    late File codexBinary;
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('codex-ai-gateway-page-');
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
  });
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
