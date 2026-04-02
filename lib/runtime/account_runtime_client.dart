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

class AccountRuntimeClient {
  AccountRuntimeClient({required String baseUrl})
    : baseUrl = _normalizeBaseUrl(baseUrl);

  final String baseUrl;

  static String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
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
      profile: remoteProfile.copyWith(
        secretLocators: _withLegacyOpenclawLocator(remoteProfile, profile),
      ),
      profileScope: _stringValue(payload['profileScope']),
      tokenConfigured: AccountTokenConfigured.fromJson(
        _asMap(payload['tokenConfigured']),
      ),
    );
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
        .map((item) => AccountSecretLocator.fromJson(item.cast<String, dynamic>()))
        .where(
          (item) =>
              item.provider.trim().isNotEmpty &&
              item.secretPath.trim().isNotEmpty &&
              item.secretKey.trim().isNotEmpty &&
              item.target.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  List<AccountSecretLocator> _withLegacyOpenclawLocator(
    AccountRemoteProfile profile,
    Map<String, dynamic> rawProfile,
  ) {
    final existing = profile.secretLocators;
    final hasOpenclawLocator = existing.any(
      (item) => item.target == kAccountManagedSecretTargetOpenclawGatewayToken,
    );
    if (hasOpenclawLocator) {
      return existing;
    }
    final legacySecretPath = _stringValue(rawProfile['vaultSecretPath']);
    final legacySecretKey = _stringValue(rawProfile['vaultSecretKey']);
    if (legacySecretPath.isEmpty || legacySecretKey.isEmpty) {
      return existing;
    }
    return <AccountSecretLocator>[
      ...existing,
      AccountSecretLocator(
        id: 'legacy-openclaw-locator',
        provider: 'vault',
        secretPath: legacySecretPath,
        secretKey: legacySecretKey,
        target: kAccountManagedSecretTargetOpenclawGatewayToken,
        required: true,
      ),
    ];
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
      final response = await request.close().timeout(const Duration(seconds: 6));
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
