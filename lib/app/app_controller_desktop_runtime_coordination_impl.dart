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
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/multi_agent_orchestrator.dart';
import '../runtime/platform_environment.dart';
import '../runtime/single_agent_runner.dart';
import '../runtime/skill_directory_access.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_single_agent.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';

Future<void> refreshAcpCapabilitiesRuntimeInternal(
  AppController controller, {
  bool forceRefresh = false,
  bool persistMountTargets = false,
}) async {
  try {
    await controller.gatewayAcpClientInternal.loadCapabilities(
      forceRefresh: forceRefresh,
    );
  } catch (_) {
    // Keep mount refresh resilient when ACP is temporarily unavailable.
  }
  if (persistMountTargets && !controller.disposedInternal) {
    final currentConfig = controller.settings.multiAgent;
    final nextConfig = await controller.multiAgentMountManagerInternal
        .reconcile(
          config: currentConfig,
          aiGatewayUrl: controller.aiGatewayUrl,
          configuredCodexCliPath: controller.configuredCodexCliPath,
        );
    if (jsonEncode(nextConfig.toJson()) != jsonEncode(currentConfig.toJson())) {
      await controller.settingsControllerInternal.saveSnapshot(
        controller.settings.copyWith(multiAgent: nextConfig),
      );
      controller.multiAgentOrchestratorInternal.updateConfig(nextConfig);
    }
  }
  if (!controller.disposedInternal) {
    controller.notifyListeners();
  }
}

Future<void> refreshSingleAgentCapabilitiesRuntimeInternal(
  AppController controller, {
  bool forceRefresh = false,
}) async {
  final capabilities = await controller.goAgentCoreClientInternal
      .loadCapabilities(
        target: AssistantExecutionTarget.singleAgent,
        forceRefresh: forceRefresh,
      );
  final next = <SingleAgentProvider, DirectSingleAgentCapabilities>{};
  for (final provider in controller.configuredSingleAgentProviders) {
    if (!capabilities.providers.contains(provider)) {
      next[provider] = const DirectSingleAgentCapabilities.unavailable(
        endpoint: '',
      );
      continue;
    }
    next[provider] = DirectSingleAgentCapabilities(
      available: true,
      supportedProviders: <SingleAgentProvider>[provider],
      endpoint: 'go-agent-core',
    );
  }
  controller.singleAgentCapabilitiesByProviderInternal = next;
  if (!controller.disposedInternal) {
    controller.notifyListeners();
  }
}

List<ManagedMountTargetState>
mergeAcpCapabilitiesIntoMountTargetsRuntimeInternal(
  AppController controller,
  List<ManagedMountTargetState> current,
  GatewayAcpCapabilities capabilities,
) {
  final source = current.isEmpty ? ManagedMountTargetState.defaults() : current;
  final providers = capabilities.providers
      .map((item) => item.providerId)
      .toSet();
  return source
      .map((item) {
        final available = switch (item.targetId) {
          'codex' => providers.contains('codex'),
          'opencode' => providers.contains('opencode'),
          'claude' => providers.contains('claude'),
          'gemini' => providers.contains('gemini'),
          'aris' => capabilities.multiAgent,
          'openclaw' => capabilities.multiAgent || capabilities.singleAgent,
          _ => false,
        };
        return item.copyWith(
          available: available,
          discoveryState: available ? 'ready' : 'unavailable',
          syncState: available ? item.syncState : 'idle',
          detail: available
              ? appText(
                  '来源：Gateway ACP capabilities',
                  'Source: Gateway ACP capabilities',
                )
              : appText(
                  'Gateway ACP 未报告该能力。',
                  'Gateway ACP did not report this capability.',
                ),
        );
      })
      .toList(growable: false);
}

String? assistantWorkingDirectoryForSessionRuntimeInternal(
  AppController controller,
  String sessionKey,
) {
  final candidate = controller
      .assistantWorkspacePathForSession(sessionKey)
      .trim();
  if (candidate.isEmpty) {
    return null;
  }
  return candidate;
}

