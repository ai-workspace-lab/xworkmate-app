@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_shell.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/features/mobile/mobile_shell.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/widgets/detail_drawer.dart';
import 'package:xworkmate/theme/app_theme.dart';

import '../../test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mobileScannerChannel = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mobileScannerChannel, (call) async {
          return switch (call.method) {
            'state' => 1,
            'request' => true,
            'start' => <Object?, Object?>{
              'textureId': 1,
              'size': <Object?, Object?>{'width': 1080.0, 'height': 1920.0},
              'numberOfCameras': 1,
              'currentTorchMode': 0,
            },
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mobileScannerChannel, null);
  });

  test('mobile shell keeps a single active entrypoint', () {
    expect(File('lib/features/mobile/mobile_shell.dart').existsSync(), isTrue);
    expect(
      File('lib/features/mobile/mobile_shell_core.dart').existsSync(),
      isTrue,
    );
    expect(
      File('lib/features/mobile/ios_mobile_shell.dart').existsSync(),
      isFalse,
    );
  });

  Future<void> pumpMobileShell(
    WidgetTester tester, {
    required Widget child,
    required TargetPlatform platform,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(platform: platform),
        darkTheme: AppTheme.dark(platform: platform),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('MobileShell workspace launcher routes into module pages', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpMobileShell(
      tester,
      child: MobileShell(controller: controller),
      platform: TargetPlatform.android,
    );

    await tester.tap(find.text('工作区'));
    await tester.pumpAndSettle();
    expect(find.text('MCP Hub'), findsOneWidget);

    await tester.tap(find.text('节点').first);
    await tester.pumpAndSettle();
    expect(controller.destination, WorkspaceDestination.nodes);
    expect(find.text('模块'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MobileShell workspace launcher filters disabled entries', (
    WidgetTester tester,
  ) async {
    final manifest = UiFeatureManifest.fallback().copyWithFeature(
      platform: UiFeaturePlatform.mobile,
      module: 'workspace',
      feature: 'mcp_server',
      enabled: false,
    );
    final controller = await createTestController(
      tester,
      uiFeatureManifest: manifest,
    );

    await pumpMobileShell(
      tester,
      child: MobileShell(controller: controller),
      platform: TargetPlatform.android,
    );

    await tester.tap(find.text('工作区'));
    await tester.pumpAndSettle();

    expect(find.text('MCP Hub'), findsNothing);
    expect(find.text('节点'), findsOneWidget);
  });

  testWidgets('MobileShell renders detail panels as bottom sheets', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpMobileShell(
      tester,
      child: MobileShell(controller: controller),
      platform: TargetPlatform.android,
    );

    controller.openDetail(
      DetailPanelData(
        title: 'Test Detail',
        subtitle: 'Mobile',
        icon: Icons.extension_rounded,
        status: const StatusInfo('Ready', StatusTone.success),
        description: 'Detail content',
        meta: const <String>[],
        sections: const <DetailSection>[],
        actions: const <String>[],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DetailSheet), findsOneWidget);
  });

  testWidgets('AppShell uses MobileShell on compact iOS and Android only', (
    WidgetTester tester,
  ) async {
    final compactController = await createTestController(tester);

    await pumpMobileShell(
      tester,
      child: AppShell(controller: compactController),
      platform: TargetPlatform.android,
    );

    expect(find.byType(MobileShell), findsOneWidget);

    final compactIosController = await createTestController(tester);
    await pumpMobileShell(
      tester,
      child: AppShell(controller: compactIosController),
      platform: TargetPlatform.iOS,
    );
    expect(find.byType(MobileShell), findsOneWidget);

    final desktopAndroidController = await createTestController(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(platform: TargetPlatform.android),
        darkTheme: AppTheme.dark(platform: TargetPlatform.android),
        home: AppShell(controller: desktopAndroidController),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MobileShell), findsNothing);
  });

  testWidgets('MobileShell exposes mobile-safe pairing shortcuts', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpMobileShell(
      tester,
      child: MobileShell(controller: controller),
      platform: TargetPlatform.iOS,
    );

    expect(find.byKey(const ValueKey('mobile-safe-strip')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-safe-open-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-safe-connect-button')),
      findsOneWidget,
    );
  });
}
