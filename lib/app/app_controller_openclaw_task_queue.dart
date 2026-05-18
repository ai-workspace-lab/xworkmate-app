import '../runtime/go_task_service_client.dart';
import '../runtime/runtime_models.dart';

const int openClawGatewayMaxActiveTasksInternal = 1;
const int openClawGatewayMaxQueuedTasksInternal = 20;

class OpenClawGatewayQueuedTurnInternal {
  OpenClawGatewayQueuedTurnInternal({
    required this.queueId,
    required this.sessionKey,
    required this.target,
    required this.provider,
    required this.message,
    required this.thinking,
    required this.selectedSkillLabels,
    required this.attachments,
    required this.localAttachments,
    required this.workingDirectory,
    required this.remoteWorkingDirectoryHint,
    required this.model,
    required this.routing,
    required this.agentId,
    required this.metadata,
    required this.resumeSessionHint,
  });

  final String queueId;
  final String sessionKey;
  final AssistantExecutionTarget target;
  final SingleAgentProvider provider;
  final String message;
  final String thinking;
  final List<String> selectedSkillLabels;
  final List<GatewayChatAttachmentPayload> attachments;
  final List<CollaborationAttachment> localAttachments;
  final String workingDirectory;
  final String remoteWorkingDirectoryHint;
  final String model;
  final ExternalCodeAgentAcpRoutingConfig routing;
  final String agentId;
  final Map<String, dynamic> metadata;
  final bool resumeSessionHint;

  bool cancelled = false;
}
