import 'dart:convert';
import 'dart:io';

import 'runtime_models.dart';

class AccountRuntimeException implements Exception {
  const AccountRuntimeException({
    required this.statusCode,
    required this.errorCode,
    required this.message,
  });

  final int statusCode;
  final String errorCode;
  final String message;

  @override
  String toString() {
    return 'AccountRuntimeException($statusCode, $errorCode, $message)';
  }
}

class BridgeBootstrapIssue {
  const BridgeBootstrapIssue({
    required this.ticket,
    required this.shortCode,
    required this.bridgeOrigin,
    required this.scheme,
    required this.expiresAt,
    required this.scopes,
    required this.oneTime,
    required this.qrPayload,
  });

  final String ticket;
  final String shortCode;
  final String bridgeOrigin;
  final String scheme;
  final String expiresAt;
  final List<String> scopes;
  final bool oneTime;
  final String qrPayload;

  static String _stringValueStatic(Object? raw) {
    return raw == null ? '' : raw.toString().trim();
  }

  factory BridgeBootstrapIssue.fromJson(Map<String, dynamic> json) {
    List<String> scopes = const <String>[];
    if (json['scopes'] is List) {
      scopes = (json['scopes'] as List)
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return BridgeBootstrapIssue(
      ticket: BridgeBootstrapIssue._stringValueStatic(json['ticket']),
      shortCode: BridgeBootstrapIssue._stringValueStatic(json['shortCode']),
      bridgeOrigin: BridgeBootstrapIssue._stringValueStatic(json['bridge']),
      scheme: BridgeBootstrapIssue._stringValueStatic(json['scheme']),
      expiresAt: BridgeBootstrapIssue._stringValueStatic(json['expiresAt']),
      scopes: scopes,
      oneTime: json['oneTime'] as bool? ?? false,
      qrPayload: BridgeBootstrapIssue._stringValueStatic(json['qrPayload']),
    );
  }
}

class BridgeBootstrapConsumeResult {
  const BridgeBootstrapConsumeResult({
    required this.setupCode,
    required this.bridgeOrigin,
    required this.authMode,
    required this.expiresAt,
    required this.issuedBy,
  });

  final String setupCode;
  final String bridgeOrigin;
  final String authMode;
  final String expiresAt;
  final String issuedBy;

  static String _stringValueStatic(Object? raw) {
    return raw == null ? '' : raw.toString().trim();
  }

  factory BridgeBootstrapConsumeResult.fromJson(Map<String, dynamic> json) {
    return BridgeBootstrapConsumeResult(
      setupCode: BridgeBootstrapConsumeResult._stringValueStatic(
        json['setupCode'],
      ),
      bridgeOrigin: BridgeBootstrapConsumeResult._stringValueStatic(
        json['bridgeOrigin'],
      ),
      authMode: BridgeBootstrapConsumeResult._stringValueStatic(
        json['authMode'],
      ),
      expiresAt: BridgeBootstrapConsumeResult._stringValueStatic(
        json['expiresAt'],
      ),
      issuedBy: BridgeBootstrapConsumeResult._stringValueStatic(
        json['issuedBy'],
      ),
    );
  }
}

class AccountRuntimeClient {
  AccountRuntimeClient({required String baseUrl})
    : baseUrl = _normalizeBaseUrl(baseUrl);

  final String baseUrl;

  static String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) {
    return _requestJson(
      method: 'POST',
      path: '/api/auth/login',
      body: <String, Object?>{
        'identifier': identifier.trim(),
        'password': password,
      },
    );
  }

  Future<Map<String, dynamic>> verifyMfa({
    required String mfaToken,
    required String code,
  }) {
    return _requestJson(
      method: 'POST',
      path: '/api/auth/mfa/verify',
      body: <String, Object?>{
        'mfaToken': mfaToken.trim(),
        'method': 'totp',
        'totpCode': code.trim(),
        'code': code.trim(),
      },
    );
  }

  Future<AccountSessionSummary> loadSession({required String token}) async {
    final payload = await _requestJson(
      method: 'GET',
      path: '/api/auth/session',
      bearerToken: token,
    );
    final user = _asMap(payload['user']);
    return _accountSessionSummaryFromUserJson(user);
  }

  Future<AccountProfileResponse> loadProfile({required String token}) async {
    final payload = await _requestJson(
      method: 'GET',
      path: '/api/auth/xworkmate/profile',
      bearerToken: token,
    );
    final profile = _asMap(payload['profile']);
    final remoteProfile = AccountRemoteProfile.defaults().copyWith(
      openclawUrl: _stringValue(profile['openclawUrl']),
      openclawOrigin: _stringValue(profile['openclawOrigin']),
      vaultUrl: _stringValue(profile['vaultUrl']),
      vaultNamespace: _stringValue(profile['vaultNamespace']),
      apisixUrl: _stringValue(profile['apisixUrl']),
      secretLocators: _decodeLocators(profile),
    );
    return AccountProfileResponse(
      profile: remoteProfile,
      profileScope: _stringValue(payload['profileScope']),
      tokenConfigured: AccountTokenConfigured.fromJson(
        _asMap(payload['tokenConfigured']),
      ),
    );
  }

