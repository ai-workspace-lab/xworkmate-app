import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_capabilities.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

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
        WorkspaceDestination.tasks,
        WorkspaceDestination.skills,
        WorkspaceDestination.nodes,
        WorkspaceDestination.secrets,
        WorkspaceDestination.aiGateway,
        WorkspaceDestination.settings,
      }),
    );
    expect(capabilities.supportsFileAttachments, isTrue);
    expect(capabilities.supportsLocalGateway, isTrue);
    expect(capabilities.supportsRelayGateway, isTrue);
    expect(capabilities.supportsDesktopRuntime, isFalse);
    expect(capabilities.supportsDiagnostics, isFalse);
  });

  test(
    'execution target arrays respect task dialog auto gating on desktop',
    () {
      final manifest = UiFeatureManifest.fallback();
      final desktopAccess = manifest.forPlatform(
        UiFeaturePlatform.desktop,
        buildMode: UiFeatureBuildMode.release,
      );
      final mobileAccess = manifest.forPlatform(
        UiFeaturePlatform.mobile,
        buildMode: UiFeatureBuildMode.release,
      );
      final webAccess = manifest.forPlatform(
        UiFeaturePlatform.web,
        buildMode: UiFeatureBuildMode.release,
      );

      expect(
        desktopAccess.availableExecutionTargets,
        equals(<AssistantExecutionTarget>[
          AssistantExecutionTarget.singleAgent,
          AssistantExecutionTarget.local,
          AssistantExecutionTarget.remote,
        ]),
      );
      expect(
        mobileAccess.availableExecutionTargets,
        equals(<AssistantExecutionTarget>[AssistantExecutionTarget.remote]),
      );
      expect(
        webAccess.availableExecutionTargets,
        equals(<AssistantExecutionTarget>[
          AssistantExecutionTarget.auto,
          AssistantExecutionTarget.singleAgent,
          AssistantExecutionTarget.local,
          AssistantExecutionTarget.remote,
        ]),
      );
    },
  );

  test(
    'sanitizeExecutionTarget falls back to local on desktop when auto is gated off',
    () {
      final manifest = UiFeatureManifest.fallback();
      final desktopAccess = manifest.forPlatform(
        UiFeaturePlatform.desktop,
        buildMode: UiFeatureBuildMode.release,
      );
      final webAccess = manifest.forPlatform(
        UiFeaturePlatform.web,
        buildMode: UiFeatureBuildMode.release,
      );

      expect(
        desktopAccess.sanitizeExecutionTarget(null),
        AssistantExecutionTarget.local,
      );
      expect(
        webAccess.sanitizeExecutionTarget(null),
        AssistantExecutionTarget.auto,
      );
    },
  );

  test('desktop auto execution target can be re-enabled from the manifest', () {
    final manifest = UiFeatureManifest.fallback().copyWithFeature(
      platform: UiFeaturePlatform.desktop,
      module: 'assistant',
      feature: 'task_dialog_mode_auto',
      enabled: true,
      releaseTier: UiFeatureReleaseTier.stable,
    );
    final desktopAccess = manifest.forPlatform(
      UiFeaturePlatform.desktop,
      buildMode: UiFeatureBuildMode.release,
    );

    expect(
      desktopAccess.availableExecutionTargets,
      equals(<AssistantExecutionTarget>[
        AssistantExecutionTarget.auto,
        AssistantExecutionTarget.singleAgent,
        AssistantExecutionTarget.local,
        AssistantExecutionTarget.remote,
      ]),
    );
    expect(
      desktopAccess.sanitizeExecutionTarget(null),
      AssistantExecutionTarget.auto,
    );
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

  test('copyWithFeature keeps build mode sets isolated', () {
    final manifest = UiFeatureManifest.fallback();
    final originalFlag = manifest.lookup(
      UiFeaturePlatform.desktop,
      'assistant',
      'direct_ai',
    )!;

    final copied = manifest.copyWithFeature(
      platform: UiFeaturePlatform.desktop,
      module: 'assistant',
      feature: 'direct_ai',
      enabled: false,
    );
    final copiedFlag = copied.lookup(
      UiFeaturePlatform.desktop,
      'assistant',
      'direct_ai',
    )!;

    expect(identical(copiedFlag.buildModes, originalFlag.buildModes), isFalse);
    expect(copiedFlag.buildModes, equals(originalFlag.buildModes));
  });
}
