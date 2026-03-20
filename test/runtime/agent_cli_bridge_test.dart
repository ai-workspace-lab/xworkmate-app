import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/agent_cli_bridge.dart';
import 'package:xworkmate/runtime/multi_agent_broker.dart';
import 'package:xworkmate/runtime/multi_agent_orchestrator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JsonRpcCliBridge can drive a broker-backed external session', () async {
    final server = MultiAgentBrokerServer(_BridgeFakeOrchestrator());
    await server.start();
    addTearDown(server.stop);

    final bridge = JsonRpcCliBridge(server.wsUri!);
    final result = await bridge.run(
      const AgentCliBridgeRequest(
        sessionId: 'bridge-session',
        taskPrompt: 'hello bridge',
        workingDirectory: '/tmp',
        attachments: <CollaborationAttachment>[],
        selectedSkills: <String>['aris'],
        aiGatewayBaseUrl: '',
        aiGatewayApiKey: '',
      ),
    );

    expect(result.success, isTrue);
    expect(result.events, isNotEmpty);
  });
}

class _BridgeFakeOrchestrator extends MultiAgentOrchestrator {
  _BridgeFakeOrchestrator()
    : super(config: MultiAgentConfig.defaults().copyWith(enabled: true));

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
    onEvent?.call(
      const MultiAgentRunEvent(
        type: 'step',
        title: 'Engineer',
        message: 'running',
        pending: false,
        error: false,
        role: 'engineer',
      ),
    );
    return const CollaborationResult(
      success: true,
      steps: <CollaborationStep>[],
      finalCode: 'ok',
      finalScore: 7,
      duration: Duration(milliseconds: 10),
      iterations: 0,
    );
  }
}
