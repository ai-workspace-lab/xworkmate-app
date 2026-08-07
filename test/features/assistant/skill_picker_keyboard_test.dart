import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_skill_picker.dart';
import 'package:xworkmate/theme/app_theme.dart';

/// The picker used to be mouse-only: an OverlayPortal with a search field and
/// a list, and no way to choose a row from the keyboard. Typing to filter then
/// reaching for the mouse is the whole cost this removes.
void main() {
  testWidgets('Enter toggles the highlighted skill, which starts at the top', (
    tester,
  ) async {
    final toggled = <String>[];
    await _pump(tester, onToggleSkill: toggled.add);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(toggled, <String>['alpha']);
  });

  testWidgets('ArrowDown moves the highlight before Enter commits', (
    tester,
  ) async {
    final toggled = <String>[];
    await _pump(tester, onToggleSkill: toggled.add);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(toggled, <String>['beta']);
  });

  testWidgets('ArrowUp from the top wraps to the last row', (tester) async {
    final toggled = <String>[];
    await _pump(tester, onToggleSkill: toggled.add);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(toggled, <String>['gamma'], reason: 'the list wraps');
  });

  testWidgets('Escape dismisses the picker', (tester) async {
    var dismissed = 0;
    await _pump(tester, onDismiss: () => dismissed++);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(dismissed, 1);
  });

  testWidgets('the highlighted row is visually distinct from a selected one', (
    tester,
  ) async {
    await _pump(tester, selectedSkillKeys: const <String>['gamma']);

    final tiles = tester
        .widgetList<SkillPickerTileInternal>(
          find.byType(SkillPickerTileInternal),
        )
        .toList();

    final highlighted = tiles.where((t) => t.highlighted).toList();
    final selected = tiles.where((t) => t.selected).toList();

    expect(highlighted.length, 1);
    expect(highlighted.single.option.key, 'alpha');
    expect(selected.single.option.key, 'gamma');
    expect(
      highlighted.single.selected,
      isFalse,
      reason: 'highlight is where Enter lands, selection is what gets sent',
    );
  });

  testWidgets('an empty result set swallows Enter instead of throwing', (
    tester,
  ) async {
    final toggled = <String>[];
    await _pump(
      tester,
      skills: const <ComposerSkillOptionInternal>[],
      onToggleSkill: toggled.add,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(toggled, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  List<ComposerSkillOptionInternal> skills =
      const <ComposerSkillOptionInternal>[
        ComposerSkillOptionInternal(
          key: 'alpha',
          label: 'Alpha',
          description: 'first',
          sourceLabel: 'builtin',
          groupLabel: 'Built-in',
          groupSortOrder: 0,
          icon: Icons.key_rounded,
        ),
        ComposerSkillOptionInternal(
          key: 'beta',
          label: 'Beta',
          description: 'second',
          sourceLabel: 'builtin',
          groupLabel: 'Built-in',
          groupSortOrder: 0,
          icon: Icons.key_rounded,
        ),
        ComposerSkillOptionInternal(
          key: 'gamma',
          label: 'Gamma',
          description: 'third',
          sourceLabel: 'builtin',
          groupLabel: 'Built-in',
          groupSortOrder: 0,
          icon: Icons.key_rounded,
        ),
      ],
  List<String> selectedSkillKeys = const <String>[],
  ValueChanged<String>? onToggleSkill,
  VoidCallback? onDismiss,
}) async {
  final searchController = TextEditingController();
  final searchFocusNode = FocusNode();
  addTearDown(searchController.dispose);
  addTearDown(searchFocusNode.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: SkillPickerPopoverInternal(
          maxHeight: 360,
          searchController: searchController,
          searchFocusNode: searchFocusNode,
          selectedSkillKeys: selectedSkillKeys,
          filteredSkills: skills,
          isLoading: false,
          errorText: null,
          hasQuery: false,
          onQueryChanged: (_) {},
          onToggleSkill: onToggleSkill ?? (_) {},
          onDismiss: onDismiss,
        ),
      ),
    ),
  );
  await tester.pump();
}
