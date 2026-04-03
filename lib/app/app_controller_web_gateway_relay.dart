// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/runtime_models.dart';
import '../web/web_acp_client.dart';
import '../web/web_ai_gateway_client.dart';
import '../web/web_artifact_proxy_client.dart';
import '../web/web_relay_gateway_client.dart';
import '../web/web_session_repository.dart';
import '../web/web_store.dart';
import '../web/web_workspace_controllers.dart';
import 'app_capabilities.dart';
import 'ui_feature_manifest.dart';
import 'app_controller_web_core.dart';
import 'app_controller_web_sessions.dart';
import 'app_controller_web_workspace.dart';
import 'app_controller_web_session_actions.dart';
import 'app_controller_web_gateway_config.dart';
import 'app_controller_web_gateway_chat.dart';
import 'app_controller_web_helpers.dart';

extension AppControllerWebGatewayRelay on AppController {
  Future<void> connectRelay({AssistantExecutionTarget? target}) async {
    relayBusyInternal = true;
    notifyChangedInternal();
    try {
      final resolvedTarget =
          sanitizeTargetInternal(target) ??
          (() {
            final current = assistantExecutionTargetForSession(
              currentSessionKeyInternal,
            );
            return current == AssistantExecutionTarget.local ||
                    current == AssistantExecutionTarget.remote
                ? current
                : AssistantExecutionTarget.remote;
          })();
      final profileIndex = profileIndexForTargetInternal(resolvedTarget);
      final profile = profileForTargetInternal(resolvedTarget).copyWith(
        mode: resolvedTarget == AssistantExecutionTarget.local
            ? RuntimeConnectionMode.local
            : RuntimeConnectionMode.remote,
        useSetupCode: false,
        setupCode: '',
      );
      await relayClientInternal.connect(
        profile: profile,
        authToken: (relayTokenByProfileInternal[profileIndex] ?? '').trim(),
        authPassword: (relayPasswordByProfileInternal[profileIndex] ?? '')
            .trim(),
      );
      final acpEndpoint = acpEndpointForTargetInternal(resolvedTarget);
      if (acpEndpoint != null) {
        await refreshAcpCapabilitiesInternal(acpEndpoint);
      }
      await refreshRelaySessions();
      await refreshRelayWorkspaceResources();
      await refreshRelayHistory(sessionKey: currentSessionKeyInternal);
      await refreshRelaySkillsForSession(currentSessionKeyInternal);
    } finally {
      relayBusyInternal = false;
      notifyChangedInternal();
    }
  }

  Future<void> disconnectRelay() async {
    relayBusyInternal = true;
    notifyChangedInternal();
    try {
      await relayClientInternal.disconnect();
      relayAgentsInternal = const <GatewayAgentSummary>[];
      relayInstancesInternal = const <GatewayInstanceSummary>[];
      relayConnectorsInternal = const <GatewayConnectorSummary>[];
      relayModelsInternal = const <GatewayModelSummary>[];
      relayCronJobsInternal = const <GatewayCronJobSummary>[];
      recomputeDerivedWorkspaceStateInternal();
    } finally {
      relayBusyInternal = false;
      notifyChangedInternal();
    }
  }

  Future<void> refreshRelaySessions() async {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    final target = assistantExecutionTargetForModeInternal(connection.mode);
    final sessions = await relayClientInternal.listSessions(limit: 50);
    for (final session in sessions) {
      final sessionKey = normalizedSessionKeyInternal(session.key);
      final existing = threadRecordsInternal[sessionKey];
      final resolvedExecutionTarget = existing?.executionTarget ?? target;
      final resolvedProvider =
          existing?.singleAgentProvider ?? SingleAgentProvider.auto;
      final next = TaskThread(
        threadId: sessionKey,
        createdAtMs:
            existing?.createdAtMs ??
            DateTime.now().millisecondsSinceEpoch.toDouble(),
        updatedAtMs:
            session.updatedAtMs ??
            existing?.updatedAtMs ??
            DateTime.now().millisecondsSinceEpoch.toDouble(),
        title: (session.derivedTitle ?? session.displayName ?? session.key)
            .trim(),
        ownerScope:
            existing?.ownerScope ??
            const ThreadOwnerScope(
              realm: ThreadRealm.remote,
              subjectType: ThreadSubjectType.user,
              subjectId: '',
              displayName: '',
            ),
        workspaceBinding:
            existing?.workspaceBinding ??
            WorkspaceBinding(
              workspaceId: sessionKey,
              workspaceKind: WorkspaceKind.remoteFs,
              workspacePath: '',
              displayPath: '',
              writable: true,
            ),
        executionBinding:
            existing?.executionBinding ??
            ExecutionBinding(
              executionMode: switch (resolvedExecutionTarget) {
                AssistantExecutionTarget.auto => ThreadExecutionMode.auto,
                AssistantExecutionTarget.singleAgent =>
                  ThreadExecutionMode.localAgent,
                AssistantExecutionTarget.local =>
                  ThreadExecutionMode.gatewayLocal,
                AssistantExecutionTarget.remote =>
                  ThreadExecutionMode.gatewayRemote,
              },
              executorId: resolvedProvider.providerId,
              providerId: resolvedProvider.providerId,
              endpointId: '',
            ),
        contextState:
            existing?.contextState ??
            ThreadContextState(
              messages: const <GatewayChatMessage>[],
              selectedModelId: '',
              selectedSkillKeys: const <String>[],
              importedSkills: const <AssistantThreadSkillEntry>[],
              permissionLevel: AssistantPermissionLevel.defaultAccess,
              messageViewMode: AssistantMessageViewMode.rendered,
              latestResolvedRuntimeModel: '',
              gatewayEntryState: gatewayEntryStateForTargetInternal(
                resolvedExecutionTarget,
              ),
            ),
        lifecycleState:
            existing?.lifecycleState ??
            const ThreadLifecycleState(
              archived: false,
              status: 'needs_workspace',
              lastRunAtMs: null,
              lastResultCode: null,
            ),
      );
      threadRecordsInternal[sessionKey] = next;
      await ensureWebTaskThreadBindingInternal(
        sessionKey,
        executionTarget: next.executionTarget,
      );
    }
    await persistThreadsInternal();
    recomputeDerivedWorkspaceStateInternal();
    notifyChangedInternal();
  }

