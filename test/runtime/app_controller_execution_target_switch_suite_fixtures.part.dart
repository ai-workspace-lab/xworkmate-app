part of 'app_controller_execution_target_switch_suite.dart';

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

SettingsSnapshot _withRemoteGatewayProfile(
  SettingsSnapshot snapshot,
  GatewayConnectionProfile profile,
) {
  return snapshot.copyWithGatewayProfileAt(kGatewayRemoteProfileIndex, profile);
}

SettingsSnapshot _withLocalGatewayProfile(
  SettingsSnapshot snapshot,
  GatewayConnectionProfile profile,
) {
  return snapshot.copyWithGatewayProfileAt(kGatewayLocalProfileIndex, profile);
}
