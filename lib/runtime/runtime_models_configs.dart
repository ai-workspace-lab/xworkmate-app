// ignore_for_file: unused_import, unnecessary_import

import 'dart:convert';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import 'runtime_models_connection.dart';
import 'runtime_models_profiles.dart';
import 'runtime_models_settings_snapshot.dart';
import 'runtime_models_runtime_payloads.dart';
import 'runtime_models_gateway_entities.dart';
import 'runtime_models_multi_agent.dart';

class GatewayConnectionProfile {
  const GatewayConnectionProfile({
    required this.mode,
    required this.useSetupCode,
    required this.setupCode,
    required this.host,
    required this.port,
    required this.tls,
    required this.tokenRef,
    required this.passwordRef,
    required this.selectedAgentId,
  });

  final RuntimeConnectionMode mode;
  final bool useSetupCode;
  final String setupCode;
  final String host;
  final int port;
  final bool tls;
  final String tokenRef;
  final String passwordRef;
  final String selectedAgentId;

  factory GatewayConnectionProfile.defaults() {
    return GatewayConnectionProfile.defaultsRemote();
  }

  factory GatewayConnectionProfile.defaultsLocal() {
    return const GatewayConnectionProfile(
      mode: RuntimeConnectionMode.local,
      useSetupCode: false,
      setupCode: '',
      host: '127.0.0.1',
      port: 18789,
      tls: false,
      tokenRef: 'gateway_token_0',
      passwordRef: 'gateway_password_0',
      selectedAgentId: '',
    );
  }

  factory GatewayConnectionProfile.defaultsRemote() {
    return const GatewayConnectionProfile(
      mode: RuntimeConnectionMode.remote,
      useSetupCode: false,
      setupCode: '',
      host: 'openclaw.svc.plus',
      port: 443,
      tls: true,
      tokenRef: 'gateway_token_1',
      passwordRef: 'gateway_password_1',
      selectedAgentId: '',
    );
  }

  factory GatewayConnectionProfile.emptySlot({required int index}) {
    return GatewayConnectionProfile(
      mode: RuntimeConnectionMode.unconfigured,
      useSetupCode: false,
      setupCode: '',
      host: '',
      port: 443,
      tls: true,
      tokenRef: 'gateway_token_$index',
      passwordRef: 'gateway_password_$index',
      selectedAgentId: '',
    );
  }

  GatewayConnectionProfile copyWith({
    RuntimeConnectionMode? mode,
    bool? useSetupCode,
    String? setupCode,
    String? host,
    int? port,
    bool? tls,
    String? tokenRef,
    String? passwordRef,
    String? selectedAgentId,
  }) {
    final normalized = normalizeGatewayManualEndpointInternal(
      host: host ?? this.host,
      port: port ?? this.port,
      tls: tls ?? this.tls,
    );
    return GatewayConnectionProfile(
      mode: mode ?? this.mode,
      useSetupCode: useSetupCode ?? this.useSetupCode,
      setupCode: setupCode ?? this.setupCode,
      host: normalized.host,
      port: normalized.port,
      tls: normalized.tls,
      tokenRef: tokenRef ?? this.tokenRef,
      passwordRef: passwordRef ?? this.passwordRef,
      selectedAgentId: selectedAgentId ?? this.selectedAgentId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.name,
      'useSetupCode': useSetupCode,
      'setupCode': setupCode,
      'host': host,
      'port': port,
      'tls': tls,
      'tokenRef': tokenRef,
      'passwordRef': passwordRef,
      'selectedAgentId': selectedAgentId,
    };
  }

