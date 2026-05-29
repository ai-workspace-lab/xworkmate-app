import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/assistant/assistant_page_main.dart';
import 'package:xworkmate/features/assistant/assistant_page_state_actions.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  testWidgets('does not render conversation messages from another session', (
    tester,
  ) async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    await controller.sessionsController.switchSession('current-session');
    controller.localSessionMessagesInternal['current-session'] =
        const <GatewayChatMessage>[
          GatewayChatMessage(
            id: 'current-local',
            role: 'assistant',
            text: 'current session message',
            timestampMs: 1,
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: false,
          ),
        ];
    controller.chatController
      ..sessionKeyInternal = 'stale-session'
      ..messagesInternal = const <GatewayChatMessage>[
        GatewayChatMessage(
          id: 'stale-gateway',
          role: 'assistant',
          text: 'stale gateway message',
          timestampMs: 2,
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Material(
          child: SizedBox(
            width: 1280,
            height: 760,
            child: AssistantPage(
              controller: controller,
              showStandaloneTaskRail: false,
              onOpenDetail: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('current session message'), findsAtLeastNWidgets(1));
    expect(find.text('stale gateway message'), findsNothing);
  });

  testWidgets('preserves unsent composer drafts per assistant session', (
    tester,
  ) async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);
    final pageKey = GlobalKey<AssistantPageStateInternal>();

    await controller.sessionsController.switchSession('draft-session-a');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Material(
          child: SizedBox(
            width: 1280,
            height: 760,
            child: AssistantPage(
              key: pageKey,
              controller: controller,
              showStandaloneTaskRail: false,
              onOpenDetail: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final state = pageKey.currentState!;
    state.composerDraftSessionKeyInternal = 'draft-session-a';
    state.inputControllerInternal.text = 'draft prompt A';

    state.syncComposerDraftForActiveSessionInternal('draft-session-b');
    expect(state.inputControllerInternal.text, isEmpty);

    state.inputControllerInternal.text = 'draft prompt B';
    state.syncComposerDraftForActiveSessionInternal('draft-session-a');
    expect(state.inputControllerInternal.text, 'draft prompt A');

    state.syncComposerDraftForActiveSessionInternal('draft-session-b');
    expect(state.inputControllerInternal.text, 'draft prompt B');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('keeps follow-up submit bound to the running task', (
    tester,
  ) async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);
    final pageKey = GlobalKey<AssistantPageStateInternal>();

    const sessionKey = 'running-task';
    await controller.sessionsController.switchSession(sessionKey);
    controller.aiGatewayPendingSessionKeysInternal.add(sessionKey);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Material(
          child: SizedBox(
            width: 1280,
            height: 760,
            child: AssistantPage(
              key: pageKey,
              controller: controller,
              showStandaloneTaskRail: false,
              onOpenDetail: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final state = pageKey.currentState!;
    state.inputControllerInternal.text = 'continue current task';

    unawaited(
      state.submitPromptInternal().catchError((_) {
        return null;
      }),
    );
    await tester.pump();

    expect(controller.currentSessionKey, sessionKey);
    expect(
      controller.assistantSessions.map((session) => session.key),
      isNot(contains(startsWith('draft:'))),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
