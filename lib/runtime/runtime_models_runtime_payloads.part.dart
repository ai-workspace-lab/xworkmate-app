part of 'runtime_models.dart';

class GatewayConnectionSnapshot {
  const GatewayConnectionSnapshot({
    required this.status,
    required this.mode,
    required this.statusText,
    required this.serverName,
    required this.remoteAddress,
    required this.mainSessionKey,
    required this.lastError,
    required this.lastErrorCode,
    required this.lastErrorDetailCode,
    required this.lastConnectedAtMs,
    required this.deviceId,
    required this.authRole,
    required this.authScopes,
    required this.connectAuthMode,
    required this.connectAuthFields,
    required this.connectAuthSources,
    required this.hasSharedAuth,
    required this.hasDeviceToken,
    required this.healthPayload,
    required this.statusPayload,
  });

  final RuntimeConnectionStatus status;
  final RuntimeConnectionMode mode;
  final String statusText;
  final String? serverName;
  final String? remoteAddress;
  final String? mainSessionKey;
  final String? lastError;
  final String? lastErrorCode;
  final String? lastErrorDetailCode;
  final int? lastConnectedAtMs;
  final String? deviceId;
  final String? authRole;
  final List<String> authScopes;
  final String? connectAuthMode;
  final List<String> connectAuthFields;
  final List<String> connectAuthSources;
  final bool hasSharedAuth;
  final bool hasDeviceToken;
  final Map<String, dynamic>? healthPayload;
  final Map<String, dynamic>? statusPayload;

  factory GatewayConnectionSnapshot.initial({
    RuntimeConnectionMode mode = RuntimeConnectionMode.unconfigured,
  }) {
    return GatewayConnectionSnapshot(
      status: RuntimeConnectionStatus.offline,
      mode: mode,
      statusText: 'Offline',
      serverName: null,
      remoteAddress: null,
      mainSessionKey: null,
      lastError: null,
      lastErrorCode: null,
      lastErrorDetailCode: null,
      lastConnectedAtMs: null,
      deviceId: null,
      authRole: null,
      authScopes: const <String>[],
      connectAuthMode: null,
      connectAuthFields: const <String>[],
      connectAuthSources: const <String>[],
      hasSharedAuth: false,
      hasDeviceToken: false,
      healthPayload: null,
      statusPayload: null,
    );
  }

  GatewayConnectionSnapshot copyWith({
    RuntimeConnectionStatus? status,
    RuntimeConnectionMode? mode,
    String? statusText,
    String? serverName,
    String? remoteAddress,
    String? mainSessionKey,
    String? lastError,
    String? lastErrorCode,
    String? lastErrorDetailCode,
    int? lastConnectedAtMs,
    String? deviceId,
    String? authRole,
    List<String>? authScopes,
    String? connectAuthMode,
    List<String>? connectAuthFields,
    List<String>? connectAuthSources,
    bool? hasSharedAuth,
    bool? hasDeviceToken,
    Map<String, dynamic>? healthPayload,
    Map<String, dynamic>? statusPayload,
    bool clearServerName = false,
    bool clearRemoteAddress = false,
    bool clearMainSessionKey = false,
    bool clearLastError = false,
    bool clearLastErrorCode = false,
    bool clearLastErrorDetailCode = false,
  }) {
    return GatewayConnectionSnapshot(
      status: status ?? this.status,
      mode: mode ?? this.mode,
      statusText: statusText ?? this.statusText,
      serverName: clearServerName ? null : (serverName ?? this.serverName),
      remoteAddress: clearRemoteAddress
          ? null
          : (remoteAddress ?? this.remoteAddress),
      mainSessionKey: clearMainSessionKey
          ? null
          : (mainSessionKey ?? this.mainSessionKey),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastErrorCode: clearLastErrorCode
          ? null
          : (lastErrorCode ?? this.lastErrorCode),
      lastErrorDetailCode: clearLastErrorDetailCode
          ? null
          : (lastErrorDetailCode ?? this.lastErrorDetailCode),
      lastConnectedAtMs: lastConnectedAtMs ?? this.lastConnectedAtMs,
      deviceId: deviceId ?? this.deviceId,
      authRole: authRole ?? this.authRole,
      authScopes: authScopes ?? this.authScopes,
      connectAuthMode: connectAuthMode ?? this.connectAuthMode,
      connectAuthFields: connectAuthFields ?? this.connectAuthFields,
      connectAuthSources: connectAuthSources ?? this.connectAuthSources,
      hasSharedAuth: hasSharedAuth ?? this.hasSharedAuth,
      hasDeviceToken: hasDeviceToken ?? this.hasDeviceToken,
      healthPayload: healthPayload ?? this.healthPayload,
      statusPayload: statusPayload ?? this.statusPayload,
    );
  }

