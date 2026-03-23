import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_store_policy.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test('apple app store policy disables restricted desktop surfaces', () {
    final manifest = applyAppleAppStorePolicy(
      UiFeatureManifest.fallback(),
      hostPlatform: UiFeaturePlatform.desktop,
      isAppleHost: true,
      enabled: true,
    );
    final access = manifest.forPlatform(
      UiFeaturePlatform.desktop,
      buildMode: UiFeatureBuildMode.release,
    );

    expect(access.supportsDesktopRuntime, isFalse);
    expect(access.supportsMultiAgent, isFalse);
    expect(
      access.allowedDestinations.contains(WorkspaceDestination.agents),
      isFalse,
    );
    expect(
      access.allowedDestinations.contains(WorkspaceDestination.clawHub),
      isFalse,
    );
    expect(access.availableSettingsTabs.contains(SettingsTab.agents), isFalse);
  });

  test('apple app store policy disables local mobile assistant features', () {
    final manifest = applyAppleAppStorePolicy(
      UiFeatureManifest.fallback(),
      hostPlatform: UiFeaturePlatform.mobile,
      isAppleHost: true,
      enabled: true,
    );
    final access = manifest.forPlatform(
      UiFeaturePlatform.mobile,
      buildMode: UiFeatureBuildMode.release,
    );

    expect(access.supportsLocalGateway, isFalse);
    expect(access.supportsMultiAgent, isFalse);
    expect(
      access.availableExecutionTargets,
      equals(<AssistantExecutionTarget>[AssistantExecutionTarget.remote]),
    );
  });

  test('single-agent provider selection is forced to auto for app store', () {
    expect(
      sanitizeAppStoreSingleAgentProvider(
        SingleAgentProvider.codex,
        isAppleHost: true,
        enabled: true,
      ),
      SingleAgentProvider.auto,
    );
    expect(
      sanitizeAppStoreSingleAgentProvider(
        SingleAgentProvider.gemini,
        isAppleHost: false,
        enabled: true,
      ),
      SingleAgentProvider.gemini,
    );
  });
}
