part of 'app_controller_web.dart';

WebSessionRepository _defaultRemoteSessionRepository(
  WebSessionPersistenceConfig config,
  String clientId,
  String accessToken,
) {
  return RemoteWebSessionRepository(
    baseUrl: config.remoteBaseUrl,
    clientId: clientId,
    accessToken: accessToken,
  );
}

extension AppControllerWebHelpers on AppController {
  SettingsTab _sanitizeSettingsTab(SettingsTab tab) {
    return switch (tab) {
      SettingsTab.workspace ||
      SettingsTab.agents ||
      SettingsTab.diagnostics ||
      SettingsTab.experimental => SettingsTab.gateway,
      _ => tab,
    };
  }

  SettingsSnapshot _sanitizeSettings(SettingsSnapshot snapshot) {
    final allowedDestinations = featuresFor(
      UiFeaturePlatform.web,
    ).allowedDestinations;
    final target = featuresFor(UiFeaturePlatform.web).sanitizeExecutionTarget(
      _sanitizeTarget(snapshot.assistantExecutionTarget),
    );
    final assistantNavigationDestinations =
        normalizeAssistantNavigationDestinations(
              snapshot.assistantNavigationDestinations,
            )
            .where((entry) {
              final destination = entry.destination;
              if (destination != null) {
                return allowedDestinations.contains(destination);
              }
              return allowedDestinations.contains(
                WorkspaceDestination.settings,
              );
            })
            .toList(growable: false);
    final normalizedSessionBaseUrl =
        RemoteWebSessionRepository.normalizeBaseUrl(
          snapshot.webSessionPersistence.remoteBaseUrl,
        )?.toString() ??
        '';
    final localProfile = snapshot.primaryLocalGatewayProfile.copyWith(
      mode: RuntimeConnectionMode.local,
      useSetupCode: false,
      setupCode: '',
      tls: false,
    );
    final remoteProfile = snapshot.primaryRemoteGatewayProfile.copyWith(
      mode: RuntimeConnectionMode.remote,
      useSetupCode: false,
      setupCode: '',
    );
    return snapshot.copyWith(
      assistantExecutionTarget: target,
      gatewayProfiles: replaceGatewayProfileAt(
        replaceGatewayProfileAt(
          snapshot.gatewayProfiles,
          kGatewayLocalProfileIndex,
          localProfile,
        ),
        kGatewayRemoteProfileIndex,
        remoteProfile,
      ),
      webSessionPersistence: snapshot.webSessionPersistence.copyWith(
        remoteBaseUrl: normalizedSessionBaseUrl,
      ),
      assistantNavigationDestinations: assistantNavigationDestinations,
    );
  }

  AssistantThreadRecord _sanitizeRecord(AssistantThreadRecord record) {
    final target =
        _sanitizeTarget(record.executionTarget) ??
        AssistantExecutionTarget.singleAgent;
    return record.copyWith(
      executionTarget: target,
      title: record.title.trim().isEmpty
          ? appText('新对话', 'New conversation')
          : record.title.trim(),
      workspaceRef: record.workspaceRef.trim().isEmpty
          ? _defaultWorkspaceRefForSession(record.sessionKey)
          : record.workspaceRef.trim(),
      workspaceRefKind: record.workspaceRef.trim().isEmpty
          ? WorkspaceRefKind.objectStore
          : record.workspaceRefKind,
    );
  }

  AssistantExecutionTarget? _sanitizeTarget(AssistantExecutionTarget? target) {
    return switch (target) {
      AssistantExecutionTarget.local => AssistantExecutionTarget.local,
      AssistantExecutionTarget.remote => AssistantExecutionTarget.remote,
      AssistantExecutionTarget.singleAgent =>
        AssistantExecutionTarget.singleAgent,
      _ => AssistantExecutionTarget.singleAgent,
    };
  }

