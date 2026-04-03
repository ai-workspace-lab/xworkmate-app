// ignore_for_file: unused_import, unnecessary_import

import 'dart:convert';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import 'runtime_models_connection.dart';
import 'runtime_models_profiles.dart';
import 'runtime_models_configs.dart';
import 'runtime_models_settings_snapshot.dart';
import 'runtime_models_gateway_entities.dart';
import 'runtime_models_multi_agent.dart';

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

const int taskThreadSchemaVersion = 20260403;

enum ThreadRealm { local, remote }

extension ThreadRealmCopy on ThreadRealm {
  static ThreadRealm fromJsonValue(String? value) {
    return ThreadRealm.values.firstWhere(
      (item) => item.name == value?.trim(),
      orElse: () => ThreadRealm.local,
    );
  }
}

enum ThreadSubjectType { tenant, user }

extension ThreadSubjectTypeCopy on ThreadSubjectType {
  static ThreadSubjectType fromJsonValue(String? value) {
    return ThreadSubjectType.values.firstWhere(
      (item) => item.name == value?.trim(),
      orElse: () => ThreadSubjectType.user,
    );
  }
}

enum WorkspaceKind { localFs, remoteFs }

extension WorkspaceKindCopy on WorkspaceKind {
  static WorkspaceKind fromJsonValue(String? value) {
    final normalized = value?.trim();
    switch (normalized) {
      case 'localPath':
      case 'local_fs':
      case 'localFs':
        return WorkspaceKind.localFs;
      case 'remotePath':
      case 'objectStore':
      case 'remote_fs':
      case 'remoteFs':
        return WorkspaceKind.remoteFs;
      default:
        return WorkspaceKind.localFs;
    }
  }
}

enum ThreadExecutionMode { auto, localAgent, gatewayLocal, gatewayRemote }

extension ThreadExecutionModeCopy on ThreadExecutionMode {
  static ThreadExecutionMode fromJsonValue(String? value) {
    final normalized = value?.trim();
    switch (normalized) {
      case 'auto':
        return ThreadExecutionMode.auto;
      case 'singleAgent':
      case 'local_agent':
      case 'localAgent':
        return ThreadExecutionMode.localAgent;
      case 'local':
      case 'gateway_local':
      case 'gatewayLocal':
        return ThreadExecutionMode.gatewayLocal;
      case 'remote':
      case 'gateway_remote':
      case 'gatewayRemote':
        return ThreadExecutionMode.gatewayRemote;
      default:
        return ThreadExecutionMode.auto;
    }
  }
}

enum ThreadSelectionSource { inherited, explicit }

extension ThreadSelectionSourceCopy on ThreadSelectionSource {
  static ThreadSelectionSource fromJsonValue(String? value) {
    return ThreadSelectionSource.values.firstWhere(
      (item) => item.name == value?.trim(),
      orElse: () => ThreadSelectionSource.inherited,
    );
  }
}

class ThreadOwnerScope {
  const ThreadOwnerScope({
    required this.realm,
    required this.subjectType,
    required this.subjectId,
    required this.displayName,
  });

  final ThreadRealm realm;
  final ThreadSubjectType subjectType;
  final String subjectId;
  final String displayName;

  ThreadOwnerScope copyWith({
    ThreadRealm? realm,
    ThreadSubjectType? subjectType,
    String? subjectId,
    String? displayName,
  }) {
    return ThreadOwnerScope(
      realm: realm ?? this.realm,
      subjectType: subjectType ?? this.subjectType,
      subjectId: subjectId ?? this.subjectId,
      displayName: displayName ?? this.displayName,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'realm': realm.name,
      'subjectType': subjectType.name,
      'subjectId': subjectId,
      'displayName': displayName,
    };
  }

  factory ThreadOwnerScope.fromJson(Map<String, dynamic> json) {
    return ThreadOwnerScope(
      realm: ThreadRealmCopy.fromJsonValue(json['realm']?.toString()),
      subjectType: ThreadSubjectTypeCopy.fromJsonValue(
        json['subjectType']?.toString(),
      ),
      subjectId: json['subjectId']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
    );
  }
}

