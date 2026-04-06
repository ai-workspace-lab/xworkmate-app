part of 'gateway_runtime_core.dart';

extension GatewayRuntimeApiInternal on GatewayRuntime {
  Future<Map<String, dynamic>> _healthInternal() async {
    final payload = asMap(await request('health'));
    snapshotInternal = snapshotInternal.copyWith(healthPayload: payload);
    appendLogInternal(this, 'debug', 'health', 'health snapshot refreshed');
    _notifyRuntimeChangedInternal();
    return payload;
  }

  Future<Map<String, dynamic>> _statusInternal() async {
    final payload = asMap(await request('status'));
    snapshotInternal = snapshotInternal.copyWith(statusPayload: payload);
    appendLogInternal(this, 'debug', 'health', 'status snapshot refreshed');
    _notifyRuntimeChangedInternal();
    return payload;
  }

  Future<List<GatewayAgentSummary>> _listAgentsInternal() async {
    final payload = asMap(
      await request('agents.list', params: const <String, dynamic>{}),
    );
    final agents = asList(payload['agents'])
        .map((item) {
          final map = asMap(item);
          final identity = asMap(map['identity']);
          return GatewayAgentSummary(
            id: stringValue(map['id']) ?? 'unknown',
            name:
                stringValue(map['name']) ??
                stringValue(identity['name']) ??
                'Agent',
            emoji: stringValue(identity['emoji']) ?? '·',
            theme: stringValue(identity['theme']) ?? 'default',
          );
        })
        .toList(growable: false);
    if (snapshotInternal.mainSessionKey == null ||
        snapshotInternal.mainSessionKey!.trim().isEmpty) {
      snapshotInternal = snapshotInternal.copyWith(
        mainSessionKey: stringValue(payload['mainKey']) ?? 'main',
      );
      _notifyRuntimeChangedInternal();
    }
    return agents;
  }

  Future<List<GatewaySessionSummary>> _listSessionsInternal({
    String? agentId,
    int limit = 24,
  }) async {
    final payload = asMap(
      await request(
        'sessions.list',
        params: <String, dynamic>{
          'includeGlobal': true,
          'includeUnknown': false,
          'includeDerivedTitles': true,
          'includeLastMessage': true,
          'limit': limit,
          if (agentId != null && agentId.trim().isNotEmpty)
            'agentId': agentId.trim(),
        },
      ),
    );
    return asList(payload['sessions'])
        .map((item) {
          final map = asMap(item);
          return GatewaySessionSummary(
            key: stringValue(map['key']) ?? 'main',
            kind: stringValue(map['kind']),
            displayName:
                stringValue(map['displayName']) ?? stringValue(map['label']),
            surface: stringValue(map['surface']),
            subject: stringValue(map['subject']),
            room: stringValue(map['room']),
            space: stringValue(map['space']),
            updatedAtMs: doubleValue(map['updatedAt']),
            sessionId: stringValue(map['sessionId']),
            systemSent: boolValue(map['systemSent']),
            abortedLastRun: boolValue(map['abortedLastRun']),
            thinkingLevel: stringValue(map['thinkingLevel']),
            verboseLevel: stringValue(map['verboseLevel']),
            inputTokens: intValue(map['inputTokens']),
            outputTokens: intValue(map['outputTokens']),
            totalTokens: intValue(map['totalTokens']),
            model: stringValue(map['model']),
            contextTokens: intValue(map['contextTokens']),
            derivedTitle: stringValue(map['derivedTitle']),
            lastMessagePreview: stringValue(map['lastMessagePreview']),
          );
        })
        .toList(growable: false);
  }

  Future<List<GatewayChatMessage>> _loadHistoryInternal(
    String sessionKey, {
    int limit = 120,
  }) async {
    final payload = asMap(
      await request(
        'chat.history',
        params: <String, dynamic>{'sessionKey': sessionKey, 'limit': limit},
      ),
    );
    return asList(payload['messages'])
        .map((item) {
          final map = asMap(item);
          return GatewayChatMessage(
            id: randomIdInternal(),
            role: stringValue(map['role']) ?? 'assistant',
            text: extractMessageText(map),
            timestampMs: doubleValue(map['timestamp']),
            toolCallId:
                stringValue(map['toolCallId']) ??
                stringValue(map['tool_call_id']),
            toolName:
                stringValue(map['toolName']) ?? stringValue(map['tool_name']),
            stopReason: stringValue(map['stopReason']),
            pending: false,
            error: false,
          );
        })
        .toList(growable: false);
  }

