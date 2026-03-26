@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('External ACP endpoint settings', () {
    test('defaults expose the preset providers', () {
      final snapshot = SettingsSnapshot.defaults();

      expect(
        snapshot.externalAcpEndpoints
            .take(2)
            .map((item) => item.providerKey)
            .toList(growable: false),
        const <String>['codex', 'opencode'],
      );
    });

    test('round-trip preserves built-in entries and custom extensions', () {
      final snapshot = SettingsSnapshot.defaults().copyWith(
        externalAcpEndpoints: normalizeExternalAcpEndpoints(
          profiles: <ExternalAcpEndpointProfile>[
            ExternalAcpEndpointProfile.defaultsForProvider(
              SingleAgentProvider.codex,
            ).copyWith(endpoint: 'ws://127.0.0.1:9001'),
            ExternalAcpEndpointProfile.defaultsForProvider(
              SingleAgentProvider.opencode,
            ).copyWith(endpoint: 'https://opencode.example.com'),
            const ExternalAcpEndpointProfile(
              providerKey: 'custom-lab',
              label: 'Custom Lab',
              badge: 'CL',
              endpoint: 'wss://lab.example.com/acp',
              enabled: true,
            ),
          ],
        ),
      );

      final decoded = SettingsSnapshot.fromJson(snapshot.toJson());

      expect(
        decoded
            .externalAcpEndpointForProvider(SingleAgentProvider.codex)
            .endpoint,
        'ws://127.0.0.1:9001',
      );
      expect(
        decoded
            .externalAcpEndpointForProvider(SingleAgentProvider.opencode)
            .endpoint,
        'https://opencode.example.com',
      );
      expect(
        decoded.externalAcpEndpoints.any(
          (item) =>
              item.providerKey == 'custom-lab' &&
              item.endpoint == 'wss://lab.example.com/acp',
        ),
        isTrue,
      );
    });
  });
}