class WorkspaceBinding {
  const WorkspaceBinding({
    required this.workspaceId,
    required this.workspaceKind,
    required this.workspacePath,
    required this.displayPath,
    required this.writable,
  });

  final String workspaceId;
  final WorkspaceKind workspaceKind;
  final String workspacePath;
  final String displayPath;
  final bool writable;

  WorkspaceBinding copyWith({
    String? workspaceId,
    WorkspaceKind? workspaceKind,
    String? workspacePath,
    String? displayPath,
    bool? writable,
  }) {
    return WorkspaceBinding(
      workspaceId: workspaceId ?? this.workspaceId,
      workspaceKind: workspaceKind ?? this.workspaceKind,
      workspacePath: workspacePath ?? this.workspacePath,
      displayPath: displayPath ?? this.displayPath,
      writable: writable ?? this.writable,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'workspaceId': workspaceId,
      'workspaceKind': workspaceKind.name,
      'workspacePath': workspacePath,
      'displayPath': displayPath,
      'writable': writable,
    };
  }

  factory WorkspaceBinding.fromJson(Map<String, dynamic> json) {
    final path = json['workspacePath']?.toString() ?? '';
    return WorkspaceBinding(
      workspaceId: json['workspaceId']?.toString() ?? '',
      workspaceKind: WorkspaceKindCopy.fromJsonValue(
        json['workspaceKind']?.toString(),
      ),
      workspacePath: path,
      displayPath: json['displayPath']?.toString() ?? path,
      writable: json['writable'] as bool? ?? true,
    );
  }
}

class ExecutionBinding {
  const ExecutionBinding({
    required this.executionMode,
    required this.executorId,
    required this.providerId,
    required this.endpointId,
    this.executionModeSource = ThreadSelectionSource.inherited,
    this.providerSource = ThreadSelectionSource.inherited,
  });

  final ThreadExecutionMode executionMode;
  final String executorId;
  final String providerId;
  final String endpointId;
  final ThreadSelectionSource executionModeSource;
  final ThreadSelectionSource providerSource;

  ExecutionBinding copyWith({
    ThreadExecutionMode? executionMode,
    String? executorId,
    String? providerId,
    String? endpointId,
    ThreadSelectionSource? executionModeSource,
    ThreadSelectionSource? providerSource,
  }) {
    return ExecutionBinding(
      executionMode: executionMode ?? this.executionMode,
      executorId: executorId ?? this.executorId,
      providerId: providerId ?? this.providerId,
      endpointId: endpointId ?? this.endpointId,
      executionModeSource: executionModeSource ?? this.executionModeSource,
      providerSource: providerSource ?? this.providerSource,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'executionMode': executionMode.name,
      'executorId': executorId,
      'providerId': providerId,
      'endpointId': endpointId,
      'executionModeSource': executionModeSource.name,
      'providerSource': providerSource.name,
    };
  }

  factory ExecutionBinding.fromJson(Map<String, dynamic> json) {
    return ExecutionBinding(
      executionMode: ThreadExecutionModeCopy.fromJsonValue(
        json['executionMode']?.toString(),
      ),
      executorId: json['executorId']?.toString() ?? '',
      providerId: json['providerId']?.toString() ?? '',
      endpointId: json['endpointId']?.toString() ?? '',
      executionModeSource: ThreadSelectionSourceCopy.fromJsonValue(
        json['executionModeSource']?.toString(),
      ),
      providerSource: ThreadSelectionSourceCopy.fromJsonValue(
        json['providerSource']?.toString(),
      ),
    );
  }
}

class ThreadContextState {
  const ThreadContextState({
    required this.messages,
    required this.selectedModelId,
    required this.selectedSkillKeys,
    required this.importedSkills,
    required this.permissionLevel,
    required this.messageViewMode,
    required this.latestResolvedRuntimeModel,
    this.selectedModelSource = ThreadSelectionSource.inherited,
    this.selectedSkillsSource = ThreadSelectionSource.inherited,
    this.gatewayEntryState,
  });

