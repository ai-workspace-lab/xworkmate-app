// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'app_metadata.dart';
import 'app_capabilities.dart';
import 'app_store_policy.dart';
import 'ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/device_identity_store.dart';
import '../runtime/aris_bundle.dart';
import '../runtime/go_core.dart';
import '../runtime/runtime_bootstrap.dart';
import '../runtime/desktop_platform_service.dart';
import '../runtime/gateway_runtime.dart';
import '../runtime/runtime_controllers.dart';
import '../runtime/runtime_models.dart';
import '../runtime/secure_config_store.dart';
import '../runtime/embedded_agent_launch_policy.dart';
import '../runtime/runtime_coordinator.dart';
import '../runtime/direct_single_agent_app_server_client.dart';
import '../runtime/gateway_acp_client.dart';
import '../runtime/codex_runtime.dart';
import '../runtime/codex_config_bridge.dart';
import '../runtime/code_agent_node_orchestrator.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/desktop_thread_artifact_service.dart';
import '../runtime/go_task_service_client.dart';
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/multi_agent_orchestrator.dart';
import '../runtime/platform_environment.dart';
import '../runtime/single_agent_runner.dart';
import '../runtime/skill_directory_access.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_thread_sessions.dart';

extension AppControllerDesktopGoAgentCoreRouting on AppController {
  Future<List<ExternalCodeAgentAcpSyncedProvider>>
  buildExternalAcpSyncedProvidersInternal() async {
    final providers = <ExternalCodeAgentAcpSyncedProvider>[];
    for (final profile in settings.externalAcpEndpoints) {
      final providerId = profile.providerKey.trim();
      final endpoint = profile.endpoint.trim();
      if (providerId.isEmpty || endpoint.isEmpty) {
        continue;
      }
      final authorizationHeader = profile.authRef.trim().isEmpty
          ? ''
          : await settingsControllerInternal.resolveSecretValueInternal(
              refName: profile.authRef.trim(),
            );
      providers.add(
        ExternalCodeAgentAcpSyncedProvider(
          providerId: providerId,
          label: profile.label,
          endpoint: endpoint,
          authorizationHeader: authorizationHeader,
          enabled: profile.enabled,
        ),
      );
    }
    return providers;
  }

  Future<void> syncExternalAcpProvidersInternal() async {
    final providers = await buildExternalAcpSyncedProvidersInternal();
    syncedGoAgentProvidersInternal
      ..clear()
      ..addEntries(
        providers.map((item) => MapEntry(item.providerId.trim(), item)),
      );
    await goTaskServiceClientInternal.syncExternalProviders(providers);
  }

  void updateLatestRoutingResolutionInternal(
    String sessionKey,
    GoTaskServiceResult result,
  ) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    latestRoutingResolutionBySessionInternal[normalizedSessionKey] =
        <String, dynamic>{
          'resolvedExecutionTarget': result.resolvedExecutionTarget,
          'resolvedEndpointTarget': result.resolvedEndpointTarget,
          'resolvedProviderId': result.resolvedProviderId,
          'resolvedModel': result.resolvedModel.trim(),
          'resolvedSkills': result.resolvedSkills,
          'skillResolutionSource': result.skillResolutionSource,
          'skillCandidates': result.skillCandidates,
          'needsSkillInstall': result.needsSkillInstall,
          'skillInstallRequestId': result.skillInstallRequestId,
          'memorySources': result.memorySources,
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        };
  }
}