  Future<String> _sendChatInternal({
    required String sessionKey,
    required String message,
    required String thinking,
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    String? agentId,
    Map<String, dynamic>? metadata,
  }) async {
    final runId = randomIdInternal();
    final payload = asMap(
      await request(
        'chat.send',
        params: <String, dynamic>{
          'sessionKey': sessionKey,
          'message': message,
          'thinking': thinking,
          'timeoutMs': 30000,
          'idempotencyKey': runId,
          if (agentId != null && agentId.trim().isNotEmpty)
            'agentId': agentId.trim(),
          if (attachments.isNotEmpty)
            'attachments': attachments
                .map((attachment) => attachment.toJson())
                .toList(growable: false),
        },
        timeout: const Duration(seconds: 35),
      ),
    );
    return stringValue(payload['runId']) ?? runId;
  }

  Future<void> _abortChatInternal({
    required String sessionKey,
    required String runId,
  }) async {
    await request(
      'chat.abort',
      params: <String, dynamic>{'sessionKey': sessionKey, 'runId': runId},
      timeout: const Duration(seconds: 10),
    );
  }

  Future<List<GatewayInstanceSummary>> _listInstancesInternal() async {
    final payload = await request(
      'system-presence',
      params: const <String, dynamic>{},
    );
    return asList(payload)
        .map((item) {
          final map = asMap(item);
          return GatewayInstanceSummary(
            id: stringValue(map['id']) ?? randomIdInternal(),
            host: stringValue(map['host']),
            ip: stringValue(map['ip']),
            version: stringValue(map['version']),
            platform: stringValue(map['platform']),
            deviceFamily: stringValue(map['deviceFamily']),
            modelIdentifier: stringValue(map['modelIdentifier']),
            lastInputSeconds: intValue(map['lastInputSeconds']),
            mode: stringValue(map['mode']),
            reason: stringValue(map['reason']),
            text: stringValue(map['text']) ?? '',
            timestampMs:
                doubleValue(map['ts']) ??
                DateTime.now().millisecondsSinceEpoch.toDouble(),
          );
        })
        .toList(growable: false);
  }

  Future<List<GatewaySkillSummary>> _listSkillsInternal({
    String? agentId,
  }) async {
    final payload = asMap(
      await request(
        'skills.status',
        params: <String, dynamic>{
          if (agentId != null && agentId.trim().isNotEmpty)
            'agentId': agentId.trim(),
        },
      ),
    );
    return asList(payload['skills'])
        .map((item) {
          final map = asMap(item);
          return GatewaySkillSummary(
            name: stringValue(map['name']) ?? 'Skill',
            description: stringValue(map['description']) ?? '',
            source: stringValue(map['source']) ?? 'workspace',
            skillKey:
                stringValue(map['skillKey']) ??
                stringValue(map['name']) ??
                'skill',
            primaryEnv: stringValue(map['primaryEnv']),
            eligible: boolValue(map['eligible']) ?? false,
            disabled: boolValue(map['disabled']) ?? false,
            missingBins: stringList(asMap(map['missing'])['bins']),
            missingEnv: stringList(asMap(map['missing'])['env']),
            missingConfig: stringList(asMap(map['missing'])['config']),
          );
        })
        .toList(growable: false);
  }

