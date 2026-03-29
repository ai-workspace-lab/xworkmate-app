// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/app_store_policy.dart';
import '../../app/ui_feature_manifest.dart';
import '../../app/workspace_navigation.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/gateway_runtime.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import 'codex_integration_card.dart';
import 'skill_directory_authorization_card.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';
import 'settings_page_core.dart';
import 'settings_page_sections.dart';
import 'settings_page_gateway.dart';
import 'settings_page_gateway_connection.dart';
import 'settings_page_presentation.dart';
import 'settings_page_multi_agent.dart';
import 'settings_page_support.dart';
import 'settings_page_device.dart';
import 'settings_page_widgets.dart';

extension SettingsPageGatewayLlmMixinInternal on SettingsPageStateInternal {
  Widget buildAiGatewayCardBodyInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    syncDraftControllerValueInternal(
      aiGatewayNameControllerInternal,
      settings.aiGateway.name,
      syncedValue: aiGatewayNameSyncedValueInternal,
      onSyncedValueChanged: (value) => aiGatewayNameSyncedValueInternal = value,
    );
    syncDraftControllerValueInternal(
      aiGatewayUrlControllerInternal,
      settings.aiGateway.baseUrl,
      syncedValue: aiGatewayUrlSyncedValueInternal,
      onSyncedValueChanged: (value) => aiGatewayUrlSyncedValueInternal = value,
    );
    syncDraftControllerValueInternal(
      aiGatewayApiKeyRefControllerInternal,
      settings.aiGateway.apiKeyRef,
      syncedValue: aiGatewayApiKeyRefSyncedValueInternal,
      onSyncedValueChanged: (value) =>
          aiGatewayApiKeyRefSyncedValueInternal = value,
    );
    final selectedModels = settings.aiGateway.selectedModels.isNotEmpty
        ? settings.aiGateway.selectedModels
        : settings.aiGateway.availableModels.take(5).toList(growable: false);
    final filteredModels = filterAiGatewayModelsInternal(
      settings.aiGateway.availableModels,
    );
    final hasStoredAiGatewayApiKey =
        controller.settingsController.secureRefs['ai_gateway_api_key'] != null;
    final statusTheme = aiGatewayFeedbackThemeInternal(
      context,
      aiGatewayTestMessageInternal.isEmpty
          ? settings.aiGateway.syncState
          : aiGatewayTestStateInternal,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('ai-gateway-name-field'),
          controller: aiGatewayNameControllerInternal,
          decoration: InputDecoration(
            labelText: appText('配置名称', 'Profile Name'),
          ),
          onChanged: (_) => unawaited(
            saveAiGatewayDraftInternal(controller, settings).catchError((_) {}),
          ),
          onSubmitted: (_) => saveAiGatewayDraftInternal(controller, settings),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('ai-gateway-url-field'),
          controller: aiGatewayUrlControllerInternal,
          decoration: InputDecoration(
            labelText: appText('LLM API Endpoint', 'LLM API Endpoint'),
          ),
          onChanged: (_) => unawaited(
            saveAiGatewayDraftInternal(controller, settings).catchError((_) {}),
          ),
          onSubmitted: (_) => saveAiGatewayDraftInternal(controller, settings),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('ai-gateway-api-key-ref-field'),
          controller: aiGatewayApiKeyRefControllerInternal,
          decoration: InputDecoration(
            labelText: appText('LLM API Token 引用', 'LLM API Token Ref'),
          ),
          onChanged: (_) => unawaited(
            saveAiGatewayDraftInternal(controller, settings).catchError((_) {}),
          ),
          onSubmitted: (_) => saveAiGatewayDraftInternal(controller, settings),
        ),
        buildSecureFieldInternal(
          fieldKey: const ValueKey('ai-gateway-api-key-field'),
          controller: aiGatewayApiKeyControllerInternal,
          label:
              '${appText('LLM API Token', 'LLM API Token')} (${aiGatewayApiKeyRefControllerInternal.text.trim().isEmpty ? settings.aiGateway.apiKeyRef : aiGatewayApiKeyRefControllerInternal.text.trim()})',
          hasStoredValue: hasStoredAiGatewayApiKey,
          fieldState: aiGatewayApiKeyStateInternal,
          onStateChanged: (value) =>
              setStateInternal(() => aiGatewayApiKeyStateInternal = value),
          loadValue: controller.settingsController.loadAiGatewayApiKey,
          onSubmitted: (value) async =>
              controller.saveAiGatewayApiKeyDraft(value),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示；可直接测试，也可通过本区保存并生效提交。',
            'Stored securely. Test directly or submit it with the local Save & apply action.',
          ),
          emptyHelperText: appText(
            '输入后可直接测试，也可通过本区保存并生效提交。',
            'Test it now, or submit it with the local Save & apply action.',
          ),
        ),
        const SizedBox(height: 12),
        buildSettingsSectionActionsInternal(
          controller: controller,
          testKey: const ValueKey('ai-gateway-test-button'),
          applyKey: const ValueKey('ai-gateway-apply-button'),
          testing: aiGatewayTestingInternal,
          onTest: () => testAiGatewayConnectionInternal(controller, settings),
          onApply: () => saveAiGatewayAndApplyInternal(controller, settings),
        ),
        const SizedBox(height: 12),
        Text(
          settings.aiGateway.syncMessage,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (aiGatewayTestMessageInternal.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('ai-gateway-test-feedback'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusTheme.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  aiGatewayTestMessageInternal,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: statusTheme.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (aiGatewayTestEndpointInternal.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    aiGatewayTestEndpointInternal,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: statusTheme.foreground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (settings.aiGateway.availableModels.isNotEmpty) ...[
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('ai-gateway-model-search'),
            controller: aiGatewayModelSearchControllerInternal,
            decoration: InputDecoration(
              labelText: appText('搜索模型', 'Search models'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon:
                  aiGatewayModelSearchControllerInternal.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: appText('清空搜索', 'Clear search'),
                      onPressed: () {
                        aiGatewayModelSearchControllerInternal.clear();
                        setStateInternal(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
            onChanged: (_) => setStateInternal(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                appText(
                  '已选 ${selectedModels.length} / ${settings.aiGateway.availableModels.length}',
                  'Selected ${selectedModels.length} / ${settings.aiGateway.availableModels.length}',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              OutlinedButton(
                key: const ValueKey('ai-gateway-select-filtered'),
                onPressed: filteredModels.isEmpty
                    ? null
                    : () async {
                        await controller.updateAiGatewaySelection(
                          <String>{
                            ...selectedModels,
                            ...filteredModels,
                          }.toList(growable: false),
                        );
                      },
                child: Text(appText('选择筛选结果', 'Select filtered')),
              ),
              OutlinedButton(
                key: const ValueKey('ai-gateway-reset-default'),
                onPressed: () async {
                  await controller.updateAiGatewaySelection(
                    settings.aiGateway.availableModels
                        .take(5)
                        .toList(growable: false),
                  );
                },
                child: Text(appText('恢复默认 5 个', 'Reset default 5')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (filteredModels.isEmpty)
            Text(
              appText('没有匹配的模型。', 'No matching models.'),
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filteredModels
                  .map((modelId) {
                    final selected = selectedModels.contains(modelId);
                    return FilterChip(
                      label: Text(modelId),
                      selected: selected,
                      onSelected: (_) async {
                        final nextSelection = selected
                            ? selectedModels
                                  .where((item) => item != modelId)
                                  .toList(growable: true)
                            : <String>[...selectedModels, modelId];
                        await controller.updateAiGatewaySelection(
                          nextSelection,
                        );
                      },
                    );
                  })
                  .toList(growable: false),
            ),
        ],
      ],
    );
  }

  Widget buildOllamaLocalEndpointBodyInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EditableFieldInternal(
          label: appText('服务地址', 'Endpoint'),
          value: settings.ollamaLocal.endpoint,
          onSubmitted: (value) => saveSettingsInternal(
            controller,
            settings.copyWith(
              ollamaLocal: settings.ollamaLocal.copyWith(endpoint: value),
            ),
          ),
        ),
        EditableFieldInternal(
          label: appText('默认模型', 'Default Model'),
          value: settings.ollamaLocal.defaultModel,
          onSubmitted: (value) => saveSettingsInternal(
            controller,
            settings.copyWith(
              ollamaLocal: settings.ollamaLocal.copyWith(defaultModel: value),
            ),
          ),
        ),
        SwitchRowInternal(
          label: appText('自动发现', 'Auto Discover'),
          value: settings.ollamaLocal.autoDiscover,
          onChanged: (value) => saveSettingsInternal(
            controller,
            settings.copyWith(
              ollamaLocal: settings.ollamaLocal.copyWith(autoDiscover: value),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => controller.testOllamaConnection(cloud: false),
            child: Text(
              '${appText('测试连接', 'Test Connection')} · ${controller.settingsController.ollamaStatus}',
            ),
          ),
        ),
      ],
    );
  }

  Widget buildOllamaCloudEndpointBodyInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final hasStoredOllamaApiKey =
        controller.settingsController.secureRefs['ollama_cloud_api_key'] !=
        null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EditableFieldInternal(
          label: appText('基础地址', 'Base URL'),
          value: settings.ollamaCloud.baseUrl,
          onSubmitted: (value) => saveSettingsInternal(
            controller,
            settings.copyWith(
              ollamaCloud: settings.ollamaCloud.copyWith(baseUrl: value),
            ),
          ),
        ),
        EditableFieldInternal(
          label: appText('工作区 / 组织', 'Workspace / Org'),
          value:
              '${settings.ollamaCloud.organization} / ${settings.ollamaCloud.workspace}',
          onSubmitted: (value) {
            final parts = value.split('/');
            saveSettingsInternal(
              controller,
              settings.copyWith(
                ollamaCloud: settings.ollamaCloud.copyWith(
                  organization: parts.isNotEmpty ? parts.first.trim() : '',
                  workspace: parts.length > 1 ? parts[1].trim() : '',
                ),
              ),
            );
          },
        ),
        EditableFieldInternal(
          label: appText('默认模型', 'Default Model'),
          value: settings.ollamaCloud.defaultModel,
          onSubmitted: (value) => saveSettingsInternal(
            controller,
            settings.copyWith(
              ollamaCloud: settings.ollamaCloud.copyWith(defaultModel: value),
            ),
          ),
        ),
        buildSecureFieldInternal(
          controller: ollamaApiKeyControllerInternal,
          label:
              '${appText('API Key', 'API Key')} (${settings.ollamaCloud.apiKeyRef})',
          hasStoredValue: hasStoredOllamaApiKey,
          fieldState: ollamaApiKeyStateInternal,
          onStateChanged: (value) =>
              setStateInternal(() => ollamaApiKeyStateInternal = value),
          loadValue: controller.settingsController.loadOllamaCloudApiKey,
          onSubmitted: (value) async =>
              controller.saveOllamaCloudApiKeyDraft(value),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示；可直接测试，也可通过本区保存并生效提交。',
            'Stored securely. Test directly or submit it with the local Save & apply action.',
          ),
          emptyHelperText: appText(
            '输入后可直接测试，也可通过本区保存并生效提交。',
            'Test it now, or submit it with the local Save & apply action.',
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => controller.testOllamaConnection(cloud: true),
            child: Text(
              '${appText('测试云端', 'Test Cloud')} · ${controller.settingsController.ollamaStatus}',
            ),
          ),
        ),
      ],
    );
  }

  int resolvedVisibleLlmEndpointCountInternal(
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final requiredCount = requiredLlmEndpointSlotCountInternal(
      controller,
      settings,
    );
    return requiredCount > llmEndpointSlotLimitInternal
        ? requiredCount
        : llmEndpointSlotLimitInternal;
  }

  int requiredLlmEndpointSlotCountInternal(
    AppController controller,
    SettingsSnapshot settings,
  ) {
    var requiredCount = 1;
    if (isOllamaLocalEndpointConfiguredInternal(settings)) {
      requiredCount = 2;
    }
    if (isOllamaCloudEndpointConfiguredInternal(controller, settings)) {
      requiredCount = 3;
    }
    return requiredCount;
  }

  bool isLlmEndpointSlotConfiguredInternal(
    AppController controller,
    SettingsSnapshot settings,
    LlmEndpointSlotInternal slot,
  ) {
    return switch (slot) {
      LlmEndpointSlotInternal.aiGateway =>
        isAiGatewayEndpointConfiguredInternal(controller, settings),
      LlmEndpointSlotInternal.ollamaLocal =>
        isOllamaLocalEndpointConfiguredInternal(settings),
      LlmEndpointSlotInternal.ollamaCloud =>
        isOllamaCloudEndpointConfiguredInternal(controller, settings),
    };
  }

  bool isAiGatewayEndpointConfiguredInternal(
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final defaults = AiGatewayProfile.defaults();
    final config = settings.aiGateway;
    return config.name.trim() != defaults.name ||
        config.baseUrl.trim().isNotEmpty ||
        config.apiKeyRef.trim() != defaults.apiKeyRef ||
        config.availableModels.isNotEmpty ||
        config.selectedModels.isNotEmpty ||
        controller.settingsController.secureRefs['ai_gateway_api_key'] != null;
  }

  bool isOllamaLocalEndpointConfiguredInternal(SettingsSnapshot settings) {
    final defaults = OllamaLocalConfig.defaults();
    final config = settings.ollamaLocal;
    return config.endpoint.trim() != defaults.endpoint ||
        config.defaultModel.trim() != defaults.defaultModel ||
        config.autoDiscover != defaults.autoDiscover;
  }

  bool isOllamaCloudEndpointConfiguredInternal(
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final defaults = OllamaCloudConfig.defaults();
    final config = settings.ollamaCloud;
    return config.baseUrl.trim() != defaults.baseUrl ||
        config.organization.trim().isNotEmpty ||
        config.workspace.trim().isNotEmpty ||
        config.defaultModel.trim() != defaults.defaultModel ||
        config.apiKeyRef.trim() != defaults.apiKeyRef ||
        controller.settingsController.secureRefs['ollama_cloud_api_key'] !=
            null;
  }
}
