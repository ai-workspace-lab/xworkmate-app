import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/multi_agent_broker.dart';
import 'package:xworkmate/runtime/multi_agent_orchestrator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MultiAgentBroker supports session start, message, cancel, and close', () async {
    final orchestrator = _FakeOrchestrator();
    final server = MultiAgentBrokerServer(orchestrator);
    await server.start();
    addTearDown(server.stop);

    final client = MultiAgentBrokerClient(server.wsUri!);
    final firstEvents = await client
        .startSession(
          sessionId: 'session-1',
          taskPrompt: 'first turn',
          workingDirectory: '/tmp',
          attachments: const <CollaborationAttachment>[],
          selectedSkills: const <String>['aris'],
          aiGatewayBaseUrl: '',
          aiGatewayApiKey: '',
        )
        .toList();
    final secondEvents = await client
        .sendSessionMessage(
          sessionId: 'session-1',
          taskPrompt: 'second turn',
          workingDirectory: '/tmp',
          attachments: const <CollaborationAttachment>[],
          selectedSkills: const <String>['aris'],
          aiGatewayBaseUrl: '',
          aiGatewayApiKey: '',
        )
        .toList();

    await client.cancelSession('session-1');
    await client.closeSession('session-1');

    expect(orchestrator.prompts, hasLength(2));
    expect(orchestrator.prompts.first, contains('first turn'));
    expect(orchestrator.prompts.last, contains('first turn'));
    expect(orchestrator.prompts.last, contains('second turn'));
    expect(firstEvents.last.type, 'result');
    expect(secondEvents.last.type, 'result');
    expect(orchestrator.abortCount, 1);
  });
}

class _FakeOrchestrator extends MultiAgentOrchestrator {
  _FakeOrchestrator()
    : super(config: MultiAgentConfig.defaults().copyWith(enabled: true));

  final List<String> prompts = <String>[];
  int abortCount = 0;

  @override
  Future<CollaborationResult> runCollaboration({
    required String taskPrompt,
    required String workingDirectory,
    List<CollaborationAttachment> attachments = const [],
    List<String> selectedSkills = const [],
    String aiGatewayBaseUrl = '',
    String aiGatewayApiKey = '',
    void Function(MultiAgentRunEvent event)? onEvent,
  }) async {
    prompts.add(taskPrompt);
    onEvent?.call(
      const MultiAgentRunEvent(
        type: 'step',
        title: 'Architect',
        message: 'planning',
        pending: false,
        error: false,
        role: 'architect',
      ),
    );
    return const CollaborationResult(
      success: true,
      steps: <CollaborationStep>[],
      finalCode: 'ok',
      finalScore: 9,
      duration: Duration(milliseconds: 10),
      iterations: 0,
    );
  }

  @override
  Future<void> abort() async {
    abortCount += 1;
  }
}
