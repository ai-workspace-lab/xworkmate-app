import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/desktop_thread_artifact_sync.dart';
import 'package:xworkmate/runtime/external_code_agent_acp_desktop_transport.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

const _providerEndpoints = <String, String>{
  'codex': 'https://acp-server.svc.plus/codex/acp/rpc',
  'opencode': 'https://acp-server.svc.plus/opencode/acp/rpc',
  'gemini': 'https://acp-server.svc.plus/gemini/acp/rpc',
};

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z0x8AAAAASUVORK5CYII=';

void main() {
  final runRealE2E =
      Platform.environment['RUN_REAL_BRIDGE_E2E'] == '1' ||
      Platform.environment['RUN_REAL_BRIDGE_E2E'] == 'true';
  final bridgeAuthToken =
      Platform.environment['BRIDGE_AUTH_TOKEN']?.trim() ?? '';
  final bridgeAcpEndpoint =
      Platform.environment['BRIDGE_ACP_ENDPOINT']?.trim() ?? '';
  final openclawGatewayToken =
      Platform.environment['OPENCLAW_GATEWAY_TOKEN']?.trim() ?? '';

  group('real bridge provider matrix', () {
    late ExternalCodeAgentAcpDesktopTransport transport;

    setUpAll(() async {
      if (!runRealE2E || bridgeAuthToken.isEmpty || bridgeAcpEndpoint.isEmpty) {
        return;
      }
      final client = GatewayAcpClient(
        endpointResolver: () => Uri.parse(bridgeAcpEndpoint),
        authorizationResolver: (_) async => 'Bearer $bridgeAuthToken',
      );
      transport = ExternalCodeAgentAcpDesktopTransport(
        client: client,
        endpointResolver: (_) => Uri.parse(bridgeAcpEndpoint),
      );
      await transport.syncExternalProviders(
        _providerEndpoints.entries
            .map(
              (entry) => ExternalCodeAgentAcpSyncedProvider(
                providerId: entry.key,
                label: entry.key,
                endpoint: entry.value,
                authorizationHeader: 'Bearer $bridgeAuthToken',
                enabled: true,
              ),
            )
            .toList(growable: false),
      );
    });

    tearDownAll(() async {
      if (runRealE2E &&
          bridgeAuthToken.isNotEmpty &&
          bridgeAcpEndpoint.isNotEmpty) {
        await transport.dispose();
      }
    });

    test('loads external ACP capabilities and provider catalog', () async {
      if (!runRealE2E || bridgeAuthToken.isEmpty || bridgeAcpEndpoint.isEmpty) {
        return;
      }
      final capabilities = await transport.loadExternalAcpCapabilities(
        target: AssistantExecutionTarget.singleAgent,
      );
      expect(capabilities.singleAgent, isTrue);
      expect(
        capabilities.providerCatalog.map((item) => item.providerId),
        containsAll(<String>['codex', 'opencode', 'gemini']),
      );
    });

    for (final providerId in _providerEndpoints.keys) {
      test('$providerId supports a two-turn conversation', () async {
        if (!runRealE2E ||
            bridgeAuthToken.isEmpty ||
            bridgeAcpEndpoint.isEmpty) {
          return;
        }
        final workdir = await Directory.systemTemp.createTemp(
          'xworkmate-$providerId-conversation-',
        );
        addTearDown(() async {
          if (await workdir.exists()) {
            await workdir.delete(recursive: true);
          }
        });

        final startResult = await transport.executeTask(
          _buildRequest(
            providerId: providerId,
            sessionId: 'conversation-$providerId',
            threadId: 'conversation-$providerId',
            workingDirectory: workdir.path,
            prompt: 'Reply with exactly pong.',
          ),
          onUpdate: (_) {},
        );
        expect(startResult.success, isTrue);
        expect(startResult.resolvedProviderId, providerId);

        final messageResult = await transport.executeTask(
          _buildRequest(
            providerId: providerId,
            sessionId: 'conversation-$providerId',
            threadId: 'conversation-$providerId',
            workingDirectory: workdir.path,
            prompt: 'Reply with exactly round2.',
            resumeSession: true,
          ),
          onUpdate: (_) {},
        );
        expect(messageResult.success, isTrue);
        expect(messageResult.resolvedProviderId, providerId);
        expect(
          messageResult.message.toLowerCase(),
          contains('round2'),
          reason: 'follow-up should stay on the same provider/thread',
        );
      });
    }

    for (final providerId in <String>['codex', 'opencode']) {
      for (final scenario in _artifactScenarios) {
        test(
          '$providerId can return ${scenario.skill} artifacts to local workspace',
          () async {
            if (!runRealE2E || bridgeAuthToken.isEmpty) {
              return;
            }
            final workdir = await Directory.systemTemp.createTemp(
              'xworkmate-$providerId-${scenario.skill}-',
            );
            addTearDown(() async {
              if (await workdir.exists()) {
                await workdir.delete(recursive: true);
              }
            });
            await scenario.prepare?.call(workdir);

            final result = await transport.executeTask(
              _buildRequest(
                providerId: providerId,
                sessionId: '$providerId-${scenario.skill}',
                threadId: '$providerId-${scenario.skill}',
                workingDirectory: workdir.path,
                prompt: scenario.prompt,
                selectedSkills: <String>[scenario.skill],
              ),
              onUpdate: (_) {},
            );

            expect(result.success, isTrue, reason: result.errorMessage);
            expect(result.resolvedProviderId, providerId);
            expect(result.remoteWorkingDirectory.trim(), isNotEmpty);
            expect(result.remoteWorkspaceRefKind, WorkspaceRefKind.remotePath);
            expect(result.resultSummary.trim(), isNotEmpty);
            expect(result.artifacts, isNotEmpty);

            final syncResult = await syncInlineArtifactsToLocalWorkspace(
              root: workdir,
              artifacts: result.artifacts,
            );
            expect(syncResult.wroteArtifact, isTrue);
            expect(
              syncResult.writtenFiles.any(
                (path) => path.endsWith(scenario.expectedSuffix),
              ),
              isTrue,
            );
          },
          timeout: const Timeout(Duration(minutes: 4)),
        );
      }
    }

    for (final scenario in _artifactScenarios) {
      test(
        'gemini reports either success or a provider limitation for ${scenario.skill}',
        () async {
          if (!runRealE2E || bridgeAuthToken.isEmpty) {
            return;
          }
          final workdir = await Directory.systemTemp.createTemp(
            'xworkmate-gemini-${scenario.skill}-',
          );
          addTearDown(() async {
            if (await workdir.exists()) {
              await workdir.delete(recursive: true);
            }
          });
          await scenario.prepare?.call(workdir);

          final result = await transport.executeTask(
            _buildRequest(
              providerId: 'gemini',
              sessionId: 'gemini-${scenario.skill}',
              threadId: 'gemini-${scenario.skill}',
              workingDirectory: workdir.path,
              prompt: scenario.prompt,
              selectedSkills: <String>[scenario.skill],
            ),
            onUpdate: (_) {},
          );

          expect(result.resolvedProviderId, 'gemini');
          if (result.success) {
            final syncResult = await syncInlineArtifactsToLocalWorkspace(
              root: workdir,
              artifacts: result.artifacts,
            );
            expect(syncResult.wroteArtifact, isTrue);
          } else {
            expect(
              result.errorMessage.trim().isNotEmpty ||
                  result.message.trim().isNotEmpty,
              isTrue,
              reason:
                  'provider limitation should still surface a clear summary',
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 4)),
      );
    }
  });

  group('bridge-owned deployment examples', () {
    test('default gateway profile starts unconfigured', () {
      final profile = GatewayConnectionProfile.defaults();
      expect(profile.host, isEmpty);
      expect(profile.port, 443);
      expect(profile.tls, isTrue);
      expect(profile.mode, RuntimeConnectionMode.unconfigured);
    });

    test('wss endpoint is reachable', () async {
      if (!runRealE2E) {
        return;
      }
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.getUrl(
        Uri.parse('https://openclaw.svc.plus'),
      );
      final response = await request.close();
      expect(response.statusCode, anyOf(200, 400, 401, 403, 404, 426));
    });

    test(
      'gateway token is wired for future remote runtime coverage',
      () {
        if (!runRealE2E) {
          return;
        }
        expect(
          openclawGatewayToken.isNotEmpty,
          isTrue,
          reason:
              'Set OPENCLAW_GATEWAY_TOKEN to run remote gateway-chat coverage against openclaw.svc.plus.',
        );
      },
      skip: !runRealE2E || openclawGatewayToken.isNotEmpty,
    );
  });
}

class _ArtifactScenario {
  const _ArtifactScenario({
    required this.skill,
    required this.prompt,
    required this.expectedSuffix,
    this.prepare,
  });

  final String skill;
  final String prompt;
  final String expectedSuffix;
  final Future<void> Function(Directory root)? prepare;
}

final _artifactScenarios = <_ArtifactScenario>[
  const _ArtifactScenario(
    skill: 'docx',
    prompt:
        'Use the docx skill to create report.docx in the working directory. Include a title and a 2-column table with two rows.',
    expectedSuffix: '/report.docx',
  ),
  const _ArtifactScenario(
    skill: 'pptx',
    prompt:
        'Use the pptx skill to create deck.pptx in the working directory with two slides titled Intro and Summary.',
    expectedSuffix: '/deck.pptx',
  ),
  const _ArtifactScenario(
    skill: 'xlsx',
    prompt:
        'Use the xlsx skill to create sales.xlsx in the working directory with a totals formula column.',
    expectedSuffix: '/sales.xlsx',
  ),
  const _ArtifactScenario(
    skill: 'pdf',
    prompt:
        'Use the pdf skill to create summary.pdf in the working directory with a one-page summary of bridge validation.',
    expectedSuffix: '/summary.pdf',
  ),
  _ArtifactScenario(
    skill: 'image-resizer',
    prompt:
        'Use the image-resizer skill to resize input.png to 1200x800 and save the output as resized.png in the working directory.',
    expectedSuffix: '/resized.png',
    prepare: (root) async {
      final bytes = base64Decode(_tinyPngBase64);
      await File('${root.path}/input.png').writeAsBytes(bytes, flush: true);
    },
  ),
];

GoTaskServiceRequest _buildRequest({
  required String providerId,
  required String sessionId,
  required String threadId,
  required String workingDirectory,
  required String prompt,
  List<String> selectedSkills = const <String>[],
  bool resumeSession = false,
}) {
  return GoTaskServiceRequest(
    sessionId: sessionId,
    threadId: threadId,
    target: AssistantExecutionTarget.singleAgent,
    prompt: prompt,
    workingDirectory: workingDirectory,
    model: '',
    thinking: '',
    selectedSkills: selectedSkills,
    inlineAttachments: const <GatewayChatAttachmentPayload>[],
    localAttachments: const <CollaborationAttachment>[],
    agentId: '',
    metadata: const <String, dynamic>{},
    routing: ExternalCodeAgentAcpRoutingConfig(
      mode: ExternalCodeAgentAcpRoutingMode.explicit,
      preferredGatewayTarget: 'gateway',
      explicitExecutionTarget: 'singleAgent',
      explicitProviderId: providerId,
      explicitModel: '',
      explicitSkills: selectedSkills,
      allowSkillInstall: false,
      availableSkills: const <ExternalCodeAgentAcpAvailableSkill>[],
    ),
    provider: SingleAgentProviderCopy.fromJsonValue(providerId),
    remoteWorkingDirectoryHint: '',
    resumeSession: resumeSession,
  );
}
