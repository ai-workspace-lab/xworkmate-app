import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsStore v1', () {
    test('resolves a single settings file and watch directory', () async {
      final root = await Directory.systemTemp.createTemp(
        'xworkmate-settings-store-v1-',
      );
      final store = SettingsStore(
        appDataRootPathResolver: () async => root.path,
        supportRootPathResolver: () async => root.path,
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      await store.initialize();

      final file = await store.resolvedSettingsFile();
      final watchDirectory = await store.resolvedSettingsWatchDirectory();

      expect(file?.path, '${root.path}/config/settings.yaml');
      expect(watchDirectory?.path, '${root.path}/config');
    });

    test('old schema resets to defaults and reports invalid reload', () async {
      final root = await Directory.systemTemp.createTemp(
        'xworkmate-settings-store-v1-invalid-',
      );
      final store = SettingsStore(
        appDataRootPathResolver: () async => root.path,
        supportRootPathResolver: () async => root.path,
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      await store.initialize();
      final file = await store.resolvedSettingsFile();
      expect(file, isNotNull);

      await file!.create(recursive: true);
      await file.writeAsString(
        'appLanguage: zh\nassistantExecutionTarget: singleAgent\n',
      );

      final reload = await store.reloadSettingsSnapshotResult();
      final loaded = await store.loadSettingsSnapshot();

      expect(reload.status, SettingsSnapshotReloadStatus.invalid);
      expect(reload.snapshot.toJsonString(), loaded.toJsonString());
      expect(loaded.schemaVersion, settingsSnapshotSchemaVersion);
    });
  });
}
