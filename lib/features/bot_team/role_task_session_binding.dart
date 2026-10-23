import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../runtime/acp_endpoint_paths.dart';
import '../../runtime/task_session_binding.dart';
import '../../runtime/task_session_client.dart';
import '../../runtime/task_session_sync_service.dart';

/// Opaque scoped keys keep endpoint/identity data out of binding records.
/// ACP transport suffixes share a scope; different base paths do not.
String roleTaskBindingKey({
  required String threadKey,
  required String source,
  required Uri endpoint,
}) {
  final base = endpoint.replace(
    path: AcpEndpointPaths.fromBaseEndpoint(endpoint).basePath,
    userInfo: '',
    query: null,
    fragment: null,
  );
  return 'role-task:${sha256.convert(utf8.encode(jsonEncode([source, base.toString(), threadKey])))}';
}

Future<TaskSessionSummary?> loadRoleTaskSession({
  required TaskSessionBindingStore store,
  required TaskSessionClient client,
  required String bindingKey,
}) async {
  final binding = await store.load(bindingKey);
  if (binding == null) return null;
  final namespace = await client.personalNamespaceId();
  if (namespace != binding.namespaceId) {
    throw const TaskSessionBindingMismatch(field: 'namespaceId');
  }
  // listSessions is namespace-scoped; do not append a stale or foreign ID.
  final sessions = await client.listSessions(namespace);
  for (final session in sessions) {
    if (session.sessionId == binding.cloudSessionId) return session;
  }
  throw const TaskSessionBindingMismatch(field: 'sessionId');
}
