part of 'app_controller_web.dart';

extension AppControllerWebSessions on AppController {
  AssistantExecutionTarget assistantExecutionTargetForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final recordTarget = _sanitizeTarget(
      _threadRecords[normalizedSessionKey]?.executionTarget,
    );
    final fallback = _sanitizeTarget(_settings.assistantExecutionTarget);
    return recordTarget ?? fallback ?? AssistantExecutionTarget.singleAgent;
  }

  AssistantExecutionTarget get assistantExecutionTarget =>
      assistantExecutionTargetForSession(_currentSessionKey);
  AssistantExecutionTarget get currentAssistantExecutionTarget =>
      assistantExecutionTarget;
  bool get isSingleAgentMode =>
      assistantExecutionTarget == AssistantExecutionTarget.singleAgent;

  AssistantMessageViewMode assistantMessageViewModeForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    return _threadRecords[normalizedSessionKey]?.messageViewMode ??
        AssistantMessageViewMode.rendered;
  }

  AssistantMessageViewMode get currentAssistantMessageViewMode =>
      assistantMessageViewModeForSession(_currentSessionKey);

  String assistantWorkspaceRefForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final recordRef =
        _threadRecords[normalizedSessionKey]?.workspaceRef.trim() ?? '';
    if (recordRef.isNotEmpty) {
      return recordRef;
    }
    return _defaultWorkspaceRefForSession(normalizedSessionKey);
  }

  WorkspaceRefKind assistantWorkspaceRefKindForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final record = _threadRecords[normalizedSessionKey];
    if (record != null && record.workspaceRef.trim().isNotEmpty) {
      return record.workspaceRefKind;
    }
    return WorkspaceRefKind.objectStore;
  }

  Future<AssistantArtifactSnapshot> loadAssistantArtifactSnapshot({
    String? sessionKey,
  }) {
    final resolvedSessionKey = _normalizedSessionKey(
      sessionKey ?? _currentSessionKey,
    );
    return _artifactProxyClient.loadSnapshot(
      sessionKey: resolvedSessionKey,
      workspaceRef: assistantWorkspaceRefForSession(resolvedSessionKey),
      workspaceRefKind: assistantWorkspaceRefKindForSession(resolvedSessionKey),
    );
  }

  Future<AssistantArtifactPreview> loadAssistantArtifactPreview(
    AssistantArtifactEntry entry, {
    String? sessionKey,
  }) {
    final resolvedSessionKey = _normalizedSessionKey(
      sessionKey ?? _currentSessionKey,
    );
    return _artifactProxyClient.loadPreview(
      sessionKey: resolvedSessionKey,
      entry: entry,
    );
  }

  SingleAgentProvider singleAgentProviderForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final stored =
        _threadRecords[normalizedSessionKey]?.singleAgentProvider ??
        SingleAgentProvider.auto;
    return _settings.resolveSingleAgentProvider(stored);
  }

  SingleAgentProvider get currentSingleAgentProvider =>
      singleAgentProviderForSession(_currentSessionKey);

  List<SingleAgentProvider> get singleAgentProviderOptions =>
      <SingleAgentProvider>[
        SingleAgentProvider.auto,
        ..._settings.availableSingleAgentProviders,
      ];

  bool singleAgentUsesAiChatFallbackForSession(String sessionKey) {
    final provider = singleAgentProviderForSession(sessionKey);
    return provider == SingleAgentProvider.auto && canUseAiGatewayConversation;
  }

  bool get currentSingleAgentUsesAiChatFallback =>
      singleAgentUsesAiChatFallbackForSession(_currentSessionKey);

  String singleAgentRuntimeModelForSession(String sessionKey) {
    return _singleAgentRuntimeModelBySession[_normalizedSessionKey(sessionKey)]
            ?.trim() ??
        '';
  }

  String get currentSingleAgentRuntimeModel =>
      singleAgentRuntimeModelForSession(_currentSessionKey);

  String assistantModelForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    final recordModel =
        _threadRecords[normalizedSessionKey]?.assistantModelId.trim() ?? '';
    if (target == AssistantExecutionTarget.singleAgent) {
      if (singleAgentUsesAiChatFallbackForSession(normalizedSessionKey)) {
        if (recordModel.isNotEmpty) {
          return recordModel;
        }
        return resolvedAiGatewayModel;
      }
      final runtimeModel = singleAgentRuntimeModelForSession(
        normalizedSessionKey,
      );
      if (runtimeModel.isNotEmpty) {
        return runtimeModel;
      }
      if (recordModel.isNotEmpty) {
        return recordModel;
      }
      return resolvedAiGatewayModel;
    }
    if (recordModel.isNotEmpty) {
      return recordModel;
    }
    return _settings.defaultModel.trim();
  }

  String get resolvedAssistantModel =>
      assistantModelForSession(_currentSessionKey);

  List<String> assistantModelChoicesForSession(String sessionKey) {
    final target = assistantExecutionTargetForSession(sessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      if (singleAgentUsesAiChatFallbackForSession(sessionKey)) {
        return aiGatewayConversationModelChoices;
      }
      final runtime = singleAgentRuntimeModelForSession(sessionKey);
      if (runtime.isNotEmpty) {
        return <String>[runtime];
      }
      final recordModel = assistantModelForSession(sessionKey);
      if (recordModel.isNotEmpty) {
        return <String>[recordModel];
      }
      return aiGatewayConversationModelChoices;
    }
    final model = _settings.defaultModel.trim();
    if (model.isEmpty) {
      return const <String>[];
    }
    return <String>[model];
  }

  List<String> get assistantModelChoices =>
      assistantModelChoicesForSession(_currentSessionKey);

  List<AssistantThreadSkillEntry> assistantImportedSkillsForSession(
    String sessionKey,
  ) {
    return _threadRecords[_normalizedSessionKey(sessionKey)]?.importedSkills ??
        const <AssistantThreadSkillEntry>[];
  }

  List<String> assistantSelectedSkillKeysForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final importedKeys = assistantImportedSkillsForSession(
      normalizedSessionKey,
    ).map((item) => item.key).toSet();
    final selected =
        _threadRecords[normalizedSessionKey]?.selectedSkillKeys ??
        const <String>[];
    return selected
        .where((item) => importedKeys.contains(item))
        .toList(growable: false);
  }

  int get currentAssistantSkillCount {
    final target = assistantExecutionTargetForSession(_currentSessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      return assistantImportedSkillsForSession(_currentSessionKey).length;
    }
    return assistantImportedSkillsForSession(_currentSessionKey).length;
  }

  String _defaultWorkspaceRefForSession(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    return 'object://thread/$normalizedSessionKey';
  }

  void _syncThreadWorkspaceRef(String sessionKey) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final nextWorkspaceRef = _defaultWorkspaceRefForSession(
      normalizedSessionKey,
    );
    final existing = _threadRecords[normalizedSessionKey];
    if (existing != null &&
        existing.workspaceRef == nextWorkspaceRef &&
        existing.workspaceRefKind == WorkspaceRefKind.objectStore) {
      return;
    }
    _upsertThreadRecord(
      normalizedSessionKey,
      workspaceRef: nextWorkspaceRef,
      workspaceRefKind: WorkspaceRefKind.objectStore,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
  }

  List<GatewaySkillSummary> get skills => assistantImportedSkillsForSession(
    _currentSessionKey,
  ).map(_gatewaySkillFromThreadEntry).toList(growable: false);

  List<GatewayModelSummary> get models {
    if (_relayModels.isNotEmpty &&
        assistantExecutionTargetForSession(_currentSessionKey) !=
            AssistantExecutionTarget.singleAgent) {
      return _relayModels;
    }
    return aiGatewayConversationModelChoices
        .map(
          (item) => GatewayModelSummary(
            id: item,
            name: item,
            provider: _settings.defaultProvider.trim().isEmpty
                ? 'gateway'
                : _settings.defaultProvider.trim(),
            contextWindow: null,
            maxOutputTokens: null,
          ),
        )
        .toList(growable: false);
  }

  bool get currentSingleAgentNeedsAiGatewayConfiguration =>
      currentSingleAgentUsesAiChatFallback && !canUseAiGatewayConversation;

  List<SecretReferenceEntry> get secretReferences {
    final entries = <SecretReferenceEntry>[
      if (storedRelayTokenMaskForProfile(kGatewayLocalProfileIndex) != null)
        SecretReferenceEntry(
          name: 'gateway_token.local',
          provider: 'Gateway',
          module: 'Assistant',
          maskedValue: storedRelayTokenMaskForProfile(
            kGatewayLocalProfileIndex,
          )!,
          status: 'In Use',
        ),
      if (storedRelayPasswordMaskForProfile(kGatewayLocalProfileIndex) != null)
        SecretReferenceEntry(
          name: 'gateway_password.local',
          provider: 'Gateway',
          module: 'Assistant',
          maskedValue: storedRelayPasswordMaskForProfile(
            kGatewayLocalProfileIndex,
          )!,
          status: 'In Use',
        ),
      if (storedRelayTokenMaskForProfile(kGatewayRemoteProfileIndex) != null)
        SecretReferenceEntry(
          name: 'gateway_token.remote',
          provider: 'Gateway',
          module: 'Assistant',
          maskedValue: storedRelayTokenMaskForProfile(
            kGatewayRemoteProfileIndex,
          )!,
          status: 'In Use',
        ),
      if (storedRelayPasswordMaskForProfile(kGatewayRemoteProfileIndex) != null)
        SecretReferenceEntry(
          name: 'gateway_password.remote',
          provider: 'Gateway',
          module: 'Assistant',
          maskedValue: storedRelayPasswordMaskForProfile(
            kGatewayRemoteProfileIndex,
          )!,
          status: 'In Use',
        ),
      if (storedAiGatewayApiKeyMask != null)
        SecretReferenceEntry(
          name: _settings.aiGateway.apiKeyRef,
          provider: 'LLM API',
          module: 'Settings',
          maskedValue: storedAiGatewayApiKeyMask!,
          status: 'In Use',
        ),
      SecretReferenceEntry(
        name: _settings.aiGateway.name,
        provider: 'LLM API',
        module: 'Settings',
        maskedValue: _settings.aiGateway.baseUrl.trim().isEmpty
            ? 'Not set'
            : _settings.aiGateway.baseUrl.trim(),
        status: _settings.aiGateway.syncState,
      ),
    ];
    return entries;
  }

  List<GatewayChatMessage> get chatMessages {
    final base = List<GatewayChatMessage>.from(_currentRecord.messages);
    final streaming = _streamingTextBySession[_currentSessionKey]?.trim() ?? '';
    if (streaming.isNotEmpty) {
      base.add(
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
    return base;
  }

  List<WebConversationSummary> get conversations {
    final archivedKeys = _settings.assistantArchivedTaskKeys
        .map(_normalizedSessionKey)
        .toSet();
    final entries =
        _threadRecords.values
            .where(
              (record) =>
                  !record.archived &&
                  !archivedKeys.contains(
                    _normalizedSessionKey(record.sessionKey),
                  ),
            )
            .map(
              (record) => WebConversationSummary(
                sessionKey: record.sessionKey,
                title: _titleForRecord(record),
                preview: _previewForRecord(record),
                updatedAtMs:
                    record.updatedAtMs ??
                    DateTime.now().millisecondsSinceEpoch.toDouble(),
                executionTarget: assistantExecutionTargetForSession(
                  record.sessionKey,
                ),
                pending: _pendingSessionKeys.contains(record.sessionKey),
                current: record.sessionKey == _currentSessionKey,
              ),
            )
            .toList(growable: true)
          ..sort((left, right) {
            if (left.current != right.current) {
              return left.current ? -1 : 1;
            }
            return right.updatedAtMs.compareTo(left.updatedAtMs);
          });
    return entries;
  }

  List<WebConversationSummary> conversationsForTarget(
    AssistantExecutionTarget target,
  ) {
    return conversations
        .where((item) => item.executionTarget == target)
        .toList(growable: false);
  }

  String get aiGatewayUrl => _settings.aiGateway.baseUrl.trim();
  String get resolvedAiGatewayModel {
    final current = _settings.defaultModel.trim();
    final choices = aiGatewayConversationModelChoices;
    if (choices.contains(current)) {
      return current;
    }
    if (choices.isNotEmpty) {
      return choices.first;
    }
    return '';
  }

  List<String> get aiGatewayConversationModelChoices {
    final selected = _settings.aiGateway.selectedModels
        .map((item) => item.trim())
        .where(
          (item) =>
              item.isNotEmpty &&
              _settings.aiGateway.availableModels.contains(item),
        )
        .toList(growable: false);
    if (selected.isNotEmpty) {
      return selected;
    }
    return _settings.aiGateway.availableModels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  bool get canUseAiGatewayConversation =>
      aiGatewayUrl.isNotEmpty &&
      _aiGatewayApiKeyCache.trim().isNotEmpty &&
      resolvedAiGatewayModel.isNotEmpty;

  AssistantThreadConnectionState get currentAssistantConnectionState =>
      assistantConnectionStateForSession(_currentSessionKey);

  AssistantThreadConnectionState assistantConnectionStateForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      final provider = singleAgentProviderForSession(normalizedSessionKey);
      final model = assistantModelForSession(normalizedSessionKey);
      final host = _hostLabel(_settings.aiGateway.baseUrl);
      if (provider == SingleAgentProvider.auto) {
        final detail = _joinConnectionParts(<String>[model, host]);
        return AssistantThreadConnectionState(
          executionTarget: target,
          status: canUseAiGatewayConversation
              ? RuntimeConnectionStatus.connected
              : RuntimeConnectionStatus.offline,
          primaryLabel: target.label,
          detailLabel: detail.isEmpty
              ? appText('单机智能体未配置', 'Single Agent not configured')
              : detail,
          ready: canUseAiGatewayConversation,
          pairingRequired: false,
          gatewayTokenMissing: false,
          lastError: null,
        );
      }
      final remoteAddress = _gatewayAddressLabel(
        _settings.primaryRemoteGatewayProfile,
      );
      final remoteReady =
          connection.status == RuntimeConnectionStatus.connected &&
          connection.mode == RuntimeConnectionMode.remote;
      return AssistantThreadConnectionState(
        executionTarget: target,
        status: remoteReady
            ? RuntimeConnectionStatus.connected
            : RuntimeConnectionStatus.offline,
        primaryLabel: target.label,
        detailLabel: remoteReady
            ? _joinConnectionParts(<String>[provider.label, model])
            : appText(
                '${provider.label} 需要 Remote ACP（${remoteAddress.isEmpty ? 'Remote Gateway' : remoteAddress}）',
                '${provider.label} requires Remote ACP (${remoteAddress.isEmpty ? 'Remote Gateway' : remoteAddress}).',
              ),
        ready: remoteReady,
        pairingRequired: false,
        gatewayTokenMissing: false,
        lastError: null,
      );
    }
    final expectedMode = target == AssistantExecutionTarget.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    final profile = target == AssistantExecutionTarget.local
        ? _settings.primaryLocalGatewayProfile
        : _settings.primaryRemoteGatewayProfile;
    final matchesTarget = connection.mode == expectedMode;
    final detail = matchesTarget
        ? (connection.remoteAddress?.trim().isNotEmpty == true
              ? connection.remoteAddress!.trim()
              : _gatewayAddressLabel(profile))
        : _gatewayAddressLabel(profile);
    return AssistantThreadConnectionState(
      executionTarget: target,
      status: matchesTarget
          ? connection.status
          : RuntimeConnectionStatus.offline,
      primaryLabel:
          (matchesTarget ? connection.status : RuntimeConnectionStatus.offline)
              .label,
      detailLabel: detail.isEmpty
          ? appText('Relay 未连接', 'Relay offline')
          : detail,
      ready:
          matchesTarget &&
          connection.status == RuntimeConnectionStatus.connected,
      pairingRequired: false,
      gatewayTokenMissing: false,
      lastError: null,
    );
  }

  String get assistantConnectionStatusLabel =>
      currentAssistantConnectionState.primaryLabel;

  String get assistantConnectionTargetLabel {
    return currentAssistantConnectionState.detailLabel;
  }

  String _joinConnectionParts(List<String> parts) {
    return parts
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(' · ');
  }

  String get conversationPersistenceSummary {
    if (usesRemoteSessionPersistence) {
      return appText(
        '当前会话会同步到远端 Session API，并在浏览器中保留一份本地缓存用于恢复。',
        'Conversation history syncs to the remote session API and keeps a browser cache for local recovery.',
      );
    }
    return appText(
      '当前会话列表会在浏览器本地保存，刷新后仍可恢复单机智能体 / Relay 的历史入口。',
      'Conversation history is stored in this browser so Single Agent and Relay entries remain available after reload.',
    );
  }

  String get currentConversationTitle => _titleForRecord(_currentRecord);

  AssistantThreadRecord get _currentRecord {
    final existing = _threadRecords[_currentSessionKey];
    if (existing != null) {
      return existing;
    }
    final target =
        _sanitizeTarget(_settings.assistantExecutionTarget) ??
        AssistantExecutionTarget.singleAgent;
    final record = _newRecord(target: target);
    _threadRecords[record.sessionKey] = record;
    _currentSessionKey = record.sessionKey;
    return record;
  }
}
