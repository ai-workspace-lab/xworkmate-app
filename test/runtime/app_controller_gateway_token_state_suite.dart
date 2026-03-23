@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';

import '../test_support.dart';

void main() {
  test(
    'AppController tracks stored shared-token mask and clear action',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppController(store: createIsolatedTestStore());
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

  test(
    'AppController keeps gateway token masks independent per profile slot',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppController(store: createIsolatedTestStore());
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);

      await controller.settingsController.saveGatewaySecrets(
        profileIndex: 0,
        token: 'local-secret',
        password: '',
      );
      await controller.settingsController.saveGatewaySecrets(
        profileIndex: 1,
        token: 'remote-secret',
        password: '',
      );

      expect(controller.hasStoredGatewayTokenForProfile(0), isTrue);
      expect(controller.hasStoredGatewayTokenForProfile(1), isTrue);
      expect(controller.storedGatewayTokenMaskForProfile(0), 'loc••••ret');
      expect(controller.storedGatewayTokenMaskForProfile(1), 'rem••••ret');
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
