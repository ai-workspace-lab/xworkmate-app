import '../app/app_store_policy.dart';
import 'go_core.dart';

bool shouldBlockEmbeddedAgentLaunch({
  required bool isAppleHost,
  bool? enabled,
}) {
  return shouldApplyAppleAppStorePolicy(
    isAppleHost: isAppleHost,
    enabled: enabled,
  );
}

bool shouldBlockGoCoreLaunch(
  GoCoreLaunch launch, {
  required bool isAppleHost,
  bool? enabled,
}) {
  return shouldApplyAppleAppStorePolicy(
    isAppleHost: isAppleHost,
    enabled: enabled,
  );
}
