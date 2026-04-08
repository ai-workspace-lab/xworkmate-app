import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import '../i18n/app_language.dart';
import '../theme/app_theme.dart';
import 'app_controller.dart';
import 'app_metadata.dart';
import 'app_shell.dart';
import 'ui_feature_manifest.dart';

class XWorkmateApp extends StatefulWidget {
  const XWorkmateApp({super.key, this.featureManifest});

  final UiFeatureManifest? featureManifest;

  @override
  State<XWorkmateApp> createState() => _XWorkmateAppState();
}

class _XWorkmateAppState extends State<XWorkmateApp> {
  static const MethodChannel _appLifecycleChannel = MethodChannel(
    'plus.svc.xworkmate/app_lifecycle',
  );

  late final AppController _controller;
  late final AppThemeSurface _themeSurface;

  @override
  void initState() {
    super.initState();
    _themeSurface = resolveAppThemeSurface();
    _controller = AppController(
      uiFeatureManifest: widget.featureManifest ?? UiFeatureManifest.fallback(),
    );
    if (_supportsDesktopLifecycleChannel) {
      _appLifecycleChannel.setMethodCallHandler(_handleAppLifecycleCall);
    }
  }

  @override
  void dispose() {
    if (_supportsDesktopLifecycleChannel) {
      _appLifecycleChannel.setMethodCallHandler(null);
    }
    _controller.dispose();
    super.dispose();
  }

  bool get _supportsDesktopLifecycleChannel {
    if (kIsWeb) {
      return false;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  Future<Object?> _handleAppLifecycleCall(MethodCall call) async {
    switch (call.method) {
      case 'prepareForExit':
        await _controller.prepareForExit();
        return null;
      case 'desktopStatusSnapshot':
        return _controller.desktopStatusSnapshot();
      default:
        throw MissingPluginException(
          'Unhandled app lifecycle method: ${call.method}',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return MaterialApp(
          key: const Key('xworkmate-app-shell'),
          title: kSystemAppName,
          debugShowCheckedModeBanner: false,
          locale: Locale(_controller.appLanguage.code),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          themeMode: _controller.themeMode,
          theme: AppTheme.light(surface: _themeSurface),
          darkTheme: AppTheme.dark(surface: _themeSurface),
          home: AppShell(controller: _controller),
        );
      },
    );
  }
}
