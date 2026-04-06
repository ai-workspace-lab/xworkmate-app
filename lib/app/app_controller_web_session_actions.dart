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
import 'app_controller_web_gateway_config.dart';
import 'app_controller_web_gateway_relay.dart';
import 'app_controller_web_gateway_chat.dart';
import 'app_controller_web_helpers.dart';

extension AppControllerWebSessionActions on AppController {
  Future<void> createConversation({AssistantExecutionTarget? target}) async {
    final requestedTarget =
        sanitizeTargetInternal(target) ??
        assistantExecutionTargetForSession(currentSessionKeyInternal);
    final visibleTargets = visibleAssistantExecutionTargets(const <AssistantExecutionTarget>[
      AssistantExecutionTarget.singleAgent,
      AssistantExecutionTarget.local,
      AssistantExecutionTarget.remote,
    ]);
    final inheritedTarget = visibleTargets.contains(requestedTarget)
        ? requestedTarget
        : (visibleTargets.isNotEmpty ? visibleTargets.first : requestedTarget);
    final inheritedRecord = taskThreadForSessionInternal(currentSessionKeyInternal);
    final baseRecord = newRecordInternal(
      target: inheritedTarget,
      title: appText('新对话', 'New conversation'),
    );
    final record = baseRecord.copyWith(
      messageViewMode:
          inheritedRecord?.messageViewMode ?? AssistantMessageViewMode.rendered,
      executionBinding: baseRecord.executionBinding.copyWith(
        providerId:
            inheritedRecord?.executionBinding.providerId ??
            SingleAgentProvider.auto.providerId,
        executorId:
            inheritedRecord?.executionBinding.executorId ??
            SingleAgentProvider.auto.providerId,
      ),
      assistantModelId: inheritedRecord?.assistantModelId ?? '',
      importedSkills: inheritedRecord?.importedSkills ?? const [],
      selectedSkillKeys: inheritedRecord?.selectedSkillKeys ?? const [],
      gatewayEntryState: gatewayEntryStateForTargetInternal(inheritedTarget),
    );
    threadRepositoryInternal.replace(record);
    await ensureWebTaskThreadBindingInternal(
      record.sessionKey,
      executionTarget: inheritedTarget,
    );
    currentSessionKeyInternal = record.sessionKey;
    lastAssistantErrorInternal = null;
    settingsInternal = settingsInternal.copyWith(
      assistantLastSessionKey: record.sessionKey,
    );
    recomputeDerivedWorkspaceStateInternal();
    await persistSettingsInternal();
    await persistThreadsInternal();
    notifyChangedInternal();
  }

  Future<void> switchConversation(String sessionKey) async {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    if (!threadRecordsInternal.containsKey(normalizedSessionKey)) {
      return;
    }
    final previousSessionKey = normalizedSessionKeyInternal(
      currentSessionKeyInternal,
    );
    if (previousSessionKey == normalizedSessionKey) {
      return;
    }
    if (assistantExecutionTargetForSession(previousSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      streamingTextBySessionInternal.remove(previousSessionKey);
    }
    currentSessionKeyInternal = normalizedSessionKey;
    lastAssistantErrorInternal = null;
    settingsInternal = settingsInternal.copyWith(
      assistantLastSessionKey: normalizedSessionKey,
    );
    await ensureWebTaskThreadBindingInternal(normalizedSessionKey);
    await persistSettingsInternal();
    notifyChangedInternal();
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    await applyAssistantExecutionTargetInternal(
      target,
      sessionKey: normalizedSessionKey,
      persistDefaultSelection: false,
    );
    if (target == AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSessionInternal(normalizedSessionKey);
      return;
    }
    if (target == AssistantExecutionTarget.local ||
        target == AssistantExecutionTarget.remote) {
      await refreshRelayHistory(sessionKey: normalizedSessionKey);
      await refreshRelaySkillsForSession(normalizedSessionKey);
    }
  }

  Future<void> setAssistantExecutionTarget(
    AssistantExecutionTarget target,
  ) async {
    final requestedTarget =
        sanitizeTargetInternal(target) ??
        assistantExecutionTargetForSession(currentSessionKeyInternal);
    final visibleTargets = visibleAssistantExecutionTargets(const <AssistantExecutionTarget>[
      AssistantExecutionTarget.singleAgent,
      AssistantExecutionTarget.local,
      AssistantExecutionTarget.remote,
    ]);
    final resolvedTarget = visibleTargets.contains(requestedTarget)
        ? requestedTarget
        : (visibleTargets.isNotEmpty ? visibleTargets.first : requestedTarget);
    final sessionKey = normalizedSessionKeyInternal(currentSessionKeyInternal);
    upsertThreadRecordInternal(
      sessionKey,
      executionTarget: resolvedTarget,
      executionTargetSource: ThreadSelectionSource.explicit,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      gatewayEntryState: gatewayEntryStateForTargetInternal(resolvedTarget),
    );
    await ensureWebTaskThreadBindingInternal(
      sessionKey,
      executionTarget: resolvedTarget,
    );
    settingsInternal = settingsInternal.copyWith(
      assistantExecutionTarget: resolvedTarget,
    );
    await persistSettingsInternal();
    await persistThreadsInternal();
    notifyChangedInternal();
    await applyAssistantExecutionTargetInternal(
      resolvedTarget,
      sessionKey: sessionKey,
      persistDefaultSelection: true,
    );
    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSessionInternal(sessionKey);
    } else if (resolvedTarget == AssistantExecutionTarget.local ||
        resolvedTarget == AssistantExecutionTarget.remote) {
      await refreshRelaySkillsForSession(sessionKey);
    }
    notifyChangedInternal();
  }

