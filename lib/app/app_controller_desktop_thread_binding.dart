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

class DesktopThreadBindingSnapshotInternal {
  const DesktopThreadBindingSnapshotInternal({
    required this.executionTarget,
    required this.singleAgentProvider,
    required this.record,
  });

  final AssistantExecutionTarget executionTarget;
  final SingleAgentProvider singleAgentProvider;
  final TaskThread? record;
}

DesktopThreadBindingSnapshotInternal
resolveDesktopThreadBindingSnapshotInternal({
  required AssistantExecutionTarget defaultExecutionTarget,
  AssistantExecutionTarget? executionTargetOverride,
  TaskThread? latestRecord,
}) {
  final resolvedExecutionTarget =
      executionTargetOverride ??
      (latestRecord == null
          ? defaultExecutionTarget
          : assistantExecutionTargetFromExecutionMode(
              latestRecord.executionBinding.executionMode,
            ));
  final resolvedProvider = SingleAgentProviderCopy.fromJsonValue(
    latestRecord?.executionBinding.providerId ?? '',
  );
  return DesktopThreadBindingSnapshotInternal(
    executionTarget: resolvedExecutionTarget,
    singleAgentProvider: resolvedProvider,
    record: latestRecord,
  );
}

extension AppControllerDesktopThreadBinding on AppController {
  String managedLocalThreadWorkspaceSuffixInternal(String sessionKey) =>
      '/.xworkmate/threads/${threadWorkspaceDirectoryNameInternal(sessionKey)}';

  bool isManagedLocalThreadWorkspacePathInternal(
    String path,
    String sessionKey,
  ) {
    final normalizedPath = trimTrailingPathSeparatorInternal(path.trim());
    if (normalizedPath.isEmpty) {
      return false;
    }
    final normalizedSuffix = managedLocalThreadWorkspaceSuffixInternal(
      sessionKey,
    );
    return normalizedPath.endsWith(normalizedSuffix);
  }

  String localThreadWorkspacePathInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final baseWorkspace = settings.workspacePath.trim().isNotEmpty
        ? settings.workspacePath.trim()
        : resolvedUserHomeDirectoryInternal.trim();
    if (baseWorkspace.isEmpty) {
      return '';
    }
    final threadWorkspace =
        '${trimTrailingPathSeparatorInternal(baseWorkspace)}/.xworkmate/threads/${threadWorkspaceDirectoryNameInternal(normalizedSessionKey)}';
    return ensureLocalWorkspaceDirectoryInternal(threadWorkspace)
        ? threadWorkspace
        : '';
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

  bool isOwnerScopedRemoteWorkspacePathInternal(String path) {
    final normalizedPath = path.trim();
    return normalizedPath.startsWith('/owners/');
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

  bool ensureLocalWorkspaceDirectoryInternal(String path) {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return false;
    }
    try {
      Directory(normalizedPath).createSync(recursive: true);
    } catch (_) {
      // Best effort only. The caller can still decide whether to fail fast.
    }
    return Directory(normalizedPath).existsSync();
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
          existingBinding.workspaceKind == WorkspaceKind.localFs &&
          !isManagedLocalThreadWorkspacePathInternal(
            existingBinding.workspacePath,
            sessionKey,
          ) &&
          ensureLocalWorkspaceDirectoryInternal(
            existingBinding.workspacePath,
          )) {
        return existingBinding.copyWith(
          displayPath: existingBinding.workspacePath,
        );
      }
      final localPath = localThreadWorkspacePathInternal(sessionKey);
      if (localPath.isEmpty) {
        throw StateError(
          'Local executable thread $sessionKey requires a writable local workspace.',
        );
      }
      return WorkspaceBinding(
        workspaceId: normalizedAssistantSessionKeyInternal(sessionKey),
        workspaceKind: WorkspaceKind.localFs,
        workspacePath: localPath,
        displayPath: localPath,
        writable: true,
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

  AssistantExecutionTarget resolveDraftThreadExecutionTargetInternal(
    String sessionKey, {
    required Iterable<AssistantExecutionTarget> supportedTargets,
  }) {
    return pickDraftThreadExecutionTargetInternal(
      currentTarget: assistantExecutionTargetForSession(sessionKey),
      visibleTargets: visibleAssistantExecutionTargets(supportedTargets),
      localWorkspaceAvailable: localThreadWorkspacePathInternal(
        sessionKey,
      ).trim().isNotEmpty,
    );
  }

  ExecutionBinding buildDesktopExecutionBindingInternal({
    required AssistantExecutionTarget executionTarget,
    required SingleAgentProvider singleAgentProvider,
    ExecutionBinding? existingBinding,
  }) {
    final sanitizedProvider = settings.sanitizeSingleAgentProviderSelection(
      singleAgentProvider,
    );
    return (existingBinding ??
            ExecutionBinding(
              executionMode: ThreadExecutionMode.localAgent,
              executorId: sanitizedProvider.providerId,
              providerId: sanitizedProvider.providerId,
              endpointId: '',
            ))
        .copyWith(
          executionMode: switch (executionTarget) {
            AssistantExecutionTarget.singleAgent =>
              ThreadExecutionMode.localAgent,
            AssistantExecutionTarget.local => ThreadExecutionMode.gatewayLocal,
            AssistantExecutionTarget.remote =>
              ThreadExecutionMode.gatewayRemote,
          },
          executorId: sanitizedProvider.providerId,
          providerId: sanitizedProvider.providerId,
        );
  }

  Future<void> ensureDesktopTaskThreadBindingInternal(
    String sessionKey, {
    AssistantExecutionTarget? executionTarget,
  }) async {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final ownerScope = await ensureDesktopThreadOwnerScopeInternal(
      normalizedSessionKey,
    );
    final latestRecord = assistantThreadRecordsInternal[normalizedSessionKey];
    final snapshot = resolveDesktopThreadBindingSnapshotInternal(
      defaultExecutionTarget: settings.assistantExecutionTarget,
      executionTargetOverride: executionTarget,
      latestRecord: latestRecord,
    );
    final workspaceBinding = buildDesktopWorkspaceBindingInternal(
      normalizedSessionKey,
      executionTarget: snapshot.executionTarget,
      ownerScope: ownerScope,
      existingBinding: snapshot.record?.workspaceBinding,
    );
    upsertTaskThreadInternal(
      normalizedSessionKey,
      ownerScope: ownerScope,
      workspaceBinding: workspaceBinding,
      executionBinding: buildDesktopExecutionBindingInternal(
        executionTarget: snapshot.executionTarget,
        singleAgentProvider: settings.sanitizeSingleAgentProviderSelection(
          snapshot.singleAgentProvider,
        ),
        existingBinding: snapshot.record?.executionBinding,
      ),
      lifecycleState:
          (snapshot.record?.lifecycleState ??
                  const ThreadLifecycleState(
                    archived: false,
                    status: 'ready',
                    lastRunAtMs: null,
                    lastResultCode: null,
                  ))
              .copyWith(status: 'ready'),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
  }
}

AssistantExecutionTarget pickDraftThreadExecutionTargetInternal({
  required AssistantExecutionTarget currentTarget,
  required Iterable<AssistantExecutionTarget> visibleTargets,
  bool? localWorkspaceAvailable,
}) {
  final orderedTargets = <AssistantExecutionTarget>[
    if (visibleTargets.contains(currentTarget)) currentTarget,
    ...visibleTargets.where((target) => target != currentTarget),
  ];
  for (final target in orderedTargets) {
    return target;
  }
  return currentTarget;
}
