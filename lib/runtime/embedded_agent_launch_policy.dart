import '../app/app_store_policy.dart';

bool shouldBlockEmbeddedAgentLaunch({
  required bool isAppleHost,
  bool? enabled,
}) {
  return shouldApplyAppleAppStorePolicy(
    isAppleHost: isAppleHost,
    enabled: enabled,
  );
}
