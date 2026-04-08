import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xworkmate/app/app.dart';

void main() {
  testWidgets('renders XWorkmate shell', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const XWorkmateApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assistant-conversation-shell')), findsOneWidget);
    expect(find.byKey(const Key('workspace-sidebar-new-task-button')), findsOneWidget);
    expect(find.byKey(const Key('assistant-send-button')), findsOneWidget);
    expect(find.textContaining('输入需求、补充上下文'), findsOneWidget);

    if (kIsWeb) {
      expect(find.text('设置'), findsWidgets);
      expect(find.text('Tasks'), findsNothing);
      expect(find.text('LLM API'), findsNothing);
    } else {
      expect(find.text('幻灯片'), findsNothing);
    }
  });
}
