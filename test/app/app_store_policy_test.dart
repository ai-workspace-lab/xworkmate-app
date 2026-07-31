import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_store_policy.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';

void main() {
  test(
    'keeps the GitHub API repository connector in an Apple App Store build',
    () {
      final manifest = UiFeatureManifest.fromYamlString(
        File(UiFeatureManifest.assetPath).readAsStringSync(),
      );

      final restricted = applyAppleAppStorePolicy(
        manifest,
        hostPlatform: UiFeaturePlatform.desktop,
        isAppleHost: true,
        enabled: true,
      );

      expect(
        restricted
            .forPlatform(
              UiFeaturePlatform.desktop,
              buildMode: UiFeatureBuildMode.release,
            )
            .supportsGitHubRepository,
        isTrue,
      );
    },
  );
}
