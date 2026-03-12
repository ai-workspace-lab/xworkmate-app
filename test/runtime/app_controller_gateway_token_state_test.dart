import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';

void main() {
  test(
    'AppController tracks stored shared-token mask and clear action',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppController();
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);

      expect(controller.hasStoredGatewayToken, isFalse);
      expect(controller.storedGatewayTokenMask, isNull);

      await controller.settingsController.saveGatewaySecrets(
        token: 'token-secret',
        password: '',
      );

      expect(controller.hasStoredGatewayToken, isTrue);
      expect(controller.storedGatewayTokenMask, 'tok••••ret');

      await controller.clearStoredGatewayToken();

      expect(controller.hasStoredGatewayToken, isFalse);
      expect(controller.storedGatewayTokenMask, isNull);
    },
  );
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
