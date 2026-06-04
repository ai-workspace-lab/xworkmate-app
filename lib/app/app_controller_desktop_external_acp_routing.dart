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
import '../runtime/platform_environment.dart';
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
    final availableSkills = skills
        .map((item) {
          return ExternalCodeAgentAcpAvailableSkill(
            id: item.skillKey,
            label: item.name,
            description: item.description,
          );
        })
        .toList(growable: false);
    final selectedSkills = assistantSelectedSkillKeysForSession(
      normalizedSessionKey,
    );

    final currentTarget = assistantExecutionTargetForSession(
      normalizedSessionKey,
    );
    final resolvedProvider = assistantProviderForSession(normalizedSessionKey);
    final resolvedExecutionTarget =
        explicitExecutionTarget?.trim().isNotEmpty == true
        ? explicitExecutionTarget!.trim()
        : _routingExecutionTargetValueInternal(currentTarget);
    final resolvedExplicitProviderId =
        thread?.hasExplicitProviderSelection == true &&
            !currentTarget.isGateway &&
            !resolvedProvider.isUnspecified
        ? resolvedProvider.providerId
        : '';
    final resolvedExplicitModel =
        !currentTarget.isGateway && (thread?.hasExplicitModelSelection ?? false)
        ? assistantModelForSession(normalizedSessionKey)
        : '';
    final resolvedExplicitSkills = thread?.hasExplicitSkillSelection ?? false
        ? selectedSkills
        : const <String>[];
    return ExternalCodeAgentAcpRoutingConfig(
      mode: ExternalCodeAgentAcpRoutingMode.explicit,
      preferredGatewayTarget: preferredGatewayTarget,
      explicitExecutionTarget: resolvedExecutionTarget,
      explicitProviderId: resolvedExplicitProviderId,
      explicitModel: resolvedExplicitModel,
      explicitSkills: resolvedExplicitSkills,
      allowSkillInstall: false,
      availableSkills: availableSkills,
    );
  }

  String _routingExecutionTargetValueInternal(AssistantExecutionTarget target) {
    return target.promptValue;
  }
}
