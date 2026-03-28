part of 'secure_config_store_suite.dart';

Future<Directory> _createTempDirectory(
  String prefix, {
  bool resetSharedPreferences = true,
}) async {
  if (resetSharedPreferences) {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  }
  final tempDirectory = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() async {
    if (await tempDirectory.exists()) {
      await _deleteDirectoryWithRetry(tempDirectory);
    }
  });
  return tempDirectory;
}

SecureConfigStore _createStoreFromTempDirectory(
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

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
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
