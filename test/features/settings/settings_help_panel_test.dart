import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/settings_help_panel.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  testWidgets('renders setup help sections and metadata tables', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SettingsHelpPanel()),
      ),
    );

    expect(find.text('帮助'), findsWidgets);
    expect(find.text('1. 快速安装（一键部署）'), findsOneWidget);
    expect(find.text('2. 带 API Key 安装'), findsOneWidget);
    expect(find.text('环境变量参考'), findsOneWidget);
    expect(find.text('支持平台'), findsOneWidget);
    expect(find.text('DEEPSEEK_API_KEY'), findsOneWidget);
    expect(find.text('macOS (Apple Silicon / Intel)'), findsOneWidget);
  });
}
