@TestOn('vm')
library;

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/account_runtime_client.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  final env = _SmokeEnv.load();
  final skipReason = env.skipReason;

  test(
    'real account sync plus bridge wiring keeps single-thread execution bound to the thread workspace',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDir = await Directory.systemTemp.createTemp(
        'xworkmate-account-bridge-smoke-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDir.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDir.path,
      );
      final bridgeClient = _BridgeGoTaskServiceClient(
        bridgeBaseUrl: env.bridgeServerUrl,
        bridgeAuthToken: env.bridgeAuthToken,
      );
      final controller = AppController(
        store: store,
        accountClientFactory: (_) => env.accountClient,
        goTaskServiceClient: bridgeClient,
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);

      await controller.saveSettings(
        controller.settings.copyWith(
          workspacePath: tempDir.path,
          accountBaseUrl: env.accountBaseUrl,
          accountUsername: env.accountLoginName,
          assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
          externalAcpEndpoints: <ExternalAcpEndpointProfile>[
            ExternalAcpEndpointProfile.defaultsForProvider(
              SingleAgentProvider.codex,
            ).copyWith(
              endpoint: env.bridgeServerUrl,
              authRef: env.bridgeAuthRef,
            ),
            ExternalAcpEndpointProfile.defaultsForProvider(
              SingleAgentProvider.opencode,
            ).copyWith(
              endpoint: env.bridgeServerUrl,
              authRef: env.bridgeAuthRef,
            ),
            ExternalAcpEndpointProfile.defaultsForProvider(
              SingleAgentProvider.gemini,
            ).copyWith(
              endpoint: env.bridgeServerUrl,
              authRef: env.bridgeAuthRef,
            ),
          ],
        ),
        refreshAfterSave: false,
      );
      await controller.settingsController.saveSecretValueByRef(
        env.bridgeAuthRef,
        env.bridgeAuthToken,
        provider: 'Local Store',
        module: 'Settings',
      );

      await controller.settingsController.loginAccount(
        baseUrl: env.accountBaseUrl,
        identifier: env.accountLoginName,
        password: env.accountLoginPassword,
      );

      expect(controller.settingsController.accountSignedIn, isTrue);
      expect(
        controller.settingsController.accountSyncState?.syncState,
        'ready',
      );
      expect(
        controller.settings.externalAcpEndpoints.any(
          (item) =>
              item.providerKey == 'codex' &&
              item.endpoint == env.bridgeServerUrl,
        ),
        isTrue,
      );

      final capabilities = await bridgeClient.loadExternalAcpCapabilities(
        target: AssistantExecutionTarget.singleAgent,
        forceRefresh: true,
      );
      expect(capabilities.singleAgent, isTrue);
      expect(capabilities.multiAgent, isTrue);
      expect(
        capabilities.providers.contains(SingleAgentProvider.codex),
        isTrue,
      );
      expect(
        capabilities.providers.contains(SingleAgentProvider.opencode),
        isTrue,
      );
      expect(
        capabilities.providers.contains(SingleAgentProvider.gemini),
        isTrue,
      );

      final routeResolution = await bridgeClient.resolveRouting(
        sessionId: controller.currentSessionKey,
        threadId: controller.currentSessionKey,
        workingDirectory: tempDir.path,
        prompt: '请检查 ACP 路由和 gateway 路由',
      );
      expect(routeResolution['result'] != null, isTrue);
      final workspacePath = controller.assistantWorkspacePathForSession(
        controller.currentSessionKey,
      );
      expect(workspacePath, contains(tempDir.path));
      expect(Directory(workspacePath).existsSync(), isTrue);
    },
    skip: skipReason,
  );
}

class _SmokeEnv {
  const _SmokeEnv({
    required this.skipReason,
    required this.accountClient,
    required this.accountBaseUrl,
    required this.accountLoginName,
    required this.accountLoginPassword,
    required this.bridgeAuthRef,
    required this.bridgeAuthToken,
    required this.bridgeServerUrl,
    required this.codexProviderEndpoint,
    required this.opencodeProviderEndpoint,
    required this.geminiProviderEndpoint,
  });