  Future<List<GatewayConnectorSummary>> _listConnectorsInternal() async {
    final payload = asMap(
      await request(
        'channels.status',
        params: const <String, dynamic>{'probe': true, 'timeoutMs': 8000},
        timeout: const Duration(seconds: 16),
      ),
    );
    final channelMeta = <String, Map<String, dynamic>>{
      for (final entry in asList(payload['channelMeta']))
        if (stringValue(asMap(entry)['id']) != null)
          stringValue(asMap(entry)['id'])!: asMap(entry),
    };
    final labels = asMap(payload['channelLabels']);
    final detailLabels = asMap(payload['channelDetailLabels']);
    final accounts = asMap(payload['channelAccounts']);
    final order = stringList(payload['channelOrder']);

    final summaries = <GatewayConnectorSummary>[];
    for (final channelId in order) {
      final channelAccounts = asList(accounts[channelId]);
      if (channelAccounts.isEmpty) {
        final meta = channelMeta[channelId] ?? const <String, dynamic>{};
        summaries.add(
          GatewayConnectorSummary(
            id: channelId,
            label:
                stringValue(meta['label']) ??
                stringValue(labels[channelId]) ??
                channelId,
            detailLabel:
                stringValue(meta['detailLabel']) ??
                stringValue(detailLabels[channelId]) ??
                channelId,
            accountName: null,
            configured: false,
            enabled: false,
            running: false,
            connected: false,
            status: 'idle',
            lastError: null,
            meta: const <String>[],
          ),
        );
        continue;
      }
      for (final account in channelAccounts) {
        final map = asMap(account);
        final configured = boolValue(map['configured']) ?? false;
        final enabled = boolValue(map['enabled']) ?? configured;
        final running = boolValue(map['running']) ?? false;
        final connected =
            boolValue(map['connected']) ?? boolValue(map['linked']) ?? false;
        final lastError = stringValue(map['lastError']);
        final status = lastError != null && lastError.trim().isNotEmpty
            ? 'error'
            : connected
            ? 'connected'
            : running
            ? 'running'
            : configured
            ? 'configured'
            : 'idle';
        final mode = stringValue(map['mode']);
        final tokenSource = stringValue(map['tokenSource']);
        final baseUrl = stringValue(map['baseUrl']);
        summaries.add(
          GatewayConnectorSummary(
            id: channelId,
            label:
                stringValue(channelMeta[channelId]?['label']) ??
                stringValue(labels[channelId]) ??
                channelId,
            detailLabel:
                stringValue(channelMeta[channelId]?['detailLabel']) ??
                stringValue(detailLabels[channelId]) ??
                channelId,
            accountName:
                stringValue(map['name']) ?? stringValue(map['accountId']),
            configured: configured,
            enabled: enabled,
            running: running,
            connected: connected,
            status: status,
            lastError: lastError,
            meta: [
              ...?(mode == null ? null : <String>[mode]),
              ...?(tokenSource == null ? null : <String>[tokenSource]),
              ...?(baseUrl == null ? null : <String>[baseUrl]),
            ],
          ),
        );
      }
    }
    return summaries;
  }

  Future<List<GatewayModelSummary>> _listModelsInternal() async {
    final payload = asMap(
      await request(
        'models.list',
        params: const <String, dynamic>{},
        timeout: const Duration(seconds: 16),
      ),
    );
    return asList(payload['models'])
        .map((item) {
          final map = asMap(item);
          return GatewayModelSummary(
            id: stringValue(map['id']) ?? 'unknown',
            name:
                stringValue(map['name']) ?? stringValue(map['id']) ?? 'unknown',
            provider: stringValue(map['provider']) ?? 'unknown',
            contextWindow: intValue(map['contextWindow']),
            maxOutputTokens: intValue(map['maxOutputTokens']),
          );
        })
        .toList(growable: false);
  }

  Future<List<GatewayCronJobSummary>> _listCronJobsInternal() async {
    final payload = asMap(
      await request(
        'cron.list',
        params: const <String, dynamic>{'includeDisabled': true},
        timeout: const Duration(seconds: 16),
      ),
    );
    return asList(payload['jobs'])
        .map((item) {
          final map = asMap(item);
          final state = asMap(map['state']);
          return GatewayCronJobSummary(
            id: stringValue(map['id']) ?? randomIdInternal(),
            name: stringValue(map['name']) ?? 'Untitled job',
            description: stringValue(map['description']),
            enabled: boolValue(map['enabled']) ?? true,
            agentId: stringValue(map['agentId']),
            scheduleLabel: cronScheduleLabelInternal(asMap(map['schedule'])),
            nextRunAtMs: intValue(state['nextRunAtMs']),
            lastRunAtMs: intValue(state['lastRunAtMs']),
            lastStatus: stringValue(state['lastStatus']),
            lastError: stringValue(state['lastError']),
          );
        })
        .toList(growable: false);
  }

