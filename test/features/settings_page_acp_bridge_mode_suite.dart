@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/settings_page_core.dart';
import 'package:xworkmate/models/app_models.dart';

import '../test_support.dart';

void main() {
  testWidgets('SettingsPage shows ACP bridge server mode card on integrations', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.openSettings(tab: SettingsTab.gateway);

    await pumpPage(
      tester,
      child: SettingsPage(
        controller: controller,
        initialTab: SettingsTab.gateway,
      ),
    );

    expect(find.text('XWorkmate ACP Bridge Server'), findsOneWidget);
    expect(find.byKey(const ValueKey('acp-bridge-mode-cloud')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('acp-bridge-mode-self-hosted')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('acp-bridge-mode-advanced')),
      findsOneWidget,
    );
  });
}