  final List<GatewayChatMessage> messages;
  final String selectedModelId;
  final List<String> selectedSkillKeys;
  final List<AssistantThreadSkillEntry> importedSkills;
  final AssistantPermissionLevel permissionLevel;
  final AssistantMessageViewMode messageViewMode;
  final String latestResolvedRuntimeModel;
  final ThreadSelectionSource selectedModelSource;
  final ThreadSelectionSource selectedSkillsSource;
  final String? gatewayEntryState;

  ThreadContextState copyWith({
    List<GatewayChatMessage>? messages,
    String? selectedModelId,
    List<String>? selectedSkillKeys,
    List<AssistantThreadSkillEntry>? importedSkills,
    AssistantPermissionLevel? permissionLevel,
    AssistantMessageViewMode? messageViewMode,
    String? latestResolvedRuntimeModel,
    ThreadSelectionSource? selectedModelSource,
    ThreadSelectionSource? selectedSkillsSource,
    String? gatewayEntryState,
    bool clearGatewayEntryState = false,
  }) {
    return ThreadContextState(
      messages: messages ?? this.messages,
      selectedModelId: selectedModelId ?? this.selectedModelId,
      selectedSkillKeys: selectedSkillKeys ?? this.selectedSkillKeys,
      importedSkills: importedSkills ?? this.importedSkills,
      permissionLevel: permissionLevel ?? this.permissionLevel,
      messageViewMode: messageViewMode ?? this.messageViewMode,
      latestResolvedRuntimeModel:
          latestResolvedRuntimeModel ?? this.latestResolvedRuntimeModel,
      selectedModelSource: selectedModelSource ?? this.selectedModelSource,
      selectedSkillsSource: selectedSkillsSource ?? this.selectedSkillsSource,
      gatewayEntryState: clearGatewayEntryState
          ? null
          : (gatewayEntryState ?? this.gatewayEntryState),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'messages': messages.map((item) => item.toJson()).toList(growable: false),
      'selectedModelId': selectedModelId,
      'selectedSkillKeys': selectedSkillKeys,
      'importedSkills': importedSkills
          .map((item) => item.toJson())
          .toList(growable: false),
      'permissionLevel': permissionLevel.name,
      'messageViewMode': messageViewMode.name,
      'latestResolvedRuntimeModel': latestResolvedRuntimeModel,
      'selectedModelSource': selectedModelSource.name,
      'selectedSkillsSource': selectedSkillsSource.name,
      'gatewayEntryState': gatewayEntryState,
    };
  }

  factory ThreadContextState.fromJson(Map<String, dynamic> json) {
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
    final rawImportedSkills = json['importedSkills'];
    final importedSkills = rawImportedSkills is List
        ? rawImportedSkills
              .whereType<Map>()
              .map(
                (item) => AssistantThreadSkillEntry.fromJson(
                  item.cast<String, dynamic>(),
                ),
              )
              .where((item) => item.key.trim().isNotEmpty)
              .toList(growable: false)
        : const <AssistantThreadSkillEntry>[];
    final rawSelectedSkillKeys = json['selectedSkillKeys'];
    final selectedSkillKeys = rawSelectedSkillKeys is List
        ? rawSelectedSkillKeys
              .map((item) => item?.toString().trim() ?? '')
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : const <String>[];
    return ThreadContextState(
      messages: messages,
      selectedModelId: json['selectedModelId']?.toString() ?? '',
      selectedSkillKeys: selectedSkillKeys,
      importedSkills: importedSkills,
      permissionLevel: AssistantPermissionLevelCopy.fromJsonValue(
        json['permissionLevel']?.toString(),
      ),
      messageViewMode: AssistantMessageViewModeCopy.fromJsonValue(
        json['messageViewMode']?.toString(),
      ),
      latestResolvedRuntimeModel:
          json['latestResolvedRuntimeModel']?.toString() ?? '',
      selectedModelSource: ThreadSelectionSourceCopy.fromJsonValue(
        json['selectedModelSource']?.toString(),
      ),
      selectedSkillsSource: ThreadSelectionSourceCopy.fromJsonValue(
        json['selectedSkillsSource']?.toString(),
      ),
      gatewayEntryState: json['gatewayEntryState']?.toString(),
    );
  }
}

class ThreadLifecycleState {
  const ThreadLifecycleState({
    required this.archived,
    required this.status,
    required this.lastRunAtMs,
    required this.lastResultCode,
  });

