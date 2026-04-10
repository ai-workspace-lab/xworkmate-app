@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/mobile/mobile_gateway_pairing_guide_page.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mobileScannerChannel = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mobileScannerChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mobileScannerChannel, null);
  });

  Future<void> pumpGuide(
    WidgetTester tester, {
    required bool supportsQrScan,
    required VoidCallback onManual,
    required VoidCallback onManualCode,
    required Future<void> Function(String setupCode) onScanned,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(platform: TargetPlatform.iOS),
        darkTheme: AppTheme.dark(platform: TargetPlatform.iOS),
        home: MobileGatewayPairingGuidePage(
          supportsQrScan: supportsQrScan,
          onManualInput: onManual,
          onManualCodeInput: onManualCode,
          onScannedSetupCode: onScanned,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('guide shows xworkmate commands', (tester) async {
    await pumpGuide(
      tester,
      supportsQrScan: true,
      onManual: () {},
      onManualCode: () {},
      onScanned: (_) async {},
    );

    expect(find.text('配对网关'), findsOneWidget);
    expect(find.text('npm install -g xworkmate'), findsOneWidget);
    expect(find.text('xworkmate pair'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pairing-guide-install-command')),
      findsOneWidget,
    );
  });

  testWidgets('manual button triggers callback', (tester) async {
    var manualTapped = false;
    await pumpGuide(
      tester,
      supportsQrScan: true,
      onManual: () => manualTapped = true,
      onManualCode: () {},
      onScanned: (_) async {},
    );

    await tester.tap(find.byKey(const ValueKey('pairing-guide-manual-button')));
    await tester.pumpAndSettle();
    expect(manualTapped, isTrue);
  });

  testWidgets('android scan button shows placeholder toast', (tester) async {
    await pumpGuide(
      tester,
      supportsQrScan: false,
      onManual: () {},
      onManualCode: () {},
      onScanned: (_) async {},
    );

    await tester.tap(find.byKey(const ValueKey('pairing-guide-scan-button')));
    await tester.pump();
    expect(find.textContaining('Android 扫码即将支持'), findsOneWidget);
  });

  test('scan parser accepts json setup payload wrappers', () {
    const payload =
        '{"setupCode":"{\\"url\\":\\"wss://gateway.example.com\\",\\"token\\":\\"shared-token\\"}"}';

    expect(
      resolveGatewaySetupCodeFromScan(payload),
      '{"url":"wss://gateway.example.com","token":"shared-token"}',
    );
  });

  testWidgets('manual code button triggers callback', (tester) async {
    var manualCodeTapped = false;
    await pumpGuide(
      tester,
      supportsQrScan: true,
      onManual: () {},
      onManualCode: () => manualCodeTapped = true,
      onScanned: (_) async {},
    );

    await tester.tap(
      find.byKey(const ValueKey('pairing-guide-manual-code-button')),
    );
    await tester.pumpAndSettle();
    expect(manualCodeTapped, isTrue);
  });

  test('scan parser accepts bridge bootstrap envelopes and short codes', () {
    const envelope =
        '{"scheme":"xworkmate-bridge-bootstrap","ticket":"ticket-1","bridge":"https://xworkmate-bridge.svc.plus"}';

    expect(resolveGatewaySetupCodeFromScan(envelope), envelope);
    expect(resolveGatewaySetupCodeFromScan('AB12CD34'), 'AB12CD34');
  });
}
