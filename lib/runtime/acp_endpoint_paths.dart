class AcpEndpointPaths {
  const AcpEndpointPaths._({
    required this.basePath,
    required this.webSocketPath,
    required this.httpRpcPath,
  });

  final String basePath;
  final String webSocketPath;
  final String httpRpcPath;

  static AcpEndpointPaths fromBaseEndpoint(Uri endpoint) {
    final basePath = _normalizeBasePath(endpoint.path);
    final prefixedBasePath = basePath.isEmpty ? '' : basePath;
    return AcpEndpointPaths._(
      basePath: prefixedBasePath,
      webSocketPath: prefixedBasePath.isEmpty
          ? '/acp'
          : '$prefixedBasePath/acp',
      httpRpcPath: prefixedBasePath.isEmpty
          ? '/acp/rpc'
          : '$prefixedBasePath/acp/rpc',
    );
  }

  static String _normalizeBasePath(String rawPath) {
    var path = rawPath.trim();
    if (path.isEmpty || path == '/') {
      return '';
    }

    if (!path.startsWith('/')) {
      path = '/$path';
    }
    path = path.replaceFirst(RegExp(r'/+$'), '');
    if (path.isEmpty || path == '/') {
      return '';
    }

    if (path.endsWith('/acp/rpc')) {
      path = path.substring(0, path.length - '/acp/rpc'.length);
    } else if (path.endsWith('/acp')) {
      path = path.substring(0, path.length - '/acp'.length);
    }

    path = path.replaceFirst(RegExp(r'/+$'), '');
    return path == '/' ? '' : path;
  }
}

Uri? resolveAcpWebSocketEndpoint(Uri? endpoint) {
  if (endpoint == null || endpoint.host.trim().isEmpty) {
    return null;
  }
  final scheme = endpoint.scheme.trim().toLowerCase();
  final wsScheme = switch (scheme) {
    'https' || 'wss' => 'wss',
    _ => 'ws',
  };
  final paths = AcpEndpointPaths.fromBaseEndpoint(endpoint);
  return endpoint.replace(
    scheme: wsScheme,
    path: paths.webSocketPath,
    query: null,
    fragment: null,
  );
}

Uri? resolveAcpHttpRpcEndpoint(Uri? endpoint) {
  if (endpoint == null || endpoint.host.trim().isEmpty) {
    return null;
  }
  final scheme = endpoint.scheme.trim().toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return null;
  }
  final paths = AcpEndpointPaths.fromBaseEndpoint(endpoint);
  return endpoint.replace(path: paths.httpRpcPath, query: null, fragment: null);
}

Uri? resolveBridgeProviderBaseEndpoint(
  Uri? bridgeBaseEndpoint, {
  required String providerId,
  required bool gateway,
}) {
  if (bridgeBaseEndpoint == null || bridgeBaseEndpoint.host.trim().isEmpty) {
    return null;
  }
  final normalizedProviderId = providerId.trim().toLowerCase();
  if (normalizedProviderId.isEmpty) {
    return bridgeBaseEndpoint.replace(query: null, fragment: null);
  }

  // Remove trailing slashes and common ACP suffixes from the base path to avoid double-nesting
  var basePath = bridgeBaseEndpoint.path.trim().replaceFirst(
    RegExp(r'/+$'),
    '',
  );
  if (basePath.endsWith('/acp/rpc')) {
    basePath = basePath.substring(0, basePath.length - '/acp/rpc'.length);
  } else if (basePath.endsWith('/acp')) {
    basePath = basePath.substring(0, basePath.length - '/acp'.length);
  }
  basePath = basePath.replaceFirst(RegExp(r'/+$'), '');

  final providerPath = gateway
      ? '$basePath/gateway/$normalizedProviderId'
      : '$basePath/acp-server/$normalizedProviderId';

  return bridgeBaseEndpoint.replace(
    path: providerPath.replaceFirst(RegExp(r'^//+'), '/'),
    query: null,
    fragment: null,
  );
}