  Future<BridgeBootstrapIssue> createBridgeBootstrapTicket({
    required String token,
  }) async {
    final payload = await _requestJson(
      method: 'POST',
      path: '/api/auth/xworkmate/bridge/bootstrap',
      bearerToken: token,
      body: const <String, Object?>{},
    );
    return BridgeBootstrapIssue.fromJson(payload);
  }

  Future<BridgeBootstrapIssue> lookupBridgeBootstrapTicket({
    required String token,
    required String shortCode,
  }) async {
    final payload = await _requestJson(
      method: 'GET',
      path:
          '/api/auth/xworkmate/bridge/bootstrap/${Uri.encodeComponent(shortCode.trim())}',
      bearerToken: token,
    );
    return BridgeBootstrapIssue.fromJson(payload);
  }

  Future<BridgeBootstrapConsumeResult> consumeBridgeBootstrapTicket({
    required String ticket,
    required String bridgeOrigin,
  }) async {
    final payload = await _requestJson(
      method: 'POST',
      path: '/bridge/bootstrap/consume',
      body: <String, Object?>{
        'ticket': ticket.trim(),
        'bridge': bridgeOrigin.trim(),
      },
    );
    return BridgeBootstrapConsumeResult.fromJson(payload);
  }

  Future<String> readVaultSecretValue({
    required String vaultUrl,
    required String namespace,
    required String vaultToken,
    required String secretPath,
    required String secretKey,
  }) async {
    final uri = _vaultReadUri(vaultUrl, secretPath);
    final payload = await _requestJson(
      method: 'GET',
      uriOverride: uri,
      rawHeaders: <String, String>{
        if (namespace.trim().isNotEmpty) 'X-Vault-Namespace': namespace.trim(),
        if (vaultToken.trim().isNotEmpty) 'X-Vault-Token': vaultToken.trim(),
      },
    );
    final data = _asMap(payload['data']);
    final secretData = _asMap(data['data']);
    return _stringValue(secretData[secretKey]);
  }

  AccountSessionSummary _accountSessionSummaryFromUserJson(
    Map<String, dynamic> user,
  ) {
    return AccountSessionSummary(
      userId: _stringValue(user['id']),
      email: _stringValue(user['email']),
      name: _stringValue(user['name']).isNotEmpty
          ? _stringValue(user['name'])
          : _stringValue(user['username']),
      role: _stringValue(user['role']),
      mfaEnabled: user['mfaEnabled'] as bool? ?? false,
    );
  }

  List<AccountSecretLocator> _decodeLocators(Map<String, dynamic> profile) {
    final raw = profile['secretLocators'];
    if (raw is! List) {
      return const <AccountSecretLocator>[];
    }
    return raw
        .whereType<Map>()
        .map(
          (item) => AccountSecretLocator.fromJson(item.cast<String, dynamic>()),
        )
        .where(
          (item) =>
              item.provider.trim().isNotEmpty &&
              item.secretPath.trim().isNotEmpty &&
              item.secretKey.trim().isNotEmpty &&
              item.target.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  Uri _vaultReadUri(String rawBaseUrl, String secretPath) {
    final base = Uri.parse(_normalizeBaseUrl(rawBaseUrl));
    final trimmedPath = secretPath.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final segments = trimmedPath
        .split('/')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (segments.length < 2) {
      throw const AccountRuntimeException(
        statusCode: 400,
        errorCode: 'invalid_vault_path',
        message: 'invalid vault path',
      );
    }
    final mount = segments.first;
    final path = segments.skip(1).toList(growable: false);
    return base.replace(pathSegments: <String>['v1', mount, 'data', ...path]);
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    String path = '',
    Uri? uriOverride,
    String bearerToken = '',
    Map<String, Object?>? body,
    Map<String, String> rawHeaders = const <String, String>{},
  }) async {
    final uri = uriOverride ?? Uri.parse('$baseUrl$path');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await switch (method.toUpperCase()) {
        'POST' => client.postUrl(uri),
        'GET' => client.getUrl(uri),
        _ => throw UnsupportedError('Unsupported method $method'),
      };
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (bearerToken.trim().isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${bearerToken.trim()}',
        );
      }
      for (final entry in rawHeaders.entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      final rawBody = await utf8.decoder.bind(response).join();
      final decoded = rawBody.trim().isEmpty
          ? const <String, dynamic>{}
          : _asMap(jsonDecode(rawBody));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AccountRuntimeException(
          statusCode: response.statusCode,
          errorCode: _stringValue(decoded['error']).isNotEmpty
              ? _stringValue(decoded['error'])
              : 'request_failed',
          message: _stringValue(decoded['message']).isNotEmpty
              ? _stringValue(decoded['message'])
              : rawBody.trim(),
        );
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  static String _stringValue(Object? value) {
    return value?.toString().trim() ?? '';
  }
}
