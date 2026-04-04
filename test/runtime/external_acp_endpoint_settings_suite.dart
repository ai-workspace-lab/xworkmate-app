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
            .take(1)
            .map((item) => item.providerKey)
            .toList(growable: false),
        const <String>['opencode'],
      );
    });

    test(
      'round-trip preserves migrated legacy entries and custom extensions',
      () {
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
                authRef: '',
                enabled: true,
              ),
            ],
          ),
        );

        final decoded = SettingsSnapshot.fromJson(snapshot.toJson());

        expect(
          decoded.externalAcpEndpoints.any(
            (item) =>
                item.label == 'Codex' &&
                item.endpoint == 'ws://127.0.0.1:9001' &&
                item.providerKey.startsWith('custom-agent-'),
          ),
          isTrue,
        );
        expect(
          decoded
              .externalAcpEndpointForProvider(SingleAgentProvider.opencode)
              .endpoint,
          'https://opencode.example.com',
        );
        expect(
          decoded.externalAcpEndpointForProviderId('codex')?.providerKey,
          startsWith('custom-agent-'),
        );
        expect(
          decoded.externalAcpEndpoints.any(
            (item) =>
                item.providerKey == 'custom-lab' &&
                item.endpoint == 'wss://lab.example.com/acp',
          ),
          isTrue,
        );
      },
    );

    test('empty legacy claude and gemini entries are dropped', () {
      final normalized = normalizeExternalAcpEndpoints(
        profiles: const <ExternalAcpEndpointProfile>[
          ExternalAcpEndpointProfile(
            providerKey: 'claude',
            label: 'Claude',
            badge: 'Cl',
            endpoint: '',
            authRef: '',
            enabled: true,
          ),
          ExternalAcpEndpointProfile(
            providerKey: 'gemini',
            label: 'Gemini',
            badge: 'G',
            endpoint: '',
            authRef: '',
            enabled: true,
          ),
        ],
      );

      expect(
        normalized.take(1).map((item) => item.providerKey).toList(),
        const <String>['opencode'],
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
              authRef: '',
              enabled: true,
            ),
            ExternalAcpEndpointProfile(
              providerKey: 'gemini',
              label: 'Gemini',
              badge: 'G',
              endpoint: 'wss://gemini.example.com/acp',
              authRef: '',
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
            authRef: '',
            enabled: true,
          ),
          ExternalAcpEndpointProfile(
            providerKey: 'custom-agent-4',
            label: 'Gemini',
            badge: 'G',
            endpoint: '',
            authRef: '',
            enabled: true,
          ),
        ],
      );

      expect(
        normalized.map((item) => item.providerKey).toList(growable: false),
        const <String>['opencode'],
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

        expect(profile.providerKey, 'custom-agent-2');
        expect(profile.label, 'Custom ACP Endpoint 2');
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
                authRef: '',
                enabled: true,
              ),
            ],
          ),
        );

        expect(
          snapshot.availableSingleAgentProviders
              .map((item) => item.label)
              .toList(),
          const <String>['OpenCode', 'Lab Agent'],
        );
      },
    );
  });
}
