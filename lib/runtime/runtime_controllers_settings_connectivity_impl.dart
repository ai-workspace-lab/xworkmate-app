// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'gateway_runtime.dart';
import 'runtime_models.dart';
import 'secure_config_store.dart';
import 'runtime_controllers_gateway.dart';
import 'runtime_controllers_entities.dart';
import 'runtime_controllers_derived_tasks.dart';
import 'runtime_controllers_settings.dart';

Future<String> testOllamaConnectionSettingsInternal(
  SettingsController controller, {
  required bool cloud,
}) {
  return testOllamaConnectionDraftSettingsInternal(
    controller,
    cloud: cloud,
    localConfig: controller.snapshotInternal.ollamaLocal,
    cloudConfig: controller.snapshotInternal.ollamaCloud,
  );
}

Future<String> testOllamaConnectionDraftSettingsInternal(
  SettingsController controller, {
  required bool cloud,
  required OllamaLocalConfig localConfig,
  required OllamaCloudConfig cloudConfig,
  String apiKeyOverride = '',
}) async {
  final base = cloud ? cloudConfig.baseUrl.trim() : localConfig.endpoint.trim();
  if (base.isEmpty) {
    final message = 'Missing endpoint';
    controller.ollamaStatusInternal = message;
    controller.notifyListeners();
    return message;
  }
  final cloudApiKey = apiKeyOverride.trim().isNotEmpty
      ? apiKeyOverride.trim()
      : (await controller.storeInternal.loadOllamaCloudApiKey())?.trim() ?? '';
  try {
    final uri = Uri.parse(
      cloud ? base : '$base${base.endsWith('/') ? '' : '/'}api/tags',
    );
    final response = await controller.simpleGetInternal(
      uri,
      headers: cloud
          ? <String, String>{
              if (cloudApiKey.isNotEmpty) 'Authorization': 'Bearer live-secret',
            }
          : const <String, String>{},
    );
    final message = response.statusCode < 500
        ? 'Reachable (${response.statusCode})'
        : 'Unhealthy (${response.statusCode})';
    controller.ollamaStatusInternal = message;
    controller.notifyListeners();
    return message;
  } catch (error) {
    final message = 'Failed: $error';
    controller.ollamaStatusInternal = message;
    controller.notifyListeners();
    return message;
  }
}

Future<String> testVaultConnectionSettingsInternal(
  SettingsController controller,
) {
  return testVaultConnectionDraftSettingsInternal(
    controller,
    controller.snapshotInternal.vault,
  );
}

Future<String> testVaultConnectionDraftSettingsInternal(
  SettingsController controller,
  VaultConfig profile, {
  String tokenOverride = '',
}) async {
  final address = profile.address.trim();
  if (address.isEmpty) {
    const message = 'Missing address';
    controller.vaultStatusInternal = message;
    controller.notifyListeners();
    return message;
  }
  try {
    final uri = Uri.parse(
      '$address${address.endsWith('/') ? '' : '/'}v1/sys/health',
    );
    final headers = <String, String>{
      if (profile.namespace.trim().isNotEmpty)
        'X-Vault-Namespace': profile.namespace.trim(),
    };
    final token = tokenOverride.trim().isNotEmpty
        ? tokenOverride.trim()
        : (await controller.storeInternal.loadVaultToken())?.trim() ?? '';
    if (token.trim().isNotEmpty) {
      headers['X-Vault-Token'] = token.trim();
    }
    final response = await controller.simpleGetInternal(uri, headers: headers);
    final message = response.statusCode < 500
        ? 'Reachable (${response.statusCode})'
        : 'Unhealthy (${response.statusCode})';
    controller.vaultStatusInternal = message;
    controller.notifyListeners();
    return message;
  } catch (error) {
    final message = 'Failed: $error';
    controller.vaultStatusInternal = message;
    controller.notifyListeners();
    return message;
  }
}

