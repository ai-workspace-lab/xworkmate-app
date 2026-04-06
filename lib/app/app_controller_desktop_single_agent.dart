import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_single_agent_ai_gateway.dart';
import 'app_controller_desktop_single_agent_go_task_flow.dart';
import '../runtime/runtime_models.dart';

extension AppControllerDesktopSingleAgent on AppController {
  Future<void> sendSingleAgentMessageInternal(
    String message, {
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<CollaborationAttachment> localAttachments,
  }) {
    return sendSingleAgentMessageDesktopGoTaskFlowInternal(
      this,
      message,
      thinking: thinking,
      attachments: attachments,
      localAttachments: localAttachments,
    );
  }

  Future<void> abortAiGatewayRunInternal(String sessionKey) {
    return abortAiGatewaySingleAgentRunDesktopInternal(this, sessionKey);
  }

  GatewayChatMessage assistantErrorMessageInternal(String text) {
    return assistantErrorMessageSingleAgentDesktopInternal(this, text);
  }
}