  AssistantThreadRecord _newRecord({
    required AssistantExecutionTarget target,
    String? title,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final prefix = switch (target) {
      AssistantExecutionTarget.singleAgent => 'single',
      AssistantExecutionTarget.local => 'local',
      AssistantExecutionTarget.remote => 'remote',
    };
    return AssistantThreadRecord(
      sessionKey: '$prefix:$timestamp',
      messages: const <GatewayChatMessage>[],
      updatedAtMs: timestamp.toDouble(),
      title: title ?? appText('新对话', 'New conversation'),
      archived: false,
      executionTarget: target,
      messageViewMode: AssistantMessageViewMode.rendered,
      workspaceRef: 'object://thread/$prefix:$timestamp',
      workspaceRefKind: WorkspaceRefKind.objectStore,
    );
  }

  void _appendAssistantMessage({
    required String sessionKey,
    required String text,
    required bool error,
  }) {
    final existing =
        _threadRecords[sessionKey] ??
        _newRecord(target: assistantExecutionTarget);
    final messages = <GatewayChatMessage>[
      ...existing.messages,
      GatewayChatMessage(
        id: _messageId(),
        role: 'assistant',
        text: text,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        toolCallId: null,
        toolName: null,
        stopReason: error ? 'error' : null,
        pending: false,
        error: error,
      ),
    ];
    _threadRecords[sessionKey] = existing.copyWith(
      messages: messages,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      title: _deriveThreadTitle(existing.title, messages, fallback: sessionKey),
    );
    _pendingSessionKeys.remove(sessionKey);
    _streamingTextBySession.remove(sessionKey);
    _recomputeDerivedWorkspaceState();
  }

  void _handleRelayEvent(GatewayPushEvent event) {
    if (event.event != 'chat') {
      return;
    }
    final payload = _castMap(event.payload);
    final sessionKey = _normalizedSessionKey(
      payload['sessionKey']?.toString() ?? '',
    );
    if (sessionKey.isEmpty) {
      return;
    }
    final state = payload['state']?.toString().trim() ?? '';
    final message = _castMap(payload['message']);
    final text = _extractMessageText(message);
    if (text.isNotEmpty && state == 'delta') {
      _appendStreamingText(sessionKey, text);
    } else if (text.isNotEmpty && state == 'final') {
      _clearStreamingText(sessionKey);
      _appendAssistantMessage(sessionKey: sessionKey, text: text, error: false);
    }
    if (state == 'final' || state == 'aborted' || state == 'error') {
      _pendingSessionKeys.remove(sessionKey);
      if (state == 'error' && text.isNotEmpty) {
        _appendAssistantMessage(
          sessionKey: sessionKey,
          text: text,
          error: true,
        );
      }
      _clearStreamingText(sessionKey);
      unawaited(refreshRelaySessions());
      unawaited(refreshRelayHistory(sessionKey: sessionKey));
    }
    _notifyChanged();
  }

  String _normalizedSessionKey(String sessionKey) {
    final trimmed = sessionKey.trim();
    return trimmed.isEmpty ? 'main' : trimmed;
  }

  AssistantExecutionTarget _assistantExecutionTargetForMode(
    RuntimeConnectionMode mode,
  ) {
    return switch (mode) {
      RuntimeConnectionMode.local => AssistantExecutionTarget.local,
      RuntimeConnectionMode.remote => AssistantExecutionTarget.remote,
      RuntimeConnectionMode.unconfigured => AssistantExecutionTarget.remote,
    };
  }

  int _profileIndexForTarget(AssistantExecutionTarget target) {
    return switch (target) {
      AssistantExecutionTarget.local => kGatewayLocalProfileIndex,
      AssistantExecutionTarget.remote => kGatewayRemoteProfileIndex,
      AssistantExecutionTarget.singleAgent => kGatewayRemoteProfileIndex,
    };
  }

  GatewayConnectionProfile _profileForTarget(AssistantExecutionTarget target) {
    return switch (target) {
      AssistantExecutionTarget.local => _settings.primaryLocalGatewayProfile,
      AssistantExecutionTarget.remote => _settings.primaryRemoteGatewayProfile,
      AssistantExecutionTarget.singleAgent =>
        _settings.primaryRemoteGatewayProfile,
    };
  }

  String _gatewayAddressLabel(GatewayConnectionProfile profile) {
    final host = profile.host.trim();
    if (host.isEmpty || profile.port <= 0) {
      return appText('未连接目标', 'No target');
    }
    return '$host:${profile.port}';
  }

  String _gatewayEntryStateForTarget(AssistantExecutionTarget target) {
    return target.promptValue;
  }

  void _upsertThreadRecord(
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
    bool clearGatewayEntryState = false,
    String? workspaceRef,
    WorkspaceRefKind? workspaceRefKind,
  }) {
    final key = _normalizedSessionKey(sessionKey);
    final resolvedTarget =
        _sanitizeTarget(executionTarget) ??
        assistantExecutionTargetForSession(key);
    final existing = _threadRecords[key] ?? _newRecord(target: resolvedTarget);
    _threadRecords[key] = existing.copyWith(
      sessionKey: key,
      messages: messages ?? existing.messages,
      updatedAtMs: updatedAtMs ?? existing.updatedAtMs,
      title: title ?? existing.title,
      archived: archived ?? existing.archived,
      executionTarget: resolvedTarget,
      messageViewMode: messageViewMode ?? existing.messageViewMode,
      importedSkills: importedSkills ?? existing.importedSkills,
      selectedSkillKeys: selectedSkillKeys ?? existing.selectedSkillKeys,
      assistantModelId: assistantModelId ?? existing.assistantModelId,
      singleAgentProvider: singleAgentProvider ?? existing.singleAgentProvider,
      gatewayEntryState: gatewayEntryState ?? existing.gatewayEntryState,
      clearGatewayEntryState: clearGatewayEntryState,
      workspaceRef: workspaceRef ?? existing.workspaceRef,
      workspaceRefKind: workspaceRefKind ?? existing.workspaceRefKind,
    );
    _recomputeDerivedWorkspaceState();
  }

