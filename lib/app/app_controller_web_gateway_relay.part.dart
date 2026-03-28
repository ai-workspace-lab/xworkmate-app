part of 'app_controller_web.dart';

extension AppControllerWebGatewayRelay on AppController {
  Future<void> connectRelay({AssistantExecutionTarget? target}) async {
    _relayBusy = true;
    _notifyChanged();
    try {
      final resolvedTarget =
          _sanitizeTarget(target) ??
          (() {
            final current = assistantExecutionTargetForSession(
              _currentSessionKey,
            );
            return current == AssistantExecutionTarget.local ||
                    current == AssistantExecutionTarget.remote
                ? current
                : AssistantExecutionTarget.remote;
          })();
      final profileIndex = _profileIndexForTarget(resolvedTarget);
      final profile = _profileForTarget(resolvedTarget).copyWith(
        mode: resolvedTarget == AssistantExecutionTarget.local
            ? RuntimeConnectionMode.local
            : RuntimeConnectionMode.remote,
        useSetupCode: false,
        setupCode: '',
      );
      await _relayClient.connect(
        profile: profile,
        authToken: (_relayTokenByProfile[profileIndex] ?? '').trim(),
        authPassword: (_relayPasswordByProfile[profileIndex] ?? '').trim(),
      );
      final acpEndpoint = _acpEndpointForTarget(resolvedTarget);
      if (acpEndpoint != null) {
        await _refreshAcpCapabilities(acpEndpoint);
      }
      await refreshRelaySessions();
      await refreshRelayWorkspaceResources();
      await refreshRelayHistory(sessionKey: _currentSessionKey);
      await refreshRelaySkillsForSession(_currentSessionKey);
    } finally {
      _relayBusy = false;
      _notifyChanged();
    }
  }

  Future<void> disconnectRelay() async {
    _relayBusy = true;
    _notifyChanged();
    try {
      await _relayClient.disconnect();
      _relayAgents = const <GatewayAgentSummary>[];
      _relayInstances = const <GatewayInstanceSummary>[];
      _relayConnectors = const <GatewayConnectorSummary>[];
      _relayModels = const <GatewayModelSummary>[];
      _relayCronJobs = const <GatewayCronJobSummary>[];
      _recomputeDerivedWorkspaceState();
    } finally {
      _relayBusy = false;
      _notifyChanged();
    }
  }

  Future<void> refreshRelaySessions() async {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    final target = _assistantExecutionTargetForMode(connection.mode);
    final sessions = await _relayClient.listSessions(limit: 50);
    for (final session in sessions) {
      final sessionKey = _normalizedSessionKey(session.key);
      final existing = _threadRecords[sessionKey];
      final next = AssistantThreadRecord(
        sessionKey: sessionKey,
        messages: existing?.messages ?? const <GatewayChatMessage>[],
        updatedAtMs:
            session.updatedAtMs ??
            existing?.updatedAtMs ??
            DateTime.now().millisecondsSinceEpoch.toDouble(),
        title: (session.derivedTitle ?? session.displayName ?? session.key)
            .trim(),
        archived: false,
        executionTarget: existing?.executionTarget ?? target,
        messageViewMode:
            existing?.messageViewMode ?? AssistantMessageViewMode.rendered,
        importedSkills: existing?.importedSkills ?? const [],
        selectedSkillKeys: existing?.selectedSkillKeys ?? const [],
        assistantModelId: existing?.assistantModelId ?? '',
        singleAgentProvider:
            existing?.singleAgentProvider ?? SingleAgentProvider.auto,
        gatewayEntryState:
            existing?.gatewayEntryState ?? _gatewayEntryStateForTarget(target),
        workspaceRef: existing?.workspaceRef.trim().isNotEmpty == true
            ? existing!.workspaceRef
            : _defaultWorkspaceRefForSession(sessionKey),
        workspaceRefKind:
            existing?.workspaceRefKind ?? WorkspaceRefKind.objectStore,
      );
      _threadRecords[sessionKey] = next;
    }
    await _persistThreads();
    _recomputeDerivedWorkspaceState();
    _notifyChanged();
  }

