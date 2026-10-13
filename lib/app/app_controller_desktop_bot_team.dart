import '../runtime/acp_endpoint_paths.dart';
import '../runtime/task_session_client.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_runtime_helpers.dart';

/// Bot tasks go to Accounts through the Bridge `/api/v1` proxy with the
/// signed-in account token; the DSH orchestrator runs them (AI Workspace v2.1).
extension AppControllerDesktopBotTeam on AppController {
  /// Null until a Bridge endpoint resolves and an account session exists.
  TaskSessionClient? createTaskSessionClient() {
    final endpoint = resolveBridgeAcpEndpointInternal();
    final token = settingsControllerInternal.accountSessionTokenInternal.trim();
    if (endpoint == null || token.isEmpty) {
      return null;
    }
    final base = endpoint.replace(
      path: AcpEndpointPaths.fromBaseEndpoint(endpoint).basePath,
      query: null,
      fragment: null,
    );
    return HttpTaskSessionClient(bridgeBase: base, accountToken: token);
  }
}
