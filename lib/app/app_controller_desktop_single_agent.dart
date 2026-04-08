import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_single_agent_go_task_flow.dart';
import 'app_controller_desktop_single_agent_status_messages.dart';
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

  GatewayChatMessage assistantErrorMessageInternal(String text) {
    return assistantErrorMessageSingleAgentDesktopInternal(this, text);
  }
}
