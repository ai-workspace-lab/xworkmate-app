import 'package:flutter/widgets.dart';

class TestKeys {
  const TestKeys._();

  static const Key settingsGatewayTab = Key('sidebar-settings-tab-gateway');
  static const Key settingsIntegrationsTab = Key('section-tab-ACP 外部接入');
  static const Key settingsGatewayIntegrationTab = Key(
    'section-tab-OpenClaw Gateway',
  );
  static const Key settingsExternalAcpProvider = Key('external-acp-card-Codex');
  static const Key settingsExternalAcpEndpoint = Key(
    'external-acp-endpoint-Codex',
  );
  static const Key settingsExternalAcpAuth = Key('external-acp-auth-Codex');
  static const Key settingsExternalAcpTest = Key('external-acp-test-Codex');
  static const Key settingsExternalAcpSave = Key('external-acp-apply-Codex');

  static const Key assistantTaskRail = Key('assistant-task-rail');
  static const Key assistantExecutionTargetButton = Key(
    'assistant-execution-target-button',
  );
  static const Key assistantSingleAgentProviderButton = Key(
    'assistant-single-agent-provider-button',
  );
  static const Key assistantComposerInput = Key(
    'assistant-composer-input-area',
  );
  static const Key assistantSubmitButton = Key('assistant-submit-button');
  static const Key assistantNewTaskButton = Key('assistant-new-task-button');
  static const Key assistantTaskItemMain = ValueKey<String>(
    'assistant-task-item-main',
  );
}
