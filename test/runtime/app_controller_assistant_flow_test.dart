import '../test_suite_stub.dart'
    if (dart.library.io) 'app_controller_assistant_flow_suite.dart'
    as assistant_flow_suite;
import '../test_suite_stub.dart'
    if (dart.library.io) 'app_controller_bridge_bootstrap_suite.dart'
    as bridge_bootstrap_suite;

void main() {
  assistant_flow_suite.main();
  bridge_bootstrap_suite.main();
}
