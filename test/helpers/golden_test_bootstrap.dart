import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:xworkmate/theme/app_theme.dart';

Future<void> loadGoldenFonts() async {
  await loadAppFonts();
}

Widget buildGoldenApp(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: Scaffold(body: child),
  );
}

Future<void> pumpGoldenApp(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1440, 960),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(buildGoldenApp(child));
  await tester.pumpAndSettle();
}
