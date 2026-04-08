import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/assistant/assistant_page.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';

import '../runtime/app_controller_ai_gateway_chat_suite_fakes.dart';
import 'assistant_page_suite_support.dart';

Future<void> _waitForText(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for ${finder.description}');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
    'AssistantPage single agent can be selected and receive streaming reply',
    (WidgetTester tester) async {
      final workspaceDirectory = Directory.systemTemp.createTempSync(
        'xworkmate-single-agent-workspace-',
      );
      addTearDown(() async {
        if (await workspaceDirectory.exists()) {
          await workspaceDirectory.delete(recursive: true);
        }
      });
      final fakeGoTaskServiceClient = FakeGoTaskServiceClientInternal(
        capabilities: ExternalCodeAgentAcpCapabilities(
          singleAgent: true,
          multiAgent: false,
          providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
          raw: <String, dynamic>{},
        ),
        result: const GoTaskServiceResult(
          success: true,
          message: 'CODEX_REPLY',
          turnId: 'turn-1',
          raw: <String, dynamic>{},
          errorMessage: '',
          resolvedModel: 'codex-chat',
          route: GoTaskServiceRoute.externalAcpSingle,
        ),
      );
      final noopMultiAgentMountManager =
          NoopMultiAgentMountManagerInternal();
      final controller = await createControllerWithThreadRecordsInternal(
        tester: tester,
        records: <TaskThread>[
          TaskThread(
            threadId: 'main',
            workspaceBinding: const WorkspaceBinding(
              workspaceId: 'main',
              workspaceKind: WorkspaceKind.remoteFs,
              workspacePath: '',
              displayPath: '',
              writable: true,
            ).copyWith(
              workspacePath: workspaceDirectory.path,
              displayPath: workspaceDirectory.path,
            ),
            messages: const <GatewayChatMessage>[],
            updatedAtMs: 1,
            title: 'Main',
            archived: false,
            executionBinding: const ExecutionBinding(
              executionMode: ThreadExecutionMode.gatewayLocal,
              executorId: 'opencode',
              providerId: 'opencode',
              endpointId: '',
            ),
            messageViewMode: AssistantMessageViewMode.rendered,
          ),
        ],
        useFakeGatewayRuntime: true,
        assistantExecutionTargetOverride: AssistantExecutionTarget.local,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
        singleAgentSharedSkillScanRootOverrides: const <String>[],
        disableGatewayProfileEndpoints: true,
        goTaskServiceClient: fakeGoTaskServiceClient,
        multiAgentMountManager: noopMultiAgentMountManager,
      );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1000);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: Scaffold(
            body: AssistantPage(controller: controller, onOpenDetail: (_) {}),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(
        find.byKey(const ValueKey<String>('assistant-composer-input-area')),
        'hello codex',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('assistant-send-button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await _waitForText(tester, find.textContaining('CODEX_REPLY'));

      expect(find.textContaining('CODEX_REPLY'), findsWidgets);
      expect(fakeGoTaskServiceClient.executeCalls, 1);
      expect(
        fakeGoTaskServiceClient.lastRequest?.provider,
        SingleAgentProvider.opencode,
      );
      expect(find.textContaining('hello codex'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.pump();
    },
  );
}
