import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

/// 回归背景:移动端助手页在首帧 post-frame 回调里调用
/// ensureActiveAssistantThreadInternal(),此时 initializeInternal() 的
/// 线程恢复尚未完成。修复前该调用会立刻铸出新 draft 并以
/// 「仅含 draft 的部分快照」持久化,存储层的删除对账随之清掉全部
/// 历史会话键——真机表现为杀进程重开后只剩「新对话」。
class _TestSecureConfigStore extends SecureConfigStore {
  _TestSecureConfigStore({required String rootPath})
    : super(
        secretRootPathResolver: () async => '$rootPath/secrets',
        appDataRootPathResolver: () async => '$rootPath/app-data',
        supportRootPathResolver: () async => '$rootPath/support',
        enableSecureStorage: false,
      );
}

TaskThread _historyThread(String sessionKey, String workspaceRoot) {
  return TaskThread(
    threadId: sessionKey,
    title: '历史任务',
    workspaceBinding: WorkspaceBinding(
      workspaceId: sessionKey,
      workspaceKind: WorkspaceKind.localFs,
      workspacePath: '$workspaceRoot/$sessionKey',
      displayPath: '$workspaceRoot/$sessionKey',
      writable: true,
    ),
    messages: const <GatewayChatMessage>[
      GatewayChatMessage(
        id: 'history-message',
        role: 'user',
        text: '历史消息',
        timestampMs: 1,
        toolCallId: null,
        toolName: null,
        stopReason: null,
        pending: false,
        error: false,
      ),
    ],
  );
}

Future<void> _waitForControllerInitialization(AppController controller) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (controller.initializing && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(controller.initializing, isFalse);
}

void main() {
  test(
    'first-frame ensureActiveAssistantThread does not wipe persisted history',
    () async {
      final storeRoot = await Directory.systemTemp.createTemp(
        'xworkmate-startup-race-store-',
      );
      addTearDown(() async {
        if (await storeRoot.exists()) {
          await storeRoot.delete(recursive: true);
        }
      });
      final store = _TestSecureConfigStore(rootPath: storeRoot.path);
      await store.initialize();
      const sessionKey = 'draft:persisted-before-race';
      await store.saveTaskThreads(<TaskThread>[
        _historyThread(sessionKey, '${storeRoot.path}/workspaces'),
      ]);

      final controller = AppController(
        store: store,
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      // 模拟移动端首帧:初始化还在进行时就要求激活会话。
      await controller.ensureActiveAssistantThreadInternal();

      await _waitForControllerInitialization(controller);
      await controller.persistAssistantHistory();

      final persisted = await store.loadTaskThreads();
      expect(
        persisted.map((thread) => thread.threadId),
        contains(sessionKey),
        reason: '首帧的会话激活不得清掉已持久化的历史会话',
      );
      expect(
        controller.assistantSessions.map((session) => session.key),
        contains(sessionKey),
      );
    },
  );

  test(
    'ensureActiveAssistantThread after restore reuses the persisted session',
    () async {
      final storeRoot = await Directory.systemTemp.createTemp(
        'xworkmate-startup-reuse-store-',
      );
      addTearDown(() async {
        if (await storeRoot.exists()) {
          await storeRoot.delete(recursive: true);
        }
      });
      final store = _TestSecureConfigStore(rootPath: storeRoot.path);
      await store.initialize();
      const sessionKey = 'draft:persisted-reuse';
      await store.saveTaskThreads(<TaskThread>[
        _historyThread(sessionKey, '${storeRoot.path}/workspaces'),
      ]);

      final controller = AppController(
        store: store,
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      // 复刻移动端首帧路径:先等恢复信号,再激活会话。
      await controller.assistantThreadsRestoredInternal.future;
      await controller.ensureActiveAssistantThreadInternal();

      // 已有可用历史会话时不该另铸空 draft 顶掉它。
      expect(controller.currentSessionKey, sessionKey);
    },
  );
}