  Future<void> refreshRelayModels() async {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    final models = await _relayClient.listModels();
    _relayModels = models;
    final availableModels = models
        .map((item) => item.id.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (availableModels.isEmpty) {
      return;
    }
    final defaultModel = _settings.defaultModel.trim().isNotEmpty
        ? _settings.defaultModel.trim()
        : availableModels.first;
    _settings = _settings.copyWith(
      defaultModel: defaultModel,
      aiGateway: _settings.aiGateway.copyWith(
        availableModels: _settings.aiGateway.availableModels.isEmpty
            ? availableModels
            : _settings.aiGateway.availableModels,
      ),
    );
    await _persistSettings();
    _recomputeDerivedWorkspaceState();
    _notifyChanged();
  }

  Future<void> refreshRelayWorkspaceResources() async {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    try {
      _relayAgents = await _relayClient.listAgents();
    } catch (_) {
      _relayAgents = const <GatewayAgentSummary>[];
    }
    try {
      _relayInstances = await _relayClient.listInstances();
    } catch (_) {
      _relayInstances = const <GatewayInstanceSummary>[];
    }
    try {
      _relayConnectors = await _relayClient.listConnectors();
    } catch (_) {
      _relayConnectors = const <GatewayConnectorSummary>[];
    }
    try {
      _relayCronJobs = await _relayClient.listCronJobs();
    } catch (_) {
      _relayCronJobs = const <GatewayCronJobSummary>[];
    }
    await refreshRelayModels();
    _recomputeDerivedWorkspaceState();
    _notifyChanged();
  }

  Future<void> refreshRelayHistory({String? sessionKey}) async {
    final resolvedKey = _normalizedSessionKey(sessionKey ?? _currentSessionKey);
    if (resolvedKey.isEmpty ||
        connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    final target = _assistantExecutionTargetForMode(connection.mode);
    final messages = await _relayClient.loadHistory(resolvedKey, limit: 120);
    final existing = _threadRecords[resolvedKey];
    final next = (existing ?? _newRecord(target: target)).copyWith(
      sessionKey: resolvedKey,
      messages: messages,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      title: _deriveThreadTitle(
        existing?.title ?? '',
        messages,
        fallback: resolvedKey,
      ),
      executionTarget: existing?.executionTarget ?? target,
      gatewayEntryState:
          existing?.gatewayEntryState ?? _gatewayEntryStateForTarget(target),
    );
    _threadRecords[resolvedKey] = next;
    _streamingTextBySession.remove(resolvedKey);
    await _persistThreads();
    _recomputeDerivedWorkspaceState();
    _notifyChanged();
  }

  Future<void> refreshRelaySkillsForSession(String sessionKey) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    if ((target != AssistantExecutionTarget.local &&
            target != AssistantExecutionTarget.remote) ||
        connection.status != RuntimeConnectionStatus.connected) {
      return;
    }
    try {
      final payload = _castMap(await _relayClient.request('skills.status'));
      final skills = (payload['skills'] as List<dynamic>? ?? const <dynamic>[])
          .map(_castMap)
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
          (_threadRecords[normalizedSessionKey]?.selectedSkillKeys ??
                  const <String>[])
              .where(importedKeys.contains)
              .toList(growable: false);
      _upsertThreadRecord(
        normalizedSessionKey,
        importedSkills: skills,
        selectedSkillKeys: nextSelected,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
      await _persistThreads();
      _recomputeDerivedWorkspaceState();
      _notifyChanged();
    } catch (_) {
      // Best effort: skill discovery should not block chat flows.
    }
  }

  Future<void> _refreshSingleAgentSkillsForSession(String sessionKey) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return;
    }
    final endpoint = _acpEndpointForTarget(AssistantExecutionTarget.remote);
    if (endpoint == null) {
      await _replaceThreadSkillsForSession(
        normalizedSessionKey,
        const <AssistantThreadSkillEntry>[],
      );
      return;
    }
    final provider = singleAgentProviderForSession(normalizedSessionKey);
    try {
      await _refreshAcpCapabilities(endpoint);
      final response = await _acpClient.request(
        endpoint: endpoint,
        method: 'skills.status',
        params: <String, dynamic>{
          'sessionId': normalizedSessionKey,
          'threadId': normalizedSessionKey,
          'mode': 'single-agent',
          'provider': provider.providerId,
        },
      );
      final result = _castMap(response['result']);
      final payload = result.isNotEmpty ? result : response;
      final skills = (payload['skills'] as List<dynamic>? ?? const <dynamic>[])
          .map(_castMap)
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
      await _replaceThreadSkillsForSession(normalizedSessionKey, skills);
    } on WebAcpException catch (error) {
      if (_unsupportedAcpSkillsStatus(error)) {
        await _replaceThreadSkillsForSession(
          normalizedSessionKey,
          const <AssistantThreadSkillEntry>[],
        );
      }
    } catch (_) {
      // Keep current skills when transient ACP failures happen.
    }
  }

  Future<void> _replaceThreadSkillsForSession(
    String sessionKey,
    List<AssistantThreadSkillEntry> importedSkills,
  ) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final importedKeys = importedSkills.map((item) => item.key).toSet();
    final nextSelected =
        (_threadRecords[normalizedSessionKey]?.selectedSkillKeys ??
                const <String>[])
            .where(importedKeys.contains)
            .toList(growable: false);
    _upsertThreadRecord(
      normalizedSessionKey,
      importedSkills: importedSkills,
      selectedSkillKeys: nextSelected,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _persistThreads();
    _recomputeDerivedWorkspaceState();
    _notifyChanged();
  }
}
