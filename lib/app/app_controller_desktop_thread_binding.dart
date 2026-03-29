// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'app_metadata.dart';
import 'app_capabilities.dart';
import 'app_store_policy.dart';
import 'ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/device_identity_store.dart';
import '../runtime/aris_bundle.dart';
import '../runtime/go_core.dart';
import '../runtime/runtime_bootstrap.dart';
import '../runtime/desktop_platform_service.dart';
import '../runtime/gateway_runtime.dart';
import '../runtime/runtime_controllers.dart';
import '../runtime/runtime_models.dart';
import '../runtime/secure_config_store.dart';
import '../runtime/embedded_agent_launch_policy.dart';
import '../runtime/runtime_coordinator.dart';
import '../runtime/direct_single_agent_app_server_client.dart';
import '../runtime/gateway_acp_client.dart';
import '../runtime/codex_runtime.dart';
import '../runtime/codex_config_bridge.dart';
import '../runtime/code_agent_node_orchestrator.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/desktop_thread_artifact_service.dart';
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/multi_agent_orchestrator.dart';
import '../runtime/platform_environment.dart';
import '../runtime/single_agent_runner.dart';
import '../runtime/skill_directory_access.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_single_agent.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

extension AppControllerDesktopThreadBinding on AppController {
  String localThreadWorkspacePathInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final baseWorkspace = settings.workspacePath.trim();
    if (baseWorkspace.isEmpty) {
      return '';
    }
    final threadWorkspace =
        '${trimTrailingPathSeparatorInternal(baseWorkspace)}/.xworkmate/threads/${threadWorkspaceDirectoryNameInternal(normalizedSessionKey)}';
    ensureLocalWorkspaceDirectoryInternal(threadWorkspace);
    return threadWorkspace;
  }

  String remoteThreadWorkspacePathInternal(
    String sessionKey,
    ThreadOwnerScope ownerScope,
  ) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final realm = ownerScope.realm.name;
    final subjectType = ownerScope.subjectType.name;
    final subjectId = ownerScope.subjectId.trim();
    return '/owners/$realm/$subjectType/$subjectId/threads/$normalizedSessionKey';
  }

  String threadWorkspaceDirectoryNameInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final sanitized = normalizedSessionKey
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return sanitized.isEmpty ? 'thread' : sanitized;
  }

  String trimTrailingPathSeparatorInternal(String path) {
    if (path.endsWith('/') && path.length > 1) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  void ensureLocalWorkspaceDirectoryInternal(String path) {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return;
    }
    try {
      Directory(normalizedPath).createSync(recursive: true);
    } catch (_) {
      // Best effort only. The caller can still decide whether to fail fast.
    }
  }

  ThreadOwnerScope desktopThreadOwnerScopeFromIdentityInternal(
    LocalDeviceIdentity identity,
  ) {
    return ThreadOwnerScope(
      realm: ThreadRealm.local,
      subjectType: ThreadSubjectType.user,
      subjectId: identity.deviceId,
      displayName: identity.deviceId,
    );
  }

  Future<ThreadOwnerScope> ensureDesktopThreadOwnerScopeInternal(
    String sessionKey,
  ) async {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final existing =
        assistantThreadRecordsInternal[normalizedSessionKey]?.ownerScope;
    if (existing != null && existing.subjectId.trim().isNotEmpty) {
      return existing;
    }
    final identity = await DeviceIdentityStore(storeInternal).loadOrCreate();
    return desktopThreadOwnerScopeFromIdentityInternal(identity);
  }

  WorkspaceBinding buildDesktopWorkspaceBindingInternal(
    String sessionKey, {
    required AssistantExecutionTarget executionTarget,
    required ThreadOwnerScope ownerScope,
    WorkspaceBinding? existingBinding,
  }) {
    if (executionTarget == AssistantExecutionTarget.singleAgent) {
      if (existingBinding != null &&
          existingBinding.workspacePath.trim().isNotEmpty) {
        if (existingBinding.workspaceKind == WorkspaceKind.localFs) {
          ensureLocalWorkspaceDirectoryInternal(existingBinding.workspacePath);
          return existingBinding.copyWith(
            displayPath: existingBinding.workspacePath,
          );
        }
        final defaultRemotePath = remoteThreadWorkspacePathInternal(
          sessionKey,
          ownerScope,
        );
        if (existingBinding.workspacePath.trim() != defaultRemotePath) {
          return existingBinding.copyWith(
            displayPath: existingBinding.displayPath.trim().isEmpty
                ? existingBinding.workspacePath
                : null,
          );
        }
      }
      final localPath = localThreadWorkspacePathInternal(sessionKey);
      return WorkspaceBinding(
        workspaceId: normalizedAssistantSessionKeyInternal(sessionKey),
        workspaceKind: WorkspaceKind.localFs,
        workspacePath: localPath,
        displayPath: localPath,
        writable: true,
      );
    }
    if (existingBinding != null &&
        existingBinding.workspaceKind == WorkspaceKind.remoteFs &&
        existingBinding.workspacePath.trim().isNotEmpty) {
      return existingBinding.copyWith(
        displayPath: existingBinding.displayPath.trim().isEmpty
            ? existingBinding.workspacePath
            : null,
      );
    }
    final remotePath = remoteThreadWorkspacePathInternal(
      sessionKey,
      ownerScope,
    );
    return WorkspaceBinding(
      workspaceId: normalizedAssistantSessionKeyInternal(sessionKey),
      workspaceKind: WorkspaceKind.remoteFs,
      workspacePath: remotePath,
      displayPath: remotePath,
      writable: existingBinding?.writable ?? true,
    );
  }

  ExecutionBinding buildDesktopExecutionBindingInternal({
    required AssistantExecutionTarget executionTarget,
    required SingleAgentProvider singleAgentProvider,
    ExecutionBinding? existingBinding,
  }) {
    return (existingBinding ??
            ExecutionBinding(
              executionMode: ThreadExecutionMode.localAgent,
              executorId: singleAgentProvider.providerId,
              providerId: singleAgentProvider.providerId,
              endpointId: '',
            ))
        .copyWith(
          executionMode: switch (executionTarget) {
            AssistantExecutionTarget.singleAgent =>
              ThreadExecutionMode.localAgent,
            AssistantExecutionTarget.local =>
              ThreadExecutionMode.gatewayLocal,
            AssistantExecutionTarget.remote =>
              ThreadExecutionMode.gatewayRemote,
          },
          executorId: singleAgentProvider.providerId,
          providerId: singleAgentProvider.providerId,
        );
  }

  Future<void> ensureDesktopTaskThreadBindingInternal(
    String sessionKey, {
    AssistantExecutionTarget? executionTarget,
  }) async {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final existing = assistantThreadRecordsInternal[normalizedSessionKey];
    final resolvedExecutionTarget =
        executionTarget ??
        existing?.executionTarget ??
        assistantExecutionTargetForSession(normalizedSessionKey);
    final ownerScope = await ensureDesktopThreadOwnerScopeInternal(
      normalizedSessionKey,
    );
    final workspaceBinding = buildDesktopWorkspaceBindingInternal(
      normalizedSessionKey,
      executionTarget: resolvedExecutionTarget,
      ownerScope: ownerScope,
      existingBinding: existing?.workspaceBinding,
    );
    final lifecycleStatus = workspaceBinding.workspacePath.trim().isEmpty
        ? 'needs_workspace'
        : 'ready';
    upsertTaskThreadInternal(
      normalizedSessionKey,
      ownerScope: ownerScope,
      workspaceBinding: workspaceBinding,
      executionBinding: buildDesktopExecutionBindingInternal(
        executionTarget: resolvedExecutionTarget,
        singleAgentProvider:
            existing?.singleAgentProvider ?? SingleAgentProvider.auto,
        existingBinding: existing?.executionBinding,
      ),
      lifecycleState: (existing?.lifecycleState ??
              const ThreadLifecycleState(
                archived: false,
                status: 'ready',
                lastRunAtMs: null,
                lastResultCode: null,
              ))
          .copyWith(status: lifecycleStatus),
      executionTarget: resolvedExecutionTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
  }
}
