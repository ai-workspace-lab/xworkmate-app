@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

GatewayChatMessage _userMessage(String text) => GatewayChatMessage(
  id: 'user-${text.hashCode}',
  role: 'user',
  text: text,
  timestampMs: DateTime(2026, 4, 6).millisecondsSinceEpoch.toDouble(),
  toolCallId: null,
  toolName: null,
  stopReason: null,
  pending: false,
  error: false,
);

GatewayChatMessage _assistantMessage(String text) => GatewayChatMessage(
  id: 'assistant-${text.hashCode}',
  role: 'assistant',
  text: text,
  timestampMs: DateTime(2026, 4, 6).millisecondsSinceEpoch.toDouble(),
  toolCallId: null,
  toolName: null,
  stopReason: null,
  pending: false,
  error: false,
);

void main() {
  group('Task title persistence', () {
    test('derives the default task title from the first user message', () {
      final title = derivePersistedTaskTitle('新对话', <GatewayChatMessage>[
        _userMessage('请帮我排查桌面端任务边栏为什么一直显示新任务'),
      ]);

      expect(title, '请帮我排查桌面端任务边栏为什么一直显示新任务');
    });

    test('keeps the persisted auto title after later messages arrive', () {
      final title = derivePersistedTaskTitle('首条任务说明', <GatewayChatMessage>[
        _userMessage('首条任务说明'),
        _assistantMessage('收到，我来看看'),
        _userMessage('补充更多上下文，但不应该改标题'),
      ]);

      expect(title, '首条任务说明');
    });

    test('does not overwrite a custom title with an auto-derived title', () {
      final title = derivePersistedTaskTitle('我自己改过的标题', <GatewayChatMessage>[
        _userMessage('默认标题候选'),
      ], hasCustomTitle: true);

      expect(title, '我自己改过的标题');
    });

    test(
      'falls back to the persisted auto title after custom title is cleared',
      () {
        final title = derivePersistedTaskTitle(
          '已持久化的自动标题',
          <GatewayChatMessage>[_userMessage('新的消息不应该重新改标题')],
        );

        expect(title, '已持久化的自动标题');
      },
    );
  });
}
