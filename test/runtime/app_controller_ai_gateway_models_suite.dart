@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  test(
    'AppController exposes selected LLM API models to the assistant',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-app-controller-models-',
      );
      addTearDown(() => _deleteDirectoryWithRetry(tempDirectory));
      final store = _createIsolatedStore(tempDirectory.path);
      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
      );
      addTearDown(controller.dispose);
      addTearDown(store.dispose);

      await _waitFor(() => !controller.initializing);
      await controller.settingsController.saveAiGatewayApiKey('live-key');

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
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-app-controller-models-',
      );
      addTearDown(() => _deleteDirectoryWithRetry(tempDirectory));
      final store = _createIsolatedStore(tempDirectory.path);
      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
      );
      addTearDown(controller.dispose);
      addTearDown(store.dispose);

      await _waitFor(() => !controller.initializing);
      await controller.settingsController.saveAiGatewayApiKey('live-key');

      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            baseUrl: 'http://127.0.0.1:11434/v1',
            availableModels: const <String>['qwen2.5-coder:latest'],
            selectedModels: const <String>['qwen2.5-coder:latest'],
          ),
          defaultModel: 'gpt-5.4',
          assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
        ),
      );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      expect(controller.assistantModelChoices, const <String>[
        'qwen2.5-coder:latest',
      ]);
      expect(controller.resolvedAssistantModel, 'qwen2.5-coder:latest');
      expect(controller.canUseAiGatewayConversation, isTrue);

      await controller.saveSettings(
        controller.settings.copyWith(
          assistantExecutionTarget: AssistantExecutionTarget.local,
        ),
      );

      expect(controller.resolvedAssistantModel, 'gpt-5.4');
      expect(controller.assistantModelChoices, const <String>['gpt-5.4']);
    },
  );

  test(
    'AppController does not borrow LLM API model choices when an external Single Agent provider is available',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-app-controller-provider-models-',
      );
      addTearDown(() => _deleteDirectoryWithRetry(tempDirectory));
      final store = _createIsolatedStore(tempDirectory.path);
      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
      );
      addTearDown(controller.dispose);
      addTearDown(store.dispose);

      await _waitFor(() => !controller.initializing);

      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            availableModels: const <String>['qwen2.5-coder:latest'],
            selectedModels: const <String>['qwen2.5-coder:latest'],
          ),
          defaultModel: 'qwen2.5-coder:latest',
          assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
        ),
      );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      await controller.setSingleAgentProvider(SingleAgentProvider.codex);

      expect(controller.currentSingleAgentHasResolvedProvider, isTrue);
      expect(controller.currentSingleAgentUsesAiChatFallback, isFalse);
      expect(controller.currentSingleAgentShouldShowModelControl, isFalse);
      expect(controller.assistantModelChoices, isEmpty);
      expect(controller.resolvedAssistantModel, isEmpty);
    },
  );
}

SecureConfigStore _createIsolatedStore(String rootPath) {
  return SecureConfigStore(
    enableSecureStorage: false,
    databasePathResolver: () async => '$rootPath/config-store.sqlite3',
    fallbackDirectoryPathResolver: () async => rootPath,
    defaultSupportDirectoryPathResolver: () async => rootPath,
  );
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 5; attempt += 1) {
    if (!await directory.exists()) {
      return;
    }
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 4) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 80 * (attempt + 1)));
    }
  }
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