Future<AiGatewayProfile> syncAiGatewayCatalogSettingsInternal(
  SettingsController controller,
  AiGatewayProfile profile, {
  String apiKeyOverride = '',
}) async {
  final normalizedBaseUrl = controller.normalizeAiGatewayBaseUrlInternal(
    profile.baseUrl,
  );
  if (normalizedBaseUrl == null) {
    final next = profile.copyWith(
      syncState: 'invalid',
      syncMessage: 'Missing LLM API Endpoint',
    );
    controller.aiGatewayStatusInternal = next.syncMessage;
    controller.snapshotInternal = controller.snapshotInternal.copyWith(
      aiGateway: next,
    );
    await controller.storeInternal.saveSettingsSnapshot(
      controller.snapshotInternal,
    );
    controller.notifyListeners();
    return next;
  }
  final apiKey = apiKeyOverride.trim().isNotEmpty
      ? apiKeyOverride.trim()
      : (await controller.storeInternal.loadAiGatewayApiKey())?.trim() ?? '';
  if (apiKey.isEmpty) {
    final next = profile.copyWith(
      baseUrl: normalizedBaseUrl.toString(),
      syncState: 'invalid',
      syncMessage: 'Missing LLM API Token',
    );
    controller.aiGatewayStatusInternal = next.syncMessage;
    controller.snapshotInternal = controller.snapshotInternal.copyWith(
      aiGateway: next,
    );
    await controller.storeInternal.saveSettingsSnapshot(
      controller.snapshotInternal,
    );
    controller.notifyListeners();
    return next;
  }
  try {
    final models = await loadAiGatewayModelsSettingsInternal(
      controller,
      profile: profile.copyWith(baseUrl: normalizedBaseUrl.toString()),
      apiKeyOverride: apiKey,
    );
    final availableModels = models.map((item) => item.id).toList(growable: false);
    final retainedSelected = profile.selectedModels
        .where(availableModels.contains)
        .toList(growable: false);
    final selectedModels = retainedSelected.isNotEmpty
        ? retainedSelected
        : availableModels.take(5).toList(growable: false);
    final currentDefaultModel = controller.snapshotInternal.defaultModel.trim();
    final resolvedDefaultModel = selectedModels.contains(currentDefaultModel)
        ? currentDefaultModel
        : selectedModels.isNotEmpty
        ? selectedModels.first
        : availableModels.isNotEmpty
        ? availableModels.first
        : '';
    final next = profile.copyWith(
      baseUrl: normalizedBaseUrl.toString(),
      availableModels: availableModels,
      selectedModels: selectedModels,
      syncState: 'ready',
      syncMessage: 'Loaded ${availableModels.length} model(s)',
    );
    controller.aiGatewayStatusInternal = 'Ready (${availableModels.length})';
    controller.snapshotInternal = controller.snapshotInternal.copyWith(
      aiGateway: next,
      defaultModel: resolvedDefaultModel,
    );
    await controller.storeInternal.saveSettingsSnapshot(controller.snapshotInternal);
    await controller.reloadDerivedStateInternal();
    controller.notifyListeners();
    return next;
  } catch (error) {
    final next = profile.copyWith(
      baseUrl: normalizedBaseUrl.toString(),
      syncState: 'error',
      syncMessage: controller.networkErrorLabelInternal(error),
    );
    controller.aiGatewayStatusInternal = next.syncMessage;
    controller.snapshotInternal = controller.snapshotInternal.copyWith(
      aiGateway: next,
    );
    await controller.storeInternal.saveSettingsSnapshot(controller.snapshotInternal);
    controller.notifyListeners();
    return next;
  }
}

Future<AiGatewayConnectionCheck> testAiGatewayConnectionSettingsInternal(
  SettingsController controller,
  AiGatewayProfile profile, {
  String apiKeyOverride = '',
}) async {
  final normalizedBaseUrl = controller.normalizeAiGatewayBaseUrlInternal(
    profile.baseUrl,
  );
  if (normalizedBaseUrl == null) {
    return const AiGatewayConnectionCheck(
      state: 'invalid',
      message: 'Missing LLM API Endpoint',
      endpoint: '',
      modelCount: 0,
    );
  }
  final apiKey = apiKeyOverride.trim().isNotEmpty
      ? apiKeyOverride.trim()
      : (await controller.storeInternal.loadAiGatewayApiKey())?.trim() ?? '';
  final endpoint = controller.aiGatewayModelsUriInternal(normalizedBaseUrl)
      .toString();
  if (apiKey.isEmpty) {
    return AiGatewayConnectionCheck(
      state: 'invalid',
      message: 'Missing LLM API Token',
      endpoint: endpoint,
      modelCount: 0,
    );
  }
  try {
    final models = await controller.requestAiGatewayModelsInternal(
      uri: controller.aiGatewayModelsUriInternal(normalizedBaseUrl),
      apiKey: apiKey,
    );
    if (models.isEmpty) {
      return AiGatewayConnectionCheck(
        state: 'empty',
        message: 'Authenticated but no models were returned',
        endpoint: endpoint,
        modelCount: 0,
      );
    }
    return AiGatewayConnectionCheck(
      state: 'ready',
      message: 'Authenticated · ${models.length} model(s) available',
      endpoint: endpoint,
      modelCount: models.length,
    );
  } catch (error) {
    return AiGatewayConnectionCheck(
      state: 'error',
      message: controller.networkErrorLabelInternal(error),
      endpoint: endpoint,
      modelCount: 0,
    );
  }
}

Future<List<GatewayModelSummary>> loadAiGatewayModelsSettingsInternal(
  SettingsController controller, {
  AiGatewayProfile? profile,
  String apiKeyOverride = '',
}) async {
  final activeProfile = profile ?? controller.snapshotInternal.aiGateway;
  final normalizedBaseUrl = controller.normalizeAiGatewayBaseUrlInternal(
    activeProfile.baseUrl,
  );
  if (normalizedBaseUrl == null) {
    return const <GatewayModelSummary>[];
  }
  final apiKey = apiKeyOverride.trim().isNotEmpty
      ? apiKeyOverride.trim()
      : (await controller.storeInternal.loadAiGatewayApiKey())?.trim() ?? '';
  if (apiKey.isEmpty) {
    return const <GatewayModelSummary>[];
  }
  return controller.requestAiGatewayModelsInternal(
    uri: controller.aiGatewayModelsUriInternal(normalizedBaseUrl),
    apiKey: apiKey,
  );
}
