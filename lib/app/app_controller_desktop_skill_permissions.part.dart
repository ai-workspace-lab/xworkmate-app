part of 'app_controller_desktop.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopSkillPermissions on AppController {
  Future<void> _refreshSharedSingleAgentLocalSkillsCache({
    required bool forceRescan,
  }) async {
    if (!forceRescan && _singleAgentLocalSkillsHydrated) {
      return;
    }
    if (!forceRescan && await _restoreSharedSingleAgentLocalSkillsCache()) {
      return;
    }
    final existingRefresh = _singleAgentSharedSkillsRefreshInFlight;
    if (existingRefresh != null) {
      await existingRefresh;
      if (!forceRescan) {
        return;
      }
    }
    late final Future<void> refreshFuture;
    refreshFuture = () async {
      final sharedSkills = await _scanSingleAgentSharedSkillEntries();
      _singleAgentSharedImportedSkills = sharedSkills;
      _singleAgentLocalSkillsHydrated = true;
      await _persistSharedSingleAgentLocalSkillsCache();
    }();
    _singleAgentSharedSkillsRefreshInFlight = refreshFuture;
    try {
      await refreshFuture;
    } finally {
      if (identical(_singleAgentSharedSkillsRefreshInFlight, refreshFuture)) {
        _singleAgentSharedSkillsRefreshInFlight = null;
      }
    }
  }

  Future<void> ensureSharedSingleAgentLocalSkillsLoaded() async {
    if (_singleAgentLocalSkillsHydrated) {
      return;
    }
    await _refreshSharedSingleAgentLocalSkillsCache(forceRescan: false);
  }

  Future<void> _startupRefreshSharedSingleAgentLocalSkillsCache() async {
    await _refreshSharedSingleAgentLocalSkillsCache(forceRescan: true);
    if (_disposed) {
      return;
    }
    if (assistantExecutionTargetForSession(currentSessionKey) ==
        AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(currentSessionKey);
      return;
    }
    _notifyIfActive();
  }

  Future<List<AssistantThreadSkillEntry>> _singleAgentLocalSkillsForSession(
    String sessionKey,
  ) async {
    final workspaceSkills = await _scanSingleAgentWorkspaceSkillEntries(
      sessionKey,
    );
    return _mergeSingleAgentSkillEntries(
      groups: <List<AssistantThreadSkillEntry>>[
        _singleAgentSharedImportedSkills,
        workspaceSkills,
      ],
    );
  }

  List<AssistantThreadSkillEntry> _mergeSingleAgentSkillEntries({
    required List<List<AssistantThreadSkillEntry>> groups,
  }) {
    final merged = <String, AssistantThreadSkillEntry>{};
    for (final group in groups) {
      for (final skill in group) {
        final normalizedName = skill.label.trim().toLowerCase();
        if (normalizedName.isEmpty || merged.containsKey(normalizedName)) {
          continue;
        }
        merged[normalizedName] = skill;
      }
    }
    final entries = merged.values.toList(growable: false);
    entries.sort((left, right) => left.label.compareTo(right.label));
    return entries;
  }

  Future<bool> _restoreSharedSingleAgentLocalSkillsCache() async {
    try {
      final payload = await _store.loadSupportJson(
        _singleAgentLocalSkillsCacheRelativePath,
      );
      if (payload == null) {
        return false;
      }
      final schemaVersion = int.tryParse(
        payload['schemaVersion']?.toString() ?? '',
      );
      if (schemaVersion != _singleAgentLocalSkillsCacheSchemaVersion) {
        return false;
      }
      final skills = asList(payload['skills'])
          .map(asMap)
          .map(
            (item) => AssistantThreadSkillEntry.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .where((item) => item.key.trim().isNotEmpty && item.label.isNotEmpty)
          .toList(growable: false);
      if (skills.isEmpty) {
        _singleAgentSharedImportedSkills = const <AssistantThreadSkillEntry>[];
        _singleAgentLocalSkillsHydrated = false;
        return false;
      }
      _singleAgentSharedImportedSkills = skills;
      _singleAgentLocalSkillsHydrated = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistSharedSingleAgentLocalSkillsCache() async {
    try {
      await _store.saveSupportJson(
        _singleAgentLocalSkillsCacheRelativePath,
        <String, dynamic>{
          'schemaVersion': _singleAgentLocalSkillsCacheSchemaVersion,
          'savedAtMs': DateTime.now().millisecondsSinceEpoch.toDouble(),
          'skills': _singleAgentSharedImportedSkills
              .map((item) => item.toJson())
              .toList(growable: false),
        },
      );
    } catch (_) {
      // Best effort only for local cache persistence.
    }
  }

  Future<void> _replaceSingleAgentThreadSkills(
    String sessionKey,
    List<AssistantThreadSkillEntry> importedSkills,
  ) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final importedKeys = importedSkills.map((item) => item.key).toSet();
    final nextSelected =
        (_assistantThreadRecords[normalizedSessionKey]?.selectedSkillKeys ??
                const <String>[])
            .where(importedKeys.contains)
            .toList(growable: false);
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      importedSkills: importedSkills,
      selectedSkillKeys: nextSelected,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _notifyIfActive();
  }

  AssistantThreadSkillEntry _singleAgentSkillEntryFromAcp(
    Map<String, dynamic> item,
    SingleAgentProvider provider,
  ) {
    return AssistantThreadSkillEntry(
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
      sourceLabel: item['sourceLabel']?.toString().trim().isNotEmpty == true
          ? item['sourceLabel'].toString().trim()
          : (item['source']?.toString().trim().isNotEmpty == true
                ? item['source'].toString().trim()
                : provider.label),
    );
  }

  bool _unsupportedAcpSkillsStatus(GatewayAcpException error) {
    final code = (error.code ?? '').trim();
    if (code == '-32601' || code == 'METHOD_NOT_FOUND') {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('unknown method') ||
        message.contains('method not found') ||
        message.contains('skills.status');
  }

  void _upsertAssistantThreadRecord(
    String sessionKey, {
    List<GatewayChatMessage>? messages,
    double? updatedAtMs,
    String? title,
    bool? archived,
    AssistantExecutionTarget? executionTarget,
    AssistantMessageViewMode? messageViewMode,
    List<AssistantThreadSkillEntry>? importedSkills,
    List<String>? selectedSkillKeys,
    String? assistantModelId,
    SingleAgentProvider? singleAgentProvider,
    String? gatewayEntryState,
    String? workspaceRef,
    WorkspaceRefKind? workspaceRefKind,
  }) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final existing = _assistantThreadRecords[normalizedSessionKey];
    final nextExecutionTarget =
        executionTarget ??
        existing?.executionTarget ??
        settings.assistantExecutionTarget;
    final nextImportedSkills =
        importedSkills ??
        existing?.importedSkills ??
        const <AssistantThreadSkillEntry>[];
    final importedKeys = nextImportedSkills.map((item) => item.key).toSet();
    final nextSelectedSkillKeys =
        (selectedSkillKeys ?? existing?.selectedSkillKeys ?? const <String>[])
            .where(importedKeys.contains)
            .toList(growable: false);
    final nextMessages =
        messages ??
        existing?.messages ??
        _assistantThreadMessages[normalizedSessionKey] ??
        const <GatewayChatMessage>[];
    final nextRecord = AssistantThreadRecord(
      sessionKey: normalizedSessionKey,
      messages: nextMessages,
      updatedAtMs:
          updatedAtMs ??
          existing?.updatedAtMs ??
          (nextMessages.isNotEmpty ? nextMessages.last.timestampMs : null),
      title: title ?? existing?.title ?? '',
      archived:
          archived ??
          existing?.archived ??
          isAssistantTaskArchived(normalizedSessionKey),
      executionTarget: nextExecutionTarget,
      messageViewMode:
          messageViewMode ??
          existing?.messageViewMode ??
          AssistantMessageViewMode.rendered,
      importedSkills: nextImportedSkills,
      selectedSkillKeys: nextSelectedSkillKeys,
      assistantModelId:
          assistantModelId ??
          existing?.assistantModelId ??
          _resolvedAssistantModelForTarget(nextExecutionTarget),
      singleAgentProvider:
          singleAgentProvider ??
          existing?.singleAgentProvider ??
          SingleAgentProvider.auto,
      gatewayEntryState:
          gatewayEntryState ??
          existing?.gatewayEntryState ??
          _gatewayEntryStateForTarget(nextExecutionTarget),
      workspaceRef:
          workspaceRef ??
          existing?.workspaceRef ??
          _defaultWorkspaceRefForSession(normalizedSessionKey),
      workspaceRefKind:
          workspaceRefKind ??
          existing?.workspaceRefKind ??
          _defaultWorkspaceRefKindForTarget(nextExecutionTarget),
    );
    _assistantThreadRecords[normalizedSessionKey] = nextRecord;
    if (messages != null) {
      _assistantThreadMessages[normalizedSessionKey] =
          List<GatewayChatMessage>.from(messages);
    }
    final snapshot = _assistantThreadRecords.values.toList(growable: false);
    final nextPersist = _assistantThreadPersistQueue.catchError((_) {}).then((
      _,
    ) async {
      if (_disposed) {
        return;
      }
      try {
        await _store.saveAssistantThreadRecords(snapshot);
      } catch (_) {
        // Assistant thread persistence is background best-effort. Keep the
        // in-memory session usable even when teardown or temp-directory
        // cleanup races with the durable write.
      }
    });
    _assistantThreadPersistQueue = nextPersist;
    unawaited(nextPersist);
  }

  Future<void> _setCurrentAssistantSessionKey(
    String sessionKey, {
    bool persistSelection = true,
  }) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (normalizedSessionKey.isEmpty) {
      return;
    }
    await _sessionsController.switchSession(normalizedSessionKey);
    if (persistSelection) {
      await _persistAssistantLastSessionKey(normalizedSessionKey);
    }
  }
}
