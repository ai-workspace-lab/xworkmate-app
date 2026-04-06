// Legacy compatibility surface retained while the app imports are cleaned up.
//
// The direct single-agent app-server runtime has been retired in favor of the
// GoTaskService ACP lane. This library intentionally exports only the capability
// DTOs still consumed by the UI-facing state layer.
export 'direct_single_agent_app_server_client_protocol.dart';