  factory GatewayConnectionProfile.fromJson(Map<String, dynamic> json) {
    final defaults = GatewayConnectionProfile.defaults();
    final normalized = normalizeGatewayManualEndpointInternal(
      host: json['host'] as String? ?? defaults.host,
      port: json['port'] as int? ?? defaults.port,
      tls: json['tls'] as bool? ?? defaults.tls,
    );
    return GatewayConnectionProfile(
      mode: RuntimeConnectionModeCopy.fromJsonValue(json['mode'] as String?),
      useSetupCode: json['useSetupCode'] as bool? ?? false,
      setupCode: json['setupCode'] as String? ?? '',
      host: normalized.host,
      port: normalized.port,
      tls: normalized.tls,
      tokenRef: json['tokenRef'] as String? ?? '',
      passwordRef: json['passwordRef'] as String? ?? '',
      selectedAgentId: json['selectedAgentId'] as String? ?? '',
    );
  }
}

const int kGatewayProfileListLength = 5;
const int kGatewayLocalProfileIndex = 0;
const int kGatewayRemoteProfileIndex = 1;
const int kGatewayCustomProfileStartIndex = 2;

List<GatewayConnectionProfile> normalizeGatewayProfiles({
  Iterable<GatewayConnectionProfile>? profiles,
}) {
  final defaults = List<GatewayConnectionProfile>.generate(
    kGatewayProfileListLength,
    (index) => switch (index) {
      kGatewayLocalProfileIndex => GatewayConnectionProfile.defaultsLocal(),
      kGatewayRemoteProfileIndex => GatewayConnectionProfile.defaultsRemote(),
      _ => GatewayConnectionProfile.emptySlot(index: index),
    },
    growable: false,
  );
  final incoming =
      profiles?.toList(growable: false) ?? const <GatewayConnectionProfile>[];
  final normalized = <GatewayConnectionProfile>[];
  for (var index = 0; index < kGatewayProfileListLength; index += 1) {
    final fallback = defaults[index];
    final current = index < incoming.length ? incoming[index] : fallback;
    if (index == kGatewayLocalProfileIndex) {
      normalized.add(
        current.copyWith(
          mode: RuntimeConnectionMode.local,
          useSetupCode: false,
          setupCode: '',
          host: current.host.trim().isEmpty ? fallback.host : current.host,
          port: current.port > 0 ? current.port : fallback.port,
          tls: false,
          tokenRef: current.tokenRef.trim().isEmpty
              ? fallback.tokenRef
              : current.tokenRef,
          passwordRef: current.passwordRef.trim().isEmpty
              ? fallback.passwordRef
              : current.passwordRef,
        ),
      );
      continue;
    }
    if (index == kGatewayRemoteProfileIndex) {
      final useDefaultRemoteEndpoint =
          current.host.trim().isEmpty || current.port <= 0;
      normalized.add(
        current.copyWith(
          mode: RuntimeConnectionMode.remote,
          host: useDefaultRemoteEndpoint ? fallback.host : current.host,
          port: useDefaultRemoteEndpoint ? fallback.port : current.port,
          tls: useDefaultRemoteEndpoint ? fallback.tls : current.tls,
          tokenRef: current.tokenRef.trim().isEmpty
              ? fallback.tokenRef
              : current.tokenRef,
          passwordRef: current.passwordRef.trim().isEmpty
              ? fallback.passwordRef
              : current.passwordRef,
        ),
      );
      continue;
    }
    final slotMode = switch (current.mode) {
      RuntimeConnectionMode.local => RuntimeConnectionMode.local,
      RuntimeConnectionMode.remote => RuntimeConnectionMode.remote,
      RuntimeConnectionMode.unconfigured =>
        current.host.trim().isNotEmpty
            ? RuntimeConnectionMode.remote
            : RuntimeConnectionMode.unconfigured,
    };
    normalized.add(
      current.copyWith(
        mode: slotMode,
        useSetupCode: slotMode == RuntimeConnectionMode.local
            ? false
            : current.useSetupCode,
        setupCode: slotMode == RuntimeConnectionMode.local
            ? ''
            : current.setupCode,
        port: current.port > 0
            ? current.port
            : slotMode == RuntimeConnectionMode.local
            ? 18789
            : 443,
        tls: slotMode == RuntimeConnectionMode.local ? false : current.tls,
        tokenRef: current.tokenRef.trim().isEmpty
            ? fallback.tokenRef
            : current.tokenRef,
        passwordRef: current.passwordRef.trim().isEmpty
            ? fallback.passwordRef
            : current.passwordRef,
      ),
    );
  }
  return List<GatewayConnectionProfile>.unmodifiable(normalized);
}