  Future<GatewayDevicePairingList> _listDevicePairingInternal() async {
    final payload = asMap(
      await request(
        'device.pair.list',
        params: const <String, dynamic>{},
        timeout: const Duration(seconds: 12),
      ),
    );
    final identity = await storeInternal.loadDeviceIdentity();
    return GatewayDevicePairingList(
      pending: asList(payload['pending'])
          .map((item) => parsePendingDeviceInternal(asMap(item)))
          .toList(growable: false),
      paired: asList(payload['paired'])
          .map(
            (item) => parsePairedDeviceInternal(
              asMap(item),
              currentDeviceId: identity?.deviceId,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<GatewayPairedDevice?> _approveDevicePairingInternal(
    String requestId,
  ) async {
    appendLogInternal(this, 'info', 'pairing', 'approve request $requestId');
    final payload = asMap(
      await request(
        'device.pair.approve',
        params: <String, dynamic>{'requestId': requestId},
        timeout: const Duration(seconds: 12),
      ),
    );
    final identity = await storeInternal.loadDeviceIdentity();
    final device = asMap(payload['device']);
    if (device.isEmpty) {
      return null;
    }
    return parsePairedDeviceInternal(
      device,
      currentDeviceId: identity?.deviceId,
    );
  }

  Future<void> _rejectDevicePairingInternal(String requestId) async {
    appendLogInternal(this, 'info', 'pairing', 'reject request $requestId');
    await request(
      'device.pair.reject',
      params: <String, dynamic>{'requestId': requestId},
      timeout: const Duration(seconds: 12),
    );
  }

  Future<void> _removePairedDeviceInternal(String deviceId) async {
    appendLogInternal(this, 'info', 'pairing', 'remove device $deviceId');
    await request(
      'device.pair.remove',
      params: <String, dynamic>{'deviceId': deviceId},
      timeout: const Duration(seconds: 12),
    );
  }

  Future<String> _rotateDeviceTokenInternal({
    required String deviceId,
    required String role,
    List<String> scopes = const <String>[],
  }) async {
    appendLogInternal(
      this,
      'info',
      'token',
      'rotate role token | device: $deviceId | role: $role',
    );
    final payload = asMap(
      await request(
        'device.token.rotate',
        params: <String, dynamic>{
          'deviceId': deviceId,
          'role': role,
          if (scopes.isNotEmpty) 'scopes': scopes,
        },
        timeout: const Duration(seconds: 12),
      ),
    );
    final token = stringValue(payload['token']) ?? '';
    final identity = await storeInternal.loadDeviceIdentity();
    final resolvedRole = stringValue(payload['role']) ?? role;
    if (token.isNotEmpty &&
        identity != null &&
        (stringValue(payload['deviceId']) ?? deviceId) == identity.deviceId) {
      await storeInternal.saveDeviceToken(
        deviceId: identity.deviceId,
        role: resolvedRole,
        token: token,
      );
    }
    return token;
  }

  Future<void> _revokeDeviceTokenInternal({
    required String deviceId,
    required String role,
  }) async {
    appendLogInternal(
      this,
      'info',
      'token',
      'revoke role token | device: $deviceId | role: $role',
    );
    await request(
      'device.token.revoke',
      params: <String, dynamic>{'deviceId': deviceId, 'role': role},
      timeout: const Duration(seconds: 12),
    );
    final identity = await storeInternal.loadDeviceIdentity();
    if (identity != null && deviceId == identity.deviceId) {
      await storeInternal.clearDeviceToken(
        deviceId: identity.deviceId,
        role: role,
      );
    }
  }

  Future<dynamic> _requestInternal(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (sessionClientInternal != null) {
      if (!isConnected) {
        appendLogInternal(
          this,
          'warn',
          'rpc',
          'blocked request $method | offline',
        );
        throw GatewayRuntimeException('gateway not connected', code: 'OFFLINE');
      }
      return sessionClientInternal!.request(
        runtimeId: runtimeIdInternal,
        method: method,
        params: params,
        timeout: timeout,
      );
    }
    if (channelInternal == null || !isConnected) {
      appendLogInternal(
        this,
        'warn',
        'rpc',
        'blocked request $method | offline',
      );
      throw GatewayRuntimeException('gateway not connected', code: 'OFFLINE');
    }
    final result = await requestRawInternal(
      this,
      method,
      params: params,
      timeout: timeout,
    );
    return result.payload;
  }
}
