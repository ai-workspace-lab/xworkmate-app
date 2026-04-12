import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('AssistantExecutionTarget', () {
    test('maps agent and gateway values without collapsing them', () {
      expect(
        threadExecutionModeFromAssistantExecutionTarget(
          AssistantExecutionTarget.agent,
        ),
        ThreadExecutionMode.agent,
      );
      expect(
        threadExecutionModeFromAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        ),
        ThreadExecutionMode.gateway,
      );
      expect(
        assistantExecutionTargetFromExecutionMode(ThreadExecutionMode.agent),
        AssistantExecutionTarget.agent,
      );
      expect(
        assistantExecutionTargetFromExecutionMode(ThreadExecutionMode.gateway),
        AssistantExecutionTarget.gateway,
      );
    });

    test('keeps both task dialog modes visible when both are supported', () {
      expect(
        compactAssistantExecutionTargets(const <AssistantExecutionTarget>[
          AssistantExecutionTarget.agent,
          AssistantExecutionTarget.gateway,
        ]),
        const <AssistantExecutionTarget>[
          AssistantExecutionTarget.agent,
          AssistantExecutionTarget.gateway,
        ],
      );
    });

    test('recognizes openclaw as the canonical gateway provider', () {
      final provider = SingleAgentProvider.fromJsonValue('openclaw');

      expect(provider.providerId, kCanonicalGatewayProviderId);
      expect(provider.label, kCanonicalGatewayProviderLabel);
    });
  });
}
