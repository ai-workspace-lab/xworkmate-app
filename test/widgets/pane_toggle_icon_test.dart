import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/pane_toggle_icon.dart';
import 'package:xworkmate/widgets/sidebar_navigation.dart';

void main() {
  setUp(() => setActiveAppLanguage(AppLanguage.zh));

  testWidgets('the icon takes its size and colour from the icon theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: IconTheme(
          data: IconThemeData(size: 18, color: Colors.red),
          child: Center(child: PaneToggleIcon(side: PaneSide.left)),
        ),
      ),
    );
    expect(tester.getSize(find.byType(PaneToggleIcon)), const Size(18, 18));
  });

  testWidgets('the sidebar collapse button uses the left pane glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Material(
          child: SizedBox(
            width: 360,
            height: 720,
            child: SidebarNavigation(
              currentSection: WorkspaceDestination.assistant,
              sidebarState: AppSidebarState.expanded,
              appLanguage: AppLanguage.zh,
              themeMode: ThemeMode.light,
              onSectionChanged: (_) {},
              onToggleLanguage: () {},
              onCycleSidebarState: () {},
              onExpandFromCollapsed: () {},
              onOpenAccount: () {},
              onOpenThemeToggle: () {},
              accountName: 'shenlan',
              accountSubtitle: '',
            ),
          ),
        ),
      ),
    );
    final glyph = tester.widget<PaneToggleIcon>(
      find.descendant(
        of: find.byKey(const Key('workspace-sidebar-collapse-button')),
        matching: find.byType(PaneToggleIcon),
      ),
    );
    expect(glyph.side, PaneSide.left);
    expect(find.byIcon(Icons.view_sidebar_outlined), findsNothing);
  });
}
