// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'account_runtime_client.dart';
import 'gateway_runtime.dart';
import 'runtime_models.dart';
import 'secret_store.dart';
import 'secure_config_store.dart';
import 'runtime_controllers_gateway.dart';
import 'runtime_controllers_entities.dart';
import 'runtime_controllers_derived_tasks.dart';
import 'runtime_controllers_settings_account_impl.dart';
import 'runtime_controllers_settings_connectivity_impl.dart';

part 'runtime_controllers_settings_account.dart';
part 'runtime_controllers_settings_secrets_impl.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(
    this.storeInternal, {
    AccountRuntimeClient Function(String baseUrl)? accountClientFactory,
  }) : accountClientFactoryInternal = accountClientFactory;

  final SecureConfigStore storeInternal;
  final AccountRuntimeClient Function(String baseUrl)?
  accountClientFactoryInternal;
  bool disposedInternal = false;
  final List<StreamSubscription<FileSystemEvent>>
  settingsWatchSubscriptionsInternal = <StreamSubscription<FileSystemEvent>>[];
  Timer? settingsReloadDebounceInternal;
  Timer? settingsPollTimerInternal;

  SettingsSnapshot snapshotInternal = SettingsSnapshot.defaults();
  String lastSnapshotJsonInternal = SettingsSnapshot.defaults().toJsonString();
  String lastSettingsFileStampInternal = '';
  Map<String, String> secureRefsInternal = const <String, String>{};
  List<SecretAuditEntry> auditTrailInternal = const <SecretAuditEntry>[];
  String ollamaStatusInternal = 'Idle';
  String vaultStatusInternal = 'Idle';
  String aiGatewayStatusInternal = 'Idle';
  String accountSessionTokenInternal = '';
  AccountSessionSummary? accountSessionInternal;
  AccountSyncState? accountSyncStateInternal;
  bool accountBusyInternal = false;
  String accountStatusInternal = 'Signed out';
  String pendingAccountMfaTicketInternal = '';
  String pendingAccountBaseUrlInternal = '';

  SettingsSnapshot get snapshot => snapshotInternal;
  Map<String, String> get secureRefs => secureRefsInternal;
  List<SecretAuditEntry> get auditTrail => auditTrailInternal;
  String get ollamaStatus => ollamaStatusInternal;
  String get vaultStatus => vaultStatusInternal;
  String get aiGatewayStatus => aiGatewayStatusInternal;

  @override
  void notifyListeners() {
    if (disposedInternal) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    disposedInternal = true;
    settingsReloadDebounceInternal?.cancel();
    settingsPollTimerInternal?.cancel();
    for (final subscription in settingsWatchSubscriptionsInternal) {
      unawaited(subscription.cancel());
    }
    settingsWatchSubscriptionsInternal.clear();
    super.dispose();
  }

  Future<void> initialize() async {
    snapshotInternal = await storeInternal.loadSettingsSnapshot();
    lastSnapshotJsonInternal = snapshotInternal.toJsonString();
    await reloadDerivedStateInternal();
    await startSettingsWatcherInternal();
    await refreshSettingsFileStampInternal();
    startSettingsPollingInternal();
    notifyListeners();
  }

  Future<void> refreshDerivedState() async {
    await reloadDerivedStateInternal();
    notifyListeners();
  }

  Future<void> saveSnapshot(SettingsSnapshot snapshot) async {
    snapshotInternal = snapshot;
    lastSnapshotJsonInternal = snapshotInternal.toJsonString();
    await storeInternal.saveSettingsSnapshot(snapshot);
    await refreshSettingsFileStampInternal();
    await reloadDerivedStateInternal();
    notifyListeners();
  }

  Future<void> resetSnapshot(SettingsSnapshot snapshot) async {
    snapshotInternal = snapshot;
    lastSnapshotJsonInternal = snapshotInternal.toJsonString();
    await refreshSettingsFileStampInternal();
    await reloadDerivedStateInternal();
    notifyListeners();
  }

  Future<void> saveGatewaySecrets({
    int? profileIndex,
    required String token,
    required String password,
  }) => saveGatewaySecretsSettingsInternal(
    this,
    profileIndex: profileIndex,
    token: token,
    password: password,
  );

  Future<void> clearGatewaySecrets({
    int? profileIndex,
    bool token = false,
    bool password = false,
  }) => clearGatewaySecretsSettingsInternal(
    this,
    profileIndex: profileIndex,
    token: token,
    password: password,
  );

  Future<String> loadGatewayToken({int? profileIndex}) =>
      loadGatewayTokenSettingsInternal(this, profileIndex: profileIndex);

  Future<String> loadGatewayPassword({int? profileIndex}) =>
      loadGatewayPasswordSettingsInternal(this, profileIndex: profileIndex);

  bool hasStoredGatewayTokenForProfile(int profileIndex) =>
      hasStoredGatewayTokenForProfileSettingsInternal(this, profileIndex);

  bool hasStoredGatewayPasswordForProfile(int profileIndex) =>
      hasStoredGatewayPasswordForProfileSettingsInternal(this, profileIndex);

  String? storedGatewayTokenMaskForProfile(int profileIndex) =>
      storedGatewayTokenMaskForProfileSettingsInternal(this, profileIndex);

  String? storedGatewayPasswordMaskForProfile(int profileIndex) =>
      storedGatewayPasswordMaskForProfileSettingsInternal(this, profileIndex);

  String gatewayTokenRefForProfileInternal(int profileIndex) =>
      gatewayTokenRefForProfileSettingsInternal(this, profileIndex);

  String gatewayPasswordRefForProfileInternal(int profileIndex) =>
      gatewayPasswordRefForProfileSettingsInternal(this, profileIndex);

  String aiGatewayApiKeyRefInternal([AiGatewayProfile? profile]) =>
      aiGatewayApiKeyRefSettingsInternal(this, profile);

  String vaultTokenRefInternal([VaultConfig? profile]) =>
      vaultTokenRefSettingsInternal(this, profile);

  String ollamaCloudApiKeyRefInternal([OllamaCloudConfig? profile]) =>
      ollamaCloudApiKeyRefSettingsInternal(this, profile);

  Future<void> saveOllamaCloudApiKey(String value) =>
      saveOllamaCloudApiKeySettingsInternal(this, value);

  Future<String> loadOllamaCloudApiKey() =>
      loadOllamaCloudApiKeySettingsInternal(this);

  Future<void> saveVaultToken(String value) =>
      saveVaultTokenSettingsInternal(this, value);

  Future<String> loadVaultToken() => loadVaultTokenSettingsInternal(this);

  Future<void> saveAiGatewayApiKey(String value) =>
      saveAiGatewayApiKeySettingsInternal(this, value);

  Future<String> loadAiGatewayApiKey() =>
      loadAiGatewayApiKeySettingsInternal(this);

  Future<void> clearAiGatewayApiKey() =>
      clearAiGatewayApiKeySettingsInternal(this);

  Future<void> saveSecretValueByRef(
    String refName,
    String value, {
    required String provider,
    required String module,
  }) => saveSecretValueByRefSettingsInternal(
    this,
    refName,
    value,
    provider: provider,
    module: module,
  );

  Future<String> loadSecretValueByRef(String refName) =>
      loadSecretValueByRefSettingsInternal(this, refName);

  Future<String> loadVaultTokenForSecretReadsInternal({
    String tokenOverride = '',
  }) => loadVaultTokenForSecretReadsSettingsInternal(
    this,
    tokenOverride: tokenOverride,
  );

  Future<String> readVaultSecretByRefInternal(String refName) =>
      readVaultSecretByRefSettingsInternal(this, refName);

  Future<String> resolveSecretValueInternal({
    String explicitValue = '',
    String refName = '',
    String fallbackRefName = '',
    String accountTarget = '',
    bool allowVaultLookup = true,
    bool persistExplicitValue = true,
  }) => resolveSecretValueSettingsInternal(
    this,
    explicitValue: explicitValue,
    refName: refName,
    fallbackRefName: fallbackRefName,
    accountTarget: accountTarget,
    allowVaultLookup: allowVaultLookup,
    persistExplicitValue: persistExplicitValue,
  );

  Future<void> appendAudit(SecretAuditEntry entry) async {
    await storeInternal.appendAudit(entry);
    auditTrailInternal = await storeInternal.loadAuditTrail();
    notifyListeners();
  }

  Future<String> testOllamaConnection({required bool cloud}) =>
      testOllamaConnectionSettingsInternal(this, cloud: cloud);

  Future<String> testOllamaConnectionDraft({
    required bool cloud,
    required OllamaLocalConfig localConfig,
    required OllamaCloudConfig cloudConfig,
    String apiKeyOverride = '',
  }) => testOllamaConnectionDraftSettingsInternal(
    this,
    cloud: cloud,
    localConfig: localConfig,
    cloudConfig: cloudConfig,
    apiKeyOverride: apiKeyOverride,
  );

  Future<String> testVaultConnection() =>
      testVaultConnectionSettingsInternal(this);

  Future<String> testVaultConnectionDraft(
    VaultConfig profile, {
    String tokenOverride = '',
  }) => testVaultConnectionDraftSettingsInternal(
    this,
    profile,
    tokenOverride: tokenOverride,
  );

  Future<AiGatewayProfile> syncAiGatewayCatalog(
    AiGatewayProfile profile, {
    String apiKeyOverride = '',
  }) => syncAiGatewayCatalogSettingsInternal(
    this,
    profile,
    apiKeyOverride: apiKeyOverride,
  );

  Future<AiGatewayConnectionCheck> testAiGatewayConnection(
    AiGatewayProfile profile, {
    String apiKeyOverride = '',
  }) => testAiGatewayConnectionSettingsInternal(
    this,
    profile,
    apiKeyOverride: apiKeyOverride,
  );

  Future<List<GatewayModelSummary>> loadAiGatewayModels({
    AiGatewayProfile? profile,
    String apiKeyOverride = '',
  }) => loadAiGatewayModelsSettingsInternal(
    this,
    profile: profile,
    apiKeyOverride: apiKeyOverride,
  );

  Uri? normalizeAiGatewayBaseUrlInternal(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    final pathSegments = uri.pathSegments.where((item) => item.isNotEmpty);
    return uri.replace(
      pathSegments: pathSegments.isEmpty ? const <String>['v1'] : pathSegments,
      query: null,
      fragment: null,
    );
  }

  Uri aiGatewayModelsUriInternal(Uri baseUrl) {
    final pathSegments = baseUrl.pathSegments
        .where((item) => item.isNotEmpty)
        .toList(growable: true);
    if (pathSegments.isEmpty) {
      pathSegments.add('v1');
    }
    if (pathSegments.last != 'models') {
      pathSegments.add('models');
    }
    return baseUrl.replace(
      pathSegments: pathSegments,
      query: null,
      fragment: null,
    );
  }

  Future<List<GatewayModelSummary>> requestAiGatewayModelsInternal({
    required Uri uri,
    required String apiKey,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 6));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final trimmedApiKey = apiKey.trim();
      if (trimmedApiKey.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $trimmedApiKey',
        );
        request.headers.set('x-api-key', trimmedApiKey);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiGatewayResponseExceptionInternal(
          statusCode: response.statusCode,
          message: aiGatewayHttpErrorLabelInternal(
            response.statusCode,
            extractAiGatewayErrorDetailInternal(body),
          ),
        );
      }
      final decoded = jsonDecode(extractFirstJsonDocumentInternal(body));
      final rawModels = decoded is Map<String, dynamic>
          ? [
              ...asList(decoded['data']),
              if (asList(decoded['data']).isEmpty) ...asList(decoded['models']),
            ]
          : const <Object>[];
      final seen = <String>{};
      final items = <GatewayModelSummary>[];
      for (final item in rawModels) {
        final map = asMap(item);
        final modelId =
            stringValue(map['id']) ?? stringValue(map['name']) ?? '';
        if (modelId.trim().isEmpty || !seen.add(modelId)) {
          continue;
        }
        items.add(
          GatewayModelSummary(
            id: modelId,
            name: stringValue(map['name']) ?? modelId,
            provider:
                stringValue(map['provider']) ??
                stringValue(map['owned_by']) ??
                'LLM API',
            contextWindow:
                intValue(map['contextWindow']) ??
                intValue(map['context_window']),
            maxOutputTokens:
                intValue(map['maxOutputTokens']) ??
                intValue(map['max_output_tokens']),
          ),
        );
      }
      return items;
    } finally {
      client.close(force: true);
    }
  }

  String networkErrorLabelInternal(Object error) {
    if (error is AiGatewayResponseExceptionInternal) {
      return error.message;
    }
    if (error is SocketException) {
      return 'Unable to reach the LLM API';
    }
    if (error is HandshakeException) {
      return 'TLS handshake failed';
    }
    if (error is TimeoutException) {
      return 'Connection timed out';
    }
    if (error is FormatException) {
      return 'LLM API returned invalid JSON';
    }
    return 'Failed: $error';
  }

  String aiGatewayHttpErrorLabelInternal(int statusCode, String detail) {
    final base = switch (statusCode) {
      400 => 'Bad request (400)',
      401 => 'Authentication failed (401)',
      403 => 'Access denied (403)',
      404 => 'Model catalog endpoint not found (404)',
      429 => 'Rate limited by LLM API (429)',
      >= 500 => 'LLM API unavailable ($statusCode)',
      _ => 'LLM API responded $statusCode',
    };
    return detail.isEmpty ? base : '$base · $detail';
  }

  String extractAiGatewayErrorDetailInternal(String body) {
    if (body.trim().isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(extractFirstJsonDocumentInternal(body));
      final map = asMap(decoded);
      final error = asMap(map['error']);
      return (stringValue(error['message']) ??
              stringValue(map['message']) ??
              stringValue(map['detail']) ??
              '')
          .trim();
    } on FormatException {
      return '';
    }
  }

  String extractFirstJsonDocumentInternal(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty response body');
    }
    final start = trimmed.indexOf(RegExp(r'[\{\[]'));
    if (start < 0) {
      throw const FormatException('Missing JSON document');
    }
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < trimmed.length; index++) {
      final char = trimmed[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (char == '{' || char == '[') {
        depth += 1;
      } else if (char == '}' || char == ']') {
        depth -= 1;
        if (depth == 0) {
          return trimmed.substring(start, index + 1);
        }
      }
    }
    throw const FormatException('Unterminated JSON document');
  }

  Future<HttpClientResponse> simpleGetInternal(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 4));
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      return await request.close().timeout(const Duration(seconds: 4));
    } finally {
      client.close(force: true);
    }
  }

  String timeLabelInternal() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  String gatewaySecretTargetInternal(String base, int? profileIndex) {
    if (profileIndex == null) {
      return base;
    }
    return '$base.$profileIndex';
  }

  Future<void> startSettingsWatcherInternal() async {
    for (final subscription in settingsWatchSubscriptionsInternal) {
      await subscription.cancel();
    }
    settingsWatchSubscriptionsInternal.clear();
    final file = await storeInternal.resolvedSettingsFile();
    final directory = await storeInternal.resolvedSettingsWatchDirectory();
    void scheduleReload() {
      settingsReloadDebounceInternal?.cancel();
      settingsReloadDebounceInternal = Timer(
        const Duration(milliseconds: 160),
        () => unawaited(reloadSettingsFromDiskIfChangedInternal()),
      );
    }

    if (file != null) {
      try {
        if (await file.exists()) {
          settingsWatchSubscriptionsInternal.add(
            file.watch().listen((_) {
              scheduleReload();
            }),
          );
        }
      } catch (_) {
        // Best effort only. Directory watch below remains as a fallback.
      }
    }
    if (directory != null) {
      try {
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        settingsWatchSubscriptionsInternal.add(
          directory.watch().listen((_) {
            scheduleReload();
          }),
        );
      } catch (_) {
        // Best effort only. Missing watch support should not block runtime.
      }
    }
  }

  Future<void> reloadSettingsFromDiskIfChangedInternal() async {
    if (disposedInternal) {
      return;
    }
    final nextStamp = await resolveStableSettingsFileStampInternal();
    if (nextStamp == lastSettingsFileStampInternal) {
      return;
    }
    final reload = await storeInternal.reloadSettingsSnapshotResult();
    if (!reload.applied) {
      return;
    }
    lastSettingsFileStampInternal = nextStamp;
    final next = reload.snapshot;
    final nextJson = next.toJsonString();
    if (nextJson == lastSnapshotJsonInternal) {
      return;
    }
    snapshotInternal = next;
    lastSnapshotJsonInternal = nextJson;
    await reloadDerivedStateInternal();
    notifyListeners();
  }

  void startSettingsPollingInternal() {
    settingsPollTimerInternal?.cancel();
    settingsPollTimerInternal = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(pollSettingsFileChangesInternal());
    });
  }

  Future<void> pollSettingsFileChangesInternal() async {
    if (disposedInternal) {
      return;
    }
    final previousStamp = lastSettingsFileStampInternal;
    final nextStamp = await computeSettingsFileStampInternal();
    if (nextStamp == previousStamp) {
      return;
    }
    await reloadSettingsFromDiskIfChangedInternal();
  }

  Future<void> refreshSettingsFileStampInternal() async {
    lastSettingsFileStampInternal = await computeSettingsFileStampInternal();
  }

  Future<String> resolveStableSettingsFileStampInternal() async {
    var current = await computeSettingsFileStampInternal();
    for (var attempt = 0; attempt < 4; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final next = await computeSettingsFileStampInternal();
      if (next == current) {
        return next;
      }
      current = next;
    }
    return current;
  }

  Future<String> computeSettingsFileStampInternal() async {
    final buffer = StringBuffer();
    final file = await storeInternal.resolvedSettingsFile();
    if (file != null) {
      buffer.write(file.path);
      if (await file.exists()) {
        final stat = await file.stat();
        buffer
          ..write(':')
          ..write(stat.modified.millisecondsSinceEpoch)
          ..write(':')
          ..write(stat.size);
      } else {
        buffer.write(':missing');
      }
      buffer.write('|');
    }
    return buffer.toString();
  }
}
