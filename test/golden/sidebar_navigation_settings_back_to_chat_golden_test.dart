import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/widgets/sidebar_navigation.dart';

import '../helpers/golden_test_bootstrap.dart';

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
  });

  testGoldens('settings sidebar shows back to chat action', (tester) async {
    await pumpGoldenApp(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 344,
          height: 920,
          child: SidebarNavigation(
            currentSection: WorkspaceDestination.settings,
            sidebarState: AppSidebarState.expanded,
            appLanguage: AppLanguage.zh,
            themeMode: ThemeMode.light,
            onSectionChanged: (_) {},
            onToggleLanguage: () {},
            onCycleSidebarState: () {},
            onExpandFromCollapsed: () {},
            onOpenHome: () {},
            onOpenAccount: () {},
            onOpenThemeToggle: () {},
            onReturnToAssistant: () {},
            accountName: 'Tester',
            accountSubtitle: 'Workspace',
            onToggleAccountWorkspaceFollowed: () async {},
          ),
        ),
      ),
      size: const Size(400, 960),
    );

    await screenMatchesGolden(
      tester,
      'sidebar_navigation_settings_back_to_chat',
    );
  });
}
