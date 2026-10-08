import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../runtime/role_routing.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import 'assistant_page_task_dialog_controls.dart';

/// Shows the role, model and executor the bridge actually selected for the
/// current task, plus any permission prompt waiting for the user.
class AssistantRoleTaskPanelInternal extends StatelessWidget {
  const AssistantRoleTaskPanelInternal({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final sessionKey = controller.currentSessionKey;
    final status = controller.roleTaskStatusForSession(sessionKey);
    final pending = controller.pendingRolePermissionsForSession(sessionKey);
    if (status == null && pending.isEmpty) {
      return const SizedBox.shrink();
    }
    final palette = context.palette;
    final theme = Theme.of(context);
    return Container(
      key: const Key('assistant-role-task-panel'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status != null)
            Text(
              _statusLine(status),
              key: const Key('assistant-role-task-status'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: status.phase == 'failed' || status.phase == 'rejected'
                    ? palette.danger
                    : palette.textSecondary,
              ),
            ),
          for (final request in pending)
            _PermissionPromptInternal(
              controller: controller,
              sessionKey: sessionKey,
              request: request,
            ),
        ],
      ),
    );
  }

  static String _statusLine(RoleTaskStatus status) {
    final parts = <String>[
      if (status.role.isNotEmpty) roleRoutingRoleLabelInternal(status.role),
      if (status.modelId.isNotEmpty) status.modelId,
      if (status.providerId.isNotEmpty) status.providerId,
    ];
    final phase = switch (status.phase) {
      'selected' => appText('已选定', 'selected'),
      'started' => appText('执行中', 'running'),
      'completed' => appText('已完成', 'completed'),
      'failed' => appText('失败', 'failed'),
      'cancelled' => appText('已取消', 'cancelled'),
      'rejected' => appText('未派发', 'not dispatched'),
      _ => status.phase,
    };
    final head = parts.isEmpty ? phase : '${parts.join(' · ')} — $phase';
    return status.message.isEmpty ? head : '$head: ${status.message}';
  }
}

class _PermissionPromptInternal extends StatelessWidget {
  const _PermissionPromptInternal({
    required this.controller,
    required this.sessionKey,
    required this.request,
  });

  final AppController controller;
  final String sessionKey;
  final RoleTaskPermissionRequest request;

  @override
  Widget build(BuildContext context) {
    final title = request.title.isNotEmpty
        ? request.title
        : appText('执行器请求操作权限', 'The executor requests permission');
    return Padding(
      key: Key('assistant-role-permission-${request.requestId}'),
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            request.toolKind.isEmpty ? title : '$title (${request.toolKind})',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final option in request.options)
            option.allows
                ? FilledButton.tonal(
                    key: Key(
                      'assistant-role-permission-option-${option.optionId}',
                    ),
                    onPressed: () => _respond(context, option.optionId),
                    child: Text(
                      option.name.isNotEmpty ? option.name : option.optionId,
                    ),
                  )
                : OutlinedButton(
                    key: Key(
                      'assistant-role-permission-option-${option.optionId}',
                    ),
                    onPressed: () => _respond(context, option.optionId),
                    child: Text(
                      option.name.isNotEmpty ? option.name : option.optionId,
                    ),
                  ),
          TextButton(
            key: const Key('assistant-role-permission-deny'),
            onPressed: () => _respond(context, null),
            child: Text(appText('拒绝', 'Deny')),
          ),
        ],
      ),
    );
  }

  void _respond(BuildContext context, String? optionId) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    unawaited(
      controller
          .respondRolePermission(sessionKey, request, optionId: optionId)
          .catchError((Object error) {
            messenger?.showSnackBar(
              SnackBar(
                content: Text(
                  appText('权限决定发送失败：$error', 'Could not send decision: $error'),
                ),
              ),
            );
          }),
    );
  }
}
