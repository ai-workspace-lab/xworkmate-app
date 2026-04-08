import 'package:flutter_test/flutter_test.dart';

import '../test/helpers/test_keys.dart';
import 'test_support.dart';

void main() {
  initializeIntegrationHarness();

  testWidgets('assistant task flow exposes single agent target', (
    WidgetTester tester,
  ) async {
    await pumpDesktopApp(tester);
    expect(find.byKey(TestKeys.assistantTaskRail), findsOneWidget);
    expect(find.byKey(TestKeys.assistantExecutionTargetButton), findsOneWidget);
    expect(find.byKey(TestKeys.assistantComposerInput), findsOneWidget);
    expect(find.byKey(TestKeys.assistantSubmitButton), findsOneWidget);
    expect(find.text('单机智能体'), findsWidgets);
  });
}
