import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureConfigStore app ui state', () {
    test('persists ui/state.json separately from settings.yaml', () async {
      final root = await Directory.systemTemp.createTemp(
        'xworkmate-ui-state-test-',
      );
      final store = SecureConfigStore(
        enableSecureStorage: false,
        appDataRootPathResolver: () async => root.path,
        secretRootPathResolver: () async => root.path,
        supportRootPathResolver: () async => root.path,
      );
      addTearDown(() async {
        store.dispose();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      await store.initialize();
      await store.saveAppUiState(
        AppUiState.defaults().copyWith(
          assistantLastSessionKey: 'draft:1',
          assistantNavigationDestinations: const <AssistantFocusEntry>[
            AssistantFocusEntry.language,
          ],
          savedGatewayTargets: const <String>['remote'],
        ),
      );

      final loaded = await store.loadAppUiState();
      final uiStateFile = await store.supportFile('ui/state.json');
      final settingsFile = await store.resolvedSettingsFile();

      expect(loaded.assistantLastSessionKey, 'draft:1');
      expect(
        loaded.assistantNavigationDestinations,
        const <AssistantFocusEntry>[AssistantFocusEntry.language],
      );
      expect(loaded.savedGatewayTargets, const <String>['remote']);
      expect(await uiStateFile?.exists(), isTrue);
      expect(await settingsFile?.exists(), isFalse);
    });

    test(
      'clearAssistantLocalState companion clear removes ui/state.json',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'xworkmate-ui-state-clear-test-',
        );
        final store = SecureConfigStore(
          enableSecureStorage: false,
          appDataRootPathResolver: () async => root.path,
          secretRootPathResolver: () async => root.path,
          supportRootPathResolver: () async => root.path,
        );
        addTearDown(() async {
          store.dispose();
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });

        await store.initialize();
        await store.saveAppUiState(
          AppUiState.defaults().copyWith(assistantLastSessionKey: 'draft:2'),
        );

        await store.clearAppUiState();

        expect((await store.loadAppUiState()).assistantLastSessionKey, isEmpty);
        expect(
          await (await store.supportFile('ui/state.json'))?.exists(),
          isFalse,
        );
      },
    );
  });
}
