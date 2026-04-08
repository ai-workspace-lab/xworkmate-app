import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/features/settings/settings_page.dart';

import '../helpers/golden_test_bootstrap.dart';
import '../test_support.dart';

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
  });

  testGoldens('settings integrations shell', (tester) async {
    final controller = await createTestController(tester);
    await pumpGoldenApp(
      tester,
      SettingsPage(controller: controller, initialTab: SettingsTab.gateway),
    );
    await screenMatchesGolden(tester, 'settings_integrations_shell');
  });
}
