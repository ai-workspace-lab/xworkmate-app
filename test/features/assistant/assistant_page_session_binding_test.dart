import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/assistant/assistant_page_main.dart';
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

  testWidgets('does not scroll when current message metadata refreshes', (
    tester,
  ) async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);
    final pageKey = GlobalKey<AssistantPageStateInternal>();
    const sessionKey = 'stable-scroll-task';

    await controller.sessionsController.switchSession(sessionKey);
    controller.localSessionMessagesInternal[sessionKey] = _conversationMessages(
      count: 18,
      pendingLast: true,
    );

    await _pumpAssistantPage(tester, controller: controller, pageKey: pageKey);
    await tester.pump(const Duration(milliseconds: 300));

    final scrollController =
        pageKey.currentState!.conversationControllerInternal;
    scrollController.jumpTo(120);
    await tester.pump();
    final offsetBefore = scrollController.offset;

    controller.localSessionMessagesInternal[sessionKey] = _conversationMessages(
      count: 18,
      pendingLast: false,
    );
    // ignore: invalid_use_of_protected_member
    pageKey.currentState!.setState(() {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(scrollController.offset, offsetBefore);

    controller.localSessionMessagesInternal[sessionKey] = _conversationMessages(
      count: 19,
      pendingLast: false,
    );
    expect(controller.chatMessages.length, 19);
    // ignore: invalid_use_of_protected_member
    pageKey.currentState!.setState(() {});
    await tester.pump();
    expect(
      pageKey.currentState!.lastConversationScrollSignatureInternal,
      'stable-scroll-task:19:message-18',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(scrollController.offset, greaterThan(offsetBefore));
    expect(
      scrollController.offset,
      greaterThanOrEqualTo(scrollController.position.maxScrollExtent - 1),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}

Future<void> _pumpAssistantPage(
  WidgetTester tester, {
  required AppController controller,
  required GlobalKey<AssistantPageStateInternal> pageKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Material(
        child: SizedBox(
          width: 1280,
          height: 520,
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
}

List<GatewayChatMessage> _conversationMessages({
  required int count,
  required bool pendingLast,
}) {
  return List<GatewayChatMessage>.generate(count, (index) {
    final isLast = index == count - 1;
    return GatewayChatMessage(
      id: 'message-$index',
      role: index.isEven ? 'user' : 'assistant',
      text:
          'message $index ${'long content keeps the conversation scrollable ' * 8}',
      timestampMs: index.toDouble(),
      toolCallId: null,
      toolName: null,
      stopReason: null,
      pending: isLast && pendingLast,
      error: false,
    );
  }, growable: false);
}
