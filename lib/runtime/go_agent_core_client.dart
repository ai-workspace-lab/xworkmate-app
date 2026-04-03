import 'runtime_models.dart';

class GoAgentCoreCapabilities {
  const GoAgentCoreCapabilities({
    required this.singleAgent,
    required this.multiAgent,
    required this.providers,
    required this.raw,
  });

  const GoAgentCoreCapabilities.empty()
    : singleAgent = false,
      multiAgent = false,
      providers = const <SingleAgentProvider>{},
      raw = const <String, dynamic>{};

  final bool singleAgent;
  final bool multiAgent;
  final Set<SingleAgentProvider> providers;
  final Map<String, dynamic> raw;
}

enum GoAgentCoreRoutingMode { auto, explicit }

class GoAgentCoreAvailableSkill {
  const GoAgentCoreAvailableSkill({
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

class GoAgentCoreRoutingConfig {
  const GoAgentCoreRoutingConfig({
    required this.mode,
    required this.preferredGatewayTarget,
    required this.explicitExecutionTarget,
    required this.explicitProviderId,
    required this.explicitModel,
    required this.explicitSkills,
    required this.allowSkillInstall,
    required this.availableSkills,
  });

  const GoAgentCoreRoutingConfig.auto({
    this.preferredGatewayTarget = '',
    this.availableSkills = const <GoAgentCoreAvailableSkill>[],
  }) : mode = GoAgentCoreRoutingMode.auto,
       explicitExecutionTarget = '',
       explicitProviderId = '',
       explicitModel = '',
       explicitSkills = const <String>[],
       allowSkillInstall = false;

  final GoAgentCoreRoutingMode mode;
  final String preferredGatewayTarget;
  final String explicitExecutionTarget;
  final String explicitProviderId;
  final String explicitModel;
  final List<String> explicitSkills;
  final bool allowSkillInstall;
  final List<GoAgentCoreAvailableSkill> availableSkills;

  bool get isAuto => mode == GoAgentCoreRoutingMode.auto;

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
    };
  }
}

class GoAgentCoreSessionRequest {
  const GoAgentCoreSessionRequest({
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
    this.provider = SingleAgentProvider.auto,
    this.resumeSession = false,
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
  final GoAgentCoreRoutingConfig? routing;
  final SingleAgentProvider provider;
  final bool resumeSession;
  final bool multiAgent;

  String get mode {
    if (multiAgent) {
      return 'multi-agent';
    }
    return switch (target) {
      AssistantExecutionTarget.auto => 'single-agent',
      AssistantExecutionTarget.singleAgent => 'single-agent',
      AssistantExecutionTarget.local => _gatewaySessionMode,
      AssistantExecutionTarget.remote => _gatewaySessionMode,
    };
  }

  String get routingExecutionTarget {
    if (multiAgent) {
      return 'multi-agent';
    }
    return switch (target) {
      AssistantExecutionTarget.auto => 'single-agent',
      AssistantExecutionTarget.singleAgent => 'single-agent',
      AssistantExecutionTarget.local => 'gateway',
      AssistantExecutionTarget.remote => 'gateway',
    };
  }

  bool get hasInlineAttachments => inlineAttachments.isNotEmpty;

  Map<String, dynamic> toAcpParams() {
    final params = <String, dynamic>{
      'sessionId': sessionId,
      'threadId': threadId,
      'mode': mode,
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
                'sizeBytes': goAgentCoreBase64Size(item.content),
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
      if (routing != null) 'routing': routing!.toJson(),
      if (_usesGatewaySessionMode(mode)) ...<String, dynamic>{
        'executionTarget': target.promptValue,
        if (agentId.trim().isNotEmpty) 'agentId': agentId.trim(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      },
    };
    return params;
  }
}

const String _gatewaySessionMode = 'gateway-chat';

bool _usesGatewaySessionMode(String mode) {
  final normalized = mode.trim();
  return normalized == 'gateway' || normalized == _gatewaySessionMode;
}

class GoAgentCoreSessionUpdate {
  const GoAgentCoreSessionUpdate({
    required this.sessionId,
    required this.threadId,
    required this.turnId,
    required this.type,
    required this.text,
    required this.message,
    required this.pending,
    required this.error,
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
  final Map<String, dynamic> payload;

  bool get isDelta => type == 'delta' && text.isNotEmpty;
  bool get isDone => type == 'done' || payload['event'] == 'completed';
}

class GoAgentCoreRunResult {
  const GoAgentCoreRunResult({
    required this.success,
    required this.message,
    required this.turnId,
    required this.raw,
    required this.errorMessage,
    required this.resolvedModel,
  });

  final bool success;
  final String message;
  final String turnId;
  final Map<String, dynamic> raw;
  final String errorMessage;
  final String resolvedModel;

  String get resolvedWorkingDirectory =>
      raw['resolvedWorkingDirectory']?.toString().trim() ??
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

  WorkspaceRefKind? get resolvedWorkspaceRefKind {
    final rawValue = raw['resolvedWorkspaceRefKind']?.toString().trim() ?? '';
    if (rawValue.isEmpty) {
      return null;
    }
    return WorkspaceRefKindCopy.fromJsonValue(rawValue);
  }
}

abstract class GoAgentCoreClient {
  Future<GoAgentCoreCapabilities> loadCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  });

  Future<GoAgentCoreRunResult> executeSession(
    GoAgentCoreSessionRequest request, {
    required void Function(GoAgentCoreSessionUpdate update) onUpdate,
  });

  Future<void> cancelSession({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  });

  Future<void> closeSession({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  });

  Future<void> dispose();
}

GoAgentCoreSessionUpdate? goAgentCoreUpdateFromNotification(
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
  return GoAgentCoreSessionUpdate(
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
    payload: payload,
  );
}

GoAgentCoreRunResult goAgentCoreRunResultFromResponse(
  Map<String, dynamic> response, {
  String streamedText = '',
  String? completedMessage,
}) {
  final result = _castMap(response['result']);
  final primaryText =
      (completedMessage?.trim().isNotEmpty == true
              ? completedMessage!.trim()
              : streamedText.trim().isNotEmpty
              ? streamedText.trim()
              : (result['output']?.toString().trim().isNotEmpty == true
                    ? result['output'].toString().trim()
                    : result['summary']?.toString().trim().isNotEmpty == true
                    ? result['summary'].toString().trim()
                    : result['message']?.toString().trim() ?? ''))
          .trim();
  return GoAgentCoreRunResult(
    success: _boolValue(result['success']) ?? true,
    message: primaryText,
    turnId: result['turnId']?.toString().trim() ?? '',
    raw: result,
    errorMessage: result['error']?.toString() ?? '',
    resolvedModel:
        result['model']?.toString().trim() ??
        result['resolvedModel']?.toString().trim() ??
        '',
  );
}

Map<String, dynamic> mergeGoAgentCoreResponseResult(
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

int goAgentCoreBase64Size(String base64) {
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
  final text = raw?.toString().trim().toLowerCase();
  if (text == null || text.isEmpty) {
    return null;
  }
  if (text == 'true' || text == '1' || text == 'yes') {
    return true;
  }
  if (text == 'false' || text == '0' || text == 'no') {
    return false;
  }
  return null;
}
