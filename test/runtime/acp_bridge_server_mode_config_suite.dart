@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test('AcpBridgeServerModeConfig defaults to cloud synced mode', () {
    final config = AcpBridgeServerModeConfig.defaults();

    expect(config.mode, AcpBridgeServerMode.cloudSynced);
    expect(config.usesCloudSyncBase, isTrue);
    expect(config.usesSelfHostedBase, isFalse);
    expect(config.selfHosted.passwordRef, 'acp_bridge_server_password');
  });

  test('advanced custom mode can inherit self hosted base when configured', () {
    final config = AcpBridgeServerModeConfig.defaults().copyWith(
      mode: AcpBridgeServerMode.advancedCustom,
      selfHosted: AcpBridgeServerSelfHostedConfig.defaults().copyWith(
        serverUrl: 'https://bridge.example.com',
        username: 'review',
      ),
    );

    expect(config.usesSelfHostedBase, isTrue);
    expect(config.usesCloudSyncBase, isFalse);
    expect(config.sourceTag, 'advancedOverride');
  });

  test('SettingsSnapshot captures current advanced overrides into mode config', () {
    final snapshot = SettingsSnapshot.defaults().copyWith(
      gatewayProfiles: SettingsSnapshot.defaults().gatewayProfiles,
      vault: VaultConfig.defaults().copyWith(address: 'https://vault.example'),
      aiGateway: AiGatewayProfile.defaults().copyWith(
        baseUrl: 'https://llm.example.com/v1',
      ),
      externalAcpEndpoints: <ExternalAcpEndpointProfile>[
        ExternalAcpEndpointProfile.defaultsForProvider(
          SingleAgentProvider.codex,
        ).copyWith(endpoint: 'https://agent.example.com'),
      ],
      authorizedSkillDirectories: const <AuthorizedSkillDirectory>[
        AuthorizedSkillDirectory(path: '/tmp/skills'),
      ],
    );

    final captured = snapshot.captureAcpBridgeServerAdvancedOverrides();

    expect(
      captured.acpBridgeServerModeConfig.advancedOverrides.vault.address,
      'https://vault.example',
    );
    expect(
      captured.acpBridgeServerModeConfig.advancedOverrides.aiGateway.baseUrl,
      'https://llm.example.com/v1',
    );
    expect(
      captured
          .acpBridgeServerModeConfig
          .advancedOverrides
          .acpBridgeServerProfiles
          .firstWhere((item) => item.providerKey == 'codex')
          .endpoint,
      'https://agent.example.com',
    );
    expect(
      captured
          .acpBridgeServerModeConfig
          .advancedOverrides
          .authorizedSkillDirectories
          .single
          .path,
      '/tmp/skills',
    );
  });
}
