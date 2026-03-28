part of 'app_controller_desktop.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopThreadStorage on AppController {
  Future<void> _applyPersistedAiGatewaySettings(
    SettingsSnapshot snapshot,
  ) async {
    final apiKey = await _settingsController.loadAiGatewayApiKey();
    if (snapshot.aiGateway.baseUrl.trim().isEmpty || apiKey.trim().isEmpty) {
      return;
    }
    try {
      await syncAiGatewayCatalog(snapshot.aiGateway, apiKeyOverride: apiKey);
    } catch (_) {
      // Keep the saved draft applied even if model sync fails immediately.
    }
  }

  Future<void> _ensureActiveAssistantThread() async {
    if (!isSingleAgentMode ||
        !isAssistantTaskArchived(_sessionsController.currentSessionKey)) {
      return;
    }
    final fallback = _assistantSessionSummaries().firstWhere(
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
    await _setCurrentAssistantSessionKey(fallback.key);
  }

  Future<void> _restoreInitialAssistantSessionSelection() async {
    final normalized = _normalizedAssistantSessionKey(
      settings.assistantLastSessionKey,
    );
    final known =
        normalized == 'main' ||
        _assistantThreadRecords.containsKey(normalized) ||
        _assistantThreadMessages.containsKey(normalized);
    if (normalized.isEmpty || !known || isAssistantTaskArchived(normalized)) {
      return;
    }
    await _setCurrentAssistantSessionKey(normalized, persistSelection: false);
  }

  void _handleRuntimeEvent(GatewayPushEvent event) {
    _chatController.handleEvent(event);
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

  SettingsSnapshot _sanitizeMultiAgentSettings(SettingsSnapshot snapshot) {
    final resolved = _resolveMultiAgentConfig(snapshot);
    if (jsonEncode(snapshot.multiAgent.toJson()) ==
        jsonEncode(resolved.toJson())) {
      return snapshot;
    }
    return snapshot.copyWith(multiAgent: resolved);
  }

  SettingsSnapshot _sanitizeFeatureFlagSettings(SettingsSnapshot snapshot) {
    final features = featuresFor(_hostUiFeaturePlatform);
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

  SettingsSnapshot _sanitizeOllamaCloudSettings(SettingsSnapshot snapshot) {
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

  SettingsTab _sanitizeSettingsTab(SettingsTab tab) {
    return featuresFor(_hostUiFeaturePlatform).sanitizeSettingsTab(tab);
  }

  AssistantExecutionTarget _sanitizeExecutionTarget(
    AssistantExecutionTarget? target,
  ) {
    return featuresFor(_hostUiFeaturePlatform).sanitizeExecutionTarget(target);
  }

  MultiAgentConfig _resolveMultiAgentConfig(SettingsSnapshot snapshot) {
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

  void _appendAssistantThreadMessage(
    String sessionKey,
    GatewayChatMessage message,
  ) {
    final key = _normalizedAssistantSessionKey(sessionKey);
    final next = List<GatewayChatMessage>.from(
      _assistantThreadMessages[key] ?? const <GatewayChatMessage>[],
    )..add(message);
    _assistantThreadMessages[key] = next;
    _upsertAssistantThreadRecord(
      key,
      messages: next,
      updatedAtMs:
          message.timestampMs ??
          DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _notifyIfActive();
  }

  Future<void> _flushAssistantThreadPersistence() async {
    await _assistantThreadPersistQueue.catchError((_) {});
  }

  void _appendLocalSessionMessage(
    String sessionKey,
    GatewayChatMessage message,
  ) {
    final key = _normalizedAssistantSessionKey(sessionKey);
    final next = List<GatewayChatMessage>.from(
      _localSessionMessages[key] ?? const <GatewayChatMessage>[],
    )..add(message);
    _localSessionMessages[key] = next;
    _notifyIfActive();
  }

  void _preserveGatewayHistoryForSession(String sessionKey) {
    final key = _normalizedAssistantSessionKey(sessionKey);
    if (_chatController.messages.isEmpty) {
      return;
    }
    _gatewayHistoryCache[key] = List<GatewayChatMessage>.from(
      _chatController.messages,
    );
  }

  List<GatewaySessionSummary> _assistantSessionSummaries() {
    final archivedKeys = settings.assistantArchivedTaskKeys
        .map(_normalizedAssistantSessionKey)
        .toSet();
    final items = <GatewaySessionSummary>[];

    for (final record in _assistantThreadRecords.values) {
      final sessionKey = _normalizedAssistantSessionKey(record.sessionKey);
      if (archivedKeys.contains(sessionKey) || record.archived) {
        continue;
      }
      items.add(_assistantSessionSummaryFor(sessionKey, record: record));
    }

    final currentSessionKey = _normalizedAssistantSessionKey(
      _sessionsController.currentSessionKey,
    );
    final hasCurrent = items.any(
      (item) => matchesSessionKey(item.key, currentSessionKey),
    );
    if (!hasCurrent && !archivedKeys.contains(currentSessionKey)) {
      items.add(_assistantSessionSummaryFor(currentSessionKey));
    }

    items.sort((left, right) {
      return (right.updatedAtMs ?? 0).compareTo(left.updatedAtMs ?? 0);
    });
    return items;
  }

  GatewaySessionSummary _assistantSessionSummaryFor(
    String sessionKey, {
    AssistantThreadRecord? record,
  }) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final resolvedRecord =
        record ?? _assistantThreadRecords[normalizedSessionKey];
    final messages =
        resolvedRecord?.messages ??
        _assistantThreadMessages[normalizedSessionKey] ??
        const <GatewayChatMessage>[];
    final preview = _assistantThreadPreview(messages);
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

  String? _assistantThreadPreview(List<GatewayChatMessage> messages) {
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

  String _gatewayEntryStateForTarget(AssistantExecutionTarget target) {
    return target.promptValue;
  }

  Future<List<AssistantThreadSkillEntry>> _scanSingleAgentSkillEntries(
    List<_SingleAgentSkillScanRoot> roots, {
    String workspaceRef = '',
  }) async {
    final dedupedByName = <String, AssistantThreadSkillEntry>{};
    for (final rootSpec in roots) {
      var resolvedRootPath = _resolveSingleAgentSkillRootPath(
        rootSpec.path,
        workspaceRef: workspaceRef,
      );
      if (resolvedRootPath.isEmpty) {
        continue;
      }
      SkillDirectoryAccessHandle? accessHandle;
      try {
        if (rootSpec.bookmark.trim().isNotEmpty) {
          accessHandle = await _skillDirectoryAccessService.openDirectory(
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
        final skillFiles = await _collectSkillFilesFromDirectory(root);
        for (final entity in skillFiles) {
          final entry = await _skillEntryFromFile(
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

  Future<List<File>> _collectSkillFilesFromDirectory(Directory root) async {
    final skillFiles = <File>[];
    final visitedDirectories = <String>{};

    Future<void> visitDirectory(Directory directory) async {
      final directoryKey = await _directoryScanKey(directory);
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

  Future<String> _directoryScanKey(Directory directory) async {
    try {
      return await directory.resolveSymbolicLinks();
    } catch (_) {
      return directory.absolute.path;
    }
  }

  Future<List<AssistantThreadSkillEntry>> _scanSingleAgentSharedSkillEntries() {
    return _scanSingleAgentSkillEntries(_singleAgentSharedSkillScanRoots);
  }

  Future<List<AssistantThreadSkillEntry>> _scanSingleAgentWorkspaceSkillEntries(
    String sessionKey,
  ) {
    if (assistantWorkspaceRefKindForSession(sessionKey) !=
        WorkspaceRefKind.localPath) {
      return Future<List<AssistantThreadSkillEntry>>.value(
        const <AssistantThreadSkillEntry>[],
      );
    }
    return _scanSingleAgentSkillEntries(
      AppController._defaultSingleAgentWorkspaceSkillScanRoots,
      workspaceRef: assistantWorkspaceRefForSession(sessionKey),
    );
  }

  _SingleAgentSkillScanRoot _singleAgentSharedSkillScanRootFromOverride(
    String rawPath,
  ) {
    final normalizedPath = rawPath.trim();
    final lowered = normalizedPath.toLowerCase();
    return _SingleAgentSkillScanRoot(
      path: normalizedPath,
      source: _sourceForSkillRootPath(lowered),
      scope: normalizedPath.startsWith('/etc/') ? 'system' : 'user',
    );
  }

  _SingleAgentSkillScanRoot
  _singleAgentSharedSkillScanRootFromAuthorizedDirectory(
    AuthorizedSkillDirectory directory,
  ) {
    final normalizedPath = normalizeAuthorizedSkillDirectoryPath(
      directory.path,
    );
    final lowered = normalizedPath.toLowerCase();
    return _SingleAgentSkillScanRoot(
      path: normalizedPath,
      source: _sourceForSkillRootPath(lowered),
      scope: normalizedPath.startsWith('/etc/') ? 'system' : 'user',
      bookmark: directory.bookmark,
    );
  }

  String _resolveSingleAgentSkillRootPath(
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
      final home = _resolvedUserHomeDirectory.trim();
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

  String _sourceForSkillRootPath(String path) {
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

  Future<AssistantThreadSkillEntry> _skillEntryFromFile(
    File file,
    _SingleAgentSkillScanRoot root,
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

  void _restoreAssistantThreads(List<AssistantThreadRecord> records) {
    _assistantThreadRecords.clear();
    _assistantThreadMessages.clear();
    _singleAgentSharedImportedSkills = const <AssistantThreadSkillEntry>[];
    _singleAgentLocalSkillsHydrated = false;
    final archivedKeys = settings.assistantArchivedTaskKeys
        .map(_normalizedAssistantSessionKey)
        .toSet();
    for (final record in records) {
      final sessionKey = _normalizedAssistantSessionKey(record.sessionKey);
      if (sessionKey.isEmpty) {
        continue;
      }
      final titleFromSettings = assistantCustomTaskTitle(sessionKey);
      final shouldMigrateWorkspaceRef = _shouldMigrateWorkspaceRef(
        sessionKey,
        executionTarget:
            record.executionTarget ?? settings.assistantExecutionTarget,
        workspaceRef: record.workspaceRef,
        workspaceRefKind: record.workspaceRefKind,
      );
      final normalizedRecord = record.copyWith(
        sessionKey: sessionKey,
        title: titleFromSettings.isEmpty
            ? record.title.trim()
            : titleFromSettings,
        archived: record.archived || archivedKeys.contains(sessionKey),
        executionTarget:
            record.executionTarget ?? settings.assistantExecutionTarget,
        messageViewMode: record.messageViewMode,
        selectedSkillKeys: record.selectedSkillKeys
            .where(
              (item) => record.importedSkills.any((skill) => skill.key == item),
            )
            .toList(growable: false),
        assistantModelId: record.assistantModelId.trim().isEmpty
            ? _resolvedAssistantModelForTarget(
                record.executionTarget ?? settings.assistantExecutionTarget,
              )
            : record.assistantModelId.trim(),
        singleAgentProvider: record.singleAgentProvider,
        gatewayEntryState: (record.gatewayEntryState ?? '').trim().isEmpty
            ? _gatewayEntryStateForTarget(
                record.executionTarget ?? settings.assistantExecutionTarget,
              )
            : record.gatewayEntryState,
        workspaceRef: shouldMigrateWorkspaceRef
            ? _defaultWorkspaceRefForSession(sessionKey)
            : record.workspaceRef.trim(),
        workspaceRefKind: shouldMigrateWorkspaceRef
            ? _defaultWorkspaceRefKindForTarget(
                record.executionTarget ?? settings.assistantExecutionTarget,
              )
            : record.workspaceRefKind,
      );
      _assistantThreadRecords[sessionKey] = normalizedRecord;
      if (normalizedRecord.messages.isNotEmpty) {
        _assistantThreadMessages[sessionKey] = List<GatewayChatMessage>.from(
          normalizedRecord.messages,
        );
      }
    }
  }
}
