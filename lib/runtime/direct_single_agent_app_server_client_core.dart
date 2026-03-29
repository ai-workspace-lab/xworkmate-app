// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'runtime_models.dart';
import 'direct_single_agent_app_server_client_protocol.dart';
import 'direct_single_agent_app_server_client_transport.dart';
import 'direct_single_agent_app_server_client_helpers.dart';

class DirectSingleAgentAppServerClient {
  DirectSingleAgentAppServerClient({required this.endpointResolver});

  final Uri? Function(SingleAgentProvider provider) endpointResolver;
  final DirectSingleAgentWebSocketTransportInternal webSocketTransportInternal =
      DirectSingleAgentWebSocketTransportInternal();
  final DirectSingleAgentRestTransportInternal restTransportInternal =
      DirectSingleAgentRestTransportInternal();

  final Map<SingleAgentProvider, DirectSingleAgentCapabilities>
  cachedCapabilitiesInternal =
      <SingleAgentProvider, DirectSingleAgentCapabilities>{};
  final Map<SingleAgentProvider, DateTime> capabilitiesRefreshedAtInternal =
      <SingleAgentProvider, DateTime>{};
  final Map<SingleAgentProvider, DirectSingleAgentTransportKindInternal>
  transportKindsInternal =
      <SingleAgentProvider, DirectSingleAgentTransportKindInternal>{};

  Future<DirectSingleAgentCapabilities> loadCapabilities({
    required SingleAgentProvider provider,
    bool forceRefresh = false,
    String gatewayToken = '',
  }) async {
    final cached = cachedCapabilitiesInternal[provider];
    final refreshedAt = capabilitiesRefreshedAtInternal[provider];
    if (!forceRefresh &&
        cached != null &&
        refreshedAt != null &&
        DateTime.now().difference(refreshedAt) < const Duration(seconds: 15)) {
      return cached;
    }

    final descriptor = describeEndpointInternal(provider);
    if (!descriptor.isSupported || descriptor.baseUri == null) {
      final unavailable = const DirectSingleAgentCapabilities.unavailable(
        endpoint: '',
        errorMessage: 'Single-agent app-server endpoint is not configured.',
      );
      cachedCapabilitiesInternal[provider] = unavailable;
      capabilitiesRefreshedAtInternal[provider] = DateTime.now();
      return unavailable;
    }

    try {
      final transport = await resolveTransportInternal(
        provider,
        descriptor: descriptor,
        gatewayToken: gatewayToken,
      );
      transportKindsInternal[provider] = transport.kind;
      cachedCapabilitiesInternal[provider] = DirectSingleAgentCapabilities(
        available: true,
        supportedProviders: <SingleAgentProvider>[provider],
        endpoint: transport.endpoint.toString(),
      );
    } catch (error) {
      cachedCapabilitiesInternal[provider] =
          DirectSingleAgentCapabilities.unavailable(
            endpoint: descriptor.baseUri.toString(),
            errorMessage: error.toString(),
          );
      transportKindsInternal.remove(provider);
    } finally {
      capabilitiesRefreshedAtInternal[provider] = DateTime.now();
    }

    return cachedCapabilitiesInternal[provider]!;
  }

  Future<DirectSingleAgentRunResult> run(
    DirectSingleAgentRunRequest request,
  ) async {
    final descriptor = describeEndpointInternal(request.provider);
    if (!descriptor.isSupported || descriptor.baseUri == null) {
      return const DirectSingleAgentRunResult(
        success: false,
        output: '',
        errorMessage: 'Single-agent app-server endpoint is missing.',
      );
    }
    late final ResolvedSingleAgentTransportInternal transport;
    try {
      transport = await resolveTransportInternal(
        request.provider,
        descriptor: descriptor,
        gatewayToken: request.gatewayToken,
      );
    } catch (error) {
      return DirectSingleAgentRunResult(
        success: false,
        output: '',
        errorMessage: error.toString(),
      );
    }
    if (transport.kind ==
        DirectSingleAgentTransportKindInternal.restSessionApi) {
      return transport.rest!.run(
        request,
        base: transport.endpoint,
      );
    }
    return transport.websocket!.run(
      request,
      endpoint: transport.endpoint,
    );
  }

  Future<void> abort(String sessionId) async {
    await restTransportInternal.abort(
      sessionId,
      candidateBases: <Uri>[
        for (final entry in transportKindsInternal.entries)
          if (entry.value ==
              DirectSingleAgentTransportKindInternal.restSessionApi) ...[
            if (describeEndpointInternal(entry.key).baseUri != null)
              describeEndpointInternal(entry.key).baseUri!,
          ],
      ],
    );
    await webSocketTransportInternal.abort(sessionId);
  }

  Future<void> dispose() async {
    await webSocketTransportInternal.dispose();
  }

  DirectSingleAgentEndpointDescriptor describeEndpointInternal(
    SingleAgentProvider provider,
  ) {
    return DirectSingleAgentEndpointDescriptor.describe(
      endpointResolver(provider),
    );
  }

  Future<ResolvedSingleAgentTransportInternal> resolveTransportInternal(
    SingleAgentProvider provider, {
    required DirectSingleAgentEndpointDescriptor descriptor,
    required String gatewayToken,
  }) async {
    final cachedKind = transportKindsInternal[provider];
    if (cachedKind != null) {
      final cachedEndpoint =
          cachedKind ==
              DirectSingleAgentTransportKindInternal.websocketAppServer
          ? descriptor.websocketUri
          : descriptor.baseUri;
      if (cachedEndpoint != null) {
        return ResolvedSingleAgentTransportInternal(
          kind: cachedKind,
          endpoint: cachedEndpoint,
          websocket:
              cachedKind ==
                  DirectSingleAgentTransportKindInternal.websocketAppServer
              ? webSocketTransportInternal
              : null,
          rest:
              cachedKind ==
                  DirectSingleAgentTransportKindInternal.restSessionApi
              ? restTransportInternal
              : null,
        );
      }
    }

    if (descriptor.prefersWebSocket) {
      final endpoint = descriptor.websocketUri;
      if (endpoint == null) {
        throw StateError('Single-agent websocket endpoint is not configured.');
      }
      await webSocketTransportInternal.probe(
        endpoint,
        gatewayToken: gatewayToken,
      );
      return ResolvedSingleAgentTransportInternal(
        kind: DirectSingleAgentTransportKindInternal.websocketAppServer,
        endpoint: endpoint,
        websocket: webSocketTransportInternal,
      );
    }

    if (descriptor.allowsRest) {
      final base = descriptor.baseUri;
      if (base == null) {
        throw StateError('Single-agent endpoint is not configured.');
      }
      try {
        await restTransportInternal.probe(base, gatewayToken: gatewayToken);
        return ResolvedSingleAgentTransportInternal(
          kind: DirectSingleAgentTransportKindInternal.restSessionApi,
          endpoint: base,
          rest: restTransportInternal,
        );
      } catch (_) {
        final websocket = descriptor.websocketUri;
        if (websocket == null) {
          rethrow;
        }
        await webSocketTransportInternal.probe(
          websocket,
          gatewayToken: gatewayToken,
        );
        return ResolvedSingleAgentTransportInternal(
          kind: DirectSingleAgentTransportKindInternal.websocketAppServer,
          endpoint: websocket,
          websocket: webSocketTransportInternal,
        );
      }
    }

    throw StateError(
      'Single-agent endpoint mode ${descriptor.mode.name} is not supported.',
    );
  }
}
