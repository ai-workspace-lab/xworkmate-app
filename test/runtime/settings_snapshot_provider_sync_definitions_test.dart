import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('SettingsSnapshot schema v1', () {
    test('defaults include provider sync presets', () {
      final providerKeys = SettingsSnapshot.defaults().providerSyncDefinitions
          .map((item) => item.providerKey)
          .toList(growable: false);

      expect(providerKeys, <String>['codex', 'opencode', 'gemini']);
    });

    test('round trips providerSyncDefinitions and schemaVersion', () {
      final snapshot = SettingsSnapshot.defaults().copyWith(
        providerSyncDefinitions: <ExternalAcpEndpointProfile>[
          ExternalAcpEndpointProfile.defaultsForProvider(
            SingleAgentProvider.codex,
          ).copyWith(endpoint: 'https://codex.example.com'),
          ExternalAcpEndpointProfile.defaultsForProvider(
            SingleAgentProvider.opencode,
          ),
          ExternalAcpEndpointProfile.defaultsForProvider(
            SingleAgentProvider.gemini,
          ),
        ],
      );

      final decoded = SettingsSnapshot.fromJson(snapshot.toJson());

      expect(decoded.schemaVersion, settingsSnapshotSchemaVersion);
      expect(
        decoded.providerSyncDefinitions.first.endpoint,
        'https://codex.example.com',
      );
    });

    test('missing schemaVersion is rejected', () {
      expect(
        () => SettingsSnapshot.fromJson(<String, dynamic>{
          'assistantExecutionTarget': 'singleAgent',
          'gatewayProfiles': <Map<String, dynamic>>[],
        }),
        throwsFormatException,
      );
    });

    test('removed ui restore fields are not serialized', () {
      final json = SettingsSnapshot.defaults().toJson();

      expect(json.containsKey('assistantLastSessionKey'), isFalse);
      expect(json.containsKey('assistantNavigationDestinations'), isFalse);
      expect(json.containsKey('assistantCustomTaskTitles'), isFalse);
      expect(json.containsKey('assistantArchivedTaskKeys'), isFalse);
      expect(json.containsKey('savedGatewayTargets'), isFalse);
      expect(json.containsKey('externalAcpEndpoints'), isFalse);
      expect(json.containsKey('providerSyncDefinitions'), isTrue);
    });
  });

  group('AcpBridgeServerModeConfig advanced overrides', () {
    test('advanced override ACP profiles are normalized to full presets', () {
      final config = AcpBridgeServerModeConfig.fromJson(<String, dynamic>{
        'advancedOverrides': <String, dynamic>{
          'acpBridgeServerProfiles': <Map<String, dynamic>>[
            <String, dynamic>{
              'providerKey': 'opencode',
              'label': 'OpenCode',
              'badge': 'O',
              'endpoint': '',
              'authRef': '',
              'enabled': true,
            },
          ],
        },
      });

      final providerKeys = config.advancedOverrides.acpBridgeServerProfiles
          .map((item) => item.providerKey)
          .toList(growable: false);

      expect(providerKeys, <String>['codex', 'opencode', 'gemini']);
    });
  });
}