String? resolveLocalAssistantWorkingDirectoryForSessionRuntimeInternal(
  AppController controller,
  String sessionKey, {
  bool requireLocalExistence = true,
}) {
  final record =
      controller.assistantThreadRecordsInternal[controller
          .normalizedAssistantSessionKeyInternal(sessionKey)];
  if (record?.workspaceKind != WorkspaceKind.localFs) {
    return null;
  }
  final candidate = assistantWorkingDirectoryForSessionRuntimeInternal(
    controller,
    sessionKey,
  );
  if (candidate == null) {
    return null;
  }
  final directory = Directory(candidate);
  if (directory.existsSync()) {
    return directory.path;
  }
  if (requireLocalExistence) {
    return null;
  }
  return candidate;
}

String? resolveSingleAgentWorkingDirectoryForSessionRuntimeInternal(
  AppController controller,
  String sessionKey, {
  SingleAgentProvider? provider,
}) {
  final record =
      controller.assistantThreadRecordsInternal[controller
          .normalizedAssistantSessionKeyInternal(sessionKey)];
  if (record?.workspaceKind == WorkspaceKind.remoteFs) {
    return assistantWorkingDirectoryForSessionRuntimeInternal(
      controller,
      sessionKey,
    );
  }
  return resolveLocalAssistantWorkingDirectoryForSessionRuntimeInternal(
    controller,
    sessionKey,
    requireLocalExistence:
        provider == null ||
        singleAgentProviderRequiresLocalPathRuntimeInternal(
          controller,
          provider,
        ),
  );
}

bool singleAgentProviderRequiresLocalPathRuntimeInternal(
  AppController controller,
  SingleAgentProvider provider,
) {
  final endpoint = resolveSingleAgentEndpointRuntimeInternal(
    controller,
    provider,
  );
  if (endpoint == null) {
    return true;
  }
  final scheme = endpoint.scheme.trim().toLowerCase();
  if (scheme == 'wss' || scheme == 'https') {
    return false;
  }
  final host = endpoint.host.trim();
  if (host.isEmpty) {
    return true;
  }
  final address = InternetAddress.tryParse(host);
  if (address != null) {
    return !(address.isLoopback || address.type == InternetAddressType.unix);
  }
  final normalizedHost = host.toLowerCase();
  if (normalizedHost == 'localhost') {
    return true;
  }
  return false;
}

CodeAgentNodeState buildCodeAgentNodeStateRuntimeInternal(
  AppController controller,
) {
  return CodeAgentNodeState(
    selectedAgentId: controller.agentsControllerInternal.selectedAgentId,
    gatewayConnected: controller.runtimeInternal.isConnected,
    executionTarget: controller.currentAssistantExecutionTarget,
    runtimeMode: controller.effectiveCodeAgentRuntimeMode,
    bridgeEnabled: controller.isCodexBridgeEnabledInternal,
    bridgeState: controller.codexCooperationStateInternal.name,
    preferredProviderId: 'codex',
    resolvedCodexCliPath: controller.resolvedCodexCliPathInternal,
    configuredCodexCliPath: controller.configuredCodexCliPath,
  );
}

GatewayMode bridgeGatewayModeRuntimeInternal(AppController controller) {
  if (!controller.runtimeInternal.isConnected) {
    return GatewayMode.offline;
  }
  return switch (controller.currentAssistantExecutionTarget) {
    AssistantExecutionTarget.auto => GatewayMode.offline,
    AssistantExecutionTarget.singleAgent => GatewayMode.offline,
    AssistantExecutionTarget.local => GatewayMode.local,
    AssistantExecutionTarget.remote => GatewayMode.remote,
  };
}

