import 'runtime_models.dart';

enum GoTaskServiceRoute { externalAcpSingle, externalAcpMulti }

enum GoTaskServiceCollaborationMode { standard, multiAgent }

class ExternalCodeAgentAcpCapabilities {
  const ExternalCodeAgentAcpCapabilities({
    required this.singleAgent,
    required this.multiAgent,
    required this.providers,
    required this.raw,
  });

  const ExternalCodeAgentAcpCapabilities.empty()
    : singleAgent = false,
      multiAgent = false,
      providers = const <SingleAgentProvider>{},
      raw = const <String, dynamic>{};

  final bool singleAgent;
  final bool multiAgent;
  final Set<SingleAgentProvider> providers;
  final Map<String, dynamic> raw;
}

class ExternalCodeAgentAcpSyncedProvider {
  const ExternalCodeAgentAcpSyncedProvider({
    required this.providerId,
    required this.label,
    required this.endpoint,
    required this.authorizationHeader,
    required this.enabled,
  });

  final String providerId;
  final String label;
  final String endpoint;
  final String authorizationHeader;
  final bool enabled;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'providerId': providerId.trim(),
      'label': label.trim(),
      'endpoint': endpoint.trim(),
      'authorizationHeader': authorizationHeader.trim(),
      'enabled': enabled,
    };
  }
}

enum ExternalCodeAgentAcpRoutingMode { auto, explicit }

class ExternalCodeAgentAcpAvailableSkill {
  const ExternalCodeAgentAcpAvailableSkill({
    required this.id,
    required this.label,
    required this.description,
    this.installed = true,
  });

  final String id;
  final String label;
  final String description;
  final bool installed;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id.trim(),
      'label': label.trim(),
      'description': description.trim(),
      'installed': installed,
    };
  }
}

class ExternalCodeAgentAcpRoutingConfig {
  const ExternalCodeAgentAcpRoutingConfig({
    required this.mode,
    required this.preferredGatewayTarget,
    required this.explicitExecutionTarget,
    required this.explicitProviderId,
    required this.explicitModel,
    required this.explicitSkills,
    required this.allowSkillInstall,
    required this.availableSkills,
    this.installApproval,
  });

  const ExternalCodeAgentAcpRoutingConfig.auto({
    this.preferredGatewayTarget = '',
    this.availableSkills = const <ExternalCodeAgentAcpAvailableSkill>[],
  }) : mode = ExternalCodeAgentAcpRoutingMode.auto,
       explicitExecutionTarget = '',
       explicitProviderId = '',
       explicitModel = '',
       explicitSkills = const <String>[],
       allowSkillInstall = false,
       installApproval = null;

  final ExternalCodeAgentAcpRoutingMode mode;
  final String preferredGatewayTarget;
  final String explicitExecutionTarget;
  final String explicitProviderId;
  final String explicitModel;
  final List<String> explicitSkills;
  final bool allowSkillInstall;
  final List<ExternalCodeAgentAcpAvailableSkill> availableSkills;
  final ExternalCodeAgentAcpSkillInstallApproval? installApproval;

  bool get isAuto => mode == ExternalCodeAgentAcpRoutingMode.auto;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'routingMode': mode.name,
      if (preferredGatewayTarget.trim().isNotEmpty)
        'preferredGatewayTarget': preferredGatewayTarget.trim(),
      if (explicitExecutionTarget.trim().isNotEmpty)
        'explicitExecutionTarget': explicitExecutionTarget.trim(),
      if (explicitProviderId.trim().isNotEmpty)
        'explicitProviderId': explicitProviderId.trim(),
      if (explicitModel.trim().isNotEmpty)
        'explicitModel': explicitModel.trim(),
      'explicitSkills': explicitSkills
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      'allowSkillInstall': allowSkillInstall,
      'availableSkills': availableSkills
          .map((item) => item.toJson())
          .toList(growable: false),
      if (installApproval != null) 'installApproval': installApproval!.toJson(),
    };
  }
}

