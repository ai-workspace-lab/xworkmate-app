@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xworkmate/app/app.dart';
import 'package:xworkmate/widgets/sidebar_navigation.dart';

void main() {
  testWidgets('web shell aligns with app workspace layout and expanded pages', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const XWorkmateApp());
    await tester.pumpAndSettle();

    expect(find.text('助手'), findsWidgets);
    expect(find.byKey(const Key('assistant-task-rail')), findsNothing);
    expect(
      find.byKey(const Key('workspace-sidebar-task-search')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('workspace-sidebar-new-task-button')),
      findsOneWidget,
    );
    expect(find.text('自动化'), findsNothing);
    expect(find.text('MCP Hub'), findsNothing);
    expect(find.text('ClawHub'), findsNothing);
    expect(
      find.byKey(const Key('assistant-workspace-chrome-toggle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assistant-session-settings-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assistant-workspace-status-chip')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('assistant-top-target-button')), findsNothing);
    expect(find.byKey(const Key('assistant-target-button')), findsNothing);
    expect(
      find.byKey(const Key('assistant-attachment-menu-button')),
      findsOneWidget,
    );
    expect(find.text('连接设置'), findsNothing);
    expect(find.byType(SidebarNavigation), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('assistant-workspace-chrome-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('连接设置'), findsNothing);

    await tester.tap(
      find.byKey(const Key('assistant-workspace-chrome-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('连接设置'), findsNothing);

    await tester.tap(
      find.byKey(const Key('assistant-session-settings-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('assistant-session-settings-sheet-title')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('assistant-target-button')), findsOneWidget);
    expect(
      find.byKey(const Key('assistant-message-view-mode-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('assistant-thinking-button')), findsOneWidget);
    expect(
      find.byKey(const Key('assistant-permission-button')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(24, 24));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assistant-side-pane-tab-quick')), findsNothing);
    expect(find.byKey(const Key('assistant-focus-panel-title')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-footer-settings')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SidebarNavigation), findsOneWidget);
    expect(find.text('设置'), findsWidgets);
    expect(
      find.byKey(const ValueKey('web-settings-search-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('sidebar-settings-tab-gateway')),
      findsNothing,
    );
  });
}
