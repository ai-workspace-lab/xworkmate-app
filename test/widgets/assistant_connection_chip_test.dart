@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/assistant_page_message_widgets.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  testWidgets(
    'ConnectionStatusChipInternal ellipsizes long labels inside narrow containers',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: ConnectionStatusChipInternal(
                  key: const Key('assistant-connection-chip'),
                  statusLabel:
                      'Auto · qwen2.5-coder-super-long-model-name-for-toolbar · 127.0.0.1:11434',
                  backgroundColor: Colors.blueGrey,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chipFinder = find.byKey(const Key('assistant-connection-chip'));
      expect(chipFinder, findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(chipFinder).width, lessThanOrEqualTo(180));

      final chipText = tester.widget<Text>(
        find.descendant(of: chipFinder, matching: find.byType(Text)),
      );
      expect(chipText.maxLines, 1);
      expect(chipText.overflow, TextOverflow.ellipsis);
      expect(chipText.softWrap, isFalse);
    },
  );
}