  Future<void> setSingleAgentProvider(SingleAgentProvider provider) async {
    final resolvedProvider = settingsInternal.resolveSingleAgentProvider(
      provider,
    );
    if (!singleAgentProviderOptions.contains(resolvedProvider)) {
      return;
    }
    final sessionKey = normalizedSessionKeyInternal(currentSessionKeyInternal);
    if (singleAgentProviderForSession(sessionKey) == resolvedProvider) {
      return;
    }
    upsertThreadRecordInternal(
      sessionKey,
      singleAgentProvider: resolvedProvider,
      singleAgentProviderSource: ThreadSelectionSource.explicit,
      latestResolvedRuntimeModel: '',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await persistThreadsInternal();
    notifyChangedInternal();
    if (assistantExecutionTargetForSession(sessionKey) ==
        AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSessionInternal(sessionKey);
    }
  }

  Future<void> setAssistantMessageViewMode(
    AssistantMessageViewMode mode,
  ) async {
    final sessionKey = normalizedSessionKeyInternal(currentSessionKeyInternal);
    if (assistantMessageViewModeForSession(sessionKey) == mode) {
      return;
    }
    upsertThreadRecordInternal(
      sessionKey,
      messageViewMode: mode,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await persistThreadsInternal();
    notifyChangedInternal();
  }

  Future<void> selectAssistantModelForSession(
    String sessionKey,
    String modelId,
  ) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    if (assistantModelForSession(normalizedSessionKey) == trimmed) {
      return;
    }
    upsertThreadRecordInternal(
      normalizedSessionKey,
      assistantModelId: trimmed,
      assistantModelSource: ThreadSelectionSource.explicit,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await persistThreadsInternal();
    notifyChangedInternal();
  }

  Future<void> selectAssistantModel(String modelId) async {
    await selectAssistantModelForSession(currentSessionKeyInternal, modelId);
  }

  Future<void> saveAssistantTaskTitle(String sessionKey, String title) async {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    if (!threadRecordsInternal.containsKey(normalizedSessionKey)) {
      return;
    }
    final trimmedTitle = title.trim();
    final nextTitles = Map<String, String>.from(
      settingsInternal.assistantCustomTaskTitles,
    );
    if (trimmedTitle.isEmpty) {
      nextTitles.remove(normalizedSessionKey);
    } else {
      nextTitles[normalizedSessionKey] = trimmedTitle;
    }
    settingsInternal = settingsInternal.copyWith(
      assistantCustomTaskTitles: nextTitles,
    );
    upsertThreadRecordInternal(normalizedSessionKey, title: trimmedTitle);
    await persistSettingsInternal();
    await persistThreadsInternal();
    notifyChangedInternal();
  }

  bool isAssistantTaskArchived(String sessionKey) {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    final archivedKeys = settingsInternal.assistantArchivedTaskKeys
        .map(normalizedSessionKeyInternal)
        .toSet();
    if (archivedKeys.contains(normalizedSessionKey)) {
      return true;
    }
    return threadRecordsInternal[normalizedSessionKey]?.archived ?? false;
  }

  Future<void> saveAssistantTaskArchived(
    String sessionKey,
    bool archived,
  ) async {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    if (!threadRecordsInternal.containsKey(normalizedSessionKey)) {
      return;
    }
    final archivedKeys = settingsInternal.assistantArchivedTaskKeys
        .map(normalizedSessionKeyInternal)
        .toSet();
    if (archived) {
      archivedKeys.add(normalizedSessionKey);
    } else {
      archivedKeys.remove(normalizedSessionKey);
    }
    settingsInternal = settingsInternal.copyWith(
      assistantArchivedTaskKeys: archivedKeys.toList(growable: false),
    );
    upsertThreadRecordInternal(
      normalizedSessionKey,
      archived: archived,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    if (archived && currentSessionKeyInternal == normalizedSessionKey) {
      final fallback = threadRecordsInternal.values
          .where(
            (record) =>
                !record.archived && record.sessionKey != normalizedSessionKey,
          )
          .toList(growable: false);
      if (fallback.isNotEmpty) {
        currentSessionKeyInternal = fallback.first.sessionKey;
      } else {
        final newRecord = newRecordInternal(
          target: settingsInternal.assistantExecutionTarget,
          title: appText('新对话', 'New conversation'),
        );
        threadRepositoryInternal.replace(newRecord);
        currentSessionKeyInternal = newRecord.sessionKey;
      }
    }
    recomputeDerivedWorkspaceStateInternal();
    await persistSettingsInternal();
    await persistThreadsInternal();
    notifyChangedInternal();
  }

  Future<void> toggleAssistantSkillForSession(
    String sessionKey,
    String skillKey,
  ) async {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    final normalizedSkillKey = skillKey.trim();
    if (normalizedSkillKey.isEmpty) {
      return;
    }
    final importedKeys = assistantImportedSkillsForSession(
      normalizedSessionKey,
    ).map((item) => item.key).toSet();
    if (!importedKeys.contains(normalizedSkillKey)) {
      return;
    }
    final selected = assistantSelectedSkillKeysForSession(
      normalizedSessionKey,
    ).toSet();
    if (!selected.add(normalizedSkillKey)) {
      selected.remove(normalizedSkillKey);
    }
    upsertThreadRecordInternal(
      normalizedSessionKey,
      selectedSkillKeys: selected.toList(growable: false),
      selectedSkillsSource: ThreadSelectionSource.explicit,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await persistThreadsInternal();
    notifyChangedInternal();
  }
}
