import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app/app_store_policy.dart';
import 'go_core.dart';

typedef ArisProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      String? workingDirectory,
    });

class ArisLlmChatClient {
  ArisLlmChatClient({
    ArisProcessStarter? processStarter,
    GoCoreLocator? bridgeLocator,
    Duration rpcTimeout = const Duration(minutes: 2),
  }) : _processStarter =
           processStarter ??
           ((executable, arguments, {environment, workingDirectory}) {
             return Process.start(
               executable,
               arguments,
               environment: environment,
               workingDirectory: workingDirectory,
             );
           }),
       _bridgeLocator = bridgeLocator ?? GoCoreLocator(),
       _rpcTimeout = rpcTimeout;

  final ArisProcessStarter _processStarter;
  final GoCoreLocator _bridgeLocator;
  final Duration _rpcTimeout;

  Future<String> chat({
    required String endpoint,
    required String apiKey,
    required String model,
    required String prompt,
    String systemPrompt = '',
  }) {
    return _callTool(
      toolName: 'chat',
      environment: <String, String>{
        ...Platform.environment,
        'LLM_API_KEY': apiKey,
        'LLM_BASE_URL': endpoint,
        'LLM_MODEL': model,
        'LLM_SERVER_NAME': 'xworkmate-aris-llm-chat',
      },
      arguments: <String, dynamic>{
        'prompt': prompt,
        'model': model,
        if (systemPrompt.trim().isNotEmpty) 'system': systemPrompt.trim(),
      },
    );
  }

  Future<String> claudeReview({
    required String prompt,
    String model = '',
    String systemPrompt = '',
    String tools = '',
  }) {
    return _callTool(
      toolName: 'claude_review',
      environment: <String, String>{
        ...Platform.environment,
        if (model.trim().isNotEmpty) 'CLAUDE_REVIEW_MODEL': model.trim(),
        if (systemPrompt.trim().isNotEmpty)
          'CLAUDE_REVIEW_SYSTEM': systemPrompt.trim(),
        if (tools.trim().isNotEmpty) 'CLAUDE_REVIEW_TOOLS': tools.trim(),
      },
      arguments: <String, dynamic>{
        'prompt': prompt,
        if (model.trim().isNotEmpty) 'model': model.trim(),
        if (systemPrompt.trim().isNotEmpty) 'system': systemPrompt.trim(),
        if (tools.trim().isNotEmpty) 'tools': tools.trim(),
      },
    );
  }

  Future<String> _callTool({
    required String toolName,
    required Map<String, String> environment,
    required Map<String, dynamic> arguments,
  }) async {
    if (blocksAppStoreEmbeddedAgentProcesses(
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    )) {
      throw UnsupportedError(
        'App Store builds do not allow launching the bundled Go core process.',
      );
    }
    final launch = await _bridgeLocator.locate();
    if (launch == null) {
      throw StateError('Go core is unavailable.');
    }

    final process = await _processStarter(
      launch.executable,
      launch.arguments,
      environment: environment,
      workingDirectory: launch.workingDirectory,
    );

    final responseCompleter = Completer<String>();
    final errorBuffer = StringBuffer();
    late final StreamSubscription<String> stdoutSubscription;
    late final StreamSubscription<String> stderrSubscription;
    late final StreamSubscription<int> exitSubscription;

    stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.trim().isEmpty) {
            return;
          }
          late final Map<String, dynamic> message;
          try {
            message = jsonDecode(line) as Map<String, dynamic>;
          } catch (error) {
            if (!responseCompleter.isCompleted) {
              responseCompleter.completeError(
                StateError('Go core returned invalid JSON: $error'),
              );
            }
            return;
          }
          if (message['id'] == 2) {
            final result =
                (message['result'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            final content =
                (result['content'] as List?)
                    ?.whereType<Map>()
                    .map((item) => item['text']?.toString() ?? '')
                    .join('\n')
                    .trim() ??
                '';
            if (!responseCompleter.isCompleted) {
              responseCompleter.complete(content);
            }
          } else if (message['error'] is Map &&
              !responseCompleter.isCompleted) {
            final error = (message['error'] as Map).cast<String, dynamic>();
            responseCompleter.completeError(
              StateError(error['message']?.toString() ?? 'Go core error'),
            );
          }
        });

    stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(errorBuffer.write);
    exitSubscription = process.exitCode.asStream().listen((exitCode) {
      scheduleMicrotask(() {
        if (responseCompleter.isCompleted) {
          return;
        }
        final stderrText = errorBuffer.toString().trim();
        if (exitCode != 0) {
          responseCompleter.completeError(
            StateError(
              stderrText.isNotEmpty
                  ? stderrText
                  : 'Go core exited with code $exitCode',
            ),
          );
          return;
        }
        responseCompleter.completeError(
          StateError(
            stderrText.isNotEmpty
                ? stderrText
                : 'Go core closed without returning a tool result.',
          ),
        );
      });
    });

    void send(Object payload) {
      process.stdin.writeln(jsonEncode(payload));
    }

    send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': <String, dynamic>{},
    });
    send(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
      'params': <String, dynamic>{},
    });
    send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/call',
      'params': <String, dynamic>{'name': toolName, 'arguments': arguments},
    });

    try {
      return await responseCompleter.future.timeout(
        _rpcTimeout,
        onTimeout: () => throw TimeoutException(
          'Go core timed out after ${_rpcTimeout.inSeconds}s',
          _rpcTimeout,
        ),
      );
    } finally {
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      await exitSubscription.cancel();
      try {
        process.kill();
      } catch (_) {
        // Best effort only.
      }
      await process.stdin.close();
      final stderrText = errorBuffer.toString().trim();
      if (stderrText.isNotEmpty && !responseCompleter.isCompleted) {
        throw StateError(stderrText);
      }
    }
  }
}
