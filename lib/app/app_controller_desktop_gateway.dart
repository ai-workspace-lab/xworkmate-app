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
import '../runtime/account_runtime_client.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_single_agent.dart';
import 'app_controller_desktop_thread_binding.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

extension AppControllerDesktopGateway on AppController {
  Future<String> resolveConnectSetupCode(String rawInput) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    if (decodeGatewaySetupCode(trimmed) != null) {
      return trimmed;
    }
    final bootstrapEnvelope = decodeBridgeBootstrapEnvelope(trimmed);
    if (bootstrapEnvelope != null) {
      final bridgeClient = AccountRuntimeClient(
        baseUrl: bootstrapEnvelope.bridgeOrigin,
      );
      final consumed = await bridgeClient.consumeBridgeBootstrapTicket(
        ticket: bootstrapEnvelope.ticket,
        bridgeOrigin: bootstrapEnvelope.bridgeOrigin,
      );
      return consumed.setupCode.trim();
    }
    if (isBridgeBootstrapShortCode(trimmed)) {
      final sessionToken =
          (await storeInternal.loadAccountSessionToken())?.trim() ?? '';
      final accountBaseUrl = settings.accountBaseUrl.trim().isNotEmpty
          ? settings.accountBaseUrl.trim()
          : settingsControllerInternal.snapshot.accountBaseUrl.trim();
      if (sessionToken.isEmpty || accountBaseUrl.isEmpty) {
        throw StateError(
          'Account sign-in is required before using a bridge verification code.',
        );
      }
      final accountClient = settingsControllerInternal.buildAccountClient(
        accountBaseUrl,
      );
      final issue = await accountClient.lookupBridgeBootstrapTicket(
        token: sessionToken,
        shortCode: trimmed,
      );
      final bridgeClient = AccountRuntimeClient(baseUrl: issue.bridgeOrigin);
      final consumed = await bridgeClient.consumeBridgeBootstrapTicket(
        ticket: issue.ticket,
        bridgeOrigin: issue.bridgeOrigin,
      );
      return consumed.setupCode.trim();
    }
    return trimmed;
  }

  Future<void> connectWithSetupCode({
    required String setupCode,
    String token = '',
    String password = '',
  }) async {
    final resolvedSetupCode = await resolveConnectSetupCode(setupCode);
    final decoded = decodeGatewaySetupCode(resolvedSetupCode);
    final resolvedToken = token.trim().isNotEmpty
        ? token.trim()
        : (decoded?.token.trim() ?? '');
    final resolvedPassword = password.trim().isNotEmpty
        ? password.trim()
        : (decoded?.password.trim() ?? '');
    final resolvedProfileIndex = gatewayProfileIndexForExecutionTargetInternal(
      assistantExecutionTargetForModeInternal(
        modeFromHostInternal(
          decoded?.host ?? settings.primaryGatewayProfile.host,
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
        decoded?.host ?? settings.primaryGatewayProfile.host,
      ),
    );
    final currentProfile = gatewayProfileForAssistantExecutionTargetInternal(
      resolvedTarget,
    );
    final nextProfile = currentProfile.copyWith(
      useSetupCode: true,
      setupCode: resolvedSetupCode.trim(),
      host: decoded?.host ?? currentProfile.host,
      port: decoded?.port ?? currentProfile.port,
      tls: decoded?.tls ?? currentProfile.tls,
      mode: RuntimeConnectionMode.remote,
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
    final sessionKey = sessionsControllerInternal.currentSessionKey;
    final ownerScope = await ensureDesktopThreadOwnerScopeInternal(sessionKey);
    final workspaceBinding = buildDesktopWorkspaceBindingInternal(
      sessionKey,
      executionTarget: resolvedTarget,
      ownerScope: ownerScope,
    );
    upsertTaskThreadInternal(
      sessionKey,
      executionTarget: resolvedTarget,
      ownerScope: ownerScope,
      workspaceBinding: workspaceBinding,
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
    final normalizedMode = RuntimeConnectionMode.remote;
    final nextTarget = assistantExecutionTargetForModeInternal(normalizedMode);
    final nextProfileIndex = gatewayProfileIndexForExecutionTargetInternal(
      nextTarget,
    );
    await settingsControllerInternal.saveGatewaySecrets(
      profileIndex: nextProfileIndex,
      token: token.trim(),
      password: password.trim(),
    );
    final resolvedHost = host.trim();
    final resolvedPort = port;
    final nextProfile =
        gatewayProfileForAssistantExecutionTargetInternal(nextTarget).copyWith(
          mode: normalizedMode,
          useSetupCode: false,
          setupCode: '',
          host: resolvedHost,
          port: resolvedPort <= 0 ? 443 : resolvedPort,
          tls: tls,
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
    final sessionKey = sessionsControllerInternal.currentSessionKey;
    final ownerScope = await ensureDesktopThreadOwnerScopeInternal(sessionKey);
    final workspaceBinding = buildDesktopWorkspaceBindingInternal(
      sessionKey,
      executionTarget: nextTarget,
      ownerScope: ownerScope,
    );
    upsertTaskThreadInternal(
      sessionKey,
      executionTarget: nextTarget,
      ownerScope: ownerScope,
      workspaceBinding: workspaceBinding,
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
    await skillsControllerInternal.refresh();
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
    await skillsControllerInternal.refresh(
      agentId: agentsControllerInternal.selectedAgentId.isEmpty
          ? null
          : agentsControllerInternal.selectedAgentId,
    );
    await modelsControllerInternal.refresh();
    await cronJobsControllerInternal.refresh();
    await devicesControllerInternal.refresh(quiet: true);
    await settingsControllerInternal.refreshDerivedState();
    await ensureCodexGatewayRegistrationInternal();
    recomputeTasksInternal();
  }
}