  final bool archived;
  final String status;
  final double? lastRunAtMs;
  final String? lastResultCode;

  ThreadLifecycleState copyWith({
    bool? archived,
    String? status,
    double? lastRunAtMs,
    String? lastResultCode,
    bool clearLastResultCode = false,
  }) {
    return ThreadLifecycleState(
      archived: archived ?? this.archived,
      status: status ?? this.status,
      lastRunAtMs: lastRunAtMs ?? this.lastRunAtMs,
      lastResultCode: clearLastResultCode
          ? null
          : (lastResultCode ?? this.lastResultCode),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'archived': archived,
      'status': status,
      'lastRunAtMs': lastRunAtMs,
      'lastResultCode': lastResultCode,
    };
  }

  factory ThreadLifecycleState.fromJson(Map<String, dynamic> json) {
    double? asDouble(Object? value) {
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value?.toString() ?? '');
    }

    return ThreadLifecycleState(
      archived: json['archived'] as bool? ?? false,
      status: json['status']?.toString() ?? 'ready',
      lastRunAtMs: asDouble(json['lastRunAtMs']),
      lastResultCode: json['lastResultCode']?.toString(),
    );
  }
}

class TaskThread {
  TaskThread({
    String? threadId,
    String? sessionKey,
    String? title,
    ThreadOwnerScope? ownerScope,
    WorkspaceBinding? workspaceBinding,
    ExecutionBinding? executionBinding,
    ThreadContextState? contextState,
    ThreadLifecycleState? lifecycleState,
    double? createdAtMs,
    this.updatedAtMs,
    List<GatewayChatMessage>? messages,
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
    String? displayPath,
    AssistantPermissionLevel? permissionLevel,
    String? latestResolvedRuntimeModel,
    String? lifecycleStatus,
    double? lastRunAtMs,
    String? lastResultCode,
  }) : threadId = _resolveThreadId(threadId, sessionKey),
       title = title ?? '',
       ownerScope =
           ownerScope ??
           const ThreadOwnerScope(
             realm: ThreadRealm.local,
             subjectType: ThreadSubjectType.user,
             subjectId: '',
             displayName: '',
           ),
       workspaceBinding =
           workspaceBinding ??
           WorkspaceBinding(
             workspaceId: _resolveThreadId(threadId, sessionKey),
             workspaceKind: _workspaceKindFromLegacy(workspaceRefKind),
             workspacePath: workspaceRef?.trim() ?? '',
             displayPath: (displayPath ?? workspaceRef ?? '').trim(),
             writable: true,
           ),
       executionBinding =
           executionBinding ??
           ExecutionBinding(
             executionMode: _executionModeFromLegacy(executionTarget),
             executorId:
                 (singleAgentProvider ?? SingleAgentProvider.auto).providerId,
             providerId:
                 (singleAgentProvider ?? SingleAgentProvider.auto).providerId,
             endpointId: '',
           ),
       contextState =
           contextState ??
           ThreadContextState(
             messages: messages ?? const <GatewayChatMessage>[],
             selectedModelId: assistantModelId?.trim() ?? '',
             selectedSkillKeys: selectedSkillKeys ?? const <String>[],
             importedSkills:
                 importedSkills ?? const <AssistantThreadSkillEntry>[],
             permissionLevel:
                 permissionLevel ?? AssistantPermissionLevel.defaultAccess,
             messageViewMode:
                 messageViewMode ?? AssistantMessageViewMode.rendered,
             latestResolvedRuntimeModel:
                 latestResolvedRuntimeModel?.trim() ?? '',
             gatewayEntryState: gatewayEntryState?.trim(),
           ),
       lifecycleState =
           lifecycleState ??
           ThreadLifecycleState(
             archived: archived ?? false,
             status:
                 lifecycleStatus ??
                 ((workspaceRef?.trim().isEmpty ?? true)
                     ? 'needs_workspace'
                     : 'ready'),
             lastRunAtMs: lastRunAtMs,
             lastResultCode: lastResultCode?.trim(),
           ),
       createdAtMs =
           createdAtMs ??
           updatedAtMs ??
           DateTime.now().millisecondsSinceEpoch.toDouble();