  bool get pairingRequired {
    final detailCode = lastErrorDetailCode?.trim().toUpperCase();
    final errorCode = lastErrorCode?.trim().toUpperCase();
    final errorText = lastError?.toLowerCase() ?? '';
    return status != RuntimeConnectionStatus.connected &&
        (detailCode == 'PAIRING_REQUIRED' ||
            errorCode == 'NOT_PAIRED' ||
            errorText.contains('pairing required'));
  }

  bool get gatewayTokenMissing {
    final detailCode = lastErrorDetailCode?.trim().toUpperCase();
    final errorText = lastError?.toLowerCase() ?? '';
    return detailCode == 'AUTH_TOKEN_MISSING' ||
        errorText.contains('gateway token missing');
  }

  String get connectAuthSummary {
    final mode = connectAuthMode?.trim() ?? 'none';
    final fields = connectAuthFields.isEmpty
        ? 'none'
        : connectAuthFields.join(', ');
    final sources = connectAuthSources.isEmpty
        ? 'none'
        : connectAuthSources.join(' · ');
    return '$mode | fields: $fields | sources: $sources';
  }
}

class RuntimePackageInfo {
  const RuntimePackageInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
  });

  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;
}

class RuntimeDeviceInfo {
  const RuntimeDeviceInfo({
    required this.platform,
    required this.platformVersion,
    required this.deviceFamily,
    required this.modelIdentifier,
  });

  final String platform;
  final String platformVersion;
  final String deviceFamily;
  final String modelIdentifier;

  String get platformLabel {
    final version = platformVersion.trim();
    if (version.isEmpty) {
      return platform;
    }
    return '$platform $version';
  }
}

class RuntimeLogEntry {
  const RuntimeLogEntry({
    required this.timestampMs,
    required this.level,
    required this.category,
    required this.message,
  });

  final int timestampMs;
  final String level;
  final String category;
  final String message;

  String get timeLabel {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  String get line => '[$timeLabel] ${level.toUpperCase()} $category $message';
}

class GatewayAgentSummary {
  const GatewayAgentSummary({
    required this.id,
    required this.name,
    required this.emoji,
    required this.theme,
  });

  final String id;
  final String name;
  final String emoji;
  final String theme;
}

class GatewaySessionSummary {
  const GatewaySessionSummary({
    required this.key,
    required this.kind,
    required this.displayName,
    required this.surface,
    required this.subject,
    required this.room,
    required this.space,
    required this.updatedAtMs,
    required this.sessionId,
    required this.systemSent,
    required this.abortedLastRun,
    required this.thinkingLevel,
    required this.verboseLevel,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.model,
    required this.contextTokens,
    required this.derivedTitle,
    required this.lastMessagePreview,
  });

  final String key;
  final String? kind;
  final String? displayName;
  final String? surface;
  final String? subject;
  final String? room;
  final String? space;
  final double? updatedAtMs;
  final String? sessionId;
  final bool? systemSent;
  final bool? abortedLastRun;
  final String? thinkingLevel;
  final String? verboseLevel;
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final String? model;
  final int? contextTokens;
  final String? derivedTitle;
  final String? lastMessagePreview;

  String get label {
    final candidates = [derivedTitle, displayName, subject, room, space, key];
    return candidates.firstWhere(
      (item) => item != null && item.trim().isNotEmpty,
      orElse: () => key,
    )!;
  }
}

class GatewayChatMessage {
  const GatewayChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestampMs,
    required this.toolCallId,
    required this.toolName,
    required this.stopReason,
    required this.pending,
    required this.error,
  });

  final String id;
  final String role;
  final String text;
  final double? timestampMs;
  final String? toolCallId;
  final String? toolName;
  final String? stopReason;
  final bool pending;
  final bool error;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'text': text,
      'timestampMs': timestampMs,
      'toolCallId': toolCallId,
      'toolName': toolName,
      'stopReason': stopReason,
      'pending': pending,
      'error': error,
    };
  }

  factory GatewayChatMessage.fromJson(Map<String, dynamic> json) {
    double? asDouble(Object? value) {
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value?.toString() ?? '');
    }

    return GatewayChatMessage(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'assistant',
      text: json['text']?.toString() ?? '',
      timestampMs: asDouble(json['timestampMs']),
      toolCallId: json['toolCallId']?.toString(),
      toolName: json['toolName']?.toString(),
      stopReason: json['stopReason']?.toString(),
      pending: json['pending'] as bool? ?? false,
      error: json['error'] as bool? ?? false,
    );
  }

  GatewayChatMessage copyWith({
    String? id,
    String? role,
    String? text,
    double? timestampMs,
    String? toolCallId,
    String? toolName,
    String? stopReason,
    bool? pending,
    bool? error,
  }) {
    return GatewayChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      timestampMs: timestampMs ?? this.timestampMs,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      stopReason: stopReason ?? this.stopReason,
      pending: pending ?? this.pending,
      error: error ?? this.error,
    );
  }
}