class ExternalCodeAgentAcpSkillInstallApproval {
  const ExternalCodeAgentAcpSkillInstallApproval({
    required this.requestId,
    required this.approvedSkillKeys,
  });

  final String requestId;
  final List<String> approvedSkillKeys;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'requestId': requestId.trim(),
      'approvedSkillKeys': approvedSkillKeys
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    };
  }
}

class GoTaskServiceRequest {
  const GoTaskServiceRequest({
    required this.sessionId,
    required this.threadId,
    required this.target,
    required this.prompt,
    required this.workingDirectory,
    required this.model,
    required this.thinking,
    required this.selectedSkills,
    required this.inlineAttachments,
    required this.localAttachments,
    required this.aiGatewayBaseUrl,
    required this.aiGatewayApiKey,
    required this.agentId,
    required this.metadata,
    this.routing,
    this.routingHint = '',
    this.provider = SingleAgentProvider.auto,
    this.resumeSession = false,
    this.collaborationMode = GoTaskServiceCollaborationMode.standard,
    this.multiAgent = false,
  });

  final String sessionId;
  final String threadId;
  final AssistantExecutionTarget target;
  final String prompt;
  final String workingDirectory;
  final String model;
  final String thinking;
  final List<String> selectedSkills;
  final List<GatewayChatAttachmentPayload> inlineAttachments;
  final List<CollaborationAttachment> localAttachments;
  final String aiGatewayBaseUrl;
  final String aiGatewayApiKey;
  final String agentId;
  final Map<String, dynamic> metadata;
  final ExternalCodeAgentAcpRoutingConfig? routing;
  final String routingHint;
  final SingleAgentProvider provider;
  final bool resumeSession;
  final GoTaskServiceCollaborationMode collaborationMode;
  final bool multiAgent;

  bool get isMultiAgentRequest =>
      multiAgent ||
      collaborationMode == GoTaskServiceCollaborationMode.multiAgent;

  GoTaskServiceRoute get route {
    if (isMultiAgentRequest) {
      return GoTaskServiceRoute.externalAcpMulti;
    }
    return GoTaskServiceRoute.externalAcpSingle;
  }

  String get acpMode {
    if (route == GoTaskServiceRoute.externalAcpMulti) {
      return 'multi-agent';
    }
    return switch (target) {
      AssistantExecutionTarget.singleAgent => 'single-agent',
      AssistantExecutionTarget.local => _gatewaySessionMode,
      AssistantExecutionTarget.remote => _gatewaySessionMode,
    };
  }

  String get routingExecutionTarget {
    if (route == GoTaskServiceRoute.externalAcpMulti) {
      return 'multi-agent';
    }
    return switch (target) {
      AssistantExecutionTarget.singleAgent => 'single-agent',
      AssistantExecutionTarget.local => 'gateway',
      AssistantExecutionTarget.remote => 'gateway',
    };
  }

  bool get hasInlineAttachments => inlineAttachments.isNotEmpty;

  ExternalCodeAgentAcpRoutingConfig get effectiveRouting =>
      routing ?? _synthesizedRouting();

