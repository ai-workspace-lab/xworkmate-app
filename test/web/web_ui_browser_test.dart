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
    expect(find.byKey(const Key('assistant-task-rail')), findsOneWidget);
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
    expect(find.byType(SidebarNavigation), findsNothing);

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

    await tester.tap(find.byKey(const Key('assistant-side-pane-tab-quick')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('assistant-focus-panel-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('assistant-focus-add-settings')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('assistant-focus-add-tasks')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('assistant-focus-add-skills')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('assistant-focus-add-nodes')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('assistant-focus-add-secrets')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('assistant-focus-add-aiGateway')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('assistant-focus-add-settings')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('assistant-focus-open-page-settings')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assistant-focus-settings-language-toggle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assistant-focus-settings-theme-toggle')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('assistant-focus-open-page-settings')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SidebarNavigation), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-favorite-tasks')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('自动化'));
    await tester.pumpAndSettle();

    expect(find.text('任务工作台'), findsOneWidget);

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsWidgets);
    expect(
      find.byKey(const ValueKey('web-settings-search-field')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-settings-tab-gateway')),
    );
    await tester.pumpAndSettle();

    expect(find.text('OpenClaw Gateway'), findsWidgets);
    expect(find.text('LLM 接入点'), findsWidgets);
    expect(find.textContaining('浏览器本地存储'), findsOneWidget);
    expect(find.textContaining('Local Gateway'), findsWidgets);
    expect(find.textContaining('Remote Gateway'), findsWidgets);

    await tester.ensureVisible(
      find.byKey(const ValueKey('web-external-acp-provider-add-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Claude'), findsNothing);
    expect(find.text('Gemini'), findsNothing);
    expect(
      find.byKey(const ValueKey('web-external-acp-provider-add-button')),
      findsOneWidget,
    );
    expect(find.text('添加更多自定义配置'), findsOneWidget);
    expect(find.text('标志'), findsNothing);
    expect(find.text('Badge'), findsNothing);
  });
}
