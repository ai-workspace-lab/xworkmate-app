import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default desktop controller wires gateway runtime through bridge client', () {
    final controller = AppController();
    addTearDown(controller.dispose);

    expect(controller.runtime.usesSessionClient, isTrue);
  });
}
