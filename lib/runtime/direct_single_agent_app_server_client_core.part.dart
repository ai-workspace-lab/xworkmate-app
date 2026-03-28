part of 'direct_single_agent_app_server_client.dart';

class DirectSingleAgentAppServerClient {
  DirectSingleAgentAppServerClient({required this.endpointResolver});

  final Uri? Function(SingleAgentProvider provider) endpointResolver;
  final _DirectSingleAgentWebSocketTransport _webSocketTransport =
      _DirectSingleAgentWebSocketTransport();
  final _DirectSingleAgentRestTransport _restTransport =
      _DirectSingleAgentRestTransport();

  final Map<SingleAgentProvider, DirectSingleAgentCapabilities>
  _cachedCapabilities = <SingleAgentProvider, DirectSingleAgentCapabilities>{};
  final Map<SingleAgentProvider, DateTime> _capabilitiesRefreshedAt =
      <SingleAgentProvider, DateTime>{};
  final Map<SingleAgentProvider, _DirectSingleAgentTransportKind>
  _transportKinds = <SingleAgentProvider, _DirectSingleAgentTransportKind>{};

  Future<DirectSingleAgentCapabilities> loadCapabilities({
    required SingleAgentProvider provider,
    bool forceRefresh = false,
    String gatewayToken = '',
  }) async {
    final cached = _cachedCapabilities[provider];
    final refreshedAt = _capabilitiesRefreshedAt[provider];
    if (!forceRefresh &&
        cached != null &&
        refreshedAt != null &&
        DateTime.now().difference(refreshedAt) < const Duration(seconds: 15)) {
      return cached;
    }

    final descriptor = _describeEndpoint(provider);
    if (!descriptor.isSupported || descriptor.baseUri == null) {
      final unavailable = const DirectSingleAgentCapabilities.unavailable(
        endpoint: '',
        errorMessage: 'Single-agent app-server endpoint is not configured.',
      );
      _cachedCapabilities[provider] = unavailable;
      _capabilitiesRefreshedAt[provider] = DateTime.now();
      return unavailable;
    }

    try {
      final transport = await _resolveTransport(
        provider,
        descriptor: descriptor,
        gatewayToken: gatewayToken,
      );
      _transportKinds[provider] = transport.kind;
      _cachedCapabilities[provider] = DirectSingleAgentCapabilities(
        available: true,
        supportedProviders: <SingleAgentProvider>[provider],
        endpoint: transport.endpoint.toString(),
      );
    } catch (error) {
      _cachedCapabilities[provider] = DirectSingleAgentCapabilities.unavailable(
        endpoint: descriptor.baseUri.toString(),
        errorMessage: error.toString(),
      );
      _transportKinds.remove(provider);
    } finally {
      _capabilitiesRefreshedAt[provider] = DateTime.now();
    }

    return _cachedCapabilities[provider]!;
  }

  Future<DirectSingleAgentRunResult> run(
    DirectSingleAgentRunRequest request,
  ) async {
    final descriptor = _describeEndpoint(request.provider);
    if (!descriptor.isSupported || descriptor.baseUri == null) {
      return const DirectSingleAgentRunResult(
        success: false,
        output: '',
        errorMessage: 'Single-agent app-server endpoint is missing.',
      );
    }
    late final _ResolvedSingleAgentTransport transport;
    try {
      transport = await _resolveTransport(
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
    if (transport.kind == _DirectSingleAgentTransportKind.restSessionApi) {
      return transport.rest!.run(
        request,
        base: transport.endpoint,
        workspaceRefKind: transport.workspaceRefKind,
      );
    }
    return transport.websocket!.run(
      request,
      endpoint: transport.endpoint,
      workspaceRefKind: transport.workspaceRefKind,
    );
  }

  Future<void> abort(String sessionId) async {
    await _restTransport.abort(
      sessionId,
      candidateBases: <Uri>[
        for (final entry in _transportKinds.entries)
          if (entry.value ==
              _DirectSingleAgentTransportKind.restSessionApi) ...[
            if (_describeEndpoint(entry.key).baseUri != null)
              _describeEndpoint(entry.key).baseUri!,
          ],
      ],
    );
    await _webSocketTransport.abort(sessionId);
  }

  Future<void> dispose() async {
    await _webSocketTransport.dispose();
  }

  DirectSingleAgentEndpointDescriptor _describeEndpoint(
    SingleAgentProvider provider,
  ) {
    return DirectSingleAgentEndpointDescriptor.describe(
      endpointResolver(provider),
    );
  }

  Future<_ResolvedSingleAgentTransport> _resolveTransport(
    SingleAgentProvider provider, {
    required DirectSingleAgentEndpointDescriptor descriptor,
    required String gatewayToken,
  }) async {
    final cachedKind = _transportKinds[provider];
    if (cachedKind != null) {
      final cachedEndpoint =
          cachedKind == _DirectSingleAgentTransportKind.websocketAppServer
          ? descriptor.websocketUri
          : descriptor.baseUri;
      if (cachedEndpoint != null) {
        return _ResolvedSingleAgentTransport(
          kind: cachedKind,
          endpoint: cachedEndpoint,
          workspaceRefKind: _workspaceRefKindForEndpointMode(descriptor.mode),
          websocket:
              cachedKind == _DirectSingleAgentTransportKind.websocketAppServer
              ? _webSocketTransport
              : null,
          rest: cachedKind == _DirectSingleAgentTransportKind.restSessionApi
              ? _restTransport
              : null,
        );
      }
    }

    if (descriptor.prefersWebSocket) {
      final endpoint = descriptor.websocketUri;
      if (endpoint == null) {
        throw StateError('Single-agent websocket endpoint is not configured.');
      }
      await _webSocketTransport.probe(endpoint, gatewayToken: gatewayToken);
      return _ResolvedSingleAgentTransport(
        kind: _DirectSingleAgentTransportKind.websocketAppServer,
        endpoint: endpoint,
        workspaceRefKind: _workspaceRefKindForEndpointMode(descriptor.mode),
        websocket: _webSocketTransport,
      );
    }

    if (descriptor.allowsRest) {
      final base = descriptor.baseUri;
      if (base == null) {
        throw StateError('Single-agent endpoint is not configured.');
      }
      try {
        await _restTransport.probe(base, gatewayToken: gatewayToken);
        return _ResolvedSingleAgentTransport(
          kind: _DirectSingleAgentTransportKind.restSessionApi,
          endpoint: base,
          workspaceRefKind: _workspaceRefKindForEndpointMode(descriptor.mode),
          rest: _restTransport,
        );
      } catch (_) {
        final websocket = descriptor.websocketUri;
        if (websocket == null) {
          rethrow;
        }
        await _webSocketTransport.probe(websocket, gatewayToken: gatewayToken);
        return _ResolvedSingleAgentTransport(
          kind: _DirectSingleAgentTransportKind.websocketAppServer,
          endpoint: websocket,
          workspaceRefKind: _workspaceRefKindForEndpointMode(descriptor.mode),
          websocket: _webSocketTransport,
        );
      }
    }

    throw StateError(
      'Single-agent endpoint mode ${descriptor.mode.name} is not supported.',
    );
  }
}
