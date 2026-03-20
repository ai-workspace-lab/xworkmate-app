import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'multi_agent_orchestrator.dart';
import 'runtime_models.dart';

class AgentCliBridgeRequest {
  const AgentCliBridgeRequest({
    required this.sessionId,
    required this.taskPrompt,
    required this.workingDirectory,
    required this.attachments,
    required this.selectedSkills,
    required this.aiGatewayBaseUrl,
    required this.aiGatewayApiKey,
  });

  final String sessionId;
  final String taskPrompt;
  final String workingDirectory;
  final List<CollaborationAttachment> attachments;
  final List<String> selectedSkills;
  final String aiGatewayBaseUrl;
  final String aiGatewayApiKey;
}

class AgentCliBridgeResult {
  const AgentCliBridgeResult({
    required this.output,
    required this.success,
    required this.errorMessage,
    this.events = const <MultiAgentRunEvent>[],
  });

  final String output;
  final bool success;
  final String errorMessage;
  final List<MultiAgentRunEvent> events;
}

abstract class AgentCliBridge {
  Future<AgentCliBridgeResult> run(AgentCliBridgeRequest request);
}

class SubprocessCliBridge implements AgentCliBridge {
  const SubprocessCliBridge({
    required this.command,
    this.defaultArgs = const <String>[],
  });

  final String command;
  final List<String> defaultArgs;

  @override
  Future<AgentCliBridgeResult> run(AgentCliBridgeRequest request) async {
    try {
      final process = await Process.start(
        command,
        <String>[...defaultArgs, request.taskPrompt],
        workingDirectory: request.workingDirectory.trim().isEmpty
            ? null
            : request.workingDirectory,
      );
      await process.stdin.close();
      final stdout = await process.stdout.transform(utf8.decoder).join();
      final stderr = await process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode;
      return AgentCliBridgeResult(
        output: stdout.trim(),
        success: exitCode == 0,
        errorMessage: stderr.trim(),
      );
    } catch (error) {
      return AgentCliBridgeResult(
        output: '',
        success: false,
        errorMessage: error.toString(),
      );
    }
  }
}

class JsonRpcCliBridge implements AgentCliBridge {
  const JsonRpcCliBridge(this.endpoint);

  final Uri endpoint;

  @override
  Future<AgentCliBridgeResult> run(AgentCliBridgeRequest request) async {
    final socket = await WebSocket.connect(endpoint.toString());
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    final completer = Completer<AgentCliBridgeResult>();
    final events = <MultiAgentRunEvent>[];

    socket.listen(
      (raw) {
        final json = jsonDecode(raw as String) as Map<String, dynamic>;
        final method = json['method'] as String?;
        if (method == 'multi_agent.event') {
          final params =
              (json['params'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          events.add(MultiAgentRunEvent.fromJson(params));
          return;
        }
        if (json['id']?.toString() == requestId && json['result'] is Map) {
          final result = (json['result'] as Map).cast<String, dynamic>();
          if (!completer.isCompleted) {
            completer.complete(
              AgentCliBridgeResult(
                output: result['summary']?.toString() ?? '',
                success: result['success'] == true,
                errorMessage: result['error']?.toString() ?? '',
                events: events,
              ),
            );
          }
          unawaited(socket.close());
          return;
        }
        if (json['error'] is Map && !completer.isCompleted) {
          final error = (json['error'] as Map).cast<String, dynamic>();
          completer.complete(
            AgentCliBridgeResult(
              output: '',
              success: false,
              errorMessage: error['message']?.toString() ?? 'JSON-RPC error',
              events: events,
            ),
          );
          unawaited(socket.close());
        }
      },
      onError: (error, _) {
        if (!completer.isCompleted) {
          completer.complete(
            AgentCliBridgeResult(
              output: '',
              success: false,
              errorMessage: error.toString(),
              events: events,
            ),
          );
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(
            AgentCliBridgeResult(
              output: '',
              success: false,
              errorMessage: 'JSON-RPC bridge closed before completion',
              events: events,
            ),
          );
        }
      },
      cancelOnError: true,
    );

    socket.add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': requestId,
        'method': 'session.start',
        'params': <String, dynamic>{
          'sessionId': request.sessionId,
          'taskPrompt': request.taskPrompt,
          'workingDirectory': request.workingDirectory,
          'attachments': request.attachments
              .map(
                (item) => <String, dynamic>{
                  'name': item.name,
                  'description': item.description,
                  'path': item.path,
                },
              )
              .toList(growable: false),
          'selectedSkills': request.selectedSkills,
          'aiGatewayBaseUrl': request.aiGatewayBaseUrl,
          'aiGatewayApiKey': request.aiGatewayApiKey,
        },
      }),
    );

    return completer.future;
  }
}