  Map<String, dynamic> toExternalAcpParams() {
    final resolvedRouting = effectiveRouting;
    final params = <String, dynamic>{
      'sessionId': sessionId,
      'threadId': threadId,
      'mode': acpMode,
      'taskPrompt': prompt,
      'workingDirectory': workingDirectory.trim(),
      'selectedSkills': selectedSkills,
      'attachments': <Map<String, dynamic>>[
        ...localAttachments.map(
          (item) => <String, dynamic>{
            'name': item.name,
            'description': item.description,
            'path': item.path,
          },
        ),
        ...inlineAttachments.map(
          (item) => <String, dynamic>{
            'name': item.fileName,
            'description': item.mimeType,
            'path': '',
          },
        ),
      ],
      if (inlineAttachments.isNotEmpty)
        'inlineAttachments': inlineAttachments
            .map(
              (item) => <String, dynamic>{
                'name': item.fileName,
                'mimeType': item.mimeType,
                'content': item.content,
                'sizeBytes': goTaskServiceBase64Size(item.content),
              },
            )
            .toList(growable: false),
      if (provider != SingleAgentProvider.auto) 'provider': provider.providerId,
      if (model.trim().isNotEmpty) 'model': model.trim(),
      if (thinking.trim().isNotEmpty) 'thinking': thinking.trim(),
      if (aiGatewayBaseUrl.trim().isNotEmpty)
        'aiGatewayBaseUrl': aiGatewayBaseUrl.trim(),
      if (aiGatewayApiKey.trim().isNotEmpty)
        'aiGatewayApiKey': aiGatewayApiKey.trim(),
      'routing': resolvedRouting.toJson(),
      if (routingHint.trim().isNotEmpty) 'routingHint': routingHint.trim(),
      'requestedExecutionTarget': target.promptValue,
      if (_usesGatewaySessionMode(acpMode)) ...<String, dynamic>{
        'executionTarget': target.promptValue,
        if (agentId.trim().isNotEmpty) 'agentId': agentId.trim(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      },
    };
    return params;
  }

  ExternalCodeAgentAcpRoutingConfig _synthesizedRouting() {
    final preferredGatewayTarget = switch (target) {
      AssistantExecutionTarget.remote => 'remote',
      _ => 'local',
    };
    final explicitExecutionTarget = switch (target) {
      AssistantExecutionTarget.local => 'local',
      AssistantExecutionTarget.remote => 'remote',
      AssistantExecutionTarget.singleAgent => 'singleAgent',
    };
    final explicitProviderId = provider == SingleAgentProvider.auto
        ? ''
        : provider.providerId;
    final explicitModelValue = model.trim();
    final explicitSkillsValue = selectedSkills
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final hasExplicitSelection =
        explicitExecutionTarget.isNotEmpty ||
        explicitProviderId.isNotEmpty ||
        explicitModelValue.isNotEmpty ||
        explicitSkillsValue.isNotEmpty;
    if (!hasExplicitSelection) {
      return ExternalCodeAgentAcpRoutingConfig.auto(
        preferredGatewayTarget: preferredGatewayTarget,
      );
    }
    return ExternalCodeAgentAcpRoutingConfig(
      mode: ExternalCodeAgentAcpRoutingMode.explicit,
      preferredGatewayTarget: preferredGatewayTarget,
      explicitExecutionTarget: explicitExecutionTarget,
      explicitProviderId: explicitProviderId,
      explicitModel: explicitModelValue,
      explicitSkills: explicitSkillsValue,
      allowSkillInstall: false,
      availableSkills: const <ExternalCodeAgentAcpAvailableSkill>[],
    );
  }
}

const String _gatewaySessionMode = 'gateway-chat';

bool _usesGatewaySessionMode(String mode) {
  final normalized = mode.trim();
  return normalized == 'gateway' || normalized == _gatewaySessionMode;
}

class GoTaskServiceUpdate {
  const GoTaskServiceUpdate({
    required this.sessionId,
    required this.threadId,
    required this.turnId,
    required this.type,
    required this.text,
    required this.message,
    required this.pending,
    required this.error,
    required this.route,
    required this.payload,
  });

  final String sessionId;
  final String threadId;
  final String turnId;
  final String type;
  final String text;
  final String message;
  final bool pending;
  final bool error;
  final GoTaskServiceRoute route;
  final Map<String, dynamic> payload;

  bool get isDelta => type == 'delta' && text.isNotEmpty;
  bool get isDone => type == 'done' || payload['event'] == 'completed';
}

class GoTaskServiceResult {
  const GoTaskServiceResult({
    required this.success,
    required this.message,
    required this.turnId,
    required this.raw,
    required this.errorMessage,
    required this.resolvedModel,
    required this.route,
  });

  final bool success;
  final String message;
  final String turnId;
  final Map<String, dynamic> raw;
  final String errorMessage;
  final String resolvedModel;
  final GoTaskServiceRoute route;

  String get resolvedWorkingDirectory =>
      raw['resolvedWorkingDirectory']?.toString().trim() ??
      raw['effectiveWorkingDirectory']?.toString().trim() ??
      raw['workingDirectory']?.toString().trim() ??
      '';

