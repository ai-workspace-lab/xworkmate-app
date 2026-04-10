@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

import 'app_controller_ai_gateway_chat_suite_fakes.dart';
import 'app_controller_ai_gateway_chat_suite_fixtures.dart';

void main() {
  test(
    'single-agent thread upsert auto-binds a complete workspace binding',
    () async {
      final tempDirectory = await createTempDirectoryInternal(
        'xworkmate-single-agent-auto-bind-',
      );
      final store = createStoreFromTempDirectoryInternal(tempDirectory);
      final controller = await createAppControllerInternal(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.opencode,
        ],
        runtimeCoordinator: RuntimeCoordinator(
          gateway: FakeGatewayRuntimeInternal(store: store),
          codex: FakeCodexRuntimeInternal(),
        ),
        goTaskServiceClient: FallbackOnlyGoTaskServiceClientInternal(),
      );

      controller.upsertTaskThreadInternal(
        'main',
        singleAgentProvider: SingleAgentProvider.opencode,
        singleAgentProviderSource: ThreadSelectionSource.explicit,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        executionTarget: AssistantExecutionTarget.singleAgent,
      );

      final workspacePath = controller.assistantWorkspacePathForSession('main');
      expect(workspacePath, isNotEmpty);
      expect(Directory(workspacePath).existsSync(), isTrue);
      expect(
        controller.assistantWorkspaceKindForSession('main'),
        WorkspaceRefKind.localPath,
      );
    },
  );

  test(
    'single-agent managed thread workspace rebinds when workspace root changes',
    () async {
      final initialWorkspace = await createTempDirectoryInternal(
        'xworkmate-workspace-initial-',
      );
      final nextWorkspace = await createTempDirectoryInternal(
        'xworkmate-workspace-next-',
      );
      final store = createStoreFromTempDirectoryInternal(initialWorkspace);
      final controller = await createAppControllerInternal(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.opencode,
        ],
        runtimeCoordinator: RuntimeCoordinator(
          gateway: FakeGatewayRuntimeInternal(store: store),
          codex: FakeCodexRuntimeInternal(),
        ),
        goTaskServiceClient: FallbackOnlyGoTaskServiceClientInternal(),
      );
      addTearDown(controller.dispose);

      await controller.saveSettings(
        controller.settings.copyWith(
          workspacePath: nextWorkspace.path,
          assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
        ),
        refreshAfterSave: false,
      );

      final workspacePath = controller.assistantWorkspacePathForSession('main');
      expect(workspacePath, '${nextWorkspace.path}/.xworkmate/threads/main');
      expect(Directory(workspacePath).existsSync(), isTrue);
    },
  );
}
