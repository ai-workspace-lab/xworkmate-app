part of 'app_controller_web.dart';

extension AppControllerWebSessionActions on AppController {
  Future<void> createConversation({AssistantExecutionTarget? target}) async {
    final inheritedTarget =
        _sanitizeTarget(target) ??
        assistantExecutionTargetForSession(_currentSessionKey);
    final inheritedRecord =
        _threadRecords[_normalizedSessionKey(_currentSessionKey)];
    final baseRecord = _newRecord(
      target: inheritedTarget,
      title: appText('新对话', 'New conversation'),
    );
    final record = baseRecord.copyWith(
      messageViewMode:
          inheritedRecord?.messageViewMode ?? AssistantMessageViewMode.rendered,
      singleAgentProvider:
          inheritedRecord?.singleAgentProvider ?? SingleAgentProvider.auto,
      assistantModelId: inheritedRecord?.assistantModelId ?? '',
      importedSkills: inheritedRecord?.importedSkills ?? const [],
      selectedSkillKeys: inheritedRecord?.selectedSkillKeys ?? const [],
      gatewayEntryState: _gatewayEntryStateForTarget(inheritedTarget),
      workspaceRef: inheritedRecord?.workspaceRef.trim().isNotEmpty == true
          ? inheritedRecord!.workspaceRef
          : _defaultWorkspaceRefForSession(baseRecord.sessionKey),
      workspaceRefKind:
          inheritedRecord?.workspaceRefKind ?? WorkspaceRefKind.objectStore,
    );
    _threadRecords[record.sessionKey] = record;
    _currentSessionKey = record.sessionKey;
    _lastAssistantError = null;
    _settings = _settings.copyWith(assistantLastSessionKey: record.sessionKey);
    _recomputeDerivedWorkspaceState();
    await _persistSettings();
    await _persistThreads();
    _notifyChanged();
  }

  Future<void> switchConversation(String sessionKey) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    if (!_threadRecords.containsKey(normalizedSessionKey)) {
      return;
    }
    final previousSessionKey = _normalizedSessionKey(_currentSessionKey);
    if (previousSessionKey == normalizedSessionKey) {
      return;
    }
    if (assistantExecutionTargetForSession(previousSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      _streamingTextBySession.remove(previousSessionKey);
    }
    _currentSessionKey = normalizedSessionKey;
    _lastAssistantError = null;
    _settings = _settings.copyWith(
      assistantLastSessionKey: normalizedSessionKey,
    );
    _syncThreadWorkspaceRef(normalizedSessionKey);
    await _persistSettings();
    _notifyChanged();
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    await _applyAssistantExecutionTarget(
      target,
      sessionKey: normalizedSessionKey,
      persistDefaultSelection: false,
    );
    if (target == AssistantExecutionTarget.singleAgent) {
      await _refreshSingleAgentSkillsForSession(normalizedSessionKey);
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
    final resolvedTarget =
        _sanitizeTarget(target) ??
        assistantExecutionTargetForSession(_currentSessionKey);
    final sessionKey = _normalizedSessionKey(_currentSessionKey);
    _upsertThreadRecord(
      sessionKey,
      executionTarget: resolvedTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      gatewayEntryState: _gatewayEntryStateForTarget(resolvedTarget),
      workspaceRef: _defaultWorkspaceRefForSession(sessionKey),
      workspaceRefKind: WorkspaceRefKind.objectStore,
    );
    _settings = _settings.copyWith(assistantExecutionTarget: resolvedTarget);
    await _persistSettings();
    await _persistThreads();
    _notifyChanged();
    await _applyAssistantExecutionTarget(
      resolvedTarget,
      sessionKey: sessionKey,
      persistDefaultSelection: true,
    );
    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      await _refreshSingleAgentSkillsForSession(sessionKey);
    } else if (resolvedTarget == AssistantExecutionTarget.local ||
        resolvedTarget == AssistantExecutionTarget.remote) {
      await refreshRelaySkillsForSession(sessionKey);
    }
    _notifyChanged();
  }

