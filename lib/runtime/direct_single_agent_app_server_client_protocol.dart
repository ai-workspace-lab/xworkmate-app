// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'runtime_models.dart';
import 'direct_single_agent_app_server_client_transport.dart';
import 'direct_single_agent_app_server_client_helpers.dart';
import 'direct_single_agent_app_server_client_core.dart';

class DirectSingleAgentCapabilities {
  const DirectSingleAgentCapabilities({
    required this.available,
    required this.supportedProviders,
    required this.endpoint,
    this.errorMessage,
  });

  const DirectSingleAgentCapabilities.unavailable({
    required this.endpoint,
    this.errorMessage,
  }) : available = false,
       supportedProviders = const <SingleAgentProvider>[];

  final bool available;
  final List<SingleAgentProvider> supportedProviders;
  final String endpoint;
  final String? errorMessage;

  bool get supportsCodex => supportsProvider(SingleAgentProvider.codex);

  bool supportsProvider(SingleAgentProvider provider) =>
      supportedProviders.contains(provider);
}

class DirectSingleAgentRunResult {
  const DirectSingleAgentRunResult({
    required this.success,
    required this.output,
    required this.errorMessage,
    this.aborted = false,
    this.resolvedModel = '',
    this.resolvedWorkingDirectory = '',
    this.resolvedWorkspaceRefKind = WorkspaceRefKind.localPath,
  });

  final bool success;
  final String output;
  final String errorMessage;
  final bool aborted;
  final String resolvedModel;
  final String resolvedWorkingDirectory;
  final WorkspaceRefKind resolvedWorkspaceRefKind;
}

class DirectSingleAgentRunRequest {
  const DirectSingleAgentRunRequest({
    required this.sessionId,
    required this.provider,
    required this.prompt,
    required this.model,
    required this.workingDirectory,
    required this.gatewayToken,
    this.selectedSkills = const <AssistantThreadSkillEntry>[],
    this.onOutput,
  });

  final String sessionId;
  final SingleAgentProvider provider;
  final String prompt;
  final String model;
  final String workingDirectory;
  final String gatewayToken;
  final List<AssistantThreadSkillEntry> selectedSkills;
  final void Function(String text)? onOutput;
}

enum DirectSingleAgentEndpointMode {
  wsLocal,
  wss,
  httpLocal,
  https,
  unsupported,
}

enum DirectSingleAgentTransportKindInternal {
  websocketAppServer,
  restSessionApi,
}

class DirectSingleAgentEndpointDescriptor {
  const DirectSingleAgentEndpointDescriptor({
    required this.mode,
    required this.baseUri,
    this.websocketUri,
  });

  final DirectSingleAgentEndpointMode mode;
  final Uri? baseUri;
  final Uri? websocketUri;

  bool get isSupported => mode != DirectSingleAgentEndpointMode.unsupported;

  bool get prefersWebSocket =>
      mode == DirectSingleAgentEndpointMode.wsLocal ||
      mode == DirectSingleAgentEndpointMode.wss;

  bool get allowsRest =>
      mode == DirectSingleAgentEndpointMode.httpLocal ||
      mode == DirectSingleAgentEndpointMode.https;

  static DirectSingleAgentEndpointDescriptor describe(Uri? endpoint) {
    if (endpoint == null) {
      return const DirectSingleAgentEndpointDescriptor(
        mode: DirectSingleAgentEndpointMode.unsupported,
        baseUri: null,
      );
    }
    final scheme = endpoint.scheme.toLowerCase();
    final normalizedBase = endpoint.replace(
      path: '',
      query: null,
      fragment: null,
    );
    final isLocal = isLocalHostInternal(endpoint.host);
    if (scheme == 'ws' && isLocal) {
      return DirectSingleAgentEndpointDescriptor(
        mode: DirectSingleAgentEndpointMode.wsLocal,
        baseUri: normalizedBase,
        websocketUri: normalizedBase,
      );
    }
    if (scheme == 'wss') {
      return DirectSingleAgentEndpointDescriptor(
        mode: DirectSingleAgentEndpointMode.wss,
        baseUri: normalizedBase,
        websocketUri: normalizedBase,
      );
    }
    if (scheme == 'http' && isLocal) {
      return DirectSingleAgentEndpointDescriptor(
        mode: DirectSingleAgentEndpointMode.httpLocal,
        baseUri: normalizedBase,
        websocketUri: normalizedBase.replace(scheme: 'ws'),
      );
    }
    if (scheme == 'https') {
      return DirectSingleAgentEndpointDescriptor(
        mode: DirectSingleAgentEndpointMode.https,
        baseUri: normalizedBase,
        websocketUri: normalizedBase.replace(scheme: 'wss'),
      );
    }
    return DirectSingleAgentEndpointDescriptor(
      mode: DirectSingleAgentEndpointMode.unsupported,
      baseUri: normalizedBase,
    );
  }
}
