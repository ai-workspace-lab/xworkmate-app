import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FakeAccountVaultServer {
  FakeAccountVaultServer._(
    this._server, {
    required this.requireMfa,
    required this.includeUnmappedLocator,
  });

  final HttpServer _server;
  final bool requireMfa;
  final bool includeUnmappedLocator;

  final String loginEmail = 'user@example.com';
  final String loginPassword = 'correct-password';
  final String loginCode = '123456';
  final String sessionToken = 'account-session-token';
  final String mfaTicket = 'account-mfa-ticket';
  final String expectedVaultToken = 'vault-root-token';
  final String openclawGatewayToken = 'remote-openclaw-token';
  final String aiGatewayAccessToken = 'remote-ai-gateway-token';
  final String ollamaCloudApiKey = 'remote-ollama-api-key';

  String? lastAiGatewayAuthorization;
  String? lastVaultToken;
  String? lastVaultNamespace;

  String get accountBaseUrl => 'http://127.0.0.1:${_server.port}';
  String get vaultBaseUrl => accountBaseUrl;
  String get aiGatewayBaseUrl => '$accountBaseUrl/v1';
  String get openclawUrl => 'https://openclaw.account.example';
  String get openclawOrigin => 'https://openclaw.account.example';

  static Future<FakeAccountVaultServer> start({
    bool requireMfa = false,
    bool includeUnmappedLocator = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeAccountVaultServer._(
      server,
      requireMfa: requireMfa,
      includeUnmappedLocator: includeUnmappedLocator,
    );
    unawaited(fake._serve());
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      final path = request.uri.path;
      if (request.method == 'POST' && path == '/api/auth/login') {
        await _handleLogin(request);
        continue;
      }
      if (request.method == 'POST' && path == '/api/auth/mfa/verify') {
        await _handleVerifyMfa(request);
        continue;
      }
      if (request.method == 'GET' && path == '/api/auth/session') {
        await _handleSession(request);
        continue;
      }
      if (request.method == 'DELETE' && path == '/api/auth/session') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        continue;
      }
      if (request.method == 'GET' && path == '/api/auth/xworkmate/profile') {
        await _handleProfile(request);
        continue;
      }
      if (request.method == 'GET' && path == '/v1/models') {
        await _handleModels(request);
        continue;
      }
      if (request.method == 'GET' && path.startsWith('/v1/kv/data/')) {
        await _handleVault(request);
        continue;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  Future<void> _handleLogin(HttpRequest request) async {
    final payload = await _decodeJson(request);
    final identifier =
        (payload['identifier'] ?? payload['email'] ?? '').toString().trim();
    final password = (payload['password'] ?? '').toString().trim();
    if (identifier != loginEmail || password != loginPassword) {
      await _writeJson(
        request.response,
        HttpStatus.unauthorized,
        <String, Object?>{
          'error': 'invalid_credentials',
          'message': 'invalid credentials',
        },
      );
      return;
    }
    if (requireMfa) {
      await _writeJson(
        request.response,
        HttpStatus.ok,
        <String, Object?>{
          'message': 'mfa required',
          'mfaRequired': true,
          'mfa_required': true,
          'mfaToken': mfaTicket,
          'mfaTicket': mfaTicket,
        },
      );
      return;
    }
    await _writeJson(
      request.response,
      HttpStatus.ok,
      <String, Object?>{
        'message': 'login successful',
        'token': sessionToken,
        'access_token': sessionToken,
        'expiresAt': DateTime.utc(2030, 1, 1).toIso8601String(),
        'mfaRequired': false,
        'mfa_required': false,
        'user': _userPayload(),
      },
    );
  }

  Future<void> _handleVerifyMfa(HttpRequest request) async {
    final payload = await _decodeJson(request);
    final ticket =
        (payload['mfaToken'] ?? payload['mfa_ticket'] ?? '').toString().trim();
    final code =
        (payload['code'] ?? payload['totpCode'] ?? '').toString().trim();
    if (ticket != mfaTicket || code != loginCode) {
      await _writeJson(
        request.response,
        HttpStatus.unauthorized,
        <String, Object?>{
          'error': 'invalid_mfa_code',
          'message': 'invalid totp code',
        },
      );
      return;
    }
    await _writeJson(
      request.response,
      HttpStatus.ok,
      <String, Object?>{
        'message': 'login successful',
        'token': sessionToken,
        'access_token': sessionToken,
        'expiresAt': DateTime.utc(2030, 1, 1).toIso8601String(),
        'mfaRequired': false,
        'mfa_required': false,
        'user': _userPayload(mfaEnabled: true),
      },
    );
  }

  Future<void> _handleSession(HttpRequest request) async {
    if (!_isAuthorized(request)) {
      await _writeJson(
        request.response,
        HttpStatus.unauthorized,
        <String, Object?>{'error': 'session not found'},
      );
      return;
    }
    await _writeJson(
      request.response,
      HttpStatus.ok,
      <String, Object?>{'user': _userPayload(mfaEnabled: requireMfa)},
    );
  }

  Future<void> _handleProfile(HttpRequest request) async {
    if (!_isAuthorized(request)) {
      await _writeJson(
        request.response,
        HttpStatus.unauthorized,
        <String, Object?>{'error': 'session not found'},
      );
      return;
    }
    final secretLocators = <Map<String, Object?>>[
      <String, Object?>{
        'id': 'locator-openclaw',
        'provider': 'vault',
        'secretPath': 'kv/openclaw',
        'secretKey': 'OPENCLAW_GATEWAY_TOKEN',
        'target': 'openclaw.gateway_token',
        'required': true,
      },
      <String, Object?>{
        'id': 'locator-ai-gateway',
        'provider': 'vault',
        'secretPath': 'kv/apisix',
        'secretKey': 'AI_GATEWAY_ACCESS_TOKEN',
        'target': 'ai_gateway.access_token',
        'required': true,
      },
      <String, Object?>{
        'id': 'locator-ollama',
        'provider': 'vault',
        'secretPath': 'kv/ollama',
        'secretKey': 'OLLAMA_API_KEY',
        'target': 'ollama_cloud.api_key',
        'required': false,
      },
      if (includeUnmappedLocator)
        <String, Object?>{
          'id': 'locator-unmapped',
          'provider': 'vault',
          'secretPath': 'kv/unmapped',
          'secretKey': 'UNMAPPED_KEY',
          'target': 'unknown.target',
          'required': false,
        },
    ];
    await _writeJson(
      request.response,
      HttpStatus.ok,
      <String, Object?>{
        'profile': <String, Object?>{
          'openclawUrl': openclawUrl,
          'openclawOrigin': openclawOrigin,
          'vaultUrl': vaultBaseUrl,
          'vaultNamespace': 'team-a',
          'vaultSecretPath': 'kv/openclaw',
          'vaultSecretKey': 'OPENCLAW_GATEWAY_TOKEN',
          'apisixUrl': aiGatewayBaseUrl,
          'secretLocators': secretLocators,
        },
        'profileScope': 'user',
        'tokenConfigured': <String, Object?>{
          'openclaw': true,
          'vault': false,
          'apisix': true,
        },
      },
    );
  }

  Future<void> _handleModels(HttpRequest request) async {
    lastAiGatewayAuthorization =
        request.headers.value(HttpHeaders.authorizationHeader);
    if (lastAiGatewayAuthorization != 'Bearer $aiGatewayAccessToken') {
      await _writeJson(
        request.response,
        HttpStatus.unauthorized,
        <String, Object?>{
          'error': <String, Object?>{'message': 'invalid_api_key'},
        },
      );
      return;
    }
    await _writeJson(
      request.response,
      HttpStatus.ok,
      <String, Object?>{
        'data': <Map<String, Object?>>[
          <String, Object?>{'id': 'gpt-5.4', 'name': 'gpt-5.4'},
          <String, Object?>{'id': 'o3-mini', 'name': 'o3-mini'},
        ],
      },
    );
  }

  Future<void> _handleVault(HttpRequest request) async {
    lastVaultToken = request.headers.value('X-Vault-Token');
    lastVaultNamespace = request.headers.value('X-Vault-Namespace');
    if (lastVaultToken != expectedVaultToken) {
      await _writeJson(
        request.response,
        HttpStatus.forbidden,
        <String, Object?>{'errors': <String>['permission denied']},
      );
      return;
    }
    final path = request.uri.path.substring('/v1/kv/data/'.length);
    final data = switch (path) {
      'openclaw' => <String, Object?>{
          'OPENCLAW_GATEWAY_TOKEN': openclawGatewayToken,
        },
      'apisix' => <String, Object?>{
          'AI_GATEWAY_ACCESS_TOKEN': aiGatewayAccessToken,
        },
      'ollama' => <String, Object?>{
          'OLLAMA_API_KEY': ollamaCloudApiKey,
        },
      _ => <String, Object?>{
          'UNMAPPED_KEY': 'ignored-value',
        },
    };
    await _writeJson(
      request.response,
      HttpStatus.ok,
      <String, Object?>{
        'data': <String, Object?>{
          'data': data,
        },
      },
    );
  }

  bool _isAuthorized(HttpRequest request) {
    final authorization = request.headers.value(HttpHeaders.authorizationHeader);
    return authorization == 'Bearer $sessionToken';
  }

  Map<String, Object?> _userPayload({bool mfaEnabled = false}) {
    return <String, Object?>{
      'id': 'user-1',
      'name': 'Demo User',
      'username': 'Demo User',
      'email': loginEmail,
      'role': 'user',
      'mfaEnabled': mfaEnabled,
    };
  }

  Future<Map<String, Object?>> _decodeJson(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    if (raw.trim().isEmpty) {
      return const <String, Object?>{};
    }
    return (jsonDecode(raw) as Map).cast<String, Object?>();
  }

  Future<void> _writeJson(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> payload,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(payload));
    await response.close();
  }
}
