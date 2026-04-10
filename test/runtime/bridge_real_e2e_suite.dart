@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/desktop_thread_artifact_service.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  final config = _BridgeRealTestConfig.load();
  final skipReason = config.skipReason;
  final bridgeClient = config.bridgeClient;
  final artifactService = DesktopThreadArtifactService();

  group('xworkmate-bridge real E2E', () {
    test(
      'bridge contract keeps HTTP RPC reachable and advertises single-agent support',
      () async {
        final capabilities = await bridgeClient.loadCapabilities(
          forceRefresh: true,
        );

        expect(capabilities.singleAgent, isTrue);
        expect(capabilities.providers, isNotEmpty);
        expect(capabilities.raw, isNotEmpty);
      },
      skip: skipReason,
    );

    for (final scenario in _bridgeScenarios) {
      test(
        'scenario ${scenario.key} binds thread workdir, supports follow-up, and records artifacts',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'xworkmate-bridge-${scenario.key}-',
          );
          addTearDown(() async {
            if (await root.exists()) {
              await root.delete(recursive: true);
            }
          });

          final threadId = 'thread-${scenario.key}';
          final threadWorkspace = await Directory(
            '${root.path}/threads/$threadId',
          ).create(recursive: true);
          final firstRequest = _makeRequest(
            scenario: scenario,
            threadId: threadId,
            sessionId: 'session-$threadId',
            workingDirectory: threadWorkspace.path,
            prompt: scenario.prompt,
            resumeSession: false,
          );

          final firstResponse = await bridgeClient.request(
            method: 'session.start',
            params: firstRequest.toExternalAcpParams(),
          );
          final firstResult = goTaskServiceResultFromAcpResponse(
            firstResponse,
            route: firstRequest.route,
          );

          expect(firstResult.turnId, isNotEmpty);
          expect(firstResult.message, isNotEmpty);
          expect(
            firstResult.resolvedWorkingDirectory.isNotEmpty
                ? firstResult.resolvedWorkingDirectory
                : threadWorkspace.path,
            contains(threadId),
          );

          final resumeRequest = _makeRequest(
            scenario: scenario,
            threadId: threadId,
            sessionId: 'session-$threadId',
            workingDirectory: firstResult.resolvedWorkingDirectory.isNotEmpty
                ? firstResult.resolvedWorkingDirectory
                : threadWorkspace.path,
            prompt: scenario.followUpPrompt,
            resumeSession: true,
          );
          final resumeResponse = await bridgeClient.request(
            method: 'session.message',
            params: resumeRequest.toExternalAcpParams(),
          );
          final resumeResult = goTaskServiceResultFromAcpResponse(
            resumeResponse,
            route: resumeRequest.route,
          );

          expect(resumeResult.turnId, isNotEmpty);
          expect(resumeResult.message, isNotEmpty);
          expect(
            resumeResult.resolvedWorkingDirectory.isNotEmpty
                ? resumeResult.resolvedWorkingDirectory
                : threadWorkspace.path,
            contains(threadId),
          );

          final snapshot = await artifactService.loadSnapshot(
            workspacePath: resumeResult.resolvedWorkingDirectory.isNotEmpty
                ? resumeResult.resolvedWorkingDirectory
                : threadWorkspace.path,
            workspaceKind:
                resumeResult.resolvedWorkspaceRefKind ??
                WorkspaceRefKind.localPath,
          );

          expect(
            snapshot.workspacePath,
            isNotEmpty,
            reason: 'workspace path should be recorded for ${scenario.key}',
          );
          expect(
            snapshot.resultMessage.isNotEmpty ||
                snapshot.fileEntries.isNotEmpty ||
                snapshot.resultEntries.isNotEmpty ||
                snapshot.changes.isNotEmpty,
            isTrue,
            reason:
                'the thread workspace should contain recorded output or a tracked change for ${scenario.key}',
          );
          expect(
            Directory(
              resumeResult.resolvedWorkingDirectory.isNotEmpty
                  ? resumeResult.resolvedWorkingDirectory
                  : threadWorkspace.path,
            ).existsSync(),
            isTrue,
          );
        },
        skip: skipReason,
      );
    }
  });
}

class _BridgeScenario {
  const _BridgeScenario({
    required this.key,
    required this.prompt,
    required this.followUpPrompt,
  });

  final String key;
  final String prompt;
  final String followUpPrompt;
}

