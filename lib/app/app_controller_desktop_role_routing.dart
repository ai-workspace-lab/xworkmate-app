import 'package:flutter/foundation.dart';

import '../runtime/go_task_service_client.dart';
import '../runtime/runtime_models.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_runtime_helpers.dart';
import 'app_controller_desktop_thread_sessions.dart';

/// Role routing: the bridge decides role, executor and model; the app picks
/// auto/manual, shows the bridge's actual selection and relays approvals.
extension AppControllerDesktopRoleRouting on AppController {
  BridgeRoleRoutingCatalog get bridgeRoleRoutingCatalog =>
      bridgeRoleRoutingCatalogInternal;

  RoleRoutingSelection get assistantRoleRoutingSelection =>
      assistantRoleRoutingSelectionInternal;

  void setAssistantRoleRoutingSelection(RoleRoutingSelection selection) {
    assistantRoleRoutingSelectionInternal = selection;
    notifyIfActiveInternal();
  }

  /// Role routing applies to agent turns only, and only while the bridge
  /// advertises an enabled policy. Otherwise the existing routing is used.
  RoleRoutingSelection roleRoutingForTurnInternal(
    AssistantExecutionTarget target,
  ) {
    final selection = assistantRoleRoutingSelectionInternal;
    if (!selection.isActive ||
        target.isGateway ||
        !bridgeRoleRoutingCatalogInternal.enabled) {
      return RoleRoutingSelection.off;
    }
    return selection;
  }

  RoleTaskStatus? roleTaskStatusForSession(String sessionKey) =>
      roleTaskStatusBySessionInternal[normalizedAssistantSessionKeyInternal(
        sessionKey,
      )];

  List<RoleTaskPermissionRequest> pendingRolePermissionsForSession(
    String sessionKey,
  ) =>
      rolePendingPermissionsBySessionInternal[normalizedAssistantSessionKeyInternal(
        sessionKey,
      )] ??
      const <RoleTaskPermissionRequest>[];

  /// Applies one `type: task` update. Returns false for other updates.
  bool applyRoleTaskUpdateInternal(
    String sessionKey,
    GoTaskServiceUpdate update,
  ) {
    final event = RoleTaskEvent.fromUpdatePayloadOrNull(update.payload);
    if (event == null) {
      return false;
    }
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    final previous = roleTaskStatusBySessionInternal[key];
    final status = event.status;
    roleTaskStatusBySessionInternal[key] = RoleTaskStatus(
      phase: event.phase.startsWith('permission_')
          ? (previous?.phase ?? 'started')
          : event.phase,
      role: status.role.isNotEmpty ? status.role : previous?.role ?? '',
      providerId: status.providerId.isNotEmpty
          ? status.providerId
          : previous?.providerId ?? '',
      modelId: status.modelId.isNotEmpty
          ? status.modelId
          : previous?.modelId ?? '',
      policyVersion: status.policyVersion.isNotEmpty
          ? status.policyVersion
          : previous?.policyVersion ?? '',
      message: status.message,
    );
    final pending = List<RoleTaskPermissionRequest>.of(
      rolePendingPermissionsBySessionInternal[key] ??
          const <RoleTaskPermissionRequest>[],
    );
    final permission = event.permission;
    if (event.phase == 'permission_requested' && permission != null) {
      pending.removeWhere((item) => item.requestId == permission.requestId);
      pending.add(permission);
    } else if (event.phase == 'permission_resolved' && permission != null) {
      pending.removeWhere((item) => item.requestId == permission.requestId);
    } else if (status.terminal) {
      pending.clear();
    }
    rolePendingPermissionsBySessionInternal[key] =
        List<RoleTaskPermissionRequest>.unmodifiable(pending);
    notifyIfActiveInternal();
    return true;
  }

  /// Sends the user's decision. [optionId] must be one of the options the
  /// executor offered; null denies.
  Future<void> respondRolePermission(
    String sessionKey,
    RoleTaskPermissionRequest request, {
    String? optionId,
  }) async {
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    try {
      await goTaskServiceClientInternal.respondPermission(
        target: assistantExecutionTargetForSession(key),
        sessionId: request.sessionId,
        requestId: request.requestId,
        optionId: optionId,
      );
    } catch (error) {
      debugPrint('respondRolePermission failed: $error');
      rethrow;
    }
    final remaining = List<RoleTaskPermissionRequest>.of(
      pendingRolePermissionsForSession(key),
    )..removeWhere((item) => item.requestId == request.requestId);
    rolePendingPermissionsBySessionInternal[key] =
        List<RoleTaskPermissionRequest>.unmodifiable(remaining);
    notifyIfActiveInternal();
  }

  /// Records the bridge's final selection from a role-routed result.
  void applyRoleTaskResultInternal(
    String sessionKey,
    GoTaskServiceResult result,
  ) {
    if (result.resolvedRole.isEmpty) {
      return;
    }
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    final previous = roleTaskStatusBySessionInternal[key];
    final status = result.status.trim().toLowerCase();
    roleTaskStatusBySessionInternal[key] = RoleTaskStatus(
      phase: status == 'cancelled'
          ? 'cancelled'
          : result.success
          ? 'completed'
          : 'failed',
      role: result.resolvedRole,
      providerId: result.resolvedProviderId,
      modelId: result.resolvedModelId,
      policyVersion: previous?.policyVersion ?? '',
      message: result.success ? '' : result.errorMessage,
    );
    rolePendingPermissionsBySessionInternal.remove(key);
    notifyIfActiveInternal();
  }
}
