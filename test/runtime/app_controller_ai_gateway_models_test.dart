import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'AppController exposes selected AI Gateway models to the assistant',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppController();
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);

      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            availableModels: const <String>['gpt-5.4', 'o3-mini', 'claude-3.7'],
            selectedModels: const <String>['o3-mini', 'gpt-5.4'],
          ),
          defaultModel: 'o3-mini',
        ),
      );

      expect(controller.aiGatewayModelChoices, const <String>[
        'o3-mini',
        'gpt-5.4',
      ]);
      expect(controller.resolvedDefaultModel, 'o3-mini');
    },
  );

  test(
    'AppController switches assistant model source with the execution mode',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppController();
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);

      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            availableModels: const <String>['qwen2.5-coder:latest'],
            selectedModels: const <String>['qwen2.5-coder:latest'],
          ),
          defaultModel: 'gpt-5.4',
          assistantExecutionTarget: AssistantExecutionTarget.aiGatewayOnly,
        ),
      );

      expect(controller.assistantModelChoices, const <String>[
        'qwen2.5-coder:latest',
      ]);
      expect(controller.resolvedAssistantModel, 'qwen2.5-coder:latest');
      expect(controller.canUseAiGatewayConversation, isFalse);

      await controller.saveSettings(
        controller.settings.copyWith(
          assistantExecutionTarget: AssistantExecutionTarget.local,
        ),
      );

      expect(controller.resolvedAssistantModel, 'gpt-5.4');
      expect(controller.assistantModelChoices, const <String>['gpt-5.4']);
    },
  );
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