List<GatewayConnectionProfile> replaceGatewayProfileAt(
  List<GatewayConnectionProfile> profiles,
  int index,
  GatewayConnectionProfile profile,
) {
  final normalizedProfiles = normalizeGatewayProfiles(profiles: profiles);
  final next = List<GatewayConnectionProfile>.from(normalizedProfiles);
  final clampedIndex = index.clamp(0, kGatewayProfileListLength - 1);
  next[clampedIndex] = profile;
  return normalizeGatewayProfiles(profiles: next);
}

({String host, int port, bool tls}) normalizeGatewayManualEndpointInternal({
  required String host,
  required int port,
  required bool tls,
}) {
  final trimmedHost = host.trim();
  if (trimmedHost.isEmpty) {
    return (host: trimmedHost, port: port, tls: tls);
  }
  final normalizedInput = trimmedHost.contains('://')
      ? trimmedHost
      : '${tls ? 'https' : 'http'}://$trimmedHost:${port > 0 ? port : (tls ? 443 : 18789)}';
  final uri = Uri.tryParse(normalizedInput);
  final normalizedHost = uri?.host.trim() ?? trimmedHost;
  if (normalizedHost.isEmpty) {
    return (host: trimmedHost, port: port, tls: tls);
  }
  final scheme = uri?.scheme.trim().toLowerCase() ?? (tls ? 'https' : 'http');
  final normalizedTls = switch (scheme) {
    'ws' || 'http' => false,
    _ => true,
  };
  final normalizedPort = uri?.hasPort == true
      ? uri!.port
      : normalizedTls
      ? 443
      : 18789;
  return (
    host: normalizedHost,
    port: normalizedPort > 0 ? normalizedPort : port,
    tls: normalizedTls,
  );
}

class OllamaLocalConfig {
  const OllamaLocalConfig({
    required this.endpoint,
    required this.defaultModel,
    required this.autoDiscover,
  });

  final String endpoint;
  final String defaultModel;
  final bool autoDiscover;

  factory OllamaLocalConfig.defaults() {
    return const OllamaLocalConfig(
      endpoint: 'http://127.0.0.1:11434',
      defaultModel: 'qwen2.5-coder:latest',
      autoDiscover: true,
    );
  }

  OllamaLocalConfig copyWith({
    String? endpoint,
    String? defaultModel,
    bool? autoDiscover,
  }) {
    return OllamaLocalConfig(
      endpoint: endpoint ?? this.endpoint,
      defaultModel: defaultModel ?? this.defaultModel,
      autoDiscover: autoDiscover ?? this.autoDiscover,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'endpoint': endpoint,
      'defaultModel': defaultModel,
      'autoDiscover': autoDiscover,
    };
  }

  factory OllamaLocalConfig.fromJson(Map<String, dynamic> json) {
    return OllamaLocalConfig(
      endpoint:
          json['endpoint'] as String? ?? OllamaLocalConfig.defaults().endpoint,
      defaultModel:
          json['defaultModel'] as String? ??
          OllamaLocalConfig.defaults().defaultModel,
      autoDiscover: json['autoDiscover'] as bool? ?? true,
    );
  }
}

class OllamaCloudConfig {
  const OllamaCloudConfig({
    required this.baseUrl,
    required this.organization,
    required this.workspace,
    required this.defaultModel,
    required this.apiKeyRef,
  });

  final String baseUrl;
  final String organization;
  final String workspace;
  final String defaultModel;
  final String apiKeyRef;

