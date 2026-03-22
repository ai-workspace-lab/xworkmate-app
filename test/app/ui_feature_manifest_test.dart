import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_capabilities.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/models/app_models.dart';

void main() {
  test('fallback manifest applies release policy to feature availability', () {
    final manifest = UiFeatureManifest.fallback();
    final debugDesktop = manifest.forPlatform(
      UiFeaturePlatform.desktop,
      buildMode: UiFeatureBuildMode.debug,
    );
    final releaseDesktop = manifest.forPlatform(
      UiFeaturePlatform.desktop,
      buildMode: UiFeatureBuildMode.release,
    );

    expect(
      debugDesktop.isEnabledPath(UiFeatureKeys.settingsExperimental),
      isTrue,
    );
    expect(
      releaseDesktop.isEnabledPath(UiFeatureKeys.settingsExperimental),
      isFalse,
    );
    expect(
      releaseDesktop.allowedDestinations.contains(WorkspaceDestination.tasks),
      isTrue,
    );
  });

  test('capabilities are derived from feature access', () {
    final manifest = UiFeatureManifest.fallback();
    final webAccess = manifest.forPlatform(
      UiFeaturePlatform.web,
      buildMode: UiFeatureBuildMode.release,
    );
    final capabilities = AppCapabilities.fromFeatureAccess(webAccess);

    expect(
      capabilities.allowedDestinations,
      equals(<WorkspaceDestination>{
        WorkspaceDestination.assistant,
        WorkspaceDestination.settings,
      }),
    );
    expect(capabilities.supportsFileAttachments, isFalse);
    expect(capabilities.supportsLocalGateway, isFalse);
    expect(capabilities.supportsRelayGateway, isTrue);
    expect(capabilities.supportsDesktopRuntime, isFalse);
    expect(capabilities.supportsDiagnostics, isFalse);
  });

  test('parser rejects unsupported flag fields', () {
    expect(
      () => UiFeatureManifest.fromYamlString('''
release_policy:
  debug: [stable]
  profile: [stable]
  release: [stable]
desktop:
  navigation:
    assistant:
      enabled: true
      release_tier: stable
      build_modes: [debug]
      description: Assistant
      ui_surface: sidebar
      unsupported: bad
mobile: {}
web: {}
'''),
      throwsFormatException,
    );
  });

  test('parser rejects missing required fields', () {
    expect(
      () => UiFeatureManifest.fromYamlString('''
release_policy:
  debug: [stable]
  profile: [stable]
  release: [stable]
desktop:
  navigation:
    assistant:
      enabled: true
      build_modes: [debug]
      description: Assistant
      ui_surface: sidebar
mobile: {}
web: {}
'''),
      throwsFormatException,
    );
  });
}