  final String threadId;
  final String title;
  final ThreadOwnerScope ownerScope;
  final WorkspaceBinding workspaceBinding;
  final ExecutionBinding executionBinding;
  final ThreadContextState contextState;
  final ThreadLifecycleState lifecycleState;
  final double createdAtMs;
  final double? updatedAtMs;

  String get sessionKey => threadId;
  List<GatewayChatMessage> get messages => contextState.messages;
  List<AssistantThreadSkillEntry> get importedSkills =>
      contextState.importedSkills;
  List<String> get selectedSkillKeys => contextState.selectedSkillKeys;
  String get assistantModelId => contextState.selectedModelId;
  AssistantMessageViewMode get messageViewMode => contextState.messageViewMode;
  String? get gatewayEntryState => contextState.gatewayEntryState;
  String get latestResolvedRuntimeModel =>
      contextState.latestResolvedRuntimeModel;
  bool get hasExplicitExecutionTargetSelection =>
      executionBinding.executionModeSource == ThreadSelectionSource.explicit;
  bool get hasExplicitProviderSelection =>
      executionBinding.providerSource == ThreadSelectionSource.explicit;
  bool get hasExplicitModelSelection =>
      contextState.selectedModelSource == ThreadSelectionSource.explicit;
  bool get hasExplicitSkillSelection =>
      contextState.selectedSkillsSource == ThreadSelectionSource.explicit;
  bool get archived => lifecycleState.archived;
  String get workspaceRef => workspaceBinding.workspacePath;
  String get workspacePath => workspaceBinding.workspacePath;
  String get displayPath => workspaceBinding.displayPath;
  WorkspaceRefKind get workspaceRefKind =>
      switch (workspaceBinding.workspaceKind) {
        WorkspaceKind.localFs => WorkspaceRefKind.localPath,
        WorkspaceKind.remoteFs => WorkspaceRefKind.remotePath,
      };
  WorkspaceKind get workspaceKind => workspaceBinding.workspaceKind;
  SingleAgentProvider get singleAgentProvider =>
      SingleAgentProviderCopy.fromJsonValue(executionBinding.providerId);
  AssistantExecutionTarget get executionTarget =>
      switch (executionBinding.executionMode) {
        ThreadExecutionMode.auto => AssistantExecutionTarget.auto,
        ThreadExecutionMode.localAgent => AssistantExecutionTarget.singleAgent,
        ThreadExecutionMode.gatewayLocal => AssistantExecutionTarget.local,
        ThreadExecutionMode.gatewayRemote => AssistantExecutionTarget.remote,
      };