  final String? skipReason;
  final AccountRuntimeClient accountClient;
  final String accountBaseUrl;
  final String accountLoginName;
  final String accountLoginPassword;
  final String bridgeAuthRef;
  final String bridgeAuthToken;
  final String bridgeServerUrl;
  final String codexProviderEndpoint;
  final String opencodeProviderEndpoint;
  final String geminiProviderEndpoint;

  static _SmokeEnv load() {
    final env = <String, String>{..._loadEnvFile(), ...Platform.environment};
    final accountBaseUrl =
        env['ACCOUNT_BASE_URL'] ?? 'https://accounts.svc.plus';
    final accountLoginName =
        env['ACCOUNT_LOGIN_NAME'] ?? env['ACCOUNT_LOGIN_EMAIL'] ?? '';
    final accountLoginPassword = env['ACCOUNT_LOGIN_PASSWORD'] ?? '';
    final bridgeAuthToken =
        env['BRIDGE_AUTH_TOKEN'] ??
        env['ACP_AUTH_TOKEN'] ??
        env['INTERNAL_SERVICE_TOKEN'] ??
        '';
    final bridgeServerUrl =
        env['BRIDGE_SERVER_URL'] ??
        env['BRIDGE_URL'] ??
        'https://xworkmate-bridge.svc.plus';
    final codexProviderEndpoint =
        env['CODEX_PROVIDER_ENDPOINT'] ?? 'https://acp-server.svc.plus/codex';
    final opencodeProviderEndpoint =
        env['OPENCODE_PROVIDER_ENDPOINT'] ??
        'https://acp-server.svc.plus/opencode';
    final geminiProviderEndpoint =
        env['GEMINI_PROVIDER_ENDPOINT'] ?? 'https://acp-server.svc.plus/gemini';
    if (accountLoginName.trim().isEmpty ||
        accountLoginPassword.trim().isEmpty ||
        bridgeAuthToken.trim().isEmpty) {
      return _SmokeEnv(
        skipReason:
            'Set ACCOUNT_LOGIN_NAME, ACCOUNT_LOGIN_PASSWORD, and BRIDGE_AUTH_TOKEN to run the live account/bridge smoke test.',
        accountClient: AccountRuntimeClient(baseUrl: accountBaseUrl),
        accountBaseUrl: accountBaseUrl,
        accountLoginName: accountLoginName,
        accountLoginPassword: accountLoginPassword,
        bridgeAuthRef: 'bridge-auth-token',
        bridgeAuthToken: bridgeAuthToken,
        bridgeServerUrl: bridgeServerUrl,
        codexProviderEndpoint: codexProviderEndpoint,
        opencodeProviderEndpoint: opencodeProviderEndpoint,
        geminiProviderEndpoint: geminiProviderEndpoint,
      );
    }
    return _SmokeEnv(
      skipReason: null,
      accountClient: AccountRuntimeClient(baseUrl: accountBaseUrl),
      accountBaseUrl: accountBaseUrl,
      accountLoginName: accountLoginName,
      accountLoginPassword: accountLoginPassword,
      bridgeAuthRef: 'bridge-auth-token',
      bridgeAuthToken: bridgeAuthToken,
      bridgeServerUrl: bridgeServerUrl,
      codexProviderEndpoint: codexProviderEndpoint,
      opencodeProviderEndpoint: opencodeProviderEndpoint,
      geminiProviderEndpoint: geminiProviderEndpoint,
    );
  }
}

class _BridgeGoTaskServiceClient implements GoTaskServiceClient {
  _BridgeGoTaskServiceClient({
    required this.bridgeBaseUrl,
    required this.bridgeAuthToken,
  });

  final String bridgeBaseUrl;
  final String bridgeAuthToken;

