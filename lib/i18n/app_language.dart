import 'package:flutter/material.dart';

enum AppLanguage { zh, en }

extension AppLanguageCopy on AppLanguage {
  String get code => switch (this) {
    AppLanguage.zh => 'zh',
    AppLanguage.en => 'en',
  };

  String get buttonLabel => switch (this) {
    AppLanguage.zh => '中 / EN',
    AppLanguage.en => 'EN / 中',
  };

  static AppLanguage fromJsonValue(String? value) {
    return AppLanguage.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AppLanguage.zh,
    );
  }
}

AppLanguage _activeAppLanguage = AppLanguage.zh;

AppLanguage get activeAppLanguage => _activeAppLanguage;

Locale get activeAppLocale => Locale(_activeAppLanguage.code);

void setActiveAppLanguage(AppLanguage language) {
  _activeAppLanguage = language;
}

String appText(String zh, String en) {
  return _activeAppLanguage == AppLanguage.zh ? zh : en;
}
