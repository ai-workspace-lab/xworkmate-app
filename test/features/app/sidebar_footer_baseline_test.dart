import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/assistant_page_main.dart';
import 'package:xworkmate/widgets/sidebar_navigation.dart';

/// The sidebar footer and the composer card are the shell's two bottom blocks,
/// sitting side by side across the window. They must share a baseline and a
/// height or the mismatch reads as a misalignment — which is exactly what was
/// reported: the footer block was 139pt tall and 4pt off the pane bottom while
/// the composer card was 152pt tall and 16pt off it, leaving a 25pt step
/// between the divider and the card's top edge.
///
/// These are pure arithmetic checks on purpose. The two blocks live in
/// unrelated widgets, so nothing else would notice if one of them moved.
void main() {
  // The composer's minimum, as the layout derives it:
  //   pane   = max(minLowerPane, baseCompact) + safeAreaGap
  //   card   = pane - safeAreaGap - padding.top - padding.bottom
  const composerMinPaneHeight =
      assistantComposerBaseHeightCompactInternal +
      assistantComposerSafeAreaGapInternal;
  const composerCardPaddingVertical = 8 + 8;
  const composerCardHeight =
      composerMinPaneHeight -
      assistantComposerSafeAreaGapInternal -
      composerCardPaddingVertical;

  /// How far the composer card floats above the pane bottom.
  const composerCardBottomInset =
      assistantComposerSafeAreaGapInternal + 8;

  /// The sidebar pane's own vertical padding, which covers part of that inset.
  const sidebarPanePadding = 4.0;

  test('the composer base height is the taller of the two lower bounds', () {
    expect(
      assistantComposerBaseHeightCompactInternal,
      greaterThanOrEqualTo(assistantWorkspaceMinLowerPaneHeightInternal),
      reason:
          'if the min-lower-pane floor ever wins, composerMinPaneHeight here '
          'stops matching the layout and this whole file is measuring nothing',
    );
  });

  test('the footer block is exactly as tall as the composer card', () {
    expect(sidebarFooterBlockHeight, composerCardHeight);
  });

  test('both bottom blocks rest on the same baseline', () {
    expect(
      sidebarPanePadding + sidebarFooterBottomInset,
      composerCardBottomInset,
    );
  });

  test('the footer block is built from its parts, not a hardcoded total', () {
    expect(
      sidebarFooterBlockHeight,
      1 + sidebarFooterDividerGap + sidebarFooterRowHeight * 3 + 6 * 2,
    );
  });
}
