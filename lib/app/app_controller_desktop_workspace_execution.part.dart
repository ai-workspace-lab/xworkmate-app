part of 'app_controller_desktop.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopWorkspaceExecution on AppController {
  Future<void> setAssistantExecutionTarget(
    AssistantExecutionTarget target,
  ) async {
    final resolvedTarget = _sanitizeExecutionTarget(target);
    final currentTarget = assistantExecutionTargetForSession(
      _sessionsController.currentSessionKey,
    );
    if (currentTarget == resolvedTarget &&
        settings.assistantExecutionTarget == resolvedTarget) {
      return;
    }
    _upsertAssistantThreadRecord(
      _sessionsController.currentSessionKey,
      executionTarget: resolvedTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _syncAssistantWorkspaceRefForSession(
      _sessionsController.currentSessionKey,
      executionTarget: resolvedTarget,
    );
    _recomputeTasks();
    _notifyIfActive();
    await _applyAssistantExecutionTarget(
      resolvedTarget,
      sessionKey: _sessionsController.currentSessionKey,
      persistDefaultSelection: true,
    );
    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(
        _sessionsController.currentSessionKey,
      );
    }
    _recomputeTasks();
    _notifyIfActive();
  }

  Future<void> setSingleAgentProvider(SingleAgentProvider provider) async {
    final sessionKey = _normalizedAssistantSessionKey(currentSessionKey);
    final sanitizedProvider = settings.resolveSingleAgentProvider(provider);
    if (singleAgentProviderForSession(sessionKey) == sanitizedProvider) {
      return;
    }
    _singleAgentRuntimeModelBySession.remove(sessionKey);
    _upsertAssistantThreadRecord(
      sessionKey,
      singleAgentProvider: sanitizedProvider,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _recomputeTasks();
    _notifyIfActive();
    if (assistantExecutionTargetForSession(sessionKey) ==
        AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(sessionKey);
    }
    unawaited(refreshMultiAgentMounts(sync: settings.multiAgent.autoSync));
  }

  Future<void> setAssistantMessageViewMode(
    AssistantMessageViewMode mode,
  ) async {
    final sessionKey = _normalizedAssistantSessionKey(
      _sessionsController.currentSessionKey,
    );
    if (assistantMessageViewModeForSession(sessionKey) == mode) {
      return;
    }
    _upsertAssistantThreadRecord(
      sessionKey,
      messageViewMode: mode,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _flushAssistantThreadPersistence();
    _recomputeTasks();
    _notifyIfActive();
  }

  Future<void> setAssistantPermissionLevel(
    AssistantPermissionLevel level,
  ) async {
    if (settings.assistantPermissionLevel == level) {
      return;
    }
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(assistantPermissionLevel: level),
      refreshAfterSave: false,
    );
  }

  Future<void> _applyAssistantExecutionTarget(
    AssistantExecutionTarget target, {
    required String sessionKey,
    required bool persistDefaultSelection,
  }) async {
    final resolvedTarget = _sanitizeExecutionTarget(target);
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (resolvedTarget != AssistantExecutionTarget.singleAgent) {
      _singleAgentRuntimeModelBySession.remove(normalizedSessionKey);
    }
    if (!matchesSessionKey(
      normalizedSessionKey,
      _sessionsController.currentSessionKey,
    )) {
      await _setCurrentAssistantSessionKey(normalizedSessionKey);
    }
    if (persistDefaultSelection &&
        settings.assistantExecutionTarget != resolvedTarget) {
      await AppControllerDesktopSettings(this).saveSettings(
        settings.copyWith(assistantExecutionTarget: resolvedTarget),
        refreshAfterSave: false,
      );
    }

    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      if (_runtime.isConnected) {
        _preserveGatewayHistoryForSession(normalizedSessionKey);
      }
      await _ensureActiveAssistantThread();
      if (_runtime.isConnected) {
        try {
          await AppControllerDesktopGateway(this).disconnectGateway();
        } catch (_) {
          // Preserve the selected thread-bound target even when the active
          // gateway session does not close cleanly on the first attempt.
        }
      } else {
        _chatController.clear();
      }
      await _setCurrentAssistantSessionKey(normalizedSessionKey);
      return;
    }

    final targetProfile = _gatewayProfileForAssistantExecutionTarget(
      resolvedTarget,
    );
    try {
      await AppControllerDesktopGateway(this)._connectProfile(
        targetProfile,
        profileIndex: _gatewayProfileIndexForExecutionTarget(resolvedTarget),
      );
    } catch (_) {
      // Keep the selected execution target even when the immediate reconnect
      // fails so the user can retry or adjust gateway settings manually.
    }
    await _setCurrentAssistantSessionKey(normalizedSessionKey);
    await _chatController.loadSession(normalizedSessionKey);
  }

  Future<void> selectDefaultModel(String modelId) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty || settings.defaultModel == trimmed) {
      return;
    }
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(defaultModel: trimmed),
      refreshAfterSave: false,
    );
  }

  Future<void> selectAssistantModel(String modelId) async {
    await selectAssistantModelForSession(currentSessionKey, modelId);
  }

  Future<void> selectAssistantModelForSession(
    String sessionKey,
    String modelId,
  ) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final choices = matchesSessionKey(normalizedSessionKey, currentSessionKey)
        ? assistantModelChoices
        : _assistantModelChoicesForSession(normalizedSessionKey);
    if (choices.isNotEmpty && !choices.contains(trimmed)) {
      return;
    }
    if (_assistantThreadRecords[normalizedSessionKey]?.assistantModelId ==
        trimmed) {
      return;
    }
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      assistantModelId: trimmed,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _recomputeTasks();
    _notifyIfActive();
  }

  String assistantCustomTaskTitle(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final settingsTitle =
        settings.assistantCustomTaskTitles[normalizedSessionKey]?.trim() ?? '';
    if (settingsTitle.isNotEmpty) {
      return settingsTitle;
    }
    return _assistantThreadRecords[normalizedSessionKey]?.title.trim() ?? '';
  }

  void initializeAssistantThreadContext(
    String sessionKey, {
    String title = '',
    AssistantExecutionTarget? executionTarget,
    AssistantMessageViewMode? messageViewMode,
    SingleAgentProvider? singleAgentProvider,
  }) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final resolvedTarget =
        executionTarget ??
        assistantExecutionTargetForSession(currentSessionKey);
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      title: title.trim(),
      executionTarget: resolvedTarget,
      messageViewMode:
          messageViewMode ??
          assistantMessageViewModeForSession(currentSessionKey),
      singleAgentProvider:
          singleAgentProvider ??
          singleAgentProviderForSession(currentSessionKey),
      workspaceRef: _defaultWorkspaceRefForSession(normalizedSessionKey),
      workspaceRefKind: _defaultWorkspaceRefKindForTarget(resolvedTarget),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    unawaited(_persistAssistantLastSessionKey(normalizedSessionKey));
    _notifyIfActive();
  }

  Future<void> refreshSingleAgentSkillsForSession(String sessionKey) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return;
    }
    final localSkills = await _singleAgentLocalSkillsForSession(
      normalizedSessionKey,
    );
    final provider =
        singleAgentResolvedProviderForSession(normalizedSessionKey) ??
        currentSingleAgentResolvedProvider;
    if (provider == null) {
      await _replaceSingleAgentThreadSkills(normalizedSessionKey, localSkills);
      return;
    }
    try {
      await _refreshAcpCapabilities();
      final response = await _gatewayAcpClient.request(
        method: 'skills.status',
        params: <String, dynamic>{
          'sessionId': normalizedSessionKey,
          'threadId': normalizedSessionKey,
          'mode': 'single-agent',
          'provider': provider.providerId,
        },
      );
      final result = asMap(response['result']);
      final payload = result.isNotEmpty ? result : response;
      final skills = asList(payload['skills'])
          .map(asMap)
          .map((item) => _singleAgentSkillEntryFromAcp(item, provider))
          .where((item) => item.key.isNotEmpty && item.label.isNotEmpty)
          .toList(growable: false);
      await _replaceSingleAgentThreadSkills(
        normalizedSessionKey,
        _mergeSingleAgentSkillEntries(
          groups: <List<AssistantThreadSkillEntry>>[localSkills, skills],
        ),
      );
    } on GatewayAcpException catch (error) {
      if (_unsupportedAcpSkillsStatus(error)) {
        await _replaceSingleAgentThreadSkills(
          normalizedSessionKey,
          localSkills,
        );
        return;
      }
      await _replaceSingleAgentThreadSkills(normalizedSessionKey, localSkills);
    } catch (_) {
      await _replaceSingleAgentThreadSkills(normalizedSessionKey, localSkills);
    }
  }

  Future<void> refreshSingleAgentLocalSkillsForSession(
    String sessionKey,
  ) async {
    await _refreshSharedSingleAgentLocalSkillsCache(forceRescan: true);
    await refreshSingleAgentSkillsForSession(sessionKey);
  }

  Future<void> toggleAssistantSkillForSession(
    String sessionKey,
    String skillKey,
  ) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
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
    final nextSelected = List<String>.from(
      assistantSelectedSkillKeysForSession(normalizedSessionKey),
    );
    if (nextSelected.contains(normalizedSkillKey)) {
      nextSelected.remove(normalizedSkillKey);
    } else {
      nextSelected.add(normalizedSkillKey);
    }
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      selectedSkillKeys: nextSelected,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _notifyIfActive();
    await _flushAssistantThreadPersistence();
  }

  Future<void> saveAssistantTaskTitle(String sessionKey, String title) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (normalizedSessionKey.isEmpty) {
      return;
    }
    final normalizedTitle = title.trim();
    final next = Map<String, String>.from(settings.assistantCustomTaskTitles);
    final current = next[normalizedSessionKey]?.trim() ?? '';
    if (normalizedTitle.isEmpty) {
      if (current.isEmpty) {
        return;
      }
      next.remove(normalizedSessionKey);
    } else {
      if (current == normalizedTitle) {
        return;
      }
      next[normalizedSessionKey] = normalizedTitle;
    }
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(assistantCustomTaskTitles: next),
      refreshAfterSave: false,
    );
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      title: normalizedTitle,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _recomputeTasks();
    _notifyIfActive();
  }

  bool isAssistantTaskArchived(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    return settings.assistantArchivedTaskKeys.any(
      (item) => _normalizedAssistantSessionKey(item) == normalizedSessionKey,
    );
  }

  Future<void> saveAssistantTaskArchived(
    String sessionKey,
    bool archived,
  ) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (normalizedSessionKey.isEmpty) {
      return;
    }
    final next = <String>[
      ...settings.assistantArchivedTaskKeys.where(
        (item) => _normalizedAssistantSessionKey(item) != normalizedSessionKey,
      ),
    ];
    if (archived) {
      next.add(normalizedSessionKey);
    }
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(assistantArchivedTaskKeys: next),
      refreshAfterSave: false,
    );
    if (archived) {
      unawaited(
        _enqueueThreadTurn<void>(normalizedSessionKey, () async {
          try {
            await _gatewayAcpClient.closeSession(
              sessionId: normalizedSessionKey,
              threadId: normalizedSessionKey,
            );
          } catch (_) {
            // Best effort only.
          }
        }).catchError((_) {}),
      );
    }
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      archived: archived,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _recomputeTasks();
    _notifyIfActive();
  }
}
