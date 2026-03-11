import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../i18n/app_language.dart';
import '../theme/app_theme.dart';
import 'app_controller.dart';
import 'app_metadata.dart';
import 'app_shell.dart';

class XWorkmateApp extends StatefulWidget {
  const XWorkmateApp({super.key});

  @override
  State<XWorkmateApp> createState() => _XWorkmateAppState();
}

class _XWorkmateAppState extends State<XWorkmateApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return MaterialApp(
          title: kSystemAppName,
          debugShowCheckedModeBanner: false,
          locale: Locale(_controller.appLanguage.code),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          themeMode: _controller.themeMode,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: AppShell(controller: _controller),
        );
      },
    );
  }
}