  Future<void> refreshRelayModels() async {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    final models = await relayClientInternal.listModels();
    relayModelsInternal = models;
    final availableModels = models
        .map((item) => item.id.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (availableModels.isEmpty) {
      return;
    }
    final defaultModel = settingsInternal.defaultModel.trim().isNotEmpty
        ? settingsInternal.defaultModel.trim()
        : availableModels.first;
    settingsInternal = settingsInternal.copyWith(
      defaultModel: defaultModel,
      aiGateway: settingsInternal.aiGateway.copyWith(
        availableModels: settingsInternal.aiGateway.availableModels.isEmpty
            ? availableModels
            : settingsInternal.aiGateway.availableModels,
      ),
    );
    await persistSettingsInternal();
    recomputeDerivedWorkspaceStateInternal();
    notifyChangedInternal();
  }

  Future<void> refreshRelayWorkspaceResources() async {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    try {
      relayAgentsInternal = await relayClientInternal.listAgents();
    } catch (_) {
      relayAgentsInternal = const <GatewayAgentSummary>[];
    }
    try {
      relayInstancesInternal = await relayClientInternal.listInstances();
    } catch (_) {
      relayInstancesInternal = const <GatewayInstanceSummary>[];
    }
    try {
      relayConnectorsInternal = await relayClientInternal.listConnectors();
    } catch (_) {
      relayConnectorsInternal = const <GatewayConnectorSummary>[];
    }
    try {
      relayCronJobsInternal = await relayClientInternal.listCronJobs();
    } catch (_) {
      relayCronJobsInternal = const <GatewayCronJobSummary>[];
    }
    await refreshRelayModels();
    recomputeDerivedWorkspaceStateInternal();
    notifyChangedInternal();
  }

  Future<void> refreshRelayHistory({String? sessionKey}) async {
    final resolvedKey = normalizedSessionKeyInternal(
      sessionKey ?? currentSessionKeyInternal,
    );
    if (resolvedKey.isEmpty ||
        connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    final target = assistantExecutionTargetForModeInternal(connection.mode);
    final messages = await relayClientInternal.loadHistory(
      resolvedKey,
      limit: 120,
    );
    final existing = threadRecordsInternal[resolvedKey];
    final next = (existing ?? newRecordInternal(target: target)).copyWith(
      sessionKey: resolvedKey,
      messages: messages,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      title: deriveThreadTitleInternal(
        existing?.title ?? '',
        messages,
        fallback: resolvedKey,
      ),
      executionTarget: existing?.executionTarget ?? target,
      gatewayEntryState:
          existing?.gatewayEntryState ??
          gatewayEntryStateForTargetInternal(target),
    );
    threadRecordsInternal[resolvedKey] = next;
    await ensureWebTaskThreadBindingInternal(
      resolvedKey,
      executionTarget: next.executionTarget,
    );
    streamingTextBySessionInternal.remove(resolvedKey);
    await persistThreadsInternal();
    recomputeDerivedWorkspaceStateInternal();
    notifyChangedInternal();
  }

  Future<void> refreshRelaySkillsForSession(String sessionKey) async {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    if ((target != AssistantExecutionTarget.local &&
            target != AssistantExecutionTarget.remote) ||
        connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    try {
      final payload = castMapInternal(
        await relayClientInternal.request('skills.status'),
      );
      final skills = (payload['skills'] as List<dynamic>? ?? const <dynamic>[])
          .map(castMapInternal)
          .map(
            (item) => AssistantThreadSkillEntry(
              key: item['skillKey']?.toString().trim().isNotEmpty == true
                  ? item['skillKey'].toString().trim()
                  : (item['name']?.toString().trim() ?? ''),
              label: item['name']?.toString().trim() ?? '',
              description: item['description']?.toString().trim() ?? '',
              source: item['source']?.toString().trim() ?? 'gateway',
              sourcePath: '',
              scope: 'session',
              sourceLabel: item['source']?.toString().trim() ?? 'gateway',
            ),
          )
          .where((entry) => entry.key.isNotEmpty && entry.label.isNotEmpty)
          .toList(growable: false);
      final importedKeys = skills.map((item) => item.key).toSet();
      final nextSelected =
          (threadRecordsInternal[normalizedSessionKey]?.selectedSkillKeys ??
                  const <String>[])
              .where(importedKeys.contains)
              .toList(growable: false);
      upsertThreadRecordInternal(
        normalizedSessionKey,
        importedSkills: skills,
        selectedSkillKeys: nextSelected,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
      await persistThreadsInternal();
      recomputeDerivedWorkspaceStateInternal();
      notifyChangedInternal();
    } catch (_) {
      // Best effort: skill discovery should not block chat flows.
    }
  }

  Future<void> refreshSingleAgentSkillsForSessionInternal(
    String sessionKey,
  ) async {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return;
    }
    final endpoint = acpEndpointForTargetInternal(
      AssistantExecutionTarget.remote,
    );
    if (endpoint == null) {
      await replaceThreadSkillsForSessionInternal(
        normalizedSessionKey,
        const <AssistantThreadSkillEntry>[],
      );
      return;
    }
    final provider = singleAgentProviderForSession(normalizedSessionKey);
    try {
      await refreshAcpCapabilitiesInternal(endpoint);
      final response = await acpClientInternal.request(
        endpoint: endpoint,
        method: 'skills.status',
        params: <String, dynamic>{
          'sessionId': normalizedSessionKey,
          'threadId': normalizedSessionKey,
          'mode': 'single-agent',
          'provider': provider.providerId,
        },
      );
      final result = castMapInternal(response['result']);
      final payload = result.isNotEmpty ? result : response;
      final skills = (payload['skills'] as List<dynamic>? ?? const <dynamic>[])
          .map(castMapInternal)
          .map(
            (item) => AssistantThreadSkillEntry(
              key: item['skillKey']?.toString().trim().isNotEmpty == true
                  ? item['skillKey'].toString().trim()
                  : (item['name']?.toString().trim() ?? ''),
              label: item['name']?.toString().trim() ?? '',
              description: item['description']?.toString().trim() ?? '',
              source: item['source']?.toString().trim() ?? provider.providerId,
              sourcePath: item['path']?.toString().trim() ?? '',
              scope: item['scope']?.toString().trim().isNotEmpty == true
                  ? item['scope'].toString().trim()
                  : 'session',
              sourceLabel:
                  item['sourceLabel']?.toString().trim().isNotEmpty == true
                  ? item['sourceLabel'].toString().trim()
                  : (item['source']?.toString().trim().isNotEmpty == true
                        ? item['source'].toString().trim()
                        : provider.label),
            ),
          )
          .where((entry) => entry.key.isNotEmpty && entry.label.isNotEmpty)
          .toList(growable: false);
      await replaceThreadSkillsForSessionInternal(normalizedSessionKey, skills);
    } on WebAcpException catch (error) {
      if (unsupportedAcpSkillsStatusInternal(error)) {
        await replaceThreadSkillsForSessionInternal(
          normalizedSessionKey,
          const <AssistantThreadSkillEntry>[],
        );
      }
    } catch (_) {
      // Keep current skills when transient ACP failures happen.
    }
  }

  Future<void> replaceThreadSkillsForSessionInternal(
    String sessionKey,
    List<AssistantThreadSkillEntry> importedSkills,
  ) async {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    final importedKeys = importedSkills.map((item) => item.key).toSet();
    final nextSelected =
        (threadRecordsInternal[normalizedSessionKey]?.selectedSkillKeys ??
                const <String>[])
            .where(importedKeys.contains)
            .toList(growable: false);
    upsertThreadRecordInternal(
      normalizedSessionKey,
      importedSkills: importedSkills,
      selectedSkillKeys: nextSelected,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await persistThreadsInternal();
    recomputeDerivedWorkspaceStateInternal();
    notifyChangedInternal();
  }
}
