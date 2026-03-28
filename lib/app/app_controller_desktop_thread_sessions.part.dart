part of 'app_controller_desktop.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopThreadSessions on AppController {
  int assistantSkillCountForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) ==
        AssistantExecutionTarget.singleAgent) {
      return assistantImportedSkillsForSession(normalizedSessionKey).length;
    }
    return skills.length;
  }

  int get currentAssistantSkillCount =>
      assistantSkillCountForSession(currentSessionKey);

  List<String> assistantSelectedSkillKeysForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final importedKeys = assistantImportedSkillsForSession(
      normalizedSessionKey,
    ).map((item) => item.key).toSet();
    final selected =
        _assistantThreadRecords[normalizedSessionKey]?.selectedSkillKeys ??
        const <String>[];
    return selected
        .where((item) => importedKeys.contains(item))
        .toList(growable: false);
  }

  List<AssistantThreadSkillEntry> assistantSelectedSkillsForSession(
    String sessionKey,
  ) {
    final selectedKeys = assistantSelectedSkillKeysForSession(
      sessionKey,
    ).toSet();
    return assistantImportedSkillsForSession(
      sessionKey,
    ).where((item) => selectedKeys.contains(item.key)).toList(growable: false);
  }

  String assistantModelForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      if (singleAgentUsesAiChatFallbackForSession(normalizedSessionKey)) {
        final recordModel =
            _assistantThreadRecords[normalizedSessionKey]?.assistantModelId
                .trim() ??
            '';
        if (recordModel.isNotEmpty) {
          return recordModel;
        }
        return resolvedAiGatewayModel;
      }
      return singleAgentRuntimeModelForSession(normalizedSessionKey);
    }
    final recordModel =
        _assistantThreadRecords[normalizedSessionKey]?.assistantModelId
            .trim() ??
        '';
    if (recordModel.isNotEmpty) {
      return recordModel;
    }
    return _resolvedAssistantModelForTarget(target);
  }

  String assistantWorkspaceRefForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final recordRef =
        _assistantThreadRecords[normalizedSessionKey]?.workspaceRef.trim() ??
        '';
    if (recordRef.isNotEmpty) {
      return recordRef;
    }
    return _defaultWorkspaceRefForSession(normalizedSessionKey);
  }

  WorkspaceRefKind assistantWorkspaceRefKindForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final record = _assistantThreadRecords[normalizedSessionKey];
    if (record != null && record.workspaceRef.trim().isNotEmpty) {
      return record.workspaceRefKind;
    }
    return _defaultWorkspaceRefKindForTarget(
      assistantExecutionTargetForSession(normalizedSessionKey),
    );
  }

  Future<AssistantArtifactSnapshot> loadAssistantArtifactSnapshot({
    String? sessionKey,
  }) {
    final resolvedSessionKey = _normalizedAssistantSessionKey(
      sessionKey ?? currentSessionKey,
    );
    return _threadArtifactService.loadSnapshot(
      workspaceRef: assistantWorkspaceRefForSession(resolvedSessionKey),
      workspaceRefKind: assistantWorkspaceRefKindForSession(resolvedSessionKey),
    );
  }

  Future<AssistantArtifactPreview> loadAssistantArtifactPreview(
    AssistantArtifactEntry entry, {
    String? sessionKey,
  }) {
    final resolvedSessionKey = _normalizedAssistantSessionKey(
      sessionKey ?? currentSessionKey,
    );
    return _threadArtifactService.loadPreview(
      entry: entry,
      workspaceRef: assistantWorkspaceRefForSession(resolvedSessionKey),
      workspaceRefKind: assistantWorkspaceRefKindForSession(resolvedSessionKey),
    );
  }

  SingleAgentProvider singleAgentProviderForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final stored =
        _assistantThreadRecords[normalizedSessionKey]?.singleAgentProvider ??
        SingleAgentProvider.auto;
    return settings.resolveSingleAgentProvider(stored);
  }

  SingleAgentProvider get currentSingleAgentProvider =>
      singleAgentProviderForSession(currentSessionKey);

  SingleAgentProvider? singleAgentResolvedProviderForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    return _resolvedSingleAgentProvider(
      singleAgentProviderForSession(normalizedSessionKey),
    );
  }

  SingleAgentProvider? get currentSingleAgentResolvedProvider =>
      singleAgentResolvedProviderForSession(currentSessionKey);

  bool singleAgentUsesAiChatFallbackForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return false;
    }
    return !hasAnyAvailableSingleAgentProvider && canUseAiGatewayConversation;
  }

  bool get currentSingleAgentUsesAiChatFallback =>
      singleAgentUsesAiChatFallbackForSession(currentSessionKey);

  bool singleAgentNeedsAiGatewayConfigurationForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return false;
    }
    return !hasAnyAvailableSingleAgentProvider && !canUseAiGatewayConversation;
  }

  bool get currentSingleAgentNeedsAiGatewayConfiguration =>
      singleAgentNeedsAiGatewayConfigurationForSession(currentSessionKey);

  bool singleAgentHasResolvedProviderForSession(String sessionKey) {
    return singleAgentResolvedProviderForSession(sessionKey) != null;
  }

  bool get currentSingleAgentHasResolvedProvider =>
      singleAgentHasResolvedProviderForSession(currentSessionKey);

  bool singleAgentShouldSuggestAutoSwitchForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return false;
    }
    final selection = singleAgentProviderForSession(normalizedSessionKey);
    if (selection == SingleAgentProvider.auto) {
      return false;
    }
    return !_canUseSingleAgentProvider(selection) &&
        hasAnyAvailableSingleAgentProvider;
  }

  bool get currentSingleAgentShouldSuggestAutoSwitch =>
      singleAgentShouldSuggestAutoSwitchForSession(currentSessionKey);

  String singleAgentRuntimeModelForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    return _singleAgentRuntimeModelBySession[normalizedSessionKey]?.trim() ??
        '';
  }

  String get currentSingleAgentRuntimeModel =>
      singleAgentRuntimeModelForSession(currentSessionKey);

  String singleAgentModelDisplayLabelForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final runtimeModel = singleAgentRuntimeModelForSession(
      normalizedSessionKey,
    );
    if (runtimeModel.isNotEmpty) {
      return runtimeModel;
    }
    final model = assistantModelForSession(normalizedSessionKey);
    if (model.isNotEmpty) {
      return model;
    }
    if (singleAgentUsesAiChatFallbackForSession(normalizedSessionKey)) {
      return appText('AI Chat fallback', 'AI Chat fallback');
    }
    final provider =
        singleAgentResolvedProviderForSession(normalizedSessionKey) ??
        singleAgentProviderForSession(normalizedSessionKey);
    return appText(
      '请先配置 ${provider.label} 模型',
      'Configure ${provider.label} model',
    );
  }

  String get currentSingleAgentModelDisplayLabel =>
      singleAgentModelDisplayLabelForSession(currentSessionKey);

  bool singleAgentShouldShowModelControlForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return true;
    }
    if (singleAgentUsesAiChatFallbackForSession(normalizedSessionKey)) {
      return true;
    }
    return singleAgentRuntimeModelForSession(normalizedSessionKey).isNotEmpty;
  }

  bool get currentSingleAgentShouldShowModelControl =>
      singleAgentShouldShowModelControlForSession(currentSessionKey);

  List<SingleAgentProvider> get singleAgentProviderOptions =>
      <SingleAgentProvider>[
        SingleAgentProvider.auto,
        ...configuredSingleAgentProviders,
      ];

  String singleAgentProviderLabelForSession(String sessionKey) {
    return singleAgentProviderForSession(sessionKey).label;
  }

  String get assistantConversationOwnerLabel {
    if (!isSingleAgentMode) {
      return activeAgentName;
    }
    final resolvedProvider = currentSingleAgentResolvedProvider;
    if (resolvedProvider != null) {
      return resolvedProvider.label;
    }
    final provider = currentSingleAgentProvider;
    if (provider != SingleAgentProvider.auto) {
      return provider.label;
    }
    if (currentSingleAgentUsesAiChatFallback) {
      return appText('AI Chat fallback', 'AI Chat fallback');
    }
    return appText('单机智能体', 'Single Agent');
  }

  AssistantThreadConnectionState get currentAssistantConnectionState =>
      assistantConnectionStateForSession(currentSessionKey);

  AssistantThreadConnectionState assistantConnectionStateForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      final provider = singleAgentProviderForSession(normalizedSessionKey);
      final resolvedProvider = singleAgentResolvedProviderForSession(
        normalizedSessionKey,
      );
      final model = assistantModelForSession(normalizedSessionKey);
      final fallbackReady = singleAgentUsesAiChatFallbackForSession(
        normalizedSessionKey,
      );
      final host = _aiGatewayHostLabel(settings.aiGateway.baseUrl);
      final providerReady = resolvedProvider != null;
      final detail = providerReady
          ? _joinConnectionParts(<String>[resolvedProvider.label, model])
          : fallbackReady
          ? _joinConnectionParts(<String>[
              appText('AI Chat fallback', 'AI Chat fallback'),
              model,
              host,
            ])
          : singleAgentShouldSuggestAutoSwitchForSession(normalizedSessionKey)
          ? appText(
              '${provider.label} 不可用，可切到 Auto',
              '${provider.label} is unavailable. Switch to Auto.',
            )
          : singleAgentNeedsAiGatewayConfigurationForSession(
              normalizedSessionKey,
            )
          ? appText(
              '没有可用的外部 Agent ACP 端点，请配置 LLM API fallback。',
              'No external Agent ACP endpoint is available. Configure LLM API fallback.',
            )
          : appText(
              '当前线程的外部 Agent ACP 连接尚未就绪。',
              'The external Agent ACP connection for this thread is not ready yet.',
            );
      return AssistantThreadConnectionState(
        executionTarget: target,
        status: providerReady || fallbackReady
            ? RuntimeConnectionStatus.connected
            : RuntimeConnectionStatus.offline,
        primaryLabel: target.label,
        detailLabel: detail.isEmpty
            ? appText('未配置单机智能体', 'Single Agent is not configured')
            : detail,
        ready: providerReady || fallbackReady,
        pairingRequired: false,
        gatewayTokenMissing: false,
        lastError: null,
      );
    }

    final expectedMode = target == AssistantExecutionTarget.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    final matchesTarget = connection.mode == expectedMode;
    final fallbackProfile = _gatewayProfileForAssistantExecutionTarget(target);
    final fallbackAddress = _gatewayAddressLabel(fallbackProfile);
    final detail = matchesTarget
        ? (connection.remoteAddress?.trim().isNotEmpty == true
              ? connection.remoteAddress!.trim()
              : fallbackAddress)
        : fallbackAddress;
    final status = matchesTarget
        ? connection.status
        : RuntimeConnectionStatus.offline;
    return AssistantThreadConnectionState(
      executionTarget: target,
      status: status,
      primaryLabel: status.label,
      detailLabel: detail,
      ready: status == RuntimeConnectionStatus.connected,
      pairingRequired: matchesTarget && connection.pairingRequired,
      gatewayTokenMissing: matchesTarget && connection.gatewayTokenMissing,
      lastError: matchesTarget ? connection.lastError?.trim() : null,
    );
  }

  String get assistantConnectionStatusLabel =>
      currentAssistantConnectionState.primaryLabel;

  String get assistantConnectionTargetLabel {
    return currentAssistantConnectionState.detailLabel;
  }

  Future<String> loadAiGatewayApiKey() async {
    return (await _store.loadAiGatewayApiKey())?.trim() ?? '';
  }

  Future<void> saveMultiAgentConfig(MultiAgentConfig config) async {
    final resolved = _resolveMultiAgentConfig(
      settings.copyWith(multiAgent: config),
    );
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(multiAgent: resolved),
      refreshAfterSave: false,
    );
    await refreshMultiAgentMounts(sync: resolved.autoSync);
  }

  Future<void> refreshMultiAgentMounts({bool sync = false}) async {
    await _refreshAcpCapabilities(persistMountTargets: true);
  }

  Future<void> runMultiAgentCollaboration({
    required String rawPrompt,
    required String composedPrompt,
    required List<CollaborationAttachment> attachments,
    required List<String> selectedSkillLabels,
  }) async {
    final sessionKey = currentSessionKey.trim().isEmpty
        ? 'main'
        : currentSessionKey;
    await _enqueueThreadTurn<void>(sessionKey, () async {
      final aiGatewayApiKey = await loadAiGatewayApiKey();
      _multiAgentRunPending = true;
      _appendLocalSessionMessage(
        sessionKey,
        GatewayChatMessage(
          id: _nextLocalMessageId(),
          role: 'user',
          text: rawPrompt,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      );
      _recomputeTasks();
      try {
        final taskStream = _gatewayAcpClient.runMultiAgent(
          GatewayAcpMultiAgentRequest(
            sessionId: sessionKey,
            threadId: sessionKey,
            prompt: composedPrompt,
            workingDirectory:
                _assistantWorkingDirectoryForSession(sessionKey) ??
                Directory.current.path,
            attachments: attachments,
            selectedSkills: selectedSkillLabels,
            aiGatewayBaseUrl: aiGatewayUrl,
            aiGatewayApiKey: aiGatewayApiKey,
            resumeSession: true,
          ),
        );
        await for (final event in taskStream) {
          if (event.type == 'result') {
            final success = event.data['success'] == true;
            final finalScore = event.data['finalScore'];
            final iterations = event.data['iterations'];
            _appendLocalSessionMessage(
              sessionKey,
              GatewayChatMessage(
                id: _nextLocalMessageId(),
                role: 'assistant',
                text: success
                    ? appText(
                        '多 Agent 协作完成，评分 ${finalScore ?? '-'}，迭代 ${iterations ?? 0} 次。',
                        'Multi-agent collaboration completed with score ${finalScore ?? '-'} after ${iterations ?? 0} iteration(s).',
                      )
                    : appText(
                        '多 Agent 协作失败：${event.data['error'] ?? event.message}',
                        'Multi-agent collaboration failed: ${event.data['error'] ?? event.message}',
                      ),
                timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
                toolCallId: null,
                toolName: null,
                stopReason: null,
                pending: false,
                error: !success,
              ),
            );
            continue;
          }
          _appendLocalSessionMessage(
            sessionKey,
            GatewayChatMessage(
              id: _nextLocalMessageId(),
              role: 'assistant',
              text: event.message,
              timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
              toolCallId: null,
              toolName: event.title,
              stopReason: null,
              pending: event.pending,
              error: event.error,
            ),
          );
        }
      } on GatewayAcpException catch (error) {
        _appendLocalSessionMessage(
          sessionKey,
          GatewayChatMessage(
            id: _nextLocalMessageId(),
            role: 'assistant',
            text: appText(
              '多 Agent 协作不可用（Gateway ACP）：${error.message}',
              'Multi-agent collaboration is unavailable (Gateway ACP): ${error.message}',
            ),
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: 'Multi-Agent',
            stopReason: null,
            pending: false,
            error: true,
          ),
        );
      } catch (error) {
        _appendLocalSessionMessage(
          sessionKey,
          GatewayChatMessage(
            id: _nextLocalMessageId(),
            role: 'assistant',
            text: error.toString(),
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: 'Multi-Agent',
            stopReason: null,
            pending: false,
            error: true,
          ),
        );
      } finally {
        _multiAgentRunPending = false;
        _recomputeTasks();
        _notifyIfActive();
      }
    });
  }

  Future<void> openOnlineWorkspace() async {
    const url = 'https://www.svc.plus/Xworkmate';
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
        return;
      }
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
        return;
      }
      if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {
      // Best effort only. Do not surface a blocking error from a convenience link.
    }
  }

  List<String> get aiGatewayModelChoices {
    return aiGatewayConversationModelChoices;
  }

  List<String> get connectedGatewayModelChoices {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return const <String>[];
    }
    return _modelsController.items
        .map((item) => item.id.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<String> get assistantModelChoices {
    return _assistantModelChoicesForSession(currentSessionKey);
  }

  List<String> _assistantModelChoicesForSession(String sessionKey) {
    final target = assistantExecutionTargetForSession(sessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      if (singleAgentUsesAiChatFallbackForSession(sessionKey)) {
        return aiGatewayConversationModelChoices;
      }
      final selectedModel =
          _assistantThreadRecords[_normalizedAssistantSessionKey(sessionKey)]
              ?.assistantModelId
              .trim();
      if (selectedModel?.isNotEmpty == true) {
        return <String>[selectedModel!];
      }
      return const <String>[];
    }
    final runtimeModels = connectedGatewayModelChoices;
    if (runtimeModels.isNotEmpty) {
      return runtimeModels;
    }
    final resolved = resolvedDefaultModel.trim();
    if (resolved.isNotEmpty) {
      return <String>[resolved];
    }
    final localDefault = settings.ollamaLocal.defaultModel.trim();
    if (localDefault.isNotEmpty) {
      return <String>[localDefault];
    }
    return const <String>[];
  }

  String get resolvedDefaultModel {
    final current = settings.defaultModel.trim();
    if (current.isNotEmpty) {
      return current;
    }
    final localDefault = settings.ollamaLocal.defaultModel.trim();
    if (localDefault.isNotEmpty) {
      return localDefault;
    }
    final runtimeModels = connectedGatewayModelChoices;
    if (runtimeModels.isNotEmpty) {
      return runtimeModels.first;
    }
    final aiGatewayChoices = aiGatewayConversationModelChoices;
    if (aiGatewayChoices.isNotEmpty) {
      return aiGatewayChoices.first;
    }
    return '';
  }

  bool get canQuickConnectGateway {
    final target = currentAssistantExecutionTarget;
    if (target == AssistantExecutionTarget.singleAgent) {
      return false;
    }
    final profile = _gatewayProfileForAssistantExecutionTarget(target);
    if (profile.useSetupCode && profile.setupCode.trim().isNotEmpty) {
      return true;
    }
    final host = profile.host.trim();
    if (host.isEmpty || profile.port <= 0) {
      return false;
    }
    if (profile.mode == RuntimeConnectionMode.local) {
      return true;
    }
    final defaults = switch (target) {
      AssistantExecutionTarget.singleAgent =>
        GatewayConnectionProfile.emptySlot(index: kGatewayRemoteProfileIndex),
      AssistantExecutionTarget.local =>
        GatewayConnectionProfile.defaultsLocal(),
      AssistantExecutionTarget.remote =>
        GatewayConnectionProfile.defaultsRemote(),
    };
    return hasStoredGatewayCredential ||
        host != defaults.host ||
        profile.port != defaults.port ||
        profile.tls != defaults.tls ||
        profile.mode != defaults.mode;
  }

  String _joinConnectionParts(List<String> parts) {
    final normalized = parts
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return normalized.join(' · ');
  }

  String _gatewayAddressLabel(GatewayConnectionProfile profile) {
    final host = profile.host.trim();
    if (host.isEmpty || profile.port <= 0) {
      return appText('未连接目标', 'No target');
    }
    return '$host:${profile.port}';
  }

  List<SecretReferenceEntry> get secretReferences =>
      _settingsController.buildSecretReferences();
  List<SecretAuditEntry> get secretAuditTrail => _settingsController.auditTrail;
  List<RuntimeLogEntry> get runtimeLogs => _runtime.logs;
  List<AssistantFocusEntry> get assistantNavigationDestinations =>
      normalizeAssistantNavigationDestinations(
        settings.assistantNavigationDestinations,
      ).where(supportsAssistantFocusEntry).toList(growable: false);

  bool supportsAssistantFocusEntry(AssistantFocusEntry entry) {
    final destination = entry.destination;
    if (destination != null) {
      return capabilities.supportsDestination(destination);
    }
    return capabilities.supportsDestination(WorkspaceDestination.settings);
  }

  List<GatewayChatMessage> get chatMessages {
    final sessionKey = _normalizedAssistantSessionKey(
      _sessionsController.currentSessionKey,
    );
    final items = List<GatewayChatMessage>.from(
      isSingleAgentMode
          ? const <GatewayChatMessage>[]
          : _chatController.messages,
    );
    final threadItems = isSingleAgentMode
        ? _assistantThreadMessages[sessionKey]
        : null;
    if (threadItems != null && threadItems.isNotEmpty) {
      items.addAll(threadItems);
    }
    final localItems = _localSessionMessages[sessionKey];
    if (localItems != null && localItems.isNotEmpty) {
      items.addAll(localItems);
    }
    final streaming = isSingleAgentMode
        ? (_aiGatewayStreamingTextBySession[sessionKey]?.trim() ?? '')
        : (_chatController.streamingAssistantText?.trim() ?? '');
    if (streaming.isNotEmpty) {
      items.add(
        GatewayChatMessage(
          id: 'streaming',
          role: 'assistant',
          text: streaming,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: true,
          error: false,
        ),
      );
    }
    return items;
  }

  String _normalizedAssistantSessionKey(String sessionKey) {
    final trimmed = sessionKey.trim();
    return trimmed.isEmpty ? 'main' : trimmed;
  }

  AssistantExecutionTarget assistantExecutionTargetForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    return _sanitizeExecutionTarget(
      _assistantThreadRecords[normalizedSessionKey]?.executionTarget ??
          settings.assistantExecutionTarget,
    );
  }

  AssistantMessageViewMode assistantMessageViewModeForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    return _assistantThreadRecords[normalizedSessionKey]?.messageViewMode ??
        AssistantMessageViewMode.rendered;
  }

  String _defaultWorkspaceRefForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    return switch (target) {
      AssistantExecutionTarget.remote => settings.remoteProjectRoot.trim(),
      AssistantExecutionTarget.local || AssistantExecutionTarget.singleAgent =>
        _defaultLocalWorkspaceRefForSession(normalizedSessionKey),
    };
  }

  String _defaultLocalWorkspaceRefForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final baseWorkspace = settings.workspacePath.trim();
    if (baseWorkspace.isEmpty || normalizedSessionKey == 'main') {
      return baseWorkspace;
    }
    final threadWorkspace =
        '${_trimTrailingPathSeparator(baseWorkspace)}/.xworkmate/threads/${_threadWorkspaceDirectoryName(normalizedSessionKey)}';
    _ensureLocalWorkspaceDirectory(threadWorkspace);
    return threadWorkspace;
  }

  String _threadWorkspaceDirectoryName(String sessionKey) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final sanitized = normalizedSessionKey
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return sanitized.isEmpty ? 'thread' : sanitized;
  }

  String _trimTrailingPathSeparator(String path) {
    if (path.endsWith('/') && path.length > 1) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  void _ensureLocalWorkspaceDirectory(String path) {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return;
    }
    try {
      Directory(normalizedPath).createSync(recursive: true);
    } catch (_) {
      // Best effort only. The caller can still decide whether to use fallback behavior.
    }
  }

  bool _usesLegacySharedWorkspaceRef(
    String sessionKey, {
    AssistantExecutionTarget? executionTarget,
    String? workspaceRef,
    WorkspaceRefKind? workspaceRefKind,
  }) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (normalizedSessionKey == 'main') {
      return false;
    }
    final resolvedTarget =
        executionTarget ??
        assistantExecutionTargetForSession(normalizedSessionKey);
    if (resolvedTarget == AssistantExecutionTarget.remote) {
      return false;
    }
    final normalizedRef = workspaceRef?.trim() ?? '';
    if (normalizedRef.isEmpty) {
      return false;
    }
    return workspaceRefKind == WorkspaceRefKind.localPath &&
        normalizedRef == settings.workspacePath.trim();
  }

  bool _usesDefaultThreadWorkspaceRefFromAnotherRoot(
    String sessionKey, {
    AssistantExecutionTarget? executionTarget,
    String? workspaceRef,
    WorkspaceRefKind? workspaceRefKind,
  }) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final resolvedTarget =
        executionTarget ??
        assistantExecutionTargetForSession(normalizedSessionKey);
    if (resolvedTarget == AssistantExecutionTarget.remote) {
      return false;
    }
    final normalizedRef = workspaceRef?.trim() ?? '';
    if (normalizedRef.isEmpty ||
        workspaceRefKind != WorkspaceRefKind.localPath) {
      return false;
    }
    final expectedDefault = _defaultWorkspaceRefForSession(
      normalizedSessionKey,
    ).trim();
    if (expectedDefault.isEmpty) {
      return false;
    }
    final normalizedPath = _trimTrailingPathSeparator(
      normalizedRef.replaceAll('\\', '/'),
    );
    final normalizedExpected = _trimTrailingPathSeparator(
      expectedDefault.replaceAll('\\', '/'),
    );
    if (normalizedPath == normalizedExpected) {
      return false;
    }
    if (normalizedSessionKey == 'main') {
      return normalizedPath == SettingsSnapshot.defaults().workspacePath;
    }
    final expectedSuffix =
        '/.xworkmate/threads/${_threadWorkspaceDirectoryName(normalizedSessionKey)}';
    return normalizedPath.endsWith(expectedSuffix);
  }

  bool _shouldMigrateWorkspaceRef(
    String sessionKey, {
    AssistantExecutionTarget? executionTarget,
    String? workspaceRef,
    WorkspaceRefKind? workspaceRefKind,
  }) {
    final normalizedRef = workspaceRef?.trim() ?? '';
    if (normalizedRef.isEmpty) {
      return true;
    }
    return _usesLegacySharedWorkspaceRef(
          sessionKey,
          executionTarget: executionTarget,
          workspaceRef: normalizedRef,
          workspaceRefKind: workspaceRefKind,
        ) ||
        _usesDefaultThreadWorkspaceRefFromAnotherRoot(
          sessionKey,
          executionTarget: executionTarget,
          workspaceRef: normalizedRef,
          workspaceRefKind: workspaceRefKind,
        );
  }

  WorkspaceRefKind _defaultWorkspaceRefKindForTarget(
    AssistantExecutionTarget target,
  ) {
    return switch (target) {
      AssistantExecutionTarget.remote => WorkspaceRefKind.remotePath,
      AssistantExecutionTarget.local ||
      AssistantExecutionTarget.singleAgent => WorkspaceRefKind.localPath,
    };
  }

  void _syncAssistantWorkspaceRefForSession(
    String sessionKey, {
    AssistantExecutionTarget? executionTarget,
  }) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final resolvedTarget =
        executionTarget ??
        assistantExecutionTargetForSession(normalizedSessionKey);
    final nextWorkspaceRef = _defaultWorkspaceRefForSession(
      normalizedSessionKey,
    );
    final nextWorkspaceRefKind = _defaultWorkspaceRefKindForTarget(
      resolvedTarget,
    );
    final existing = _assistantThreadRecords[normalizedSessionKey];
    final existingWorkspaceRef = existing?.workspaceRef.trim() ?? '';
    if (existing != null &&
        existingWorkspaceRef.isNotEmpty &&
        existing.workspaceRefKind == nextWorkspaceRefKind &&
        !_shouldMigrateWorkspaceRef(
          normalizedSessionKey,
          executionTarget: resolvedTarget,
          workspaceRef: existingWorkspaceRef,
          workspaceRefKind: existing.workspaceRefKind,
        )) {
      return;
    }
    if (existing != null &&
        existingWorkspaceRef == nextWorkspaceRef &&
        existing.workspaceRefKind == nextWorkspaceRefKind) {
      return;
    }
    _upsertAssistantThreadRecord(
      normalizedSessionKey,
      executionTarget: resolvedTarget,
      workspaceRef: nextWorkspaceRef,
      workspaceRefKind: nextWorkspaceRefKind,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
  }

  List<GatewaySessionSummary> _assistantSessions() {
    final archivedKeys = settings.assistantArchivedTaskKeys
        .map(_normalizedAssistantSessionKey)
        .toSet();
    final byKey = <String, GatewaySessionSummary>{};

    for (final session in _sessionsController.sessions) {
      final normalizedSessionKey = _normalizedAssistantSessionKey(session.key);
      if (archivedKeys.contains(normalizedSessionKey)) {
        continue;
      }
      byKey[normalizedSessionKey] = session;
    }

    for (final record in _assistantThreadRecords.values) {
      final normalizedSessionKey = _normalizedAssistantSessionKey(
        record.sessionKey,
      );
      if (normalizedSessionKey.isEmpty ||
          archivedKeys.contains(normalizedSessionKey) ||
          record.archived) {
        continue;
      }
      byKey.putIfAbsent(
        normalizedSessionKey,
        () => _assistantSessionSummaryFor(normalizedSessionKey, record: record),
      );
    }

    final currentKey = _normalizedAssistantSessionKey(currentSessionKey);
    if (!archivedKeys.contains(currentKey) && !byKey.containsKey(currentKey)) {
      byKey[currentKey] = _assistantSessionSummaryFor(currentKey);
    }

    final items = byKey.values.toList(growable: true)
      ..sort(
        (left, right) =>
            (right.updatedAtMs ?? 0).compareTo(left.updatedAtMs ?? 0),
      );
    return items;
  }
}
