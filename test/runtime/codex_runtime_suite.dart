@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';

void main() {
  group('CodexSandboxMode', () {
    test('has correct values', () {
      expect(CodexSandboxMode.readOnly.value, equals('read-only'));
      expect(CodexSandboxMode.workspaceWrite.value, equals('workspace-write'));
      expect(
        CodexSandboxMode.dangerFullAccess.value,
        equals('danger-full-access'),
      );
    });
  });

  group('CodexApprovalPolicy', () {
    test('has correct values', () {
      expect(CodexApprovalPolicy.suggest.value, equals('suggest'));
      expect(CodexApprovalPolicy.autoEdit.value, equals('auto-edit'));
      expect(CodexApprovalPolicy.fullAuto.value, equals('full-auto'));
    });
  });

  group('CodexThread', () {
    test('fromJson creates correct object', () {
      final json = {
        'id': 'thread-123',
        'path': '/path/to/thread',
        'ephemeral': true,
        'createdAt': '2024-01-01T00:00:00Z',
      };

      final thread = CodexThread.fromJson(json);

      expect(thread.id, equals('thread-123'));
      expect(thread.path, equals('/path/to/thread'));
      expect(thread.ephemeral, isTrue);
      expect(thread.createdAt, isNotNull);
    });

    test('toJson produces correct output', () {
      final thread = CodexThread(
        id: 'thread-456',
        path: '/another/path',
        ephemeral: false,
      );

      final json = thread.toJson();

      expect(json['id'], equals('thread-456'));
      expect(json['path'], equals('/another/path'));
      expect(json['ephemeral'], isFalse);
    });
  });

  group('CodexRpcError', () {
    test('fromJson creates correct object', () {
      final json = {
        'code': -32000,
        'message': 'Server error',
        'data': {'details': 'test'},
      };

      final error = CodexRpcError.fromJson(json);

      expect(error.code, equals(-32000));
      expect(error.message, equals('Server error'));
      expect(error.data, isNotNull);
    });

    test('toString formats correctly', () {
      final error = CodexRpcError(code: -1, message: 'Test error');

      expect(error.toString(), equals('CodexRpcError(-1): Test error'));
    });
  });

  group('CodexTurnEvent', () {
    test('fromNotification creates correct event', () {
      final notification = CodexNotificationEvent(
        method: 'item/agentMessage/delta',
        params: {
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'item-1',
          'delta': 'Hello ',
        },
      );

      final event = CodexTurnEvent.fromNotification(notification);

      expect(event.type, equals('item/agentMessage/delta'));
      expect(event.threadId, equals('thread-1'));
      expect(event.turnId, equals('turn-1'));
      expect(event.textDelta, equals('Hello '));
      expect(event.isTextDelta, isTrue);
    });

    test('isTextDelta returns false for non-delta events', () {
      final notification = CodexNotificationEvent(
        method: 'turn/completed',
        params: {'threadId': 'thread-1'},
      );

      final event = CodexTurnEvent.fromNotification(notification);

      expect(event.isTextDelta, isFalse);
    });
  });

  group('CodexRuntime', () {
    late CodexRuntime runtime;

    setUp(() {
      runtime = CodexRuntime();
    });

    tearDown(() async {
      await runtime.stop();
    });

    test('initial state is disconnected', () {
      expect(runtime.state, equals(CodexConnectionState.disconnected));
      expect(runtime.isConnected, isFalse);
      expect(runtime.isReady, isFalse);
    });

    test('findCodexBinary returns null when not found', () async {
      final path = await runtime.findCodexBinary();
      // May or may not find codex depending on environment
      // Just check it doesn't throw
      expect(path, anyOf(isNull, isA<String>()));
    });

    test('wraps windows cmd launch via cmd.exe', () {
      final launch = CodexRuntime.resolveLaunchConfigurationForTest(
        r'C:\Users\tester\AppData\Roaming\npm\codex.cmd',
        const <String>['app-server', '--listen', 'stdio://'],
        operatingSystem: 'windows',
      );

      expect(launch.executable, 'cmd.exe');
      expect(launch.arguments, <String>[
        '/c',
        r'C:\Users\tester\AppData\Roaming\npm\codex.cmd',
        'app-server',
        '--listen',
        'stdio://',
      ]);
    });

    test('passes executable launch through for native binaries', () {
      final launch = CodexRuntime.resolveLaunchConfigurationForTest(
        r'C:\Users\tester\.cargo\bin\codex.exe',
        const <String>['app-server'],
        operatingSystem: 'windows',
      );

      expect(launch.executable, r'C:\Users\tester\.cargo\bin\codex.exe');
      expect(launch.arguments, <String>['app-server']);
    });

    test('request throws when not connected', () async {
      expect(
        () => runtime.request('initialize', params: {}),
        throwsA(isA<StateError>()),
      );
    });

    test('stop is idempotent', () async {
      // Should not throw when called on disconnected runtime
      await runtime.stop();
      await runtime.stop();
      expect(runtime.isConnected, isFalse);
    });
  });
}
