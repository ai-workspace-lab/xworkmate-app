import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

Map<String, String> loadDotEnvValues() {
  final file = File('.env');
  if (!file.existsSync()) {
    return const <String, String>{};
  }
  final values = <String, String>{};
  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
      continue;
    }
    final index = line.indexOf('=');
    final key = line.substring(0, index).trim();
    var value = line.substring(index + 1).trim();
    if ((value.startsWith("'") && value.endsWith("'")) ||
        (value.startsWith('"') && value.endsWith('"'))) {
      value = value.substring(1, value.length - 1);
    }
    values[key] = value;
  }
  return values;
}

void main() {
  initializeIntegrationHarness();

  testWidgets('loads gateway env values for settings smoke flow', (
    WidgetTester tester,
  ) async {
    final env = loadDotEnvValues();
    expect(env.containsKey('AI-Gateway-Url'), isTrue);
    expect(env.containsKey('AI-Gateway-apiKey'), isTrue);
    await pumpDesktopApp(tester);
    await settleIntegrationUi(tester);
  });
}
