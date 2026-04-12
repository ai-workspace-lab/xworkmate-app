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
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
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

Future<String> loadAiGatewayApiKeyThreadSessionInternal(
  AppController controller,
) async {
  return controller.settingsControllerInternal.loadEffectiveAiGatewayApiKey();
}

Future<void> saveMultiAgentConfigThreadSessionInternal(
  AppController controller,
  MultiAgentConfig config,
) async {
  final resolved = controller.resolveMultiAgentConfigInternal(
    controller.settings.copyWith(multiAgent: config),
  );
  await AppControllerDesktopSettings(controller).saveSettings(
    controller.settings.copyWith(multiAgent: resolved),
    refreshAfterSave: false,
  );
  await refreshMultiAgentMountsThreadSessionInternal(
    controller,
    sync: resolved.autoSync,
  );
}

Future<void> refreshMultiAgentMountsThreadSessionInternal(
  AppController controller, {
  bool sync = false,
}) async {
  final currentConfig = controller.settings.multiAgent;
  final effectiveConfig = currentConfig.copyWith(autoSync: sync);
  var nextConfig = await controller.multiAgentMountManagerInternal.reconcile(
    config: effectiveConfig,
    aiGatewayUrl: controller.aiGatewayUrl,
    configuredCodexCliPath: controller.configuredCodexCliPath,
  );
  if (nextConfig.autoSync != currentConfig.autoSync) {
    nextConfig = nextConfig.copyWith(autoSync: currentConfig.autoSync);
  }
  if (jsonEncode(nextConfig.toJson()) != jsonEncode(currentConfig.toJson())) {
    await controller.settingsControllerInternal.saveSnapshot(
      controller.settings.copyWith(multiAgent: nextConfig),
    );
    controller.multiAgentOrchestratorInternal.updateConfig(nextConfig);
  }
  await controller.refreshAcpCapabilitiesInternal(forceRefresh: true);
  if (!controller.disposedInternal) {
    controller.notifyListeners();
  }
}

