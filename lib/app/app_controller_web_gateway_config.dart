// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/runtime_models.dart';
import '../web/web_acp_client.dart';
import '../web/web_ai_gateway_client.dart';
import '../web/web_artifact_proxy_client.dart';
import '../web/web_relay_gateway_client.dart';
import '../web/web_session_repository.dart';
import '../web/web_store.dart';
import '../web/web_workspace_controllers.dart';
import 'app_capabilities.dart';
import 'ui_feature_manifest.dart';
import 'app_controller_web_core.dart';
import 'app_controller_web_sessions.dart';
import 'app_controller_web_workspace.dart';
import 'app_controller_web_session_actions.dart';
import 'app_controller_web_gateway_relay.dart';
import 'app_controller_web_gateway_chat.dart';
import 'app_controller_web_helpers.dart';

extension AppControllerWebGatewayConfig on AppController {
  Future<void> saveAiGatewayConfiguration({
    required String name,
    required String baseUrl,
    required String provider,
    required String apiKey,
    required String defaultModel,
  }) async {
    final normalizedBaseUrl = aiGatewayClientInternal.normalizeBaseUrl(baseUrl);
    settingsInternal = settingsInternal.copyWith(
      defaultProvider: provider.trim().isEmpty ? 'gateway' : provider.trim(),
      defaultModel: defaultModel.trim(),
      aiGateway: settingsInternal.aiGateway.copyWith(
        name: name.trim().isEmpty ? 'Single Agent' : name.trim(),
        baseUrl: normalizedBaseUrl?.toString() ?? baseUrl.trim(),
      ),
    );
    aiGatewayApiKeyCacheInternal = apiKey.trim();
    await storeInternal.saveAiGatewayApiKey(aiGatewayApiKeyCacheInternal);
    await persistSettingsInternal();
    notifyChangedInternal();
  }

  Future<AiGatewayConnectionCheck> testAiGatewayConnection({
    required String baseUrl,
    required String apiKey,
  }) async {
    aiGatewayBusyInternal = true;
    notifyChangedInternal();
    try {
      return await aiGatewayClientInternal.testConnection(
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
    } finally {
      aiGatewayBusyInternal = false;
      notifyChangedInternal();
    }
  }

  Future<void> syncAiGatewayModels({
    required String name,
    required String baseUrl,
    required String provider,
    required String apiKey,
  }) async {
    aiGatewayBusyInternal = true;
    notifyChangedInternal();
    try {
      final models = await aiGatewayClientInternal.loadModels(
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      final availableModels = models
          .map((item) => item.id)
          .toList(growable: false);
      final selectedModels = availableModels.take(5).toList(growable: false);
      final resolvedDefaultModel =
          settingsInternal.defaultModel.trim().isNotEmpty &&
              availableModels.contains(settingsInternal.defaultModel.trim())
          ? settingsInternal.defaultModel.trim()
          : selectedModels.isNotEmpty
          ? selectedModels.first
          : '';
      settingsInternal = settingsInternal.copyWith(
        defaultProvider: provider.trim().isEmpty ? 'gateway' : provider.trim(),
        defaultModel: resolvedDefaultModel,
        aiGateway: settingsInternal.aiGateway.copyWith(
          name: name.trim().isEmpty ? 'Single Agent' : name.trim(),
          baseUrl:
              aiGatewayClientInternal.normalizeBaseUrl(baseUrl)?.toString() ??
              baseUrl.trim(),
          availableModels: availableModels,
          selectedModels: selectedModels,
          syncState: 'ready',
          syncMessage: 'Loaded ${availableModels.length} model(s)',
        ),
      );
      aiGatewayApiKeyCacheInternal = apiKey.trim();
      await storeInternal.saveAiGatewayApiKey(aiGatewayApiKeyCacheInternal);
      await persistSettingsInternal();
      recomputeDerivedWorkspaceStateInternal();
    } catch (error) {
      settingsInternal = settingsInternal.copyWith(
        aiGateway: settingsInternal.aiGateway.copyWith(
          syncState: 'error',
          syncMessage: aiGatewayClientInternal.networkErrorLabel(error),
        ),
      );
      await persistSettingsInternal();
      recomputeDerivedWorkspaceStateInternal();
      rethrow;
    } finally {
      aiGatewayBusyInternal = false;
      notifyChangedInternal();
    }
  }

  Future<void> saveRelayConfiguration({
    required String host,
    required int port,
    required bool tls,
    required String token,
    required String password,
    int profileIndex = kGatewayRemoteProfileIndex,
  }) async {
    final baseProfile = profileIndex == kGatewayLocalProfileIndex
        ? settingsInternal.primaryLocalGatewayProfile
        : settingsInternal.primaryRemoteGatewayProfile;
    final mode = profileIndex == kGatewayLocalProfileIndex
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    settingsInternal = settingsInternal.copyWith(
      gatewayProfiles: replaceGatewayProfileAt(
        settingsInternal.gatewayProfiles,
        profileIndex,
        baseProfile.copyWith(
          mode: mode,
          useSetupCode: false,
          setupCode: '',
          host: host.trim(),
          port: port,
          tls: mode == RuntimeConnectionMode.local ? false : tls,
        ),
      ),
    ).markGatewayTargetSaved(
      profileIndex == kGatewayLocalProfileIndex
          ? AssistantExecutionTarget.local
          : AssistantExecutionTarget.remote,
    );
    relayTokenByProfileInternal[profileIndex] = token.trim();
    relayPasswordByProfileInternal[profileIndex] = password.trim();
    await storeInternal.saveRelayToken(
      relayTokenByProfileInternal[profileIndex] ?? '',
      profileIndex: profileIndex,
    );
    await storeInternal.saveRelayPassword(
      relayPasswordByProfileInternal[profileIndex] ?? '',
      profileIndex: profileIndex,
    );
    await persistSettingsInternal();
    notifyChangedInternal();
  }

  Future<void> applyRelayConfiguration({
    required int profileIndex,
    required String host,
    required int port,
    required bool tls,
    required String token,
    required String password,
  }) async {
    await saveRelayConfiguration(
      profileIndex: profileIndex,
      host: host,
      port: port,
      tls: tls,
      token: token,
      password: password,
    );
    final currentTarget = assistantExecutionTargetForSession(
      currentSessionKeyInternal,
    );
    final currentProfileIndex = profileIndexForTargetInternal(currentTarget);
    if (currentProfileIndex == profileIndex) {
      await connectRelay(target: currentTarget);
    }
  }
}