  Future<void> _applyAssistantExecutionTarget(
    AssistantExecutionTarget target, {
    required String sessionKey,
    required bool persistDefaultSelection,
  }) async {
    final normalizedSessionKey = _normalizedSessionKey(sessionKey);
    final resolvedTarget =
        _sanitizeTarget(target) ??
        assistantExecutionTargetForSession(normalizedSessionKey);
    _upsertThreadRecord(
      normalizedSessionKey,
      executionTarget: resolvedTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      gatewayEntryState: _gatewayEntryStateForTarget(resolvedTarget),
    );
    if (persistDefaultSelection) {
      _settings = _settings.copyWith(
        assistantExecutionTarget: resolvedTarget,
        assistantLastSessionKey: normalizedSessionKey,
      );
      await _persistSettings();
      await _persistThreads();
    } else {
      await _persistThreads();
    }
    if (resolvedTarget == AssistantExecutionTarget.singleAgent) {
      return;
    }
    final targetProfile = _profileForTarget(resolvedTarget);
    if (targetProfile.host.trim().isEmpty || targetProfile.port <= 0) {
      return;
    }
    final expectedMode = resolvedTarget == AssistantExecutionTarget.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    if (connection.status == RuntimeConnectionStatus.connected &&
        connection.mode == expectedMode) {
      return;
    }
    try {
      await connectRelay(target: resolvedTarget);
    } catch (error) {
      _lastAssistantError = error.toString();
    }
  }