  factory OllamaCloudConfig.defaults() {
    return const OllamaCloudConfig(
      baseUrl: 'https://ollama.com',
      organization: '',
      workspace: '',
      defaultModel: 'gpt-oss:120b',
      apiKeyRef: 'ollama_cloud_api_key',
    );
  }

  OllamaCloudConfig copyWith({
    String? baseUrl,
    String? organization,
    String? workspace,
    String? defaultModel,
    String? apiKeyRef,
  }) {
    return OllamaCloudConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      organization: organization ?? this.organization,
      workspace: workspace ?? this.workspace,
      defaultModel: defaultModel ?? this.defaultModel,
      apiKeyRef: apiKeyRef ?? this.apiKeyRef,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'organization': organization,
      'workspace': workspace,
      'defaultModel': defaultModel,
      'apiKeyRef': apiKeyRef,
    };
  }

  factory OllamaCloudConfig.fromJson(Map<String, dynamic> json) {
    return OllamaCloudConfig(
      baseUrl:
          json['baseUrl'] as String? ?? OllamaCloudConfig.defaults().baseUrl,
      organization: json['organization'] as String? ?? '',
      workspace: json['workspace'] as String? ?? '',
      defaultModel:
          json['defaultModel'] as String? ??
          OllamaCloudConfig.defaults().defaultModel,
      apiKeyRef:
          json['apiKeyRef'] as String? ??
          OllamaCloudConfig.defaults().apiKeyRef,
    );
  }
}

class VaultConfig {
  const VaultConfig({
    required this.address,
    required this.namespace,
    required this.authMode,
    required this.tokenRef,
  });

  final String address;
  final String namespace;
  final String authMode;
  final String tokenRef;

  factory VaultConfig.defaults() {
    return const VaultConfig(
      address: 'http://127.0.0.1:8200',
      namespace: '',
      authMode: 'token',
      tokenRef: 'vault_token',
    );
  }

  VaultConfig copyWith({
    String? address,
    String? namespace,
    String? authMode,
    String? tokenRef,
  }) {
    return VaultConfig(
      address: address ?? this.address,
      namespace: namespace ?? this.namespace,
      authMode: authMode ?? this.authMode,
      tokenRef: tokenRef ?? this.tokenRef,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'namespace': namespace,
      'authMode': authMode,
      'tokenRef': tokenRef,
    };
  }

  factory VaultConfig.fromJson(Map<String, dynamic> json) {
    return VaultConfig(
      address: json['address'] as String? ?? VaultConfig.defaults().address,
      namespace:
          json['namespace'] as String? ?? VaultConfig.defaults().namespace,
      authMode: json['authMode'] as String? ?? VaultConfig.defaults().authMode,
      tokenRef: json['tokenRef'] as String? ?? VaultConfig.defaults().tokenRef,
    );
  }
}

class AiGatewayProfile {
  const AiGatewayProfile({
    required this.name,
    required this.baseUrl,
    required this.apiKeyRef,
    required this.availableModels,
    required this.selectedModels,
    required this.syncState,
    required this.syncMessage,
  });

  final String name;
  final String baseUrl;
  final String apiKeyRef;
  final List<String> availableModels;
  final List<String> selectedModels;
  final String syncState;
  final String syncMessage;

  factory AiGatewayProfile.defaults() {
    return const AiGatewayProfile(
      name: 'LLM API',
      baseUrl: '',
      apiKeyRef: 'ai_gateway_api_key',
      availableModels: <String>[],
      selectedModels: <String>[],
      syncState: 'idle',
      syncMessage: 'Ready to sync models',
    );
  }