Future<void> ensureCodexGatewayRegistrationRuntimeInternal(
  AppController controller,
) async {
  if (!controller.isCodexBridgeEnabledInternal) {
    return;
  }

  if (!controller.runtimeInternal.isConnected) {
    controller.codexCooperationStateInternal = CodexCooperationState.bridgeOnly;
    controller.codeAgentBridgeRegistryInternal.clearRegistration();
    controller.notifyListeners();
    return;
  }

  if (controller.codeAgentBridgeRegistryInternal.isRegistered) {
    controller.codexCooperationStateInternal = CodexCooperationState.registered;
    controller.notifyListeners();
    return;
  }

  try {
    final dispatch = controller.codeAgentNodeOrchestratorInternal
        .buildGatewayDispatch(
          buildCodeAgentNodeStateRuntimeInternal(controller),
        );
    final resolvedDispatch = await dispatch;
    await controller.codeAgentBridgeRegistryInternal.register(
      agentType: 'code-agent-bridge',
      name: 'XWorkmate Codex Bridge',
      version: kAppVersion,
      transport: 'stdio-bridge',
      capabilities: const <AgentCapability>[
        AgentCapability(
          name: 'chat',
          description: 'Bridge external Codex CLI chat turns.',
        ),
        AgentCapability(
          name: 'code-edit',
          description: 'Bridge code editing tasks through Codex CLI.',
        ),
        AgentCapability(
          name: 'memory-sync',
          description: 'Coordinate memory sync through OpenClaw Gateway.',
        ),
      ],
      metadata: <String, dynamic>{
        ...resolvedDispatch.metadata,
        'providerId': 'codex',
        'runtimeMode': controller.effectiveCodeAgentRuntimeMode.name,
        'gatewayMode': bridgeGatewayModeRuntimeInternal(controller).name,
        'binaryConfigured':
            (controller.resolvedCodexCliPath ??
                    controller.configuredCodexCliPath)
                .trim()
                .isNotEmpty,
        'capabilities': const <String>[
          'chat',
          'code-edit',
          'gateway-bridge',
          'memory-sync',
        ],
      },
    );
    controller.codexCooperationStateInternal = CodexCooperationState.registered;
    controller.codexBridgeErrorInternal = null;
  } catch (error) {
    controller.codexCooperationStateInternal = CodexCooperationState.bridgeOnly;
    controller.codexBridgeErrorInternal = error.toString();
  }

  controller.notifyListeners();
}

void clearCodexGatewayRegistrationRuntimeInternal(AppController controller) {
  controller.codeAgentBridgeRegistryInternal.clearRegistration();
  if (controller.isCodexBridgeEnabledInternal) {
    controller.codexCooperationStateInternal = CodexCooperationState.bridgeOnly;
  } else {
    controller.codexCooperationStateInternal = CodexCooperationState.notStarted;
  }
  controller.notifyListeners();
}

void recomputeTasksRuntimeInternal(AppController controller) {
  controller.tasksControllerInternal.recompute(
    sessions: controller.sessions,
    cronJobs: controller.cronJobsControllerInternal.items,
    currentSessionKey: controller.sessionsControllerInternal.currentSessionKey,
    hasPendingRun: controller.hasAssistantPendingRun,
    activeAgentName: controller.agentsControllerInternal.activeAgentName,
  );
}

Uri? resolveSingleAgentEndpointRuntimeInternal(
  AppController controller,
  SingleAgentProvider provider,
) {
  final endpoint = controller.settings
      .externalAcpEndpointForProvider(provider)
      .endpoint
      .trim();
  if (endpoint.isEmpty) {
    return null;
  }
  final normalizedInput = endpoint.contains('://')
      ? endpoint
      : 'ws://$endpoint';
  final uri = Uri.tryParse(normalizedInput);
  if (uri == null || uri.host.trim().isEmpty) {
    return null;
  }
  final scheme = uri.scheme.trim().toLowerCase();
  if (scheme != 'ws' &&
      scheme != 'wss' &&
      scheme != 'http' &&
      scheme != 'https') {
    return null;
  }
  return uri;
}
