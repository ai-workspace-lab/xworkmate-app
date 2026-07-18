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
import '../runtime/platform_environment.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
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
    required this.record,
  });

  final AssistantExecutionTarget executionTarget;
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
  return DesktopThreadBindingSnapshotInternal(
    executionTarget: resolvedExecutionTarget,
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

  /// 线程工作区的可写基准目录。
  ///
  /// iOS 应用进程没有 HOME 环境变量（2026-07-17 真机联调确认 home 解析为
  /// 空串），基于 env 的路径推导必然失败，绑定随之回退 remoteFs，制品同步
  /// 的 localFs 守卫会永远跳过该线程。移动端改用 initializeInternal 经
  /// path_provider 解析的应用 Documents 目录；桌面端保持 `$HOME` 不变。
  String threadWorkspaceHomeBaseInternal() {
    if (Platform.isIOS || Platform.isAndroid) {
      final base = mobileWorkspaceBaseDirectoryInternal.trim();
      return base.isEmpty ? '' : trimTrailingPathSeparatorInternal(base);
    }
    final homeDirectory = resolvedUserHomeDirectoryInternal.trim();
    if (homeDirectory.isEmpty) {
      return '';
    }
    return trimTrailingPathSeparatorInternal(homeDirectory);
  }

  String localThreadWorkspacePathInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (!isAppOwnedAssistantSessionKeyInternal(normalizedSessionKey)) {
      return '';
    }
    final baseDirectory = threadWorkspaceHomeBaseInternal();
    if (baseDirectory.isEmpty) {
      debugPrint(
        '[thread-binding] localPath bail: empty base '
        '(home="$resolvedUserHomeDirectoryInternal")',
      );
      return '';
    }
    final threadWorkspace =
        '$baseDirectory/.xworkmate/threads/${threadWorkspaceDirectoryNameInternal(normalizedSessionKey)}';
    final ensured = ensureLocalWorkspaceDirectoryInternal(threadWorkspace);
    if (!ensured) {
      debugPrint('[thread-binding] localPath mkdir failed: $threadWorkspace');
    }
    return ensured ? threadWorkspace : '';
  }

  String localThreadWorkspaceDisplayPathInternal(String sessionKey) {
    if (threadWorkspaceHomeBaseInternal().isEmpty) {
      return '';
    }
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (!isAppOwnedAssistantSessionKeyInternal(normalizedSessionKey)) {
      return '';
    }
    if (Platform.isIOS || Platform.isAndroid) {
      return '\$DOCUMENTS/.xworkmate/threads/${threadWorkspaceDirectoryNameInternal(normalizedSessionKey)}';
    }
    return localThreadWorkspacePathInternal(normalizedSessionKey);
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
    } catch (error) {
      debugPrint('Ensure local thread workspace fallback: $error');
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
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final localPath = localThreadWorkspacePathInternal(normalizedSessionKey);
    if (localPath.isEmpty) {
      final remotePath = remoteThreadWorkspacePathInternal(
        normalizedSessionKey,
        ownerScope,
      );
      return WorkspaceBinding(
        workspaceId: normalizedSessionKey,
        workspaceKind: WorkspaceKind.remoteFs,
        workspacePath: remotePath,
        displayPath: remotePath,
        writable: existingBinding?.writable ?? true,
      );
    }
    final displayPath = localThreadWorkspaceDisplayPathInternal(
      normalizedSessionKey,
    );
    return WorkspaceBinding(
      workspaceId: normalizedSessionKey,
      workspaceKind: WorkspaceKind.localFs,
      workspacePath: localPath,
      displayPath: displayPath,
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
    ExecutionBinding? existingBinding,
  }) {
    final persistedProviderId = normalizeSingleAgentProviderId(
      existingBinding?.providerId ?? '',
    );
    final existingTarget = existingBinding == null
        ? null
        : assistantExecutionTargetFromExecutionMode(
            existingBinding.executionMode,
          );
    final selectedProvider = resolveProviderForExecutionTarget(
      persistedProviderId,
      executionTarget: executionTarget,
      defaultToCatalog:
          existingBinding == null || existingTarget != executionTarget,
    );
    return (existingBinding ??
            ExecutionBinding(
              executionMode: threadExecutionModeFromAssistantExecutionTarget(
                executionTarget,
              ),
              executorId: selectedProvider.providerId,
              providerId: selectedProvider.providerId,
              endpointId: '',
            ))
        .copyWith(
          executionMode: threadExecutionModeFromAssistantExecutionTarget(
            executionTarget,
          ),
          executorId: selectedProvider.providerId,
          providerId: selectedProvider.providerId,
          providerSource:
              existingBinding?.providerSource ??
              ThreadSelectionSource.inherited,
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
    final latestRecord =
        taskThreadForSessionInternal(normalizedSessionKey) ??
        assistantThreadRecordsInternal[normalizedSessionKey];
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
    final currentRecord =
        taskThreadForSessionInternal(normalizedSessionKey) ??
        assistantThreadRecordsInternal[normalizedSessionKey];
    final existingLifecycle =
        currentRecord?.lifecycleState ??
        snapshot.record?.lifecycleState ??
        const ThreadLifecycleState(
          archived: false,
          status: 'ready',
          lastRunAtMs: null,
          lastResultCode: null,
        );
    final existingLifecycleStatus = existingLifecycle.status
        .trim()
        .toLowerCase();
    final lifecycleState = existingLifecycleStatus == 'running'
        ? existingLifecycle
        : assistantSessionHasPendingRun(normalizedSessionKey)
        ? existingLifecycle.copyWith(status: 'running')
        : existingLifecycle;
    upsertTaskThreadInternal(
      normalizedSessionKey,
      ownerScope: ownerScope,
      workspaceBinding: workspaceBinding,
      lastRemoteWorkingDirectory:
          snapshot.record?.lastRemoteWorkingDirectory?.trim().isNotEmpty == true
          ? snapshot.record?.lastRemoteWorkingDirectory
          : remoteThreadWorkspacePathInternal(normalizedSessionKey, ownerScope),
      lastRemoteWorkspaceRefKind:
          snapshot.record?.lastRemoteWorkspaceRefKind ??
          WorkspaceRefKind.remotePath,
      executionBinding: buildDesktopExecutionBindingInternal(
        executionTarget: snapshot.executionTarget,
        existingBinding: snapshot.record?.executionBinding,
      ),
      lifecycleState: lifecycleState,
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
