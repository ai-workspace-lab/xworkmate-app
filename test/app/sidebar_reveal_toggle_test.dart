// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/sidebar_reveal_toggle.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/pane_toggle_icon.dart';

void main() {
  testWidgets(
    'takes no space while the sidebar shows and brings a hidden one back',
    (tester) async {
      final controller = AppController(environmentOverride: const {});
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Material(
            child: Row(
              children: [
                SidebarRevealToggle(controller: controller),
                const Expanded(child: Text('toolbar')),
              ],
            ),
          ),
        ),
      );

      controller.setSidebarState(AppSidebarState.expanded);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sidebar-reveal-button')), findsNothing);

      controller.setSidebarState(AppSidebarState.hidden);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sidebar-reveal-button')), findsOneWidget);
      final glyph = tester.widget<PaneToggleIcon>(
        find.descendant(
          of: find.byKey(const Key('sidebar-reveal-button')),
          matching: find.byType(PaneToggleIcon),
        ),
      );
      expect(glyph.side, PaneSide.left);

      await tester.tap(find.byKey(const Key('sidebar-reveal-button')));
      await tester.pumpAndSettle();
      expect(controller.sidebarState, AppSidebarState.expanded);
      expect(find.byKey(const Key('sidebar-reveal-button')), findsNothing);
    },
  );
}
