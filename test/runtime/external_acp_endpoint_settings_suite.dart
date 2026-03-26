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

    test('empty legacy claude and gemini entries are dropped', () {
      final normalized = normalizeExternalAcpEndpoints(
        profiles: const <ExternalAcpEndpointProfile>[
          ExternalAcpEndpointProfile(
            providerKey: 'claude',
            label: 'Claude',
            badge: 'Cl',
            endpoint: '',
            enabled: true,
          ),
          ExternalAcpEndpointProfile(
            providerKey: 'gemini',
            label: 'Gemini',
            badge: 'G',
            endpoint: '',
            enabled: true,
          ),
        ],
      );

      expect(
        normalized.take(2).map((item) => item.providerKey).toList(),
        const <String>['codex', 'opencode'],
      );
      expect(
        normalized.where(
          (item) => item.providerKey.startsWith('custom-agent-'),
        ),
        isEmpty,
      );
      expect(normalized.any((item) => item.providerKey == 'claude'), isFalse);
      expect(normalized.any((item) => item.providerKey == 'gemini'), isFalse);
    });

    test(
      'configured legacy claude and gemini entries migrate into custom endpoints',
      () {
        final normalized = normalizeExternalAcpEndpoints(
          profiles: const <ExternalAcpEndpointProfile>[
            ExternalAcpEndpointProfile(
              providerKey: 'claude',
              label: 'Claude',
              badge: 'Cl',
              endpoint: 'wss://claude.example.com/acp',
              enabled: true,
            ),
            ExternalAcpEndpointProfile(
              providerKey: 'gemini',
              label: 'Gemini',
              badge: 'G',
              endpoint: 'wss://gemini.example.com/acp',
              enabled: true,
            ),
          ],
        );

        expect(
          normalized
              .where((item) => item.providerKey.startsWith('custom-agent-'))
              .map((item) => item.label)
              .toList(growable: false),
          const <String>['Claude', 'Gemini'],
        );
        expect(normalized.any((item) => item.providerKey == 'claude'), isFalse);
        expect(normalized.any((item) => item.providerKey == 'gemini'), isFalse);
      },
    );

    test('empty migrated claude and gemini placeholders are dropped', () {
      final normalized = normalizeExternalAcpEndpoints(
        profiles: const <ExternalAcpEndpointProfile>[
          ExternalAcpEndpointProfile(
            providerKey: 'custom-agent-3',
            label: 'Claude',
            badge: 'Cl',
            endpoint: '',
            enabled: true,
          ),
          ExternalAcpEndpointProfile(
            providerKey: 'custom-agent-4',
            label: 'Gemini',
            badge: 'G',
            endpoint: '',
            enabled: true,
          ),
        ],
      );

      expect(
        normalized.map((item) => item.providerKey).toList(growable: false),
        const <String>['codex', 'opencode'],
      );
    });

    test(
      'custom endpoint builder validates sequential keys and label fallback',
      () {
        final profile = buildCustomExternalAcpEndpointProfile(
          SettingsSnapshot.defaults().externalAcpEndpoints,
          label: '',
          endpoint: 'wss://lab.example.com/acp',
        );

        expect(profile.providerKey, 'custom-agent-3');
        expect(profile.label, 'Custom ACP Endpoint 3');
        expect(profile.endpoint, 'wss://lab.example.com/acp');
      },
    );

    test(
      'available single-agent providers follow normalized endpoint settings',
      () {
        final snapshot = SettingsSnapshot.defaults().copyWith(
          externalAcpEndpoints: normalizeExternalAcpEndpoints(
            profiles: <ExternalAcpEndpointProfile>[
              ...SettingsSnapshot.defaults().externalAcpEndpoints,
              buildCustomExternalAcpEndpointProfile(
                SettingsSnapshot.defaults().externalAcpEndpoints,
                label: 'Lab Agent',
                endpoint: 'wss://lab.example.com/acp',
              ),
              const ExternalAcpEndpointProfile(
                providerKey: 'claude',
                label: 'Claude',
                badge: 'Cl',
                endpoint: '',
                enabled: true,
              ),
            ],
          ),
        );

        expect(
          snapshot.availableSingleAgentProviders
              .map((item) => item.label)
              .toList(),
          const <String>['Codex', 'OpenCode', 'Lab Agent'],
        );
      },
    );
  });
}