  String get resolvedExecutionTarget =>
      raw['resolvedExecutionTarget']?.toString().trim() ?? '';

  String get resolvedEndpointTarget =>
      raw['resolvedEndpointTarget']?.toString().trim() ?? '';

  String get resolvedProviderId =>
      raw['resolvedProviderId']?.toString().trim() ?? '';

  List<String> get resolvedSkills {
    final rawList = raw['resolvedSkills'];
    if (rawList is! List) {
      return const <String>[];
    }
    return rawList
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String get skillResolutionSource =>
      raw['skillResolutionSource']?.toString().trim() ?? '';

  bool get needsSkillInstall => _boolValue(raw['needsSkillInstall']) ?? false;

  String get skillInstallRequestId =>
      raw['skillInstallRequestId']?.toString().trim() ?? '';

  List<Map<String, dynamic>> get skillCandidates =>
      _castMapList(raw['skillCandidates']);

  List<Map<String, dynamic>> get memorySources =>
      _castMapList(raw['memorySources']);

  WorkspaceRefKind? get resolvedWorkspaceRefKind {
    final rawValue = raw['resolvedWorkspaceRefKind']?.toString().trim() ?? '';
    if (rawValue.isEmpty) {
      return null;
    }
    return WorkspaceRefKindCopy.fromJsonValue(rawValue);
  }
}

String? goTaskServiceGatewayEntryState({
  required AssistantExecutionTarget requestedTarget,
  required GoTaskServiceResult result,
}) {
  final resolvedExecutionTarget = result.resolvedExecutionTarget
      .trim()
      .toLowerCase();
  switch (resolvedExecutionTarget) {
    case 'gateway':
      final resolvedEndpointTarget = result.resolvedEndpointTarget
          .trim()
          .toLowerCase();
      if (resolvedEndpointTarget ==
          AssistantExecutionTarget.remote.promptValue.toLowerCase()) {
        return AssistantExecutionTarget.remote.promptValue;
      }
      if (resolvedEndpointTarget ==
          AssistantExecutionTarget.local.promptValue.toLowerCase()) {
        return AssistantExecutionTarget.local.promptValue;
      }
      return requestedTarget == AssistantExecutionTarget.remote
          ? AssistantExecutionTarget.remote.promptValue
          : AssistantExecutionTarget.local.promptValue;
    case 'single-agent':
      return AssistantExecutionTarget.singleAgent.promptValue;
    case 'multi-agent':
      return AssistantExecutionTarget.singleAgent.promptValue;
    default:
      return requestedTarget.promptValue;
  }
}

abstract class ExternalCodeAgentAcpTransport {
  Future<void> syncExternalProviders(
    List<ExternalCodeAgentAcpSyncedProvider> providers,
  );

  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  });

  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  });

  Future<void> cancelTask({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  });

  Future<void> closeTask({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  });

  Future<void> dispose();
}

abstract class GoTaskServiceClient {
  Future<void> syncExternalProviders(
    List<ExternalCodeAgentAcpSyncedProvider> providers,
  );

  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  });

  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  });

  Future<void> cancelTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  });

  Future<void> closeTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  });

  Future<void> dispose();
}

GoTaskServiceUpdate? goTaskServiceUpdateFromAcpNotification(
  Map<String, dynamic> notification,
) {
  final method = notification['method']?.toString().trim().toLowerCase() ?? '';
  if (method != 'session.update' && method != 'acp.session.update') {
    return null;
  }
  final params = _castMap(notification['params']);
  final payload = params.isNotEmpty
      ? params
      : _castMap(notification['payload']);
  final type =
      payload['type']?.toString().trim().toLowerCase() ??
      payload['state']?.toString().trim().toLowerCase() ??
      payload['event']?.toString().trim().toLowerCase() ??
      'status';
  return GoTaskServiceUpdate(
    sessionId: payload['sessionId']?.toString().trim().isNotEmpty == true
        ? payload['sessionId'].toString().trim()
        : payload['threadId']?.toString().trim() ?? '',
    threadId: payload['threadId']?.toString().trim() ?? '',
    turnId: payload['turnId']?.toString().trim() ?? '',
    type: type,
    text:
        payload['delta']?.toString() ??
        payload['text']?.toString() ??
        _castMap(payload['message'])['content']?.toString() ??
        '',
    message: payload['message']?.toString() ?? '',
    pending: _boolValue(payload['pending']) ?? false,
    error: _boolValue(payload['error']) ?? false,
    route:
        (payload['mode']?.toString().trim() == 'multi-agent' ||
            payload['resolvedExecutionTarget']?.toString().trim() ==
                'multi-agent')
        ? GoTaskServiceRoute.externalAcpMulti
        : GoTaskServiceRoute.externalAcpSingle,
    payload: payload,
  );
}