  TaskThread copyWith({
    String? threadId,
    String? sessionKey,
    String? title,
    ThreadOwnerScope? ownerScope,
    WorkspaceBinding? workspaceBinding,
    ExecutionBinding? executionBinding,
    ThreadContextState? contextState,
    ThreadLifecycleState? lifecycleState,
    double? createdAtMs,
    double? updatedAtMs,
    List<GatewayChatMessage>? messages,
    bool? archived,
    AssistantExecutionTarget? executionTarget,
    bool clearExecutionTarget = false,
    AssistantMessageViewMode? messageViewMode,
    List<AssistantThreadSkillEntry>? importedSkills,
    List<String>? selectedSkillKeys,
    String? assistantModelId,
    SingleAgentProvider? singleAgentProvider,
    ThreadSelectionSource? executionTargetSource,
    ThreadSelectionSource? singleAgentProviderSource,
    ThreadSelectionSource? assistantModelSource,
    ThreadSelectionSource? selectedSkillsSource,
    String? gatewayEntryState,
    bool clearGatewayEntryState = false,
    String? workspaceRef,
    WorkspaceRefKind? workspaceRefKind,
    String? workspacePath,
    String? displayPath,
    WorkspaceKind? workspaceKind,
    bool? writable,
    String? lifecycleStatus,
    String? latestResolvedRuntimeModel,
  }) {
    final nextExecutionBinding = executionBinding ?? this.executionBinding;
    final nextExecutionMode = clearExecutionTarget
        ? nextExecutionBinding.executionMode
        : executionTarget == null
        ? nextExecutionBinding.executionMode
        : switch (executionTarget) {
            AssistantExecutionTarget.auto => ThreadExecutionMode.auto,
            AssistantExecutionTarget.singleAgent =>
              ThreadExecutionMode.localAgent,
            AssistantExecutionTarget.local => ThreadExecutionMode.gatewayLocal,
            AssistantExecutionTarget.remote =>
              ThreadExecutionMode.gatewayRemote,
          };
    return TaskThread(
      threadId: threadId ?? sessionKey ?? this.threadId,
      title: title ?? this.title,
      ownerScope: ownerScope ?? this.ownerScope,
      workspaceBinding: (workspaceBinding ?? this.workspaceBinding).copyWith(
        workspacePath: workspacePath ?? workspaceRef,
        displayPath: displayPath,
        workspaceKind:
            workspaceKind ??
            (workspaceRefKind == null
                ? null
                : _workspaceKindFromLegacy(workspaceRefKind)),
        writable: writable,
      ),
      executionBinding: nextExecutionBinding.copyWith(
        executionMode: nextExecutionMode,
        executorId: singleAgentProvider?.providerId,
        providerId: singleAgentProvider?.providerId,
        executionModeSource: executionTargetSource,
        providerSource: singleAgentProviderSource,
      ),
      contextState: (contextState ?? this.contextState).copyWith(
        messages: messages,
        messageViewMode: messageViewMode,
        importedSkills: importedSkills,
        selectedSkillKeys: selectedSkillKeys,
        selectedModelId: assistantModelId,
        selectedModelSource: assistantModelSource,
        selectedSkillsSource: selectedSkillsSource,
        latestResolvedRuntimeModel: latestResolvedRuntimeModel,
        gatewayEntryState: gatewayEntryState,
        clearGatewayEntryState: clearGatewayEntryState,
      ),
      lifecycleState: (lifecycleState ?? this.lifecycleState).copyWith(
        archived: archived,
        status: lifecycleStatus,
      ),
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  static String _resolveThreadId(String? threadId, String? sessionKey) {
    return (threadId ?? sessionKey ?? '').trim();
  }

  static WorkspaceKind _workspaceKindFromLegacy(WorkspaceRefKind? kind) {
    return switch (kind) {
      WorkspaceRefKind.remotePath ||
      WorkspaceRefKind.objectStore => WorkspaceKind.remoteFs,
      _ => WorkspaceKind.localFs,
    };
  }

  static ThreadExecutionMode _executionModeFromLegacy(
    AssistantExecutionTarget? target,
  ) {
    return switch (target ?? AssistantExecutionTarget.auto) {
      AssistantExecutionTarget.auto => ThreadExecutionMode.auto,
      AssistantExecutionTarget.singleAgent => ThreadExecutionMode.localAgent,
      AssistantExecutionTarget.local => ThreadExecutionMode.gatewayLocal,
      AssistantExecutionTarget.remote => ThreadExecutionMode.gatewayRemote,
    };
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': taskThreadSchemaVersion,
      'threadId': threadId,
      'title': title,
      'ownerScope': ownerScope.toJson(),
      'workspaceBinding': workspaceBinding.toJson(),
      'executionBinding': executionBinding.toJson(),
      'contextState': contextState.toJson(),
      'lifecycleState': lifecycleState.toJson(),
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
    };
  }

  factory TaskThread.fromJson(Map<String, dynamic> json) {
    double? asDouble(Object? value) {
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value?.toString() ?? '');
    }

    return TaskThread(
      threadId: json['threadId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      ownerScope: ThreadOwnerScope.fromJson(
        (json['ownerScope'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      workspaceBinding: WorkspaceBinding.fromJson(
        (json['workspaceBinding'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      executionBinding: ExecutionBinding.fromJson(
        (json['executionBinding'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      contextState: ThreadContextState.fromJson(
        (json['contextState'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      lifecycleState: ThreadLifecycleState.fromJson(
        (json['lifecycleState'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      createdAtMs:
          asDouble(json['createdAtMs']) ??
          asDouble(json['updatedAtMs']) ??
          DateTime.now().millisecondsSinceEpoch.toDouble(),
      updatedAtMs: asDouble(json['updatedAtMs']),
    );
  }
}