  Future<T> _enqueueThreadTurn<T>(String threadId, Future<T> Function() task) {
    final normalizedThreadId = _normalizedSessionKey(threadId);
    final previous =
        _threadTurnQueues[normalizedThreadId] ?? Future<void>.value();
    final completer = Completer<T>();
    late final Future<void> next;
    next = previous
        .catchError((_) {})
        .then((_) async {
          try {
            completer.complete(await task());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .whenComplete(() {
          if (identical(_threadTurnQueues[normalizedThreadId], next)) {
            _threadTurnQueues.remove(normalizedThreadId);
          }
        });
    _threadTurnQueues[normalizedThreadId] = next;
    return completer.future;
  }

  String _augmentPromptWithAttachments(
    String prompt,
    List<GatewayChatAttachmentPayload> attachments,
  ) {
    if (attachments.isEmpty) {
      return prompt;
    }
    final buffer = StringBuffer(prompt.trim());
    buffer.write('\n\n');
    buffer.writeln(appText('附件（仅供本轮参考）：', 'Attachments (for this turn only):'));
    for (final item in attachments) {
      final name = item.fileName.trim().isEmpty ? 'attachment' : item.fileName;
      final mime = item.mimeType.trim().isEmpty
          ? 'application/octet-stream'
          : item.mimeType;
      buffer.writeln('- $name ($mime)');
    }
    return buffer.toString().trim();
  }

  Uri? _acpEndpointForTarget(AssistantExecutionTarget target) {
    final resolvedTarget = target == AssistantExecutionTarget.singleAgent
        ? AssistantExecutionTarget.remote
        : target;
    final profile = _profileForTarget(resolvedTarget);
    final host = profile.host.trim();
    if (host.isEmpty) {
      return null;
    }
    final candidate = host.contains('://')
        ? host
        : '${profile.tls ? 'https' : 'http'}://$host:${profile.port}';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    final scheme = uri.scheme.trim().isEmpty
        ? (profile.tls ? 'https' : 'http')
        : uri.scheme.trim().toLowerCase();
    final resolvedPort = uri.hasPort
        ? uri.port
        : (scheme == 'https' ? 443 : 80);
    return uri.replace(
      scheme: scheme,
      port: resolvedPort,
      path: '',
      query: null,
      fragment: null,
    );
  }

  Future<Map<String, dynamic>> _requestAcpSessionMessage({
    required Uri endpoint,
    required Map<String, dynamic> params,
    required bool hasInlineAttachments,
    void Function(Map<String, dynamic> notification)? onNotification,
  }) async {
    try {
      return await _acpClient.request(
        endpoint: endpoint,
        method: 'session.message',
        params: params,
        onNotification: onNotification,
      );
    } on WebAcpException catch (error) {
      if (!hasInlineAttachments || !_canFallbackInlineAttachments(error)) {
        rethrow;
      }
      final fallbackParams = Map<String, dynamic>.from(params)
        ..remove('inlineAttachments');
      try {
        return await _acpClient.request(
          endpoint: endpoint,
          method: 'session.message',
          params: fallbackParams,
          onNotification: onNotification,
        );
      } on Object catch (fallbackError) {
        throw Exception(
          appText(
            'ACP 暂不支持 inline 附件，回退旧协议也失败：$fallbackError',
            'ACP does not support inline attachments, and fallback to legacy attachment payload failed: $fallbackError',
          ),
        );
      }
    }
  }

  Future<void> _refreshAcpCapabilities(Uri endpoint) async {
    try {
      _acpCapabilities = await _acpClient.loadCapabilities(endpoint: endpoint);
    } catch (_) {
      _acpCapabilities = const WebAcpCapabilities.empty();
    }
  }

  bool _canFallbackInlineAttachments(WebAcpException error) {
    final code = (error.code ?? '').trim();
    if (code == '-32602' || code == 'INVALID_PARAMS') {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('inlineattachment') ||
        message.contains('unexpected field') ||
        message.contains('unknown field') ||
        message.contains('invalid params');
  }

  bool _unsupportedAcpSkillsStatus(WebAcpException error) {
    final code = (error.code ?? '').trim();
    if (code == '-32601' || code == 'METHOD_NOT_FOUND') {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('unknown method') ||
        message.contains('method not found') ||
        message.contains('skills.status');
  }

  int _base64Size(String base64) {
    final normalized = base64.trim().split(',').last.trim();
    if (normalized.isEmpty) {
      return 0;
    }
    final padding = normalized.endsWith('==')
        ? 2
        : (normalized.endsWith('=') ? 1 : 0);
    return (normalized.length * 3 ~/ 4) - padding;
  }

  _AcpSessionUpdate? _acpSessionUpdateFromNotification(
    Map<String, dynamic> notification, {
    required String sessionKey,
  }) {
    final method =
        notification['method']?.toString().trim().toLowerCase() ?? '';
    final params = _castMap(notification['params']);
    final payload = params.isNotEmpty
        ? params
        : _castMap(notification['payload']);
    final event = payload['event']?.toString().trim().toLowerCase() ?? method;
    final type =
        payload['type']?.toString().trim().toLowerCase() ??
        payload['state']?.toString().trim().toLowerCase() ??
        event;
    final payloadSession = _normalizedSessionKey(
      payload['sessionId']?.toString() ??
          payload['threadId']?.toString() ??
          payload['sessionKey']?.toString() ??
          sessionKey,
    );
    if (payloadSession != _normalizedSessionKey(sessionKey)) {
      return null;
    }
    final messageMap = _castMap(payload['message']);
    final messageText = _extractMessageText(messageMap).trim().isNotEmpty
        ? _extractMessageText(messageMap).trim()
        : payload['message']?.toString().trim() ?? '';
    final text =
        payload['delta']?.toString() ??
        payload['text']?.toString() ??
        payload['outputDelta']?.toString() ??
        '';
    final error =
        (payload['error'] is bool && payload['error'] as bool) ||
        type == 'error' ||
        event.contains('error');
    return _AcpSessionUpdate(
      type: type,
      text: text,
      message: messageText,
      error: error,
    );
  }

  void _appendStreamingText(String sessionKey, String delta) {
    if (delta.isEmpty) {
      return;
    }
    final key = _normalizedSessionKey(sessionKey);
    final current = _streamingTextBySession[key] ?? '';
    _streamingTextBySession[key] = '$current$delta';
  }

  void _clearStreamingText(String sessionKey) {
    _streamingTextBySession.remove(_normalizedSessionKey(sessionKey));
  }

  Future<void> _persistSettings() async {
    await _store.saveSettingsSnapshot(_settings);
  }

  void _saveSecretDraft(String key, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _draftSecretValues.remove(key);
    } else {
      _draftSecretValues[key] = trimmed;
    }
    _settingsDraftStatusMessage = appText(
      '草稿已更新，点击顶部保存持久化。',
      'Draft updated. Use the top Save button to persist it.',
    );
    _notifyChanged();
  }

  Future<void> _persistDraftSecrets() async {
    final aiGatewayApiKey =
        _draftSecretValues[AppController._draftAiGatewayApiKeyKey];
    if ((aiGatewayApiKey ?? '').isNotEmpty) {
      _aiGatewayApiKeyCache = aiGatewayApiKey!;
      await _store.saveAiGatewayApiKey(_aiGatewayApiKeyCache);
    }
    _draftSecretValues.clear();
  }

  Future<void> _persistThreads() async {
    final records = _threadRecords.values.toList(growable: false);
    await _browserSessionRepository.saveThreadRecords(records);
    final invalidRemoteConfigMessage = _invalidRemoteSessionConfigMessage();
    if (invalidRemoteConfigMessage != null) {
      _sessionPersistenceStatusMessage = invalidRemoteConfigMessage;
      return;
    }
    final remoteRepository = _resolveRemoteSessionRepository();
    if (remoteRepository == null) {
      _sessionPersistenceStatusMessage = '';
      return;
    }
    try {
      await remoteRepository.saveThreadRecords(records);
      _sessionPersistenceStatusMessage = appText(
        '远端 Session API 已同步，浏览器缓存仍保留一份本地副本。',
        'Remote session API synced successfully; the browser cache remains as a local fallback.',
      );
    } catch (error) {
      _sessionPersistenceStatusMessage = _sessionPersistenceErrorLabel(error);
    }
  }

  Future<List<AssistantThreadRecord>> _loadThreadRecords() async {
    final browserRecords = await _browserSessionRepository.loadThreadRecords();
    final invalidRemoteConfigMessage = _invalidRemoteSessionConfigMessage();
    if (invalidRemoteConfigMessage != null) {
      _sessionPersistenceStatusMessage = invalidRemoteConfigMessage;
      return browserRecords;
    }
    final remoteRepository = _resolveRemoteSessionRepository();
    if (remoteRepository == null) {
      _sessionPersistenceStatusMessage = '';
      return browserRecords;
    }
    try {
      final remoteRecords = await remoteRepository.loadThreadRecords();
      if (remoteRecords.isNotEmpty) {
        _sessionPersistenceStatusMessage = appText(
          '远端 Session API 已启用，并覆盖浏览器中的本地缓存。',
          'Remote session API is active and overrides the browser cache.',
        );
        await _browserSessionRepository.saveThreadRecords(remoteRecords);
        return remoteRecords;
      }
      _sessionPersistenceStatusMessage = appText(
        '远端 Session API 已启用，但当前为空；浏览器缓存不会自动导入远端。',
        'The remote session API is active but empty, and the browser cache will not be imported automatically.',
      );
      return const <AssistantThreadRecord>[];
    } catch (error) {
      _sessionPersistenceStatusMessage = _sessionPersistenceErrorLabel(error);
      return browserRecords;
    }
  }

  WebSessionRepository? _resolveRemoteSessionRepository() {
    final config = _settings.webSessionPersistence;
    if (config.mode != WebSessionPersistenceMode.remote) {
      return null;
    }
    final normalizedBaseUrl = RemoteWebSessionRepository.normalizeBaseUrl(
      config.remoteBaseUrl,
    );
    if (normalizedBaseUrl == null) {
      return null;
    }
    return _remoteSessionRepositoryBuilder(
      config.copyWith(remoteBaseUrl: normalizedBaseUrl.toString()),
      _webSessionClientId,
      _webSessionApiTokenCache,
    );
  }

  String? _invalidRemoteSessionConfigMessage() {
    final config = _settings.webSessionPersistence;
    if (config.mode != WebSessionPersistenceMode.remote ||
        config.remoteBaseUrl.trim().isEmpty) {
      return null;
    }
    if (RemoteWebSessionRepository.normalizeBaseUrl(config.remoteBaseUrl) !=
        null) {
      return null;
    }
    return appText(
      'Session API URL 无效。请使用 HTTPS，或仅在 localhost / 127.0.0.1 开发环境中使用 HTTP。',
      'The Session API URL is invalid. Use HTTPS, or HTTP only for localhost / 127.0.0.1 during development.',
    );
  }

  String _sessionPersistenceErrorLabel(Object error) {
    return appText(
      '远端 Session API 当前不可用，已回退到浏览器缓存。${error.toString()}',
      'The remote session API is unavailable, so XWorkmate fell back to the browser cache. ${error.toString()}',
    );
  }

  String _titleForRecord(AssistantThreadRecord record) {
    final customTitle =
        _settings
            .assistantCustomTaskTitles[_normalizedSessionKey(record.sessionKey)]
            ?.trim() ??
        '';
    if (customTitle.isNotEmpty) {
      return customTitle;
    }
    final title = record.title.trim();
    if (title.isNotEmpty) {
      return title;
    }
    return _deriveThreadTitle('', record.messages, fallback: record.sessionKey);
  }

  String _previewForRecord(AssistantThreadRecord record) {
    for (final message in record.messages.reversed) {
      final text = message.text.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return appText(
      '等待描述这个任务的第一条消息',
      'Waiting for the first message of this task',
    );
  }

  String _deriveThreadTitle(
    String currentTitle,
    List<GatewayChatMessage> messages, {
    String fallback = '',
  }) {
    final trimmedCurrent = currentTitle.trim();
    if (trimmedCurrent.isNotEmpty &&
        trimmedCurrent != appText('新对话', 'New conversation')) {
      return trimmedCurrent;
    }
    for (final message in messages) {
      if (message.role.trim().toLowerCase() != 'user') {
        continue;
      }
      final text = message.text.trim();
      if (text.isEmpty) {
        continue;
      }
      return text.length <= 32 ? text : '${text.substring(0, 32)}...';
    }
    return fallback.isEmpty ? appText('新对话', 'New conversation') : fallback;
  }

  String _hostLabel(String rawUrl) {
    final normalized = _aiGatewayClient.normalizeBaseUrl(rawUrl);
    return normalized?.host.trim() ?? '';
  }

  String _messageId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  Map<String, dynamic> _castMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  String _extractMessageText(Map<String, dynamic> message) {
    final directContent = message['content'];
    if (directContent is String) {
      return directContent;
    }
    final parts = <String>[];
    if (directContent is List) {
      for (final part in directContent) {
        final map = _castMap(part);
        final text = map['text']?.toString().trim();
        if (text != null && text.isNotEmpty) {
          parts.add(text);
        }
      }
    }
    return parts.join('\n').trim();
  }
}

class _AcpSessionUpdate {
  const _AcpSessionUpdate({
    required this.type,
    required this.text,
    required this.message,
    required this.error,
  });

  final String type;
  final String text;
  final String message;
  final bool error;
}

class WebConversationSummary {
  const WebConversationSummary({
    required this.sessionKey,
    required this.title,
    required this.preview,
    required this.updatedAtMs,
    required this.executionTarget,
    required this.pending,
    required this.current,
  });

  final String sessionKey;
  final String title;
  final String preview;
  final double updatedAtMs;
  final AssistantExecutionTarget executionTarget;
  final bool pending;
  final bool current;
}
