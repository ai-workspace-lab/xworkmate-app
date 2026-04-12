import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('SettingsSnapshot schema v1', () {
    test('missing schemaVersion is rejected', () {
      expect(
        () => SettingsSnapshot.fromJson(<String, dynamic>{
          'assistantExecutionTarget': 'singleAgent',
          'gatewayProfiles': <Map<String, dynamic>>[],
        }),
        throwsFormatException,
      );
    });

    test('legacy provider sync and CLI fields are ignored on read', () {
      final decoded = SettingsSnapshot.fromJson(<String, dynamic>{
        'schemaVersion': settingsSnapshotSchemaVersion,
        'appLanguage': 'zh',
        'gatewayProfiles': <Map<String, dynamic>>[],
        'providerSyncDefinitions': <Map<String, dynamic>>[
          <String, dynamic>{
            'providerKey': 'codex',
            'label': 'Codex',
            'badge': 'C',
            'endpoint': 'https://codex.example.com',
            'authRef': 'secret://codex',
            'enabled': true,
          },
        ],
        'codexCliPath': '/tmp/codex',
      });

      expect(decoded.schemaVersion, settingsSnapshotSchemaVersion);
      expect(
        decoded.sanitizeSingleAgentProviderSelection(SingleAgentProvider.codex),
        SingleAgentProvider.codex,
      );
      expect(decoded.toJson().containsKey('providerSyncDefinitions'), isFalse);
      expect(decoded.toJson().containsKey('codexCliPath'), isFalse);
    });

    test('removed ui restore and local provider fields are not serialized', () {
      final json = SettingsSnapshot.defaults().toJson();

      expect(json.containsKey('assistantLastSessionKey'), isFalse);
      expect(json.containsKey('assistantNavigationDestinations'), isFalse);
      expect(json.containsKey('assistantCustomTaskTitles'), isFalse);
      expect(json.containsKey('assistantArchivedTaskKeys'), isFalse);
      expect(json.containsKey('savedGatewayTargets'), isFalse);
      expect(json.containsKey('externalAcpEndpoints'), isFalse);
      expect(json.containsKey('providerSyncDefinitions'), isFalse);
      expect(json.containsKey('codexCliPath'), isFalse);
    });
  });

  group('AcpBridgeServerModeConfig advanced overrides', () {
    test('legacy ACP bridge server profiles are ignored and not reserialized', () {
      final config = AcpBridgeServerModeConfig.fromJson(<String, dynamic>{
        'advancedOverrides': <String, dynamic>{
          'acpBridgeServerProfiles': <Map<String, dynamic>>[
            <String, dynamic>{
              'providerKey': 'opencode',
              'label': 'OpenCode',
              'badge': 'O',
              'endpoint': 'https://opencode.example.com',
              'authRef': 'secret://opencode',
              'enabled': true,
            },
          ],
        },
      });

      final json = config.toJson();
      final advancedOverrides = (json['advancedOverrides'] as Map?)?.cast<String, dynamic>();

      expect(advancedOverrides, isNotNull);
      expect(advancedOverrides!.containsKey('acpBridgeServerProfiles'), isFalse);
    });
  });
}
