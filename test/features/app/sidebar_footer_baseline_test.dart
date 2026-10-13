import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/assistant_page_main.dart';
import 'package:xworkmate/widgets/sidebar_navigation.dart';

/// The sidebar footer row and the composer card sit side by side across the
/// window. The footer used to be a three-row block that also had to match the
/// card's height (a reported 25pt step between them); it is now one control
/// row with settings, language, theme and account behind a menu, so only the
/// shared baseline remains to keep them aligned.
///
/// These are pure arithmetic checks on purpose. The two blocks live in
/// unrelated widgets, so nothing else would notice if one of them moved.
void main() {
  /// How far the composer card floats above the pane bottom.
  const composerCardBottomInset = assistantComposerSafeAreaGapInternal + 8;

  /// The sidebar pane's own vertical padding, which covers part of that inset.
  const sidebarPanePadding = 4.0;

  test('the footer is a single control row', () {
    expect(sidebarFooterRowHeight, 40);
  });

  test('the footer row and the composer card rest on the same baseline', () {
    expect(
      sidebarPanePadding + sidebarFooterBottomInset,
      composerCardBottomInset,
    );
  });
}