Future<void> runMultiAgentCollaborationThreadSessionInternal(
  AppController controller, {
  required String rawPrompt,
  required String composedPrompt,
  required List<CollaborationAttachment> attachments,
  required List<String> selectedSkillLabels,
}) async {
  final sessionKey = controller.currentSessionKey.trim().isEmpty
      ? 'main'
      : controller.currentSessionKey;
  await controller.enqueueThreadTurnInternal<void>(sessionKey, () async {
    if (controller.resolveExternalAcpEndpointForTargetInternal(
          controller.assistantExecutionTargetForSession(sessionKey),
        ) ==
        null) {
      final error = StateError(
        appText(
          'BRIDGE_SERVER_URL 未配置，无法启动任务对话。',
          'BRIDGE_SERVER_URL is unavailable, so task chat cannot start.',
        ),
      );
      controller.appendLocalSessionMessageInternal(
        sessionKey,
        GatewayChatMessage(
          id: controller.nextLocalMessageIdInternal(),
          role: 'assistant',
          text: error.message.toString(),
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: 'Multi-Agent',
          stopReason: null,
          pending: false,
          error: true,
        ),
      );
      controller.recomputeTasksInternal();
      controller.notifyIfActiveInternal();
      throw error;
    }
    await controller.ensureDesktopTaskThreadBindingInternal(
      sessionKey,
      executionTarget: controller.assistantExecutionTargetForSession(
        sessionKey,
      ),
    );
    final workingDirectory = controller
        .assistantWorkingDirectoryForSessionInternal(sessionKey);
    if (workingDirectory == null || workingDirectory.trim().isEmpty) {
      final error = StateError(
        appText(
          '当前线程缺少工作路径，无法启动 Gateway 协作。',
          'This thread has no workspace path, so gateway collaboration cannot start.',
        ),
      );
      controller.appendLocalSessionMessageInternal(
        sessionKey,
        GatewayChatMessage(
          id: controller.nextLocalMessageIdInternal(),
          role: 'assistant',
          text: error.message.toString(),
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: 'Multi-Agent',
          stopReason: null,
          pending: false,
          error: true,
        ),
      );
      controller.recomputeTasksInternal();
      controller.notifyIfActiveInternal();
      throw error;
    }
    controller.multiAgentRunPendingInternal = true;
    controller.appendLocalSessionMessageInternal(
      sessionKey,
      GatewayChatMessage(
        id: controller.nextLocalMessageIdInternal(),
        role: 'user',
        text: rawPrompt,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        toolCallId: null,
        toolName: null,
        stopReason: null,
        pending: false,
        error: false,
      ),
    );
    controller.recomputeTasksInternal();
    try {
      final result = await controller.goTaskServiceClientInternal.executeTask(
        GoTaskServiceRequest(
          sessionId: sessionKey,
          threadId: sessionKey,
          target: controller.assistantExecutionTargetForSession(sessionKey),
          prompt: composedPrompt,
          workingDirectory: workingDirectory,
          model: controller.assistantModelForSession(sessionKey),
          thinking: 'medium',
          selectedSkills: selectedSkillLabels,
          inlineAttachments: const <GatewayChatAttachmentPayload>[],
          localAttachments: attachments,
          agentId: '',
          metadata: const <String, dynamic>{},
          routingHint: 'gateway',
          collaborationMode: GoTaskServiceCollaborationMode.standard,
          resumeSession: true,
        ),
        onUpdate: (update) {
          final text = update.text.trim().isNotEmpty
              ? update.text.trim()
              : update.message.trim();
          if (text.isEmpty) {
            return;
          }
          controller.appendLocalSessionMessageInternal(
            sessionKey,
            GatewayChatMessage(
              id: controller.nextLocalMessageIdInternal(),
              role: 'assistant',
              text: text,
              timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
              toolCallId: null,
              toolName: 'Multi-Agent',
              stopReason: null,
              pending: update.pending,
              error: update.error,
            ),
          );
        },
      );
      await controller.persistGoTaskArtifactsForSessionInternal(
        sessionKey,
        result,
      );
      controller.appendLocalSessionMessageInternal(
        sessionKey,
        GatewayChatMessage(
          id: controller.nextLocalMessageIdInternal(),
          role: 'assistant',
          text: result.success
              ? (result.message.trim().isNotEmpty
                    ? result.message.trim()
                    : appText(
                        '多 Agent 协作完成。',
                        'Multi-agent collaboration completed.',
                      ))
              : appText(
                  '多 Agent 协作失败：${result.errorMessage.trim().isEmpty ? result.message : result.errorMessage}',
                  'Multi-agent collaboration failed: ${result.errorMessage.trim().isEmpty ? result.message : result.errorMessage}',
                ),
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: 'Multi-Agent',
          stopReason: null,
          pending: false,
          error: !result.success,
        ),
      );
    } on GatewayAcpException catch (error) {
      controller.appendLocalSessionMessageInternal(
        sessionKey,
        GatewayChatMessage(
          id: controller.nextLocalMessageIdInternal(),
          role: 'assistant',
          text: appText(
            '多 Agent 协作不可用（ACP）：${error.message}',
            'Multi-agent collaboration is unavailable (ACP): ${error.message}',
          ),
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: 'Multi-Agent',
          stopReason: null,
          pending: false,
          error: true,
        ),
      );
    } catch (error) {
      controller.appendLocalSessionMessageInternal(
        sessionKey,
        GatewayChatMessage(
          id: controller.nextLocalMessageIdInternal(),
          role: 'assistant',
          text: error.toString(),
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: 'Multi-Agent',
          stopReason: null,
          pending: false,
          error: true,
        ),
      );
    } finally {
      controller.multiAgentRunPendingInternal = false;
      controller.recomputeTasksInternal();
      controller.notifyIfActiveInternal();
    }
  });
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
  final normalizedSessionKey = normalizeAssistantSessionKeyThreadInternal(
    sessionKey,
  );
  final target = controller.assistantExecutionTargetForSession(
    normalizedSessionKey,
  );
  if (target == AssistantExecutionTarget.singleAgent) {
    final singleAgentUsesAiGatewayFallback =
        !controller.hasAnyAvailableSingleAgentProvider &&
        controller.canUseAiGatewayConversation;
    if (singleAgentUsesAiGatewayFallback) {
      return controller.aiGatewayConversationModelChoices;
    }
    final runtimeModel = controller.singleAgentRuntimeModelForSession(
      normalizedSessionKey,
    );
    if (runtimeModel.isNotEmpty) {
      return <String>[runtimeModel];
    }
    return const <String>[];
  }
  final runtimeModels = connectedGatewayModelChoicesThreadSessionInternal(
    controller,
  );
  if (runtimeModels.isNotEmpty) {
    return runtimeModels;
  }
  final resolved = resolvedDefaultModelThreadSessionInternal(controller).trim();
  if (resolved.isNotEmpty) {
    return <String>[resolved];
  }
  final localDefault = controller.settings.ollamaLocal.defaultModel.trim();
  if (localDefault.isNotEmpty) {
    return <String>[localDefault];
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
  if (target == AssistantExecutionTarget.singleAgent) {
    return false;
  }
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
  if (profile.mode == RuntimeConnectionMode.local) {
    return true;
  }
  final defaults = switch (target) {
    AssistantExecutionTarget.singleAgent => GatewayConnectionProfile.emptySlot(
      index: kGatewayRemoteProfileIndex,
    ),
    AssistantExecutionTarget.gateway => GatewayConnectionProfile.defaults(),
  };
  return controller.hasStoredGatewayCredential ||
      host != defaults.host ||
      profile.port != defaults.port ||
      profile.tls != defaults.tls ||
      profile.mode != defaults.mode;
}

String normalizeAssistantSessionKeyThreadInternal(String sessionKey) {
  final trimmed = sessionKey.trim();
  return trimmed.isEmpty ? 'main' : trimmed;
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