  AiGatewayProfile copyWith({
    String? name,
    String? baseUrl,
    String? apiKeyRef,
    List<String>? availableModels,
    List<String>? selectedModels,
    String? syncState,
    String? syncMessage,
  }) {
    return AiGatewayProfile(
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKeyRef: apiKeyRef ?? this.apiKeyRef,
      availableModels: availableModels ?? this.availableModels,
      selectedModels: selectedModels ?? this.selectedModels,
      syncState: syncState ?? this.syncState,
      syncMessage: syncMessage ?? this.syncMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'baseUrl': baseUrl,
      'apiKeyRef': apiKeyRef,
      'availableModels': availableModels,
      'selectedModels': selectedModels,
      'syncState': syncState,
      'syncMessage': syncMessage,
    };
  }

  factory AiGatewayProfile.fromJson(Map<String, dynamic> json) {
    List<String> normalizeList(Object? value) {
      if (value is! List) {
        return const <String>[];
      }
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    final defaults = AiGatewayProfile.defaults();
    final availableModels = normalizeList(json['availableModels']);
    final selectedModels = normalizeList(json['selectedModels'])
        .where(
          (item) => availableModels.isEmpty || availableModels.contains(item),
        )
        .toList(growable: false);
    final legacyFilePath = json['filePath'] as String?;
    final legacyBaseUrl =
        legacyFilePath != null && legacyFilePath.trim().startsWith('http')
        ? legacyFilePath.trim()
        : null;
    return AiGatewayProfile(
      name: json['name'] as String? ?? defaults.name,
      baseUrl: json['baseUrl'] as String? ?? legacyBaseUrl ?? defaults.baseUrl,
      apiKeyRef: json['apiKeyRef'] as String? ?? defaults.apiKeyRef,
      availableModels: availableModels,
      selectedModels: selectedModels,
      syncState: json['syncState'] as String? ?? defaults.syncState,
      syncMessage: json['syncMessage'] as String? ?? defaults.syncMessage,
    );
  }
}

class AiGatewayConnectionCheck {
  const AiGatewayConnectionCheck({
    required this.state,
    required this.message,
    required this.endpoint,
    required this.modelCount,
  });

  final String state;
  final String message;
  final String endpoint;
  final int modelCount;

  bool get success => state == 'ready' || state == 'empty';
}

enum WebSessionPersistenceMode { browser, remote }

extension WebSessionPersistenceModeCopy on WebSessionPersistenceMode {
  String get label => switch (this) {
    WebSessionPersistenceMode.browser => appText('浏览器本地缓存', 'Browser cache'),
    WebSessionPersistenceMode.remote => appText(
      '远端 Session API',
      'Remote session API',
    ),
  };

  static WebSessionPersistenceMode fromJsonValue(String? value) {
    return WebSessionPersistenceMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => WebSessionPersistenceMode.browser,
    );
  }
}

class WebSessionPersistenceConfig {
  const WebSessionPersistenceConfig({
    required this.mode,
    required this.remoteBaseUrl,
  });

  final WebSessionPersistenceMode mode;
  final String remoteBaseUrl;

  factory WebSessionPersistenceConfig.defaults() {
    return const WebSessionPersistenceConfig(
      mode: WebSessionPersistenceMode.browser,
      remoteBaseUrl: '',
    );
  }

  bool get usesRemoteApi =>
      mode == WebSessionPersistenceMode.remote &&
      remoteBaseUrl.trim().isNotEmpty;

  WebSessionPersistenceConfig copyWith({
    WebSessionPersistenceMode? mode,
    String? remoteBaseUrl,
  }) {
    return WebSessionPersistenceConfig(
      mode: mode ?? this.mode,
      remoteBaseUrl: remoteBaseUrl ?? this.remoteBaseUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {'mode': mode.name, 'remoteBaseUrl': remoteBaseUrl};
  }

  factory WebSessionPersistenceConfig.fromJson(Map<String, dynamic> json) {
    final defaults = WebSessionPersistenceConfig.defaults();
    return WebSessionPersistenceConfig(
      mode: WebSessionPersistenceModeCopy.fromJsonValue(
        json['mode'] as String?,
      ),
      remoteBaseUrl: json['remoteBaseUrl'] as String? ?? defaults.remoteBaseUrl,
    );
  }
}
