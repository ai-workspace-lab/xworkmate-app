// ignore_for_file: unused_import, unnecessary_import

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'secure_config_store_suite_core.dart';
import 'secure_config_store_suite_settings.dart';
import 'secure_config_store_suite_secrets.dart';
import 'secure_config_store_suite_compatibility.dart';
import 'secure_config_store_suite_lifecycle.dart';

Future<Directory> createTempDirectoryInternal(
  String prefix, {
  bool resetSharedPreferences = true,
}) async {
  if (resetSharedPreferences) {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  }
  final tempDirectory = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() async {
    if (await tempDirectory.exists()) {
      await deleteDirectoryWithRetryInternal(tempDirectory);
    }
  });
  return tempDirectory;
}

SecureConfigStore createStoreFromTempDirectoryInternal(
  Directory tempDirectory, {
  bool enableSecureStorage = false,
  Future<String> Function()? defaultSupportDirectoryPathResolver,
}) {
  return SecureConfigStore(
    enableSecureStorage: enableSecureStorage,
    databasePathResolver: () async =>
        '${tempDirectory.path}/${SettingsStore.databaseFileName}',
    fallbackDirectoryPathResolver: () async => tempDirectory.path,
    defaultSupportDirectoryPathResolver: defaultSupportDirectoryPathResolver,
  );
}

Future<void> deleteDirectoryWithRetryInternal(Directory directory) async {
  for (var attempt = 0; attempt < 5; attempt += 1) {
    if (!await directory.exists()) {
      return;
    }
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 4) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 80 * (attempt + 1)));
    }
  }
}
