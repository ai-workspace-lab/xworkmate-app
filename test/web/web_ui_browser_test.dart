@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xworkmate/app/app.dart';

void main() {
  testWidgets('web shell exposes only assistant and settings surfaces', (
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
    expect(find.text('设置'), findsWidgets);
    expect(find.text('Tasks'), findsNothing);
    expect(find.byKey(const Key('assistant-task-rail')), findsOneWidget);
    expect(find.byKey(const Key('assistant-attachment-menu-button')), findsOneWidget);

    await tester.tap(find.text('连接设置'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsWidgets);
    expect(find.textContaining('浏览器本地存储'), findsOneWidget);
    expect(find.textContaining('Local Gateway'), findsWidgets);
    expect(find.textContaining('Remote Gateway'), findsWidgets);
  });
}
