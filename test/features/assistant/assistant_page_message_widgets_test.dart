import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/assistant_page_message_widgets.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  testWidgets('shows historical user attachments as cards by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Material(
          child: MessageBubbleBodyInternal(
            text: 'Attached files:\n- 01.png\n- screenshot.png\n\n制作视频',
            renderMarkdown: false,
            compactUserMetadata: true,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('assistant-user-attachment-cards')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assistant-user-attachment-card-0')),
      findsOneWidget,
    );
    expect(find.text('01.png'), findsOneWidget);
    expect(find.text('screenshot.png'), findsOneWidget);
    expect(
      find.byKey(const Key('assistant-user-meta-attachments-toggle')),
      findsNothing,
    );
  });
}