class AssistantThreadSkillEntry {
  const AssistantThreadSkillEntry({
    required this.key,
    required this.label,
    required this.description,
    this.source = '',
    required this.sourcePath,
    this.scope = '',
    required this.sourceLabel,
  });

  final String key;
  final String label;
  final String description;
  final String source;
  final String sourcePath;
  final String scope;
  final String sourceLabel;

  AssistantThreadSkillEntry copyWith({
    String? key,
    String? label,
    String? description,
    String? source,
    String? sourcePath,
    String? scope,
    String? sourceLabel,
  }) {
    return AssistantThreadSkillEntry(
      key: key ?? this.key,
      label: label ?? this.label,
      description: description ?? this.description,
      source: source ?? this.source,
      sourcePath: sourcePath ?? this.sourcePath,
      scope: scope ?? this.scope,
      sourceLabel: sourceLabel ?? this.sourceLabel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'description': description,
      'source': source,
      'sourcePath': sourcePath,
      'scope': scope,
      'sourceLabel': sourceLabel,
    };
  }

  factory AssistantThreadSkillEntry.fromJson(Map<String, dynamic> json) {
    return AssistantThreadSkillEntry(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      sourcePath: json['sourcePath']?.toString() ?? '',
      scope: json['scope']?.toString() ?? '',
      sourceLabel: json['sourceLabel']?.toString() ?? '',
    );
  }
}

class AssistantThreadRecord {
  const AssistantThreadRecord({
    required this.sessionKey,
    required this.messages,
    required this.updatedAtMs,
    required this.title,
    required this.archived,
    required this.executionTarget,
    required this.messageViewMode,
    this.importedSkills = const <AssistantThreadSkillEntry>[],
    this.selectedSkillKeys = const <String>[],
    this.assistantModelId = '',
    this.singleAgentProvider = SingleAgentProvider.auto,
    this.gatewayEntryState,
    this.workspaceRef = '',
    this.workspaceRefKind = WorkspaceRefKind.localPath,
  });

  final String sessionKey;
  final List<GatewayChatMessage> messages;
  final double? updatedAtMs;
  final String title;
  final bool archived;
  final AssistantExecutionTarget? executionTarget;
  final AssistantMessageViewMode messageViewMode;
  final List<AssistantThreadSkillEntry> importedSkills;
  final List<String> selectedSkillKeys;
  final String assistantModelId;
  final SingleAgentProvider singleAgentProvider;
  final String? gatewayEntryState;
  final String workspaceRef;
  final WorkspaceRefKind workspaceRefKind;

