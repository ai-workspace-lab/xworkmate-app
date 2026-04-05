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
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopThreadStorage on AppController {
  Future<void> applyPersistedAiGatewaySettingsInternal(
    SettingsSnapshot snapshot,
  ) async {
    final apiKey = await settingsControllerInternal
        .loadEffectiveAiGatewayApiKey();
    if (snapshot.aiGateway.baseUrl.trim().isEmpty) {
      return;
    }
    try {
      await syncAiGatewayCatalog(snapshot.aiGateway, apiKeyOverride: apiKey);
    } catch (_) {
      // Keep the saved draft applied even if model sync fails immediately.
    }
  }

  Future<void> ensureActiveAssistantThreadInternal() async {
    if (!isSingleAgentMode ||
        !isAssistantTaskArchived(
          sessionsControllerInternal.currentSessionKey,
        )) {
      return;
    }
    final fallback = assistantSessionSummariesInternal().firstWhere(
      (item) => !isAssistantTaskArchived(item.key),
      orElse: () => GatewaySessionSummary(
        key: 'draft:${DateTime.now().millisecondsSinceEpoch}',
        kind: 'assistant',
        displayName: appText('新对话', 'New conversation'),
        surface: 'Assistant',
        subject: null,
        room: null,
        space: null,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        sessionId: null,
        systemSent: false,
        abortedLastRun: false,
        thinkingLevel: null,
        verboseLevel: null,
        inputTokens: null,
        outputTokens: null,
        totalTokens: null,
        model: null,
        contextTokens: null,
        derivedTitle: appText('新对话', 'New conversation'),
        lastMessagePreview: null,
      ),
    );
    await setCurrentAssistantSessionKeyInternal(fallback.key);
  }

  Future<void> restoreInitialAssistantSessionSelectionInternal() async {
    final normalized = normalizedAssistantSessionKeyInternal(
      settings.assistantLastSessionKey,
    );
    final known =
        normalized == 'main' ||
        assistantThreadRecordsInternal.containsKey(normalized) ||
        assistantThreadMessagesInternal.containsKey(normalized);
    if (normalized.isEmpty || !known || isAssistantTaskArchived(normalized)) {
      return;
    }
    await setCurrentAssistantSessionKeyInternal(
      normalized,
      persistSelection: false,
    );
  }

  void handleRuntimeEventInternal(GatewayPushEvent event) {
    chatControllerInternal.handleEvent(event);
    if (event.event == 'chat') {
      final payload = asMap(event.payload);
      final state = stringValue(payload['state']);
      if (state == 'final' || state == 'aborted' || state == 'error') {
        unawaited(refreshSessions());
      }
    }
    if (event.event == 'seqGap') {
      unawaited(refreshSessions());
    }
    if (event.event == 'device.pair.requested' ||
        event.event == 'device.pair.resolved') {
      unawaited(refreshDevices(quiet: true));
    }
  }

  SettingsSnapshot sanitizeMultiAgentSettingsInternal(
    SettingsSnapshot snapshot,
  ) {
    final resolved = resolveMultiAgentConfigInternal(snapshot);
    if (jsonEncode(snapshot.multiAgent.toJson()) ==
        jsonEncode(resolved.toJson())) {
      return snapshot;
    }
    return snapshot.copyWith(multiAgent: resolved);
  }

  SettingsSnapshot sanitizeFeatureFlagSettingsInternal(
    SettingsSnapshot snapshot,
  ) {
    final features = featuresFor(hostUiFeaturePlatformInternal);
    final allowedNavigation =
        normalizeAssistantNavigationDestinations(
              snapshot.assistantNavigationDestinations,
            )
            .where((entry) {
              final destination = entry.destination;
              if (destination != null) {
                return features.allowedDestinations.contains(destination);
              }
              return features.allowedDestinations.contains(
                WorkspaceDestination.settings,
              );
            })
            .toList(growable: false);
    final sanitizedExecutionTarget = features.sanitizeExecutionTarget(
      snapshot.assistantExecutionTarget,
    );
    final multiAgentConfig = features.supportsMultiAgent
        ? snapshot.multiAgent
        : snapshot.multiAgent.copyWith(enabled: false);
    final experimentalCanvas =
        features.allowsExperimentalSetting(
          UiFeatureKeys.settingsExperimentalCanvas,
        )
        ? snapshot.experimentalCanvas
        : false;
    final experimentalBridge =
        features.allowsExperimentalSetting(
          UiFeatureKeys.settingsExperimentalBridge,
        )
        ? snapshot.experimentalBridge
        : false;
    final experimentalDebug =
        features.allowsExperimentalSetting(
          UiFeatureKeys.settingsExperimentalDebug,
        )
        ? snapshot.experimentalDebug
        : false;
    return snapshot.copyWith(
      assistantExecutionTarget: sanitizedExecutionTarget,
      assistantNavigationDestinations: allowedNavigation,
      multiAgent: multiAgentConfig,
      experimentalCanvas: experimentalCanvas,
      experimentalBridge: experimentalBridge,
      experimentalDebug: experimentalDebug,
    );
  }

  SettingsSnapshot sanitizeOllamaCloudSettingsInternal(
    SettingsSnapshot snapshot,
  ) {
    final rawBaseUrl = snapshot.ollamaCloud.baseUrl.trim();
    final normalized = rawBaseUrl.endsWith('/')
        ? rawBaseUrl.substring(0, rawBaseUrl.length - 1)
        : rawBaseUrl;
    if (normalized != 'https://ollama.svc.plus') {
      return snapshot;
    }
    return snapshot.copyWith(
      ollamaCloud: snapshot.ollamaCloud.copyWith(baseUrl: 'https://ollama.com'),
    );
  }

  SettingsTab sanitizeSettingsTabInternal(SettingsTab tab) {
    return featuresFor(hostUiFeaturePlatformInternal).sanitizeSettingsTab(tab);
  }

  AssistantExecutionTarget sanitizeExecutionTargetInternal(
    AssistantExecutionTarget? target,
  ) {
    return featuresFor(
      hostUiFeaturePlatformInternal,
    ).sanitizeExecutionTarget(target);
  }

  MultiAgentConfig resolveMultiAgentConfigInternal(SettingsSnapshot snapshot) {
    final defaults = MultiAgentConfig.defaults();
    final current = snapshot.multiAgent;
    final ollamaEndpoint = snapshot.ollamaLocal.endpoint.trim().isEmpty
        ? current.ollamaEndpoint
        : snapshot.ollamaLocal.endpoint.trim();
    final engineerModel = current.engineer.model.trim().isNotEmpty
        ? current.engineer.model.trim()
        : snapshot.ollamaLocal.defaultModel.trim().isNotEmpty
        ? snapshot.ollamaLocal.defaultModel.trim()
        : defaults.engineer.model;
    final architectModel = current.architect.model.trim().isNotEmpty
        ? current.architect.model.trim()
        : defaults.architect.model;
    final testerModel = current.tester.model.trim().isNotEmpty
        ? current.tester.model.trim()
        : defaults.tester.model;
    return current.copyWith(
      framework: current.arisEnabled
          ? MultiAgentFramework.aris
          : current.framework,
      arisEnabled:
          current.framework == MultiAgentFramework.aris || current.arisEnabled,
      ollamaEndpoint: ollamaEndpoint,
      architect: current.architect.copyWith(model: architectModel),
      engineer: current.engineer.copyWith(model: engineerModel),
      tester: current.tester.copyWith(model: testerModel),
      mountTargets: current.mountTargets.isEmpty
          ? MultiAgentConfig.defaults().mountTargets
          : current.mountTargets,
    );
  }

  void appendAssistantThreadMessageInternal(
    String sessionKey,
    GatewayChatMessage message,
  ) {
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    final next = List<GatewayChatMessage>.from(
      assistantThreadMessagesInternal[key] ?? const <GatewayChatMessage>[],
    )..add(message);
    assistantThreadMessagesInternal[key] = next;
    upsertTaskThreadInternal(
      key,
      messages: next,
      updatedAtMs:
          message.timestampMs ??
          DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    notifyIfActiveInternal();
  }

  Future<void> flushAssistantThreadPersistenceInternal() async {
    await assistantThreadPersistQueueInternal.catchError((_) {});
  }

  void appendLocalSessionMessageInternal(
    String sessionKey,
    GatewayChatMessage message, {
    bool persistInThreadContext = false,
  }) {
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    final next = List<GatewayChatMessage>.from(
      localSessionMessagesInternal[key] ?? const <GatewayChatMessage>[],
    )..add(message);
    localSessionMessagesInternal[key] = next;
    if (persistInThreadContext) {
      final threadMessages = List<GatewayChatMessage>.from(
        assistantThreadRecordsInternal[key]?.messages ??
            const <GatewayChatMessage>[],
      )..add(message);
      upsertTaskThreadInternal(
        key,
        messages: threadMessages,
        updatedAtMs:
            message.timestampMs ??
            DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
    }
    notifyIfActiveInternal();
  }

  void preserveGatewayHistoryForSessionInternal(String sessionKey) {
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    if (chatControllerInternal.messages.isEmpty) {
      return;
    }
    gatewayHistoryCacheInternal[key] = List<GatewayChatMessage>.from(
      chatControllerInternal.messages,
    );
  }

  List<GatewaySessionSummary> assistantSessionSummariesInternal() {
    final archivedKeys = settings.assistantArchivedTaskKeys
        .map(normalizedAssistantSessionKeyInternal)
        .toSet();
    final items = <GatewaySessionSummary>[];

    for (final record in assistantThreadRecordsInternal.values) {
      final sessionKey = normalizedAssistantSessionKeyInternal(
        record.sessionKey,
      );
      if (archivedKeys.contains(sessionKey) || record.archived) {
        continue;
      }
      items.add(assistantSessionSummaryForInternal(sessionKey, record: record));
    }

    final currentSessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    final hasCurrent = items.any(
      (item) => matchesSessionKey(item.key, currentSessionKey),
    );
    if (!hasCurrent && !archivedKeys.contains(currentSessionKey)) {
      items.add(assistantSessionSummaryForInternal(currentSessionKey));
    }

    items.sort((left, right) {
      return (right.updatedAtMs ?? 0).compareTo(left.updatedAtMs ?? 0);
    });
    return items;
  }

  GatewaySessionSummary assistantSessionSummaryForInternal(
    String sessionKey, {
    TaskThread? record,
  }) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final resolvedRecord =
        record ?? assistantThreadRecordsInternal[normalizedSessionKey];
    final messages =
        resolvedRecord?.messages ??
        assistantThreadMessagesInternal[normalizedSessionKey] ??
        const <GatewayChatMessage>[];
    final preview = assistantThreadPreviewInternal(messages);
    final title = assistantCustomTaskTitle(normalizedSessionKey);
    final lastMessage = messages.isNotEmpty ? messages.last : null;
    final updatedAtMs =
        resolvedRecord?.updatedAtMs ??
        lastMessage?.timestampMs ??
        DateTime.now().millisecondsSinceEpoch.toDouble();
    return GatewaySessionSummary(
      key: normalizedSessionKey,
      kind: 'assistant',
      displayName: title.isEmpty ? null : title,
      surface: 'Assistant',
      subject: preview,
      room: null,
      space: null,
      updatedAtMs: updatedAtMs,
      sessionId: normalizedSessionKey,
      systemSent: false,
      abortedLastRun: lastMessage?.error == true,
      thinkingLevel: null,
      verboseLevel: null,
      inputTokens: null,
      outputTokens: null,
      totalTokens: null,
      model: assistantModelForSession(normalizedSessionKey),
      contextTokens: null,
      derivedTitle: title.isEmpty ? null : title,
      lastMessagePreview: preview,
    );
  }

  String? assistantThreadPreviewInternal(List<GatewayChatMessage> messages) {
    for (final message in messages.reversed) {
      final role = message.role.trim().toLowerCase();
      if (role != 'user' && role != 'assistant') {
        continue;
      }
      final text = message.text.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  String gatewayEntryStateForTargetInternal(AssistantExecutionTarget target) {
    return target.promptValue;
  }

  Future<List<AssistantThreadSkillEntry>> scanSingleAgentSkillEntriesInternal(
    List<SingleAgentSkillScanRootInternal> roots, {
    String workspaceRef = '',
  }) async {
    final dedupedByName = <String, AssistantThreadSkillEntry>{};
    for (final rootSpec in roots) {
      var resolvedRootPath = resolveSingleAgentSkillRootPathInternal(
        rootSpec.path,
        workspaceRef: workspaceRef,
      );
      if (resolvedRootPath.isEmpty) {
        continue;
      }
      SkillDirectoryAccessHandle? accessHandle;
      try {
        if (rootSpec.bookmark.trim().isNotEmpty) {
          accessHandle = await skillDirectoryAccessServiceInternal
              .openDirectory(
                AuthorizedSkillDirectory(
                  path: resolvedRootPath,
                  bookmark: rootSpec.bookmark,
                ),
              );
          if (accessHandle == null) {
            continue;
          }
          resolvedRootPath = normalizeAuthorizedSkillDirectoryPath(
            accessHandle.path,
          );
        }
        final root = Directory(resolvedRootPath);
        if (!await root.exists()) {
          continue;
        }
        final skillFiles = await collectSkillFilesFromDirectoryInternal(root);
        for (final entity in skillFiles) {
          final entry = await skillEntryFromFileInternal(
            entity,
            rootSpec,
            resolvedRootPath,
          );
          final normalizedName = entry.label.trim().toLowerCase();
          if (normalizedName.isEmpty) {
            continue;
          }
          dedupedByName[normalizedName] = entry;
        }
      } catch (_) {
        continue;
      } finally {
        await accessHandle?.close();
      }
    }
    final entries = dedupedByName.values.toList(growable: false);
    entries.sort((left, right) => left.label.compareTo(right.label));
    return entries;
  }

  Future<List<File>> collectSkillFilesFromDirectoryInternal(
    Directory root,
  ) async {
    final skillFiles = <File>[];
    final visitedDirectories = <String>{};

    Future<void> visitDirectory(Directory directory) async {
      final directoryKey = await directoryScanKeyInternal(directory);
      if (!visitedDirectories.add(directoryKey)) {
        return;
      }
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File) {
          if (entity.uri.pathSegments.last == 'SKILL.md') {
            skillFiles.add(entity);
          }
          continue;
        }
        if (entity is Directory) {
          await visitDirectory(entity);
          continue;
        }
        if (entity is! Link) {
          continue;
        }
        final resolvedType = await FileSystemEntity.type(
          entity.path,
          followLinks: true,
        );
        if (resolvedType == FileSystemEntityType.file) {
          if (entity.uri.pathSegments.last == 'SKILL.md') {
            skillFiles.add(File(entity.path));
          }
          continue;
        }
        if (resolvedType == FileSystemEntityType.directory) {
          await visitDirectory(Directory(entity.path));
        }
      }
    }

    await visitDirectory(root);
    return skillFiles;
  }

  Future<String> directoryScanKeyInternal(Directory directory) async {
    try {
      return await directory.resolveSymbolicLinks();
    } catch (_) {
      return directory.absolute.path;
    }
  }

  Future<List<AssistantThreadSkillEntry>>
  scanSingleAgentSharedSkillEntriesInternal() {
    return scanSingleAgentSkillEntriesInternal(
      singleAgentSharedSkillScanRootsInternal,
    );
  }

  Future<List<AssistantThreadSkillEntry>>
  scanSingleAgentWorkspaceSkillEntriesInternal(String sessionKey) {
    if (assistantWorkspaceKindForSession(sessionKey) !=
        WorkspaceRefKind.localPath) {
      return Future<List<AssistantThreadSkillEntry>>.value(
        const <AssistantThreadSkillEntry>[],
      );
    }
    return scanSingleAgentSkillEntriesInternal(
      AppController.defaultSingleAgentWorkspaceSkillScanRootsInternal,
      workspaceRef: assistantWorkspacePathForSession(sessionKey),
    );
  }

  SingleAgentSkillScanRootInternal
  singleAgentSharedSkillScanRootFromOverrideInternal(String rawPath) {
    final normalizedPath = rawPath.trim();
    final lowered = normalizedPath.toLowerCase();
    return SingleAgentSkillScanRootInternal(
      path: normalizedPath,
      source: sourceForSkillRootPathInternal(lowered),
      scope: normalizedPath.startsWith('/etc/') ? 'system' : 'user',
    );
  }

  SingleAgentSkillScanRootInternal
  singleAgentSharedSkillScanRootFromAuthorizedDirectoryInternal(
    AuthorizedSkillDirectory directory,
  ) {
    final normalizedPath = normalizeAuthorizedSkillDirectoryPath(
      directory.path,
    );
    final lowered = normalizedPath.toLowerCase();
    return SingleAgentSkillScanRootInternal(
      path: normalizedPath,
      source: sourceForSkillRootPathInternal(lowered),
      scope: normalizedPath.startsWith('/etc/') ? 'system' : 'user',
      bookmark: directory.bookmark,
    );
  }

  String resolveSingleAgentSkillRootPathInternal(
    String rawPath, {
    String workspaceRef = '',
  }) {
    final trimmed = rawPath.trim().replaceFirst(RegExp(r'^\./'), '');
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('/')) {
      return trimmed;
    }
    if (trimmed.startsWith('~/')) {
      final home = resolvedUserHomeDirectoryInternal.trim();
      return home.isEmpty ? trimmed : '$home/${trimmed.substring(2)}';
    }
    final normalizedWorkspace = workspaceRef.trim();
    if (normalizedWorkspace.isEmpty) {
      return '';
    }
    final base = normalizedWorkspace.endsWith('/')
        ? normalizedWorkspace.substring(0, normalizedWorkspace.length - 1)
        : normalizedWorkspace;
    return '$base/$trimmed';
  }

  String sourceForSkillRootPathInternal(String path) {
    if (path == '/etc/skills' || path.startsWith('/etc/skills/')) {
      return 'system';
    }
    if (path == '~/.agents/skills' || path.endsWith('/.agents/skills')) {
      return 'agents';
    }
    if (path == '~/.codex/skills' || path.endsWith('/.codex/skills')) {
      return 'codex';
    }
    if (path == '~/.workbuddy/skills' || path.endsWith('/.workbuddy/skills')) {
      return 'workbuddy';
    }
    return 'custom';
  }

  Future<AssistantThreadSkillEntry> skillEntryFromFileInternal(
    File file,
    SingleAgentSkillScanRootInternal root,
    String rootPath,
  ) async {
    final content = await file.readAsString();
    final nameMatch = RegExp(
      "^name:\\s*[\"']?(.+?)[\"']?\\s*\$",
      multiLine: true,
    ).firstMatch(content);
    final descriptionMatch = RegExp(
      "^description:\\s*[\"']?(.+?)[\"']?\\s*\$",
      multiLine: true,
    ).firstMatch(content);
    final directory = file.parent;
    final label =
        (nameMatch?.group(1) ??
                directory.uri.pathSegments
                    .where((item) => item.isNotEmpty)
                    .last)
            .trim();
    final relativeSource = directory.path.startsWith(rootPath)
        ? directory.path
              .substring(rootPath.length)
              .replaceFirst(RegExp(r'^/'), '')
        : directory.path;
    final sourceSegments = <String>[
      root.source,
      if (root.scope != root.source) root.scope,
    ].where((item) => item.trim().isNotEmpty).toList(growable: false);
    final sourceLabel = sourceSegments.join(' · ');
    return AssistantThreadSkillEntry(
      key: directory.path,
      label: label,
      description: (descriptionMatch?.group(1) ?? '').trim(),
      source: root.source,
      sourcePath: file.path,
      scope: root.scope,
      sourceLabel: relativeSource.isEmpty
          ? sourceLabel
          : '$sourceLabel · $relativeSource',
    );
  }

  void restoreAssistantThreadsInternal(List<TaskThread> records) {
    assistantThreadRecordsInternal.clear();
    assistantThreadMessagesInternal.clear();
    singleAgentSharedImportedSkillsInternal =
        const <AssistantThreadSkillEntry>[];
    singleAgentLocalSkillsHydratedInternal = false;
    final archivedKeys = settings.assistantArchivedTaskKeys
        .map(normalizedAssistantSessionKeyInternal)
        .toSet();
    for (final record in records) {
      final sessionKey = normalizedAssistantSessionKeyInternal(
        record.sessionKey,
      );
      if (sessionKey.isEmpty) {
        continue;
      }
      if (!record.workspaceBinding.isComplete) {
        continue;
      }
      final titleFromSettings = assistantCustomTaskTitle(sessionKey);
      final workspaceBinding = record.workspaceBinding.copyWith(
        workspaceId: sessionKey,
        displayPath: record.workspaceKind == WorkspaceKind.localFs
            ? record.workspacePath.trim()
            : (record.displayPath.trim().isEmpty
                  ? record.workspacePath.trim()
                  : record.displayPath.trim()),
      );
      final normalizedRecord = record.copyWith(
        threadId: sessionKey,
        title: titleFromSettings.isEmpty
            ? record.title.trim()
            : titleFromSettings,
        archived: record.archived || archivedKeys.contains(sessionKey),
        executionTarget: record.executionTarget,
        messageViewMode: record.messageViewMode,
        selectedSkillKeys: record.selectedSkillKeys
            .where(
              (item) => record.importedSkills.any((skill) => skill.key == item),
            )
            .toList(growable: false),
        assistantModelId: record.assistantModelId.trim().isEmpty
            ? resolvedAssistantModelForTargetInternal(record.executionTarget)
            : record.assistantModelId.trim(),
        singleAgentProvider: record.singleAgentProvider,
        gatewayEntryState: (record.gatewayEntryState ?? '').trim().isEmpty
            ? gatewayEntryStateForTargetInternal(record.executionTarget)
            : record.gatewayEntryState,
        workspaceBinding: workspaceBinding,
        lifecycleState: record.lifecycleState.copyWith(status: 'ready'),
      );
      if (normalizedRecord.workspaceKind == WorkspaceKind.localFs &&
          normalizedRecord.workspacePath.trim().isNotEmpty) {
        try {
          Directory(normalizedRecord.workspacePath).createSync(recursive: true);
        } catch (_) {
          // Best effort only. The thread should still restore even when the
          // directory cannot be recreated immediately.
        }
      }
      assistantThreadRecordsInternal[sessionKey] = normalizedRecord;
      if (normalizedRecord.messages.isNotEmpty) {
        assistantThreadMessagesInternal[sessionKey] =
            List<GatewayChatMessage>.from(normalizedRecord.messages);
      }
    }
  }
}