  Future<void> setSingleAgentProvider(SingleAgentProvider provider) async {
    final resolvedProvider = _settings.resolveSingleAgentProvider(provider);
    if (!singleAgentProviderOptions.contains(resolvedProvider)) {
      return;
    }
    final sessionKey = _normalizedSessionKey(_currentSessionKey);
    if (singleAgentProviderForSession(sessionKey) == resolvedProvider) {
      return;
    }
    _singleAgentRuntimeModelBySession.remove(sessionKey);
    _upsertThreadRecord(
      sessionKey,
      singleAgentProvider: resolvedProvider,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _persistThreads();
    _notifyChanged();
    if (assistantExecutionTargetForSession(sessionKey) ==
        AssistantExecutionTarget.singleAgent) {
      await _refreshSingleAgentSkillsForSession(sessionKey);
    }
  }

  Future<void> setAssistantMessageViewMode(
    AssistantMessageViewMode mode,
  ) async {
    final sessionKey = _normalizedSessionKey(_currentSessionKey);
    if (assistantMessageViewModeForSession(sessionKey) == mode) {
      return;
    }
    _upsertThreadRecord(
      sessionKey,
      messageViewMode: mode,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _persistThreads();
    _notifyChanged();
  }

  Future<void> selectAssistantModelForSession(
    String sessionKey,
    String modelId,
  ) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    if (assistantModelForSession(normalizedSessionKey) == trimmed) {
      return;
    }
    _upsertThreadRecord(
      normalizedSessionKey,
      assistantModelId: trimmed,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _persistThreads();
    _notifyChanged();
  }

  Future<void> selectAssistantModel(String modelId) async {
    await selectAssistantModelForSession(_currentSessionKey, modelId);
  }

  Future<void> saveAssistantTaskTitle(String sessionKey, String title) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    if (!_threadRecords.containsKey(normalizedSessionKey)) {
      return;
    }
    final trimmedTitle = title.trim();
    final nextTitles = Map<String, String>.from(
      _settings.assistantCustomTaskTitles,
    );
    if (trimmedTitle.isEmpty) {
      nextTitles.remove(normalizedSessionKey);
    } else {
      nextTitles[normalizedSessionKey] = trimmedTitle;
    }
    _settings = _settings.copyWith(assistantCustomTaskTitles: nextTitles);
    _upsertThreadRecord(normalizedSessionKey, title: trimmedTitle);
    await _persistSettings();
    await _persistThreads();
    _notifyChanged();
  }

  bool isAssistantTaskArchived(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final archivedKeys = _settings.assistantArchivedTaskKeys
        .map(_normalizedSessionKey)
        .toSet();
    if (archivedKeys.contains(normalizedSessionKey)) {
      return true;
    }
    return _threadRecords[normalizedSessionKey]?.archived ?? false;
  }

  Future<void> saveAssistantTaskArchived(
    String sessionKey,
    bool archived,
  ) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    if (!_threadRecords.containsKey(normalizedSessionKey)) {
      return;
    }
    final archivedKeys = _settings.assistantArchivedTaskKeys
        .map(_normalizedSessionKey)
        .toSet();
    if (archived) {
      archivedKeys.add(normalizedSessionKey);
    } else {
      archivedKeys.remove(normalizedSessionKey);
    }
    _settings = _settings.copyWith(
      assistantArchivedTaskKeys: archivedKeys.toList(growable: false),
    );
    _upsertThreadRecord(
      normalizedSessionKey,
      archived: archived,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    if (archived && _currentSessionKey == normalizedSessionKey) {
      final fallback = _threadRecords.values
          .where(
            (record) =>
                !record.archived && record.sessionKey != normalizedSessionKey,
          )
          .toList(growable: false);
      if (fallback.isNotEmpty) {
        _currentSessionKey = fallback.first.sessionKey;
      } else {
        final newRecord = _newRecord(
          target: _settings.assistantExecutionTarget,
          title: appText('新对话', 'New conversation'),
        );
        _threadRecords[newRecord.sessionKey] = newRecord;
        _currentSessionKey = newRecord.sessionKey;
      }
    }
    _recomputeDerivedWorkspaceState();
    await _persistSettings();
    await _persistThreads();
    _notifyChanged();
  }

  Future<void> toggleAssistantSkillForSession(
    String sessionKey,
    String skillKey,
  ) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
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
    _upsertThreadRecord(
      normalizedSessionKey,
      selectedSkillKeys: selected.toList(growable: false),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _persistThreads();
    _notifyChanged();
  }
}
