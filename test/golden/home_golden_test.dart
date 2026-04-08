import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:xworkmate/features/assistant/assistant_page.dart';

import '../test_support.dart';
import '../helpers/golden_test_bootstrap.dart';

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
  });

  testGoldens('assistant home shell', (tester) async {
    final controller = await createTestController(tester);
    await pumpGoldenApp(
      tester,
      AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );
    await screenMatchesGolden(tester, 'assistant_home_shell');
  });
}
