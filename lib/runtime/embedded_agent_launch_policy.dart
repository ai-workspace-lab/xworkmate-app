import '../app/app_store_policy.dart';

/// Decides whether to block embedded agent process launching based on platform policy.
///
/// In the cloud-neutral bridge model, local process launching is generally disabled.
bool shouldBlockEmbeddedAgentLaunch({
  required bool isAppleHost,
  bool? enabled,
}) {
  // Always apply policy which blocks local execution in restricted environments.
  // In the current architecture, we've moved to bridge-mediated execution.
  return shouldApplyAppleAppStorePolicy(
    isAppleHost: isAppleHost,
    enabled: enabled,
  );
}

/// Helper for Go core launch blocking check.
bool shouldBlockGoCoreLaunch({
  required bool isAppleHost,
  bool? enabled,
}) {
  return shouldBlockEmbeddedAgentLaunch(
    isAppleHost: isAppleHost,
    enabled: enabled,
  );
}
