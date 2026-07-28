import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_shell_desktop.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  testWidgets('desktop exposes workbench without removing assistant', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 960);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light().copyWith(platform: TargetPlatform.macOS),
        home: AppShell(controller: controller),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('workspace-sidebar-workbench-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assistant-conversation-shell')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('workspace-sidebar-workbench-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('工作台'), findsWidgets);
    expect(
      find.byKey(const Key('workbench-needs-attention-card')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('workbench-projects-card')), findsOneWidget);
    expect(
      find.byKey(const Key('workbench-quick-record-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('workbench-tab-myWork')));
    await tester.pumpAndSettle();
    expect(find.text('我的待办'), findsWidgets);

    await tester.tap(find.byKey(const Key('workbench-tab-inbox')));
    await tester.pumpAndSettle();
    expect(find.text('工作收件箱暂时为空'), findsOneWidget);

    await tester.tap(find.byKey(const Key('workbench-quick-record-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('workbench-quick-record-field')),
      '补充 GitHub Issues 连接器的验收场景',
    );
    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();
    expect(find.text('待整理记录'), findsOneWidget);
    expect(find.text('补充 GitHub Issues 连接器的验收场景'), findsOneWidget);

    await tester.tap(find.byKey(const Key('workbench-tab-overview')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建').last);
    await tester.pumpAndSettle();
    expect(find.text('待办列表'), findsOneWidget);
    expect(find.text('跟进统一鉴权服务上线进度'), findsOneWidget);
  });
}
