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
import '../runtime/skill_directory_access.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_thread_sessions.dart';

extension AppControllerDesktopExternalAcpRouting on AppController {
  ExternalCodeAgentAcpRoutingConfig buildExternalAcpRoutingForSessionInternal(
    String sessionKey, {
    String? explicitExecutionTarget,
  }) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final thread = assistantThreadRecordsInternal[normalizedSessionKey];
    const preferredGatewayTarget = kCanonicalGatewayProviderId;
    final availableSkills =
        assistantImportedSkillsForSession(normalizedSessionKey)
            .map((item) {
              return ExternalCodeAgentAcpAvailableSkill(
                id: item.key,
                label: item.label,
                description: item.description,
              );
            })
            .toList(growable: false);
    final selectedSkills =
        assistantSelectedSkillsForSession(normalizedSessionKey)
            .map((item) {
              return item.label.trim().isNotEmpty ? item.label : item.key;
            })
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false);

    const resolvedExplicitProviderId = '';
    final resolvedExplicitModel = thread?.hasExplicitModelSelection ?? false
        ? assistantModelForSession(normalizedSessionKey)
        : '';
    final resolvedExplicitSkills = thread?.hasExplicitSkillSelection ?? false
        ? selectedSkills
        : const <String>[];
    final hasAnyExplicitSelection =
        (thread?.hasExplicitExecutionTargetSelection ?? false) ||
        resolvedExplicitProviderId.isNotEmpty ||
        resolvedExplicitModel.trim().isNotEmpty ||
        resolvedExplicitSkills.isNotEmpty;
    final resolvedExplicitExecutionTarget =
        explicitExecutionTarget?.trim().isNotEmpty == true
        ? explicitExecutionTarget!.trim()
        : hasAnyExplicitSelection
        ? _routingExecutionTargetValueInternal(
            assistantExecutionTargetForSession(normalizedSessionKey),
          )
        : '';
    final hasExplicitSelection =
        resolvedExplicitExecutionTarget.isNotEmpty ||
        resolvedExplicitProviderId.isNotEmpty ||
        resolvedExplicitModel.trim().isNotEmpty ||
        resolvedExplicitSkills.isNotEmpty;

    if (!hasExplicitSelection) {
      return ExternalCodeAgentAcpRoutingConfig.auto(
        preferredGatewayTarget: preferredGatewayTarget,
        availableSkills: availableSkills,
      );
    }

    return ExternalCodeAgentAcpRoutingConfig(
      mode: ExternalCodeAgentAcpRoutingMode.explicit,
      preferredGatewayTarget: preferredGatewayTarget,
      explicitExecutionTarget: resolvedExplicitExecutionTarget,
      explicitProviderId: resolvedExplicitProviderId,
      explicitModel: resolvedExplicitModel,
      explicitSkills: resolvedExplicitSkills,
      allowSkillInstall: false,
      availableSkills: availableSkills,
    );
  }

  String _routingExecutionTargetValueInternal(AssistantExecutionTarget target) {
    return switch (target) {
      AssistantExecutionTarget.gateway => 'gateway',
    };
  }
}
