import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/aris_bridge.dart';
import 'package:xworkmate/runtime/aris_llm_chat_client.dart';

void main() {
  test(
    'ArisLlmChatClient returns chat content from bridge tool result',
    () async {
      final client = ArisLlmChatClient(
        bridgeLocator: _fixedLocator(),
        processStarter: (_, args, {environment, workingDirectory}) async =>
            _FakeProcess.withStdoutLines(<String>[
              jsonEncode(<String, dynamic>{
                'jsonrpc': '2.0',
                'id': 1,
                'result': <String, dynamic>{'protocolVersion': '2024-11-05'},
              }),
              jsonEncode(<String, dynamic>{
                'jsonrpc': '2.0',
                'id': 2,
                'result': <String, dynamic>{
                  'content': <Map<String, dynamic>>[
                    <String, dynamic>{'type': 'text', 'text': 'review ok'},
                  ],
                },
              }),
            ]),
      );

      final result = await client.chat(
        endpoint: 'http://127.0.0.1:11434/v1',
        apiKey: 'ollama',
        model: 'qwen2.5-coder:latest',
        prompt: 'hello',
      );

      expect(result, 'review ok');
    },
  );

  test('ArisLlmChatClient surfaces invalid bridge JSON', () async {
    final client = ArisLlmChatClient(
      bridgeLocator: _fixedLocator(),
      processStarter: (_, args, {environment, workingDirectory}) async =>
          _FakeProcess.withStdoutLines(<String>['not-json']),
    );

    await expectLater(
      () => client.chat(
        endpoint: 'http://127.0.0.1:11434/v1',
        apiKey: 'ollama',
        model: 'qwen2.5-coder:latest',
        prompt: 'hello',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('invalid JSON'),
        ),
      ),
    );
  });

  test('ArisLlmChatClient surfaces bridge process exit stderr', () async {
    final client = ArisLlmChatClient(
      bridgeLocator: _fixedLocator(),
      processStarter: (_, args, {environment, workingDirectory}) async =>
          _FakeProcess(
            stdoutLines: const <String>[],
            stderrText: 'bridge failed',
            exitCode: 2,
          ),
    );

    await expectLater(
      () => client.claudeReview(prompt: 'review this'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('bridge failed'),
        ),
      ),
    );
  });

  test('ArisLlmChatClient times out when bridge never responds', () async {
    final client = ArisLlmChatClient(
      bridgeLocator: _fixedLocator(),
      rpcTimeout: const Duration(milliseconds: 10),
      processStarter: (_, args, {environment, workingDirectory}) async =>
          _FakeHangingProcess(),
    );

    await expectLater(
      () => client.chat(
        endpoint: 'http://127.0.0.1:11434/v1',
        apiKey: 'ollama',
        model: 'qwen2.5-coder:latest',
        prompt: 'hello',
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}

ArisBridgeLocator _fixedLocator() {
  return ArisBridgeLocator(
    binaryExistsResolver: (_) async => true,
    workspaceRoot: Directory.systemTemp.path,
    resolvedExecutableResolver: () =>
        '${Directory.systemTemp.path}/XWorkmate.app/Contents/MacOS/XWorkmate',
  );
}

class _FakeProcess implements Process {
  _FakeProcess({
    required List<String> stdoutLines,
    String stderrText = '',
    int exitCode = 0,
  }) : _stdout = Stream<List<int>>.fromIterable(
         stdoutLines.map((line) => utf8.encode('$line\n')),
       ),
       _stderr = Stream<List<int>>.value(utf8.encode(stderrText)),
       _exitCode = Future<int>.value(exitCode),
       _stdin = File(
         '${Directory.systemTemp.path}/aris-llm-chat-test-${DateTime.now().microsecondsSinceEpoch}.txt',
       ).openWrite();

  factory _FakeProcess.withStdoutLines(List<String> stdoutLines) {
    return _FakeProcess(stdoutLines: stdoutLines);
  }

  final Stream<List<int>> _stdout;
  final Stream<List<int>> _stderr;
  final Future<int> _exitCode;
  final IOSink _stdin;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  int get pid => 1;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stderr => _stderr;

  @override
  Stream<List<int>> get stdout => _stdout;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

class _FakeHangingProcess implements Process {
  _FakeHangingProcess()
    : _stdin = File(
        '${Directory.systemTemp.path}/aris-llm-chat-hanging-${DateTime.now().microsecondsSinceEpoch}.txt',
      ).openWrite();

  final IOSink _stdin;
  final Completer<int> _exitCode = Completer<int>();

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 2;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(0);
    }
    return true;
  }
}