  @override
  Future<void> syncExternalProviders(
    List<ExternalCodeAgentAcpSyncedProvider> providers,
  ) async {
    await _request(
      method: 'xworkmate.providers.sync',
      params: <String, dynamic>{
        'providers': providers
            .map(
              (item) => <String, dynamic>{
                'providerId': item.providerId,
                'label': item.label,
                'endpoint': item.endpoint,
                'authorizationHeader':
                    item.authorizationHeader.startsWith('Bearer ')
                    ? item.authorizationHeader
                    : 'Bearer ${item.authorizationHeader}',
                'enabled': item.enabled,
              },
            )
            .toList(growable: false),
      },
    );
  }

  @override
  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async {
    final response = await _request(
      method: 'acp.capabilities',
      params: const <String, dynamic>{},
    );
    final result =
        (response['result'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final providers = <SingleAgentProvider>{};
    for (final raw in <Object?>[
      ..._asList(result['providers']),
      ..._asList(
        result['capabilities'] is Map
            ? (result['capabilities'] as Map)['providers']
            : null,
      ),
    ]) {
      if (raw == null) {
        continue;
      }
      final provider = SingleAgentProviderCopy.fromJsonValue(
        raw.toString().trim().toLowerCase(),
      );
      if (provider != SingleAgentProvider.auto) {
        providers.add(provider);
      }
    }
    return ExternalCodeAgentAcpCapabilities(
      singleAgent: true,
      multiAgent: true,
      providers: providers,
      raw: result,
    );
  }

  @override
  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) async {
    final response = await _request(
      method: request.resumeSession ? 'session.message' : 'session.start',
      params: request.toExternalAcpParams(),
    );
    final result =
        (response['result'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final message = result['output']?.toString().trim().isNotEmpty == true
        ? result['output'].toString().trim()
        : result['message']?.toString().trim() ?? '';
    if (message.isNotEmpty) {
      onUpdate(
        GoTaskServiceUpdate(
          sessionId: request.sessionId,
          threadId: request.threadId,
          turnId: result['turnId']?.toString().trim() ?? '',
          type: 'done',
          text: message,
          message: message,
          pending: false,
          error: false,
          route: request.route,
          payload: <String, dynamic>{'event': 'completed'},
        ),
      );
    }
    return goTaskServiceResultFromAcpResponse(
      response,
      route: request.route,
      completedMessage: message,
    );
  }

  Future<Map<String, dynamic>> resolveRouting({
    required String sessionId,
    required String threadId,
    required String workingDirectory,
    required String prompt,
  }) async {
    return _request(
      method: 'xworkmate.routing.resolve',
      params: <String, dynamic>{
        'sessionId': sessionId,
        'threadId': threadId,
        'taskPrompt': prompt,
        'workingDirectory': workingDirectory,
        'routing': <String, dynamic>{
          'routingMode': 'auto',
          'preferredGatewayTarget': 'local',
          'explicitSkills': const <String>[],
          'allowSkillInstall': false,
          'availableSkills': const <Map<String, dynamic>>[],
        },
      },
    );
  }

  @override
  Future<void> cancelTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {}

  @override
  Future<void> closeTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {}

  @override
  Future<void> dispose() async {}

  Future<Map<String, dynamic>> _request({
    required String method,
    required Map<String, dynamic> params,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$bridgeBaseUrl/acp/rpc'));
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $bridgeAuthToken',
      );
      request.write(
        jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': DateTime.now().microsecondsSinceEpoch.toString(),
          'method': method,
          'params': params,
        }),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      return (jsonDecode(body) as Map).cast<String, dynamic>();
    } finally {
      client.close(force: true);
    }
  }

  List<Object?> _asList(Object? raw) {
    if (raw is List<Object?>) {
      return raw;
    }
    if (raw is List) {
      return raw.cast<Object?>();
    }
    return const <Object?>[];
  }
}

Future<void> _waitFor(FutureOr<bool> Function() predicate) async {
  final stopwatch = Stopwatch()..start();
  while (!(await predicate())) {
    if (stopwatch.elapsed > const Duration(seconds: 15)) {
      throw StateError('Timed out waiting for predicate');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Map<String, String> _loadEnvFile() {
  final env = <String, String>{};
  var dir = Directory.current;
  while (true) {
    final file = File('${dir.path}/.env');
    if (file.existsSync()) {
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
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  return env;
}
