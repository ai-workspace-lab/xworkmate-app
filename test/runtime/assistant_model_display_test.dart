import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('Assistant model display', () {
    test('hides stale model display when no runtime model matches', () async {
      final controller = AppController();
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('session-1');

      expect(controller.resolvedAssistantModel, isNotEmpty);
      expect(controller.assistantModelChoices, isEmpty);
      expect(
        controller.assistantDisplayModelForSession(
          controller.currentSessionKey,
        ),
        isEmpty,
      );
    });

    test(
      'shows matched runtime model when gateway catalog is available',
      () async {
        final controller = AppController();
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );
        controller.runtimeInternal.snapshotInternal = controller
            .runtimeInternal
            .snapshot
            .copyWith(
              status: RuntimeConnectionStatus.connected,
              statusText: 'Connected',
            );
        controller.modelsControllerInternal.itemsInternal =
            const <GatewayModelSummary>[
              GatewayModelSummary(
                id: 'qwen2.5-coder:latest',
                name: 'Qwen 2.5 Coder',
                provider: 'ollama',
                contextWindow: null,
                maxOutputTokens: null,
              ),
            ];

        expect(controller.assistantModelChoices, const <String>[
          'qwen2.5-coder:latest',
        ]);
        expect(
          controller.assistantDisplayModelForSession(
            controller.currentSessionKey,
          ),
          'qwen2.5-coder:latest',
        );
      },
    );
  });
}
