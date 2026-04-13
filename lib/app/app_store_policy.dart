import 'ui_feature_manifest.dart';

const bool kAppStoreDistribution = bool.fromEnvironment(
  'XWORKMATE_APP_STORE',
  defaultValue: false,
);

bool shouldApplyAppleAppStorePolicy({
  required bool isAppleHost,
  bool? enabled,
}) {
  return (enabled ?? kAppStoreDistribution) && isAppleHost;
}

UiFeatureManifest applyAppleAppStorePolicy(
  UiFeatureManifest manifest, {
  required UiFeaturePlatform hostPlatform,
  required bool isAppleHost,
  bool? enabled,
}) {
  if (!shouldApplyAppleAppStorePolicy(
    isAppleHost: isAppleHost,
    enabled: enabled,
  )) {
    return manifest;
  }

  var next = manifest;
  final disabledPaths = <(UiFeaturePlatform, String, String)>[
    (
      hostPlatform,
      'settings',
      _featureKeyLeaf(UiFeatureKeys.settingsExperimentalCanvas),
    ),
    (
      hostPlatform,
      'settings',
      _featureKeyLeaf(UiFeatureKeys.settingsExperimentalBridge),
    ),
    (
      hostPlatform,
      'settings',
      _featureKeyLeaf(UiFeatureKeys.settingsExperimentalDebug),
    ),
  ];

  if (hostPlatform == UiFeaturePlatform.mobile) {
    disabledPaths.addAll(<(UiFeaturePlatform, String, String)>[
      (
        hostPlatform,
        'assistant',
        _featureKeyLeaf(UiFeatureKeys.assistantLocalGateway),
      ),
      (
        hostPlatform,
        'assistant',
        _featureKeyLeaf(UiFeatureKeys.assistantMultiAgent),
      ),
    ]);
  }

  if (hostPlatform == UiFeaturePlatform.desktop) {
    disabledPaths.addAll(<(UiFeaturePlatform, String, String)>[
      (
        hostPlatform,
        'assistant',
        _featureKeyLeaf(UiFeatureKeys.assistantMultiAgent),
      ),
      (
        hostPlatform,
        'assistant',
        _featureKeyLeaf(UiFeatureKeys.assistantLocalRuntime),
      ),
    ]);
  }

  for (final (platform, module, feature) in disabledPaths) {
    if (next.lookup(platform, module, feature) == null) {
      continue;
    }
    next = next.copyWithFeature(
      platform: platform,
      module: module,
      feature: feature,
      enabled: false,
      buildModes: const <UiFeatureBuildMode>{},
    );
  }

  return next;
}

String _featureKeyLeaf(String keyPath) {
  final segments = keyPath.split('.');
  if (segments.isEmpty) {
    throw StateError('Invalid feature key path: $keyPath');
  }
  return segments.last;
}
