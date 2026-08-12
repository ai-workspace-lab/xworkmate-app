import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/collapsed_pane_reveal_button.dart';

void main() {
  testWidgets('keeps a labelled, tappable affordance while a pane is hidden', (
    tester,
  ) async {
    var revealCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CollapsedPaneRevealButton(
            buttonKey: const Key('reveal-pane'),
            tooltip: 'Expand navigation',
            icon: Icons.keyboard_double_arrow_right_rounded,
            onTap: () => revealCount += 1,
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byKey(const Key('reveal-pane'))).label,
      'Expand navigation',
    );

    await tester.tap(find.byKey(const Key('reveal-pane')));
    expect(revealCount, 1);
  });
}
