// ignore_for_file: unused_import, unnecessary_import, invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

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
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_thread_binding.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

Future<String> loadAiGatewayApiKeyThreadSessionInternal(
  AppController controller,
) async {
  return controller.settingsControllerInternal.loadEffectiveAiGatewayApiKey();
}

Future<void> openOnlineWorkspaceThreadSessionInternal(
  AppController controller,
) async {
  const url = 'https://www.svc.plus/Xworkmate';
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
      return;
    }
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
      return;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    }
  } catch (_) {
    // Best effort only. Do not surface a blocking error from a convenience link.
  }
}

List<String> aiGatewayModelChoicesThreadSessionInternal(
  AppController controller,
) {
  return controller.aiGatewayConversationModelChoices;
}

List<String> connectedGatewayModelChoicesThreadSessionInternal(
  AppController controller,
) {
  if (controller.connection.status != RuntimeConnectionStatus.connected) {
    return const <String>[];
  }
  return controller.modelsControllerInternal.items
      .map((item) => item.id.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<String> assistantModelChoicesThreadSessionInternal(
  AppController controller,
) {
  return assistantModelChoicesForSessionThreadSessionInternal(
    controller,
    controller.currentSessionKey,
  );
}

List<String> assistantModelChoicesForSessionThreadSessionInternal(
  AppController controller,
  String sessionKey,
) {
  final target = controller.assistantExecutionTargetForSession(sessionKey);
  if (target.isGateway) {
    return connectedGatewayModelChoicesThreadSessionInternal(controller);
  }
  final aiGatewayModels = controller.aiGatewayConversationModelChoices;
  if (aiGatewayModels.isNotEmpty) {
    return aiGatewayModels;
  }
  return const <String>[];
}

String resolvedDefaultModelThreadSessionInternal(AppController controller) {
  final current = controller.settings.defaultModel.trim();
  if (current.isNotEmpty) {
    return current;
  }
  final localDefault = controller.settings.ollamaLocal.defaultModel.trim();
  if (localDefault.isNotEmpty) {
    return localDefault;
  }
  final runtimeModels = connectedGatewayModelChoicesThreadSessionInternal(
    controller,
  );
  if (runtimeModels.isNotEmpty) {
    return runtimeModels.first;
  }
  final aiGatewayChoices = controller.aiGatewayConversationModelChoices;
  if (aiGatewayChoices.isNotEmpty) {
    return aiGatewayChoices.first;
  }
  return '';
}

bool canQuickConnectGatewayThreadSessionInternal(AppController controller) {
  final target = controller.currentAssistantExecutionTarget;
  final profile = controller.gatewayProfileForAssistantExecutionTargetInternal(
    target,
  );
  if (profile.useSetupCode && profile.setupCode.trim().isNotEmpty) {
    return true;
  }
  final host = profile.host.trim();
  if (host.isEmpty || profile.port <= 0) {
    return false;
  }
  final defaults = GatewayConnectionProfile.defaults();
  return controller.hasStoredGatewayCredential ||
      host != defaults.host ||
      profile.port != defaults.port ||
      profile.tls != defaults.tls ||
      profile.mode != defaults.mode;
}

String joinConnectionPartsThreadSessionInternal(List<String> parts) {
  final normalized = parts
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return normalized.join(' · ');
}

String gatewayAddressLabelThreadSessionInternal(
  GatewayConnectionProfile profile,
) {
  final host = profile.host.trim();
  if (host.isEmpty || profile.port <= 0) {
    return appText('未连接目标', 'No target');
  }
  return '$host:${profile.port}';
}