GoTaskServiceResult goTaskServiceResultFromAcpResponse(
  Map<String, dynamic> response, {
  required GoTaskServiceRoute route,
  String streamedText = '',
  String? completedMessage,
}) {
  final result = _castMap(response['result']);
  final skillCandidates = _castMapList(result['skillCandidates'])
      .map((item) => item['id']?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  final fallbackFailureText = () {
    final success = _boolValue(result['success']) ?? true;
    if (success) {
      return '';
    }
    final errorText = result['error']?.toString().trim() ?? '';
    final needsSkillInstall = _boolValue(result['needsSkillInstall']) ?? false;
    if (needsSkillInstall && skillCandidates.isNotEmpty) {
      final candidateText = skillCandidates.join(', ');
      if (errorText.isNotEmpty) {
        return '$errorText (skills: $candidateText)';
      }
      return 'Skill install required: $candidateText';
    }
    return errorText;
  }();
  final responseText =
      (result['output']?.toString().trim().isNotEmpty == true
              ? result['output'].toString().trim()
              : result['summary']?.toString().trim().isNotEmpty == true
              ? result['summary'].toString().trim()
              : result['message']?.toString().trim() ?? '')
          .trim();
  final primaryText =
      (completedMessage?.trim().isNotEmpty == true
              ? completedMessage!.trim()
              : responseText.isNotEmpty
              ? responseText
              : fallbackFailureText.isNotEmpty
              ? fallbackFailureText
              : streamedText.trim().isNotEmpty
              ? streamedText.trim()
              : '')
          .trim();
  return GoTaskServiceResult(
    success: _boolValue(result['success']) ?? true,
    message: primaryText,
    turnId: result['turnId']?.toString().trim() ?? '',
    raw: result,
    errorMessage: result['error']?.toString() ?? '',
    resolvedModel:
        result['model']?.toString().trim() ??
        result['resolvedModel']?.toString().trim() ??
        '',
    route: route,
  );
}

Map<String, dynamic> mergeGoTaskServiceResponseResult(
  Map<String, dynamic> response,
  Map<String, dynamic> overlay,
) {
  if (overlay.isEmpty) {
    return response;
  }
  final next = Map<String, dynamic>.from(response);
  final result = Map<String, dynamic>.from(_castMap(next['result']));
  overlay.forEach((key, value) {
    if (value == null) {
      return;
    }
    if (value is String && value.trim().isEmpty) {
      if (result.containsKey(key)) {
        return;
      }
    }
    result[key] = value;
  });
  next['result'] = result;
  return next;
}

int goTaskServiceBase64Size(String base64) {
  final normalized = base64.trim().split(',').last.trim();
  if (normalized.isEmpty) {
    return 0;
  }
  final padding = normalized.endsWith('==')
      ? 2
      : (normalized.endsWith('=') ? 1 : 0);
  return (normalized.length * 3 ~/ 4) - padding;
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

bool? _boolValue(Object? raw) {
  if (raw is bool) {
    return raw;
  }
  if (raw is num) {
    return raw != 0;
  }
  if (raw is String) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  return null;
}

List<Map<String, dynamic>> _castMapList(Object? raw) {
  if (raw is! List) {
    return const <Map<String, dynamic>>[];
  }
  return raw.map(_castMap).toList(growable: false);
}
