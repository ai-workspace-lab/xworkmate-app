part of 'app_controller_desktop.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopRuntimeHelpers on AppController {
  Future<void> _persistAssistantLastSessionKey(String sessionKey) async {
    if (_disposed) {
      return;
    }
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    if (normalizedSessionKey.isEmpty ||
        settings.assistantLastSessionKey == normalizedSessionKey) {
      return;
    }
    try {
      await AppControllerDesktopSettings(this).saveSettings(
        settings.copyWith(assistantLastSessionKey: normalizedSessionKey),
        refreshAfterSave: false,
      );
    } catch (_) {
      // Best effort only during teardown-sensitive transitions.
    }
  }

  void _setAiGatewayStreamingText(String sessionKey, String text) {
    final key = _normalizedAssistantSessionKey(sessionKey);
    if (text.trim().isEmpty) {
      _aiGatewayStreamingTextBySession.remove(key);
    } else {
      _aiGatewayStreamingTextBySession[key] = text;
    }
    _notifyIfActive();
  }

  void _appendAiGatewayStreamingText(String sessionKey, String delta) {
    if (delta.isEmpty) {
      return;
    }
    final key = _normalizedAssistantSessionKey(sessionKey);
    final current = _aiGatewayStreamingTextBySession[key] ?? '';
    _aiGatewayStreamingTextBySession[key] = '$current$delta';
    _notifyIfActive();
  }

  void _clearAiGatewayStreamingText(String sessionKey) {
    final key = _normalizedAssistantSessionKey(sessionKey);
    if (_aiGatewayStreamingTextBySession.remove(key) != null) {
      _notifyIfActive();
    }
  }

  String _nextLocalMessageId() {
    _localMessageCounter += 1;
    return 'local-${DateTime.now().microsecondsSinceEpoch}-$_localMessageCounter';
  }

  Future<T> _enqueueThreadTurn<T>(String threadId, Future<T> Function() task) {
    final normalizedThreadId = _normalizedAssistantSessionKey(threadId);
    final previous =
        _assistantThreadTurnQueues[normalizedThreadId] ?? Future<void>.value();
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
          if (identical(_assistantThreadTurnQueues[normalizedThreadId], next)) {
            _assistantThreadTurnQueues.remove(normalizedThreadId);
          }
        });
    _assistantThreadTurnQueues[normalizedThreadId] = next;
    return completer.future;
  }

  Uri? _normalizeAiGatewayBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    final pathSegments = uri.pathSegments.where((item) => item.isNotEmpty);
    return uri.replace(
      pathSegments: pathSegments.isEmpty ? const <String>['v1'] : pathSegments,
      query: null,
      fragment: null,
    );
  }

  Uri _aiGatewayChatUri(Uri baseUrl) {
    final pathSegments = baseUrl.pathSegments
        .where((item) => item.isNotEmpty)
        .toList(growable: true);
    if (pathSegments.isEmpty) {
      pathSegments.add('v1');
    }
    if (pathSegments.length >= 2 &&
        pathSegments[pathSegments.length - 2] == 'chat' &&
        pathSegments.last == 'completions') {
      return baseUrl.replace(query: null, fragment: null);
    }
    if (pathSegments.last == 'models') {
      pathSegments.removeLast();
    }
    if (pathSegments.last != 'chat') {
      pathSegments.add('chat');
    }
    pathSegments.add('completions');
    return baseUrl.replace(
      pathSegments: pathSegments,
      query: null,
      fragment: null,
    );
  }

  String _aiGatewayHostLabel(String raw) {
    final uri = _normalizeAiGatewayBaseUrl(raw);
    if (uri == null) {
      return '';
    }
    if (uri.hasPort) {
      return '${uri.host}:${uri.port}';
    }
    return uri.host;
  }

  String _aiGatewayErrorLabel(Object error) {
    if (error is _AiGatewayChatException) {
      return error.message;
    }
    if (error is SocketException) {
      return appText('无法连接到 LLM API。', 'Unable to reach the LLM API.');
    }
    if (error is HandshakeException) {
      return appText('LLM API TLS 握手失败。', 'LLM API TLS handshake failed.');
    }
    if (error is TimeoutException) {
      return appText('LLM API 请求超时。', 'LLM API request timed out.');
    }
    if (error is FormatException) {
      return appText(
        'LLM API 返回了无法解析的响应。',
        'LLM API returned an invalid response.',
      );
    }
    return error.toString();
  }

  String _formatAiGatewayHttpError(int statusCode, String detail) {
    final base = switch (statusCode) {
      400 => appText(
        'LLM API 请求无效 (400)',
        'LLM API rejected the request (400)',
      ),
      401 => appText(
        'LLM API 鉴权失败 (401)',
        'LLM API authentication failed (401)',
      ),
      403 => appText('LLM API 拒绝访问 (403)', 'LLM API denied access (403)'),
      404 => appText(
        'LLM API chat 接口不存在 (404)',
        'LLM API chat endpoint was not found (404)',
      ),
      429 => appText(
        'LLM API 限流 (429)',
        'LLM API rate limited the request (429)',
      ),
      >= 500 => appText(
        'LLM API 当前不可用 ($statusCode)',
        'LLM API is unavailable right now ($statusCode)',
      ),
      _ => appText(
        'LLM API 返回状态码 $statusCode',
        'LLM API responded with status $statusCode',
      ),
    };
    final trimmed = detail.trim();
    return trimmed.isEmpty ? base : '$base · $trimmed';
  }

  String _extractAiGatewayErrorDetail(String body) {
    if (body.trim().isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(_extractFirstJsonDocument(body));
      final map = asMap(decoded);
      final error = asMap(map['error']);
      return (stringValue(error['message']) ??
              stringValue(map['message']) ??
              stringValue(map['detail']) ??
              '')
          .trim();
    } on FormatException {
      return '';
    }
  }

  String _extractAiGatewayAssistantText(Object? decoded) {
    final map = asMap(decoded);
    final choices = asList(map['choices']);
    if (choices.isNotEmpty) {
      final firstChoice = asMap(choices.first);
      final message = asMap(firstChoice['message']);
      final content = _extractAiGatewayContent(message['content']);
      if (content.isNotEmpty) {
        return content;
      }
    }

    final output = asList(map['output']);
    for (final item in output) {
      final entry = asMap(item);
      final content = _extractAiGatewayContent(entry['content']);
      if (content.isNotEmpty) {
        return content;
      }
    }

    final direct = _extractAiGatewayContent(map['content']);
    if (direct.isNotEmpty) {
      return direct;
    }
    return stringValue(map['output_text'])?.trim() ?? '';
  }

  String _extractAiGatewayContent(Object? content) {
    if (content is String) {
      return content.trim();
    }
    final parts = <String>[];
    for (final item in asList(content)) {
      final map = asMap(item);
      final nestedText = stringValue(map['text']);
      if (nestedText != null && nestedText.trim().isNotEmpty) {
        parts.add(nestedText.trim());
        continue;
      }
      final type = stringValue(map['type']) ?? '';
      if (type == 'output_text') {
        final text = stringValue(map['text']) ?? stringValue(map['value']);
        if (text != null && text.trim().isNotEmpty) {
          parts.add(text.trim());
        }
      }
    }
    return parts.join('\n').trim();
  }

  String _extractFirstJsonDocument(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty response body');
    }
    final start = trimmed.indexOf(RegExp(r'[\{\[]'));
    if (start < 0) {
      throw const FormatException('Missing JSON document');
    }
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < trimmed.length; index++) {
      final char = trimmed[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (char == '{' || char == '[') {
        depth += 1;
      } else if (char == '}' || char == ']') {
        depth -= 1;
        if (depth == 0) {
          return trimmed.substring(start, index + 1);
        }
      }
    }
    throw const FormatException('Unterminated JSON document');
  }

  SettingsSnapshot _sanitizeCodeAgentSettings(SettingsSnapshot snapshot) {
    final normalizedRuntimeMode =
        snapshot.codeAgentRuntimeMode == CodeAgentRuntimeMode.builtIn
        ? CodeAgentRuntimeMode.externalCli
        : snapshot.codeAgentRuntimeMode;
    _codexRuntimeWarning =
        snapshot.codeAgentRuntimeMode == CodeAgentRuntimeMode.builtIn
        ? appText(
            '内置 Codex 运行时当前仅保留为未来扩展位；已自动切换为 External Codex CLI。',
            'Built-in Codex runtime is reserved for a future release; XWorkmate switched back to External Codex CLI automatically.',
          )
        : null;
    final normalizedPath = snapshot.codexCliPath.trim();
    if (normalizedPath == snapshot.codexCliPath &&
        normalizedRuntimeMode == snapshot.codeAgentRuntimeMode) {
      return snapshot;
    }
    return snapshot.copyWith(
      codeAgentRuntimeMode: normalizedRuntimeMode,
      codexCliPath: normalizedPath,
    );
  }

  Future<void> _refreshAcpCapabilities({
    bool forceRefresh = false,
    bool persistMountTargets = false,
  }) async {
    GatewayAcpCapabilities capabilities;
    try {
      capabilities = await _gatewayAcpClient.loadCapabilities(
        forceRefresh: forceRefresh,
      );
    } catch (_) {
      capabilities = const GatewayAcpCapabilities.empty();
    }
    if (persistMountTargets && !_disposed) {
      final currentConfig = settings.multiAgent;
      final nextTargets = _mergeAcpCapabilitiesIntoMountTargets(
        currentConfig.mountTargets,
        capabilities,
      );
      final nextConfig = currentConfig.copyWith(mountTargets: nextTargets);
      if (jsonEncode(nextConfig.toJson()) !=
          jsonEncode(currentConfig.toJson())) {
        await _settingsController.saveSnapshot(
          settings.copyWith(multiAgent: nextConfig),
        );
        _multiAgentOrchestrator.updateConfig(nextConfig);
      }
    }
    _notifyIfActive();
  }

  Future<void> _refreshSingleAgentCapabilities({
    bool forceRefresh = false,
  }) async {
    final gatewayToken = await settingsController.loadGatewayToken();
    final next = <SingleAgentProvider, DirectSingleAgentCapabilities>{};
    for (final provider in configuredSingleAgentProviders) {
      final profile = settings.externalAcpEndpointForProvider(provider);
      if (!profile.enabled || profile.endpoint.trim().isEmpty) {
        next[provider] = const DirectSingleAgentCapabilities.unavailable(
          endpoint: '',
        );
        continue;
      }
      try {
        next[provider] = await _singleAgentAppServerClient.loadCapabilities(
          provider: provider,
          forceRefresh: forceRefresh,
          gatewayToken: gatewayToken,
        );
      } catch (_) {
        next[provider] = const DirectSingleAgentCapabilities.unavailable(
          endpoint: '',
        );
      }
    }
    _singleAgentCapabilitiesByProvider = next;
    if (!_disposed) {
      _notifyIfActive();
    }
  }

  Future<void> _refreshResolvedCodexCliPath() async {
    if (effectiveCodeAgentRuntimeMode != CodeAgentRuntimeMode.externalCli) {
      _resolvedCodexCliPath = null;
      return;
    }
    if (shouldBlockEmbeddedAgentLaunch(
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    )) {
      _resolvedCodexCliPath = null;
      return;
    }

    final configuredPath = configuredCodexCliPath;
    String? detectedPath;
    if (configuredPath.isNotEmpty) {
      try {
        if (await File(configuredPath).exists()) {
          detectedPath = configuredPath;
        }
      } catch (_) {
        detectedPath = null;
      }
    }
    detectedPath ??= await _runtimeCoordinator.codex.findCodexBinary();
    if (_disposed) {
      return;
    }
    _resolvedCodexCliPath = detectedPath;
  }

  List<ManagedMountTargetState> _mergeAcpCapabilitiesIntoMountTargets(
    List<ManagedMountTargetState> current,
    GatewayAcpCapabilities capabilities,
  ) {
    final source = current.isEmpty
        ? ManagedMountTargetState.defaults()
        : current;
    final providers = capabilities.providers
        .map((item) => item.providerId)
        .toSet();
    return source
        .map((item) {
          final available = switch (item.targetId) {
            'codex' => providers.contains('codex'),
            'opencode' => providers.contains('opencode'),
            'claude' => providers.contains('claude'),
            'gemini' => providers.contains('gemini'),
            'aris' => capabilities.multiAgent,
            'openclaw' => capabilities.multiAgent || capabilities.singleAgent,
            _ => false,
          };
          return item.copyWith(
            available: available,
            discoveryState: available ? 'ready' : 'unavailable',
            syncState: available ? item.syncState : 'idle',
            detail: available
                ? appText(
                    '来源：Gateway ACP capabilities',
                    'Source: Gateway ACP capabilities',
                  )
                : appText(
                    'Gateway ACP 未报告该能力。',
                    'Gateway ACP did not report this capability.',
                  ),
          );
        })
        .toList(growable: false);
  }

  String? _assistantWorkingDirectoryForSession(String sessionKey) {
    final candidate = assistantWorkspaceRefForSession(sessionKey).trim();
    if (candidate.isEmpty) {
      return null;
    }
    return candidate;
  }

  String? _resolveLocalAssistantWorkingDirectoryForSession(
    String sessionKey, {
    bool requireLocalExistence = true,
  }) {
    if (assistantWorkspaceRefKindForSession(sessionKey) !=
        WorkspaceRefKind.localPath) {
      return null;
    }
    final candidate = _assistantWorkingDirectoryForSession(sessionKey);
    if (candidate == null) {
      return null;
    }
    final directory = Directory(candidate);
    if (directory.existsSync()) {
      return directory.path;
    }
    if (requireLocalExistence) {
      return null;
    }
    return candidate;
  }

  String? _resolveSingleAgentWorkingDirectoryForSession(
    String sessionKey, {
    SingleAgentProvider? provider,
  }) {
    final workspaceKind = assistantWorkspaceRefKindForSession(sessionKey);
    if (workspaceKind == WorkspaceRefKind.objectStore) {
      return null;
    }
    if (workspaceKind == WorkspaceRefKind.remotePath) {
      return _assistantWorkingDirectoryForSession(sessionKey);
    }
    return _resolveLocalAssistantWorkingDirectoryForSession(
      sessionKey,
      requireLocalExistence:
          provider == null || _singleAgentProviderRequiresLocalPath(provider),
    );
  }

  bool _singleAgentProviderRequiresLocalPath(SingleAgentProvider provider) {
    final endpoint = _resolveSingleAgentEndpoint(provider);
    if (endpoint == null) {
      return true;
    }
    final scheme = endpoint.scheme.trim().toLowerCase();
    if (scheme == 'wss' || scheme == 'https') {
      return false;
    }
    final host = endpoint.host.trim();
    if (host.isEmpty) {
      return true;
    }
    final address = InternetAddress.tryParse(host);
    if (address != null) {
      return !(address.isLoopback || address.type == InternetAddressType.unix);
    }
    final normalizedHost = host.toLowerCase();
    if (normalizedHost == 'localhost') {
      return true;
    }
    return false;
  }

  void _registerCodexExternalProvider() {
    _runtimeCoordinator.registerExternalCodeAgent(
      ExternalCodeAgentProvider(
        id: 'codex',
        name: 'Codex ACP',
        command: 'xworkmate-agent-gateway',
        transport: ExternalAgentTransport.websocketJsonRpc,
        endpoint: '',
        defaultArgs: const <String>[],
        capabilities: const <String>[
          'chat',
          'code-edit',
          'gateway-bridge',
          'memory-sync',
          'single-agent',
          'multi-agent',
        ],
      ),
    );
  }

  CodeAgentNodeState _buildCodeAgentNodeState() {
    return CodeAgentNodeState(
      selectedAgentId: _agentsController.selectedAgentId,
      gatewayConnected: _runtime.isConnected,
      executionTarget: currentAssistantExecutionTarget,
      runtimeMode: effectiveCodeAgentRuntimeMode,
      bridgeEnabled: _isCodexBridgeEnabled,
      bridgeState: _codexCooperationState.name,
      preferredProviderId: 'codex',
      resolvedCodexCliPath: _resolvedCodexCliPath,
      configuredCodexCliPath: configuredCodexCliPath,
    );
  }

  GatewayMode _bridgeGatewayMode() {
    if (!_runtime.isConnected) {
      return GatewayMode.offline;
    }
    return switch (currentAssistantExecutionTarget) {
      AssistantExecutionTarget.singleAgent => GatewayMode.offline,
      AssistantExecutionTarget.local => GatewayMode.local,
      AssistantExecutionTarget.remote => GatewayMode.remote,
    };
  }

  Future<void> _ensureCodexGatewayRegistration() async {
    if (!_isCodexBridgeEnabled) {
      return;
    }

    if (!_runtime.isConnected) {
      _codexCooperationState = CodexCooperationState.bridgeOnly;
      _codeAgentBridgeRegistry.clearRegistration();
      notifyListeners();
      return;
    }

    if (_codeAgentBridgeRegistry.isRegistered) {
      _codexCooperationState = CodexCooperationState.registered;
      notifyListeners();
      return;
    }

    try {
      final dispatch = _codeAgentNodeOrchestrator.buildGatewayDispatch(
        _buildCodeAgentNodeState(),
      );
      await _codeAgentBridgeRegistry.register(
        agentType: 'code-agent-bridge',
        name: 'XWorkmate Codex Bridge',
        version: kAppVersion,
        transport: 'stdio-bridge',
        capabilities: const <AgentCapability>[
          AgentCapability(
            name: 'chat',
            description: 'Bridge external Codex CLI chat turns.',
          ),
          AgentCapability(
            name: 'code-edit',
            description: 'Bridge code editing tasks through Codex CLI.',
          ),
          AgentCapability(
            name: 'memory-sync',
            description: 'Coordinate memory sync through OpenClaw Gateway.',
          ),
        ],
        metadata: <String, dynamic>{
          ...dispatch.metadata,
          'providerId': 'codex',
          'runtimeMode': effectiveCodeAgentRuntimeMode.name,
          'gatewayMode': _bridgeGatewayMode().name,
          'binaryConfigured': (resolvedCodexCliPath ?? configuredCodexCliPath)
              .trim()
              .isNotEmpty,
          'capabilities': const <String>[
            'chat',
            'code-edit',
            'gateway-bridge',
            'memory-sync',
          ],
        },
      );
      _codexCooperationState = CodexCooperationState.registered;
      _codexBridgeError = null;
    } catch (error) {
      _codexCooperationState = CodexCooperationState.bridgeOnly;
      _codexBridgeError = error.toString();
    }

    notifyListeners();
  }

  void _clearCodexGatewayRegistration() {
    _codeAgentBridgeRegistry.clearRegistration();
    if (_isCodexBridgeEnabled) {
      _codexCooperationState = CodexCooperationState.bridgeOnly;
    } else {
      _codexCooperationState = CodexCooperationState.notStarted;
    }
    notifyListeners();
  }

  void _recomputeTasks() {
    _tasksController.recompute(
      sessions: sessions,
      cronJobs: _cronJobsController.items,
      currentSessionKey: _sessionsController.currentSessionKey,
      hasPendingRun: hasAssistantPendingRun,
      activeAgentName: _agentsController.activeAgentName,
    );
  }

  void _attachChildListeners() {
    _runtimeCoordinator.addListener(_relayChildChange);
    _settingsController.addListener(_handleSettingsControllerChange);
    _agentsController.addListener(_relayChildChange);
    _sessionsController.addListener(_relayChildChange);
    _chatController.addListener(_relayChildChange);
    _instancesController.addListener(_relayChildChange);
    _skillsController.addListener(_relayChildChange);
    _connectorsController.addListener(_relayChildChange);
    _modelsController.addListener(_relayChildChange);
    _cronJobsController.addListener(_relayChildChange);
    _devicesController.addListener(_relayChildChange);
    _tasksController.addListener(_relayChildChange);
    _multiAgentOrchestrator.addListener(_relayChildChange);
  }

  void _detachChildListeners() {
    _runtimeCoordinator.removeListener(_relayChildChange);
    _settingsController.removeListener(_handleSettingsControllerChange);
    _agentsController.removeListener(_relayChildChange);
    _sessionsController.removeListener(_relayChildChange);
    _chatController.removeListener(_relayChildChange);
    _instancesController.removeListener(_relayChildChange);
    _skillsController.removeListener(_relayChildChange);
    _connectorsController.removeListener(_relayChildChange);
    _modelsController.removeListener(_relayChildChange);
    _cronJobsController.removeListener(_relayChildChange);
    _devicesController.removeListener(_relayChildChange);
    _tasksController.removeListener(_relayChildChange);
    _multiAgentOrchestrator.removeListener(_relayChildChange);
  }

  void _handleSettingsControllerChange() {
    final previous = _lastObservedSettingsSnapshot;
    final current = settings;
    final previousJson = previous.toJsonString();
    final currentJson = current.toJsonString();
    if (currentJson == previousJson) {
      _notifyIfActive();
      return;
    }
    final hadDraftChanges =
        _settingsDraftInitialized &&
        (_settingsDraft.toJsonString() != previousJson ||
            _draftSecretValues.isNotEmpty);
    if (!_settingsDraftInitialized || !hadDraftChanges) {
      _settingsDraft = current;
      _settingsDraftInitialized = true;
      _settingsDraftStatusMessage = '';
    }
    _lastObservedSettingsSnapshot = current;
    _settingsObservationQueue = _settingsObservationQueue
        .then((_) async {
          await _handleObservedSettingsChange(
            previous: previous,
            current: current,
          );
        })
        .catchError((_) {});
    _notifyIfActive();
  }

  Future<void> _handleObservedSettingsChange({
    required SettingsSnapshot previous,
    required SettingsSnapshot current,
  }) async {
    if (_disposed) {
      return;
    }
    setActiveAppLanguage(current.appLanguage);
    _multiAgentOrchestrator.updateConfig(current.multiAgent);
    if (previous.codexCliPath != current.codexCliPath ||
        previous.codeAgentRuntimeMode != current.codeAgentRuntimeMode) {
      await _refreshResolvedCodexCliPath();
      _registerCodexExternalProvider();
      if (_disposed) {
        return;
      }
    }
    if (_authorizedSkillDirectoriesChanged(previous, current)) {
      await _refreshSharedSingleAgentLocalSkillsCache(forceRescan: true);
      if (_disposed) {
        return;
      }
      if (assistantExecutionTargetForSession(currentSessionKey) ==
          AssistantExecutionTarget.singleAgent) {
        await refreshSingleAgentSkillsForSession(currentSessionKey);
      }
    }
    _notifyIfActive();
  }

  void _relayChildChange() {
    _notifyIfActive();
  }

  void _notifyIfActive() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  Uri? _resolveSingleAgentEndpoint(SingleAgentProvider provider) {
    final endpoint = settings
        .externalAcpEndpointForProvider(provider)
        .endpoint
        .trim();
    if (endpoint.isEmpty) {
      return null;
    }
    final normalizedInput = endpoint.contains('://')
        ? endpoint
        : 'ws://$endpoint';
    final uri = Uri.tryParse(normalizedInput);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    final scheme = uri.scheme.trim().toLowerCase();
    if (scheme != 'ws' &&
        scheme != 'wss' &&
        scheme != 'http' &&
        scheme != 'https') {
      return null;
    }
    return uri;
  }

  Uri? _resolveGatewayAcpEndpoint() {
    final target = assistantExecutionTargetForSession(
      _sessionsController.currentSessionKey,
    );
    if (target == AssistantExecutionTarget.singleAgent) {
      final remote = _gatewayProfileBaseUri(
        settings.primaryRemoteGatewayProfile,
      );
      if (remote != null) {
        return remote;
      }
      return _gatewayProfileBaseUri(settings.primaryLocalGatewayProfile);
    }
    return _gatewayProfileBaseUri(
      _gatewayProfileForAssistantExecutionTarget(target),
    );
  }

  Uri? _gatewayProfileBaseUri(GatewayConnectionProfile profile) {
    final host = profile.host.trim();
    if (host.isEmpty || profile.port <= 0) {
      return null;
    }
    return Uri(
      scheme: profile.tls ? 'https' : 'http',
      host: host,
      port: profile.port,
    );
  }

  RuntimeConnectionMode _modeFromHost(String host) {
    final trimmed = host.trim().toLowerCase();
    if (_isLoopbackHost(trimmed)) {
      return RuntimeConnectionMode.local;
    }
    return RuntimeConnectionMode.remote;
  }

  bool _isLoopbackHost(String host) {
    final trimmed = host.trim().toLowerCase();
    return trimmed == '127.0.0.1' || trimmed == 'localhost';
  }

  AssistantExecutionTarget _assistantExecutionTargetForMode(
    RuntimeConnectionMode mode,
  ) {
    return switch (mode) {
      RuntimeConnectionMode.unconfigured =>
        AssistantExecutionTarget.singleAgent,
      RuntimeConnectionMode.local => AssistantExecutionTarget.local,
      RuntimeConnectionMode.remote => AssistantExecutionTarget.remote,
    };
  }

  GatewayConnectionProfile _gatewayProfileForAssistantExecutionTarget(
    AssistantExecutionTarget target,
  ) {
    return switch (target) {
      AssistantExecutionTarget.local => settings.primaryLocalGatewayProfile,
      AssistantExecutionTarget.remote => settings.primaryRemoteGatewayProfile,
      AssistantExecutionTarget.singleAgent => throw StateError(
        'Single Agent target has no OpenClaw gateway profile.',
      ),
    };
  }

  int _gatewayProfileIndexForExecutionTarget(AssistantExecutionTarget target) {
    return switch (target) {
      AssistantExecutionTarget.local => kGatewayLocalProfileIndex,
      AssistantExecutionTarget.remote => kGatewayRemoteProfileIndex,
      AssistantExecutionTarget.singleAgent => throw StateError(
        'Single Agent target has no OpenClaw gateway profile index.',
      ),
    };
  }
}

class _AiGatewayChatException implements Exception {
  const _AiGatewayChatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _AiGatewayAbortException implements Exception {
  const _AiGatewayAbortException(this.partialText);

  final String partialText;
}