const List<_BridgeScenario> _bridgeScenarios = <_BridgeScenario>[
  _BridgeScenario(
    key: 'pptx',
    prompt:
        'Create a pptx deck for a quarterly update and save the result in the current thread workspace.',
    followUpPrompt:
        'Please revise the deck with a stronger title slide and keep the same thread workspace.',
  ),
  _BridgeScenario(
    key: 'docx',
    prompt: 'Generate a weekly report docx in the current thread workspace.',
    followUpPrompt:
        'Please add a short executive summary and keep using the same thread workspace.',
  ),
  _BridgeScenario(
    key: 'xlsx',
    prompt:
        'Create an xlsx table with formulas in the current thread workspace.',
    followUpPrompt:
        'Please add one more formula row and keep using the same thread workspace.',
  ),
  _BridgeScenario(
    key: 'pdf',
    prompt:
        'Merge or convert a pdf output file in the current thread workspace.',
    followUpPrompt:
        'Please refine the pdf result and keep the same thread workspace.',
  ),
  _BridgeScenario(
    key: 'image-resizer',
    prompt:
        'Resize the attached or generated image and write the result back to the current thread.',
    followUpPrompt:
        'Please make one more resize adjustment and keep the same thread workspace.',
  ),
  _BridgeScenario(
    key: 'browser',
    prompt:
        'Search online, browse the page, and return a short summary with screenshot and logs to the current thread.',
    followUpPrompt:
        'Please continue the browser task with one more source and keep the same thread workspace.',
  ),
];

GoTaskServiceRequest _makeRequest({
  required _BridgeScenario scenario,
  required String sessionId,
  required String threadId,
  required String workingDirectory,
  required String prompt,
  required bool resumeSession,
}) {
  final routing = ExternalCodeAgentAcpRoutingConfig.auto(
    preferredGatewayTarget: 'local',
  );
  return GoTaskServiceRequest(
    sessionId: sessionId,
    threadId: threadId,
    target: AssistantExecutionTarget.singleAgent,
    prompt: prompt,
    workingDirectory: workingDirectory,
    model: '',
    thinking: 'low',
    selectedSkills: <String>[scenario.key],
    inlineAttachments: const <GatewayChatAttachmentPayload>[],
    localAttachments: const <CollaborationAttachment>[],
    aiGatewayBaseUrl: '',
    aiGatewayApiKey: '',
    agentId: '',
    metadata: <String, dynamic>{
      'scenario': scenario.key,
      'testType': 'real-bridge-e2e',
    },
    routing: routing,
    routingHint: scenario.key,
    provider: SingleAgentProvider.auto,
    resumeSession: resumeSession,
  );
}

class _BridgeRealTestConfig {
  const _BridgeRealTestConfig({
    required this.skipReason,
    required this.bridgeClient,
  });

  final String? skipReason;
  final GatewayAcpClient bridgeClient;

  static _BridgeRealTestConfig load() {
    final env = <String, String>{..._loadEnvFile(), ...Platform.environment};
    final rawUrl =
        env['BRIDGE_SERVER_URL'] ??
        env['BRIDGE_URL'] ??
        env['ACP_SERVER_URL'] ??
        '';
    final token =
        env['BRIDGE_AUTH_TOKEN'] ??
        env['ACP_AUTH_TOKEN'] ??
        env['INTERNAL_SERVICE_TOKEN'] ??
        '';
    if (rawUrl.trim().isEmpty || token.trim().isEmpty) {
      return _BridgeRealTestConfig(
        skipReason:
            'Set BRIDGE_SERVER_URL and BRIDGE_AUTH_TOKEN (or ACP_AUTH_TOKEN) to run real bridge E2E tests.',
        bridgeClient: GatewayAcpClient(endpointResolver: () => null),
      );
    }

    final endpoint = _normalizeEndpoint(rawUrl);
    final client = GatewayAcpClient(
      endpointResolver: () => endpoint,
      authorizationResolver: (_) async => 'Bearer ${token.trim()}',
    );
    return _BridgeRealTestConfig(skipReason: null, bridgeClient: client);
  }
}

Uri _normalizeEndpoint(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('https:') && !trimmed.startsWith('https://')) {
    return Uri.parse(trimmed.replaceFirst('https:', 'https://'));
  }
  if (trimmed.startsWith('http:') && !trimmed.startsWith('http://')) {
    return Uri.parse(trimmed.replaceFirst('http:', 'http://'));
  }
  final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  return Uri.parse(candidate);
}

Map<String, String> _loadEnvFile() {
  final env = <String, String>{};
  final candidates = <Directory>[
    Directory.current,
    ..._ancestorDirectories(Directory.current),
  ];
  for (final directory in candidates) {
    final file = File('${directory.path}/.env');
    if (!file.existsSync()) {
      continue;
    }
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      final separator = trimmed.contains('=')
          ? trimmed.indexOf('=')
          : trimmed.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final key = trimmed.substring(0, separator).trim();
      final value = trimmed.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        env[key] = value;
      }
    }
    if (env.isNotEmpty) {
      return env;
    }
  }
  return env;
}

List<Directory> _ancestorDirectories(Directory directory) {
  final result = <Directory>[];
  var current = directory.parent;
  while (true) {
    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    result.add(current);
    current = parent;
  }
  return result;
}
