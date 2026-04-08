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
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/multi_agent_orchestrator.dart';
import '../runtime/platform_environment.dart';
import '../runtime/skill_directory_access.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_single_agent.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

extension AppControllerDesktopGateway on AppController {
  Future<void> connectWithSetupCode({
    required String setupCode,
    String token = '',
    String password = '',
  }) async {
    final decoded = decodeGatewaySetupCode(setupCode);
    final resolvedToken = token.trim().isNotEmpty
        ? token.trim()
        : (decoded?.token.trim() ?? '');
    final resolvedPassword = password.trim().isNotEmpty
        ? password.trim()
        : (decoded?.password.trim() ?? '');
    final resolvedProfileIndex = gatewayProfileIndexForExecutionTargetInternal(
      assistantExecutionTargetForModeInternal(
        modeFromHostInternal(
          decoded?.host ?? settings.primaryRemoteGatewayProfile.host,
        ),
      ),
    );
    await settingsControllerInternal.saveGatewaySecrets(
      profileIndex: resolvedProfileIndex,
      token: resolvedToken,
      password: resolvedPassword,
    );
    final resolvedTarget = assistantExecutionTargetForModeInternal(
      modeFromHostInternal(
        decoded?.host ?? settings.primaryRemoteGatewayProfile.host,
      ),
    );
    final currentProfile = gatewayProfileForAssistantExecutionTargetInternal(
      resolvedTarget,
    );
    final nextProfile = currentProfile.copyWith(
      useSetupCode: true,
      setupCode: setupCode.trim(),
      host: decoded?.host ?? currentProfile.host,
      port: decoded?.port ?? currentProfile.port,
      tls: decoded?.tls ?? currentProfile.tls,
      mode: resolvedTarget == AssistantExecutionTarget.local
          ? RuntimeConnectionMode.local
          : RuntimeConnectionMode.remote,
    );
    await AppControllerDesktopSettings(this).saveSettings(
      settings
          .copyWithGatewayProfileAt(
            gatewayProfileIndexForExecutionTargetInternal(resolvedTarget),
            nextProfile,
          )
          .copyWith(assistantExecutionTarget: resolvedTarget),
      refreshAfterSave: false,
    );
    upsertTaskThreadInternal(
      sessionsControllerInternal.currentSessionKey,
      executionTarget: resolvedTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await AppControllerDesktopGateway(this).connectProfileInternal(
      nextProfile,
      profileIndex: resolvedProfileIndex,
      authTokenOverride: resolvedToken,
      authPasswordOverride: resolvedPassword,
    );
    await chatControllerInternal.loadSession(
      sessionsControllerInternal.currentSessionKey,
    );
  }

  Future<void> connectManual({
    required String host,
    required int port,
    required bool tls,
    required RuntimeConnectionMode mode,
    String token = '',
    String password = '',
  }) async {
    final nextTarget = assistantExecutionTargetForModeInternal(mode);
    final nextProfileIndex = gatewayProfileIndexForExecutionTargetInternal(
      nextTarget,
    );
    await settingsControllerInternal.saveGatewaySecrets(
      profileIndex: nextProfileIndex,
      token: token.trim(),
      password: password.trim(),
    );
    final resolvedHost =
        host.trim().isEmpty && mode == RuntimeConnectionMode.local
        ? '127.0.0.1'
        : host.trim();
    final resolvedPort = mode == RuntimeConnectionMode.local && port <= 0
        ? 18789
        : port;
    final nextProfile =
        gatewayProfileForAssistantExecutionTargetInternal(nextTarget).copyWith(
          mode: mode,
          useSetupCode: false,
          setupCode: '',
          host: resolvedHost,
          port: resolvedPort <= 0 ? 443 : resolvedPort,
          tls: mode == RuntimeConnectionMode.local ? false : tls,
        );
    await AppControllerDesktopSettings(this).saveSettings(
      settings
          .copyWithGatewayProfileAt(
            gatewayProfileIndexForExecutionTargetInternal(nextTarget),
            nextProfile,
          )
          .copyWith(assistantExecutionTarget: nextTarget),
      refreshAfterSave: false,
    );
    upsertTaskThreadInternal(
      sessionsControllerInternal.currentSessionKey,
      executionTarget: nextTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await AppControllerDesktopGateway(this).connectProfileInternal(
      nextProfile,
      profileIndex: nextProfileIndex,
      authTokenOverride: token.trim(),
      authPasswordOverride: password.trim(),
    );
    await chatControllerInternal.loadSession(
      sessionsControllerInternal.currentSessionKey,
    );
  }

  Future<void> disconnectGateway() async {
    clearCodexGatewayRegistrationInternal();
    await runtimeInternal.disconnect(clearDesiredProfile: false);
    await settingsControllerInternal.refreshDerivedState();
    await agentsControllerInternal.refresh();
    await sessionsControllerInternal.refresh();
    chatControllerInternal.clear();
    await instancesControllerInternal.refresh();
    await skillsControllerInternal.refresh();
    await connectorsControllerInternal.refresh();
    await modelsControllerInternal.refresh();
    await cronJobsControllerInternal.refresh();
    devicesControllerInternal.clear();
    recomputeTasksInternal();
  }

  Future<void> connectProfileInternal(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    final resolvedProfileIndex =
        profileIndex ??
        gatewayProfileIndexForExecutionTargetInternal(
          assistantExecutionTargetForModeInternal(profile.mode),
        );
    final effectiveAuthTokenOverride = authTokenOverride.trim().isNotEmpty
        ? authTokenOverride.trim()
        : await settingsControllerInternal.loadEffectiveGatewayToken(
            profileIndex: resolvedProfileIndex,
          );
    final effectiveAuthPasswordOverride = authPasswordOverride.trim().isNotEmpty
        ? authPasswordOverride.trim()
        : await settingsControllerInternal.loadEffectiveGatewayPassword(
            profileIndex: resolvedProfileIndex,
          );
    await runtimeInternal.connectProfile(
      profile,
      profileIndex: resolvedProfileIndex,
      authTokenOverride: effectiveAuthTokenOverride,
      authPasswordOverride: effectiveAuthPasswordOverride,
    );
    await refreshGatewayHealth();
    await refreshAgents();
    await refreshSessions();
    await instancesControllerInternal.refresh();
    await skillsControllerInternal.refresh(
      agentId: agentsControllerInternal.selectedAgentId.isEmpty
          ? null
          : agentsControllerInternal.selectedAgentId,
    );
    await connectorsControllerInternal.refresh();
    await modelsControllerInternal.refresh();
    await cronJobsControllerInternal.refresh();
    await devicesControllerInternal.refresh(quiet: true);
    await settingsControllerInternal.refreshDerivedState();
    await ensureCodexGatewayRegistrationInternal();
    recomputeTasksInternal();
  }
}
