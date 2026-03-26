@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';

import '../test_support.dart';

void main() {
  test(
    'AppController exposes a stable desktop status snapshot shape',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppController(store: createIsolatedTestStore());
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);

      final snapshot = controller.desktopStatusSnapshot();
      expect(snapshot['connectionStatus'], 'disconnected');
      expect(snapshot['connectionLabel'], isA<String>());
      expect(snapshot['runningTasks'], 0);
      expect(snapshot['pausedTasks'], 0);
      expect(snapshot['timedOutTasks'], 0);
      expect(snapshot['queuedTasks'], 0);
      expect(snapshot['scheduledTasks'], 0);
      expect(snapshot['failedTasks'], 0);
      expect(snapshot['totalTasks'], 0);
      expect(snapshot['badgeCount'], 0);
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