  AssistantThreadRecord copyWith({
    String? sessionKey,
    List<GatewayChatMessage>? messages,
    double? updatedAtMs,
    String? title,
    bool? archived,
    AssistantExecutionTarget? executionTarget,
    bool clearExecutionTarget = false,
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
    return AssistantThreadRecord(
      sessionKey: sessionKey ?? this.sessionKey,
      messages: messages ?? this.messages,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      title: title ?? this.title,
      archived: archived ?? this.archived,
      executionTarget: clearExecutionTarget
          ? null
          : (executionTarget ?? this.executionTarget),
      messageViewMode: messageViewMode ?? this.messageViewMode,
      importedSkills: importedSkills ?? this.importedSkills,
      selectedSkillKeys: selectedSkillKeys ?? this.selectedSkillKeys,
      assistantModelId: assistantModelId ?? this.assistantModelId,
      singleAgentProvider: singleAgentProvider ?? this.singleAgentProvider,
      gatewayEntryState: clearGatewayEntryState
          ? null
          : (gatewayEntryState ?? this.gatewayEntryState),
      workspaceRef: workspaceRef ?? this.workspaceRef,
      workspaceRefKind: workspaceRefKind ?? this.workspaceRefKind,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionKey': sessionKey,
      'messages': messages.map((item) => item.toJson()).toList(growable: false),
      'updatedAtMs': updatedAtMs,
      'title': title,
      'archived': archived,
      'executionTarget': executionTarget?.name,
      'messageViewMode': messageViewMode.name,
      'importedSkills': importedSkills
          .map((item) => item.toJson())
          .toList(growable: false),
      'selectedSkillKeys': selectedSkillKeys,
      'assistantModelId': assistantModelId,
      'singleAgentProvider': singleAgentProvider.providerId,
      'gatewayEntryState': gatewayEntryState,
      'workspaceRef': workspaceRef,
      'workspaceRefKind': workspaceRefKind.name,
    };
  }

  factory AssistantThreadRecord.fromJson(Map<String, dynamic> json) {
    double? asDouble(Object? value) {
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value?.toString() ?? '');
    }

    final rawMessages = json['messages'];
    final messages = rawMessages is List
        ? rawMessages
              .whereType<Map>()
              .map(
                (item) =>
                    GatewayChatMessage.fromJson(item.cast<String, dynamic>()),
              )
              .toList(growable: false)
        : const <GatewayChatMessage>[];
    List<AssistantThreadSkillEntry> normalizeSkillEntries(Object? value) {
      if (value is! List) {
        return const <AssistantThreadSkillEntry>[];
      }
      final entries = <AssistantThreadSkillEntry>[];
      final seen = <String>{};
      for (final item in value.whereType<Map>()) {
        final entry = AssistantThreadSkillEntry.fromJson(
          item.cast<String, dynamic>(),
        );
        final normalizedKey = entry.key.trim();
        if (normalizedKey.isEmpty || !seen.add(normalizedKey)) {
          continue;
        }
        entries.add(entry);
      }
      return entries;
    }

    List<String> normalizeSkillKeys(Object? value) {
      if (value is! List) {
        return const <String>[];
      }
      final keys = <String>[];
      final seen = <String>{};
      for (final item in value) {
        final normalized = item?.toString().trim() ?? '';
        if (normalized.isEmpty || !seen.add(normalized)) {
          continue;
        }
        keys.add(normalized);
      }
      return keys;
    }

    String? normalizeGatewayEntryState(Object? value) {
      final normalized = value?.toString().trim() ?? '';
      if (normalized.isEmpty) {
        return null;
      }
      if (normalized == 'ai-gateway-only') {
        return 'single-agent';
      }
      return normalized;
    }

    WorkspaceRefKind normalizeWorkspaceRefKind(
      Object? value, {
      required AssistantExecutionTarget? executionTarget,
      required String workspaceRef,
    }) {
      final raw = value?.toString().trim();
      if (raw != null && raw.isNotEmpty) {
        return WorkspaceRefKindCopy.fromJsonValue(raw);
      }
      if (workspaceRef.startsWith('object://')) {
        return WorkspaceRefKind.objectStore;
      }
      if (executionTarget != null &&
          executionTarget != AssistantExecutionTarget.singleAgent) {
        return WorkspaceRefKind.remotePath;
      }
      return WorkspaceRefKind.localPath;
    }

    // Keep tolerating legacy payloads that still contain discoveredSkills,
    // but do not map the retired field back into the runtime model.
    normalizeSkillEntries(json['discoveredSkills']);

    final executionTarget = json['executionTarget'] == null
        ? null
        : AssistantExecutionTargetCopy.fromJsonValue(
            json['executionTarget']?.toString(),
          );
    final workspaceRef = json['workspaceRef']?.toString() ?? '';

    return AssistantThreadRecord(
      sessionKey: json['sessionKey']?.toString() ?? '',
      messages: messages,
      updatedAtMs: asDouble(json['updatedAtMs']),
      title: json['title']?.toString() ?? '',
      archived: json['archived'] as bool? ?? false,
      executionTarget: executionTarget,
      messageViewMode: AssistantMessageViewModeCopy.fromJsonValue(
        json['messageViewMode']?.toString(),
      ),
      importedSkills: normalizeSkillEntries(json['importedSkills']),
      selectedSkillKeys: normalizeSkillKeys(json['selectedSkillKeys']),
      assistantModelId: json['assistantModelId']?.toString() ?? '',
      singleAgentProvider: SingleAgentProviderCopy.fromJsonValue(
        json['singleAgentProvider']?.toString(),
      ),
      gatewayEntryState: normalizeGatewayEntryState(json['gatewayEntryState']),
      workspaceRef: workspaceRef,
      workspaceRefKind: normalizeWorkspaceRefKind(
        json['workspaceRefKind'],
        executionTarget: executionTarget,
        workspaceRef: workspaceRef,
      ),
    );
  }
}
