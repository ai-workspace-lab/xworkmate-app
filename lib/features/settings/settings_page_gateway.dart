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
import 'settings_page_gateway_connection.dart';
import 'settings_page_gateway_llm.dart';
import 'settings_page_presentation.dart';
import 'settings_page_multi_agent.dart';
import 'settings_page_support.dart';
import 'settings_page_device.dart';
import 'settings_page_widgets.dart';

extension SettingsPageGatewayMixinInternal on SettingsPageStateInternal {
  List<Widget> buildGatewayInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
  ) {
    if (!widget.showSectionTabs) {
      return buildUnifiedGatewaySectionsInternal(
        context,
        controller,
        settings,
        uiFeatures,
      );
    }
    final tabLabel = switch (integrationSubTabInternal) {
      GatewayIntegrationSubTabInternal.gateway => 'OpenClaw Gateway',
      GatewayIntegrationSubTabInternal.vault => appText(
        'Vault Server',
        'Vault Server',
      ),
      GatewayIntegrationSubTabInternal.llm => appText(
        'LLM 接入点',
        'LLM Endpoints',
      ),
      GatewayIntegrationSubTabInternal.acp => appText(
        'ACP 外部接入',
        'External ACP',
      ),
      GatewayIntegrationSubTabInternal.skills => appText(
        'SKILLS 目录授权',
        'SKILLS Directory Authorization',
      ),
    };
    return [
      SectionTabs(
        items: <String>[
          'OpenClaw Gateway',
          appText('Vault Server', 'Vault Server'),
          appText('LLM 接入点', 'LLM Endpoints'),
          appText('ACP 外部接入', 'External ACP'),
          appText('SKILLS 目录授权', 'SKILLS Directory Authorization'),
        ],
        value: tabLabel,
        onChanged: (value) => setStateInternal(() {
          integrationSubTabInternal = switch (value) {
            'OpenClaw Gateway' => GatewayIntegrationSubTabInternal.gateway,
            _ when value == appText('Vault Server', 'Vault Server') =>
              GatewayIntegrationSubTabInternal.vault,
            _ when value == appText('LLM 接入点', 'LLM Endpoints') =>
              GatewayIntegrationSubTabInternal.llm,
            _ when value == appText('ACP 外部接入', 'External ACP') =>
              GatewayIntegrationSubTabInternal.acp,
            _ => GatewayIntegrationSubTabInternal.skills,
          };
        }),
      ),
      const SizedBox(height: 16),
      ...switch (integrationSubTabInternal) {
        GatewayIntegrationSubTabInternal.gateway => <Widget>[
          buildCollapsibleGatewaySectionInternal(
            context: context,
            title: 'OpenClaw Gateway',
            expanded: openClawGatewayExpandedInternal,
            onChanged: (value) => setStateInternal(() {
              openClawGatewayExpandedInternal = value;
            }),
            child: buildOpenClawGatewayCardInternal(
              context,
              controller,
              settings,
            ),
          ),
        ],
        GatewayIntegrationSubTabInternal.vault => <Widget>[
          if (uiFeatures.supportsVaultServer)
            buildCollapsibleGatewaySectionInternal(
              context: context,
              title: appText('Vault Server', 'Vault Server'),
              expanded: vaultServerExpandedInternal,
              onChanged: (value) => setStateInternal(() {
                vaultServerExpandedInternal = value;
              }),
              child: buildVaultProviderCardInternal(
                context,
                controller,
                settings,
              ),
            )
          else
            SurfaceCard(
              borderWidth: settingsHairlineBorderWidthInternal,
              child: Text(
                appText(
                  '当前发布配置未开放 Vault Server 参数。',
                  'Vault Server settings are disabled in this release configuration.',
                ),
              ),
            ),
        ],
        GatewayIntegrationSubTabInternal.llm => <Widget>[
          buildCollapsibleGatewaySectionInternal(
            context: context,
            title: appText('LLM 接入点', 'LLM Endpoints'),
            expanded: aiGatewayExpandedInternal,
            onChanged: (value) => setStateInternal(() {
              aiGatewayExpandedInternal = value;
            }),
            child: buildLlmEndpointManagerInternal(
              context,
              controller,
              settings,
            ),
          ),
        ],
        GatewayIntegrationSubTabInternal.acp => <Widget>[
          buildCollapsibleGatewaySectionInternal(
            context: context,
            title: appText(
              '外部 ACP Server Endpoint',
              'External ACP Server Endpoints',
            ),
            expanded: externalAcpExpandedInternal,
            onChanged: (value) => setStateInternal(() {
              externalAcpExpandedInternal = value;
            }),
            child: buildExternalAcpEndpointManagerInternal(
              context,
              controller,
              settings,
            ),
          ),
        ],
        GatewayIntegrationSubTabInternal.skills => <Widget>[
          SkillDirectoryAuthorizationCard(controller: controller),
        ],
      },
    ];
  }

  List<Widget> buildUnifiedGatewaySectionsInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
  ) {
    return [
      buildCollapsibleGatewaySectionInternal(
        context: context,
        title: 'OpenClaw Gateway',
        expanded: openClawGatewayExpandedInternal,
        onChanged: (value) => setStateInternal(() {
          openClawGatewayExpandedInternal = value;
        }),
        child: buildOpenClawGatewayCardInternal(context, controller, settings),
      ),
      const SizedBox(height: 16),
      if (uiFeatures.supportsVaultServer)
        buildCollapsibleGatewaySectionInternal(
          context: context,
          title: appText('Vault Server', 'Vault Server'),
          expanded: vaultServerExpandedInternal,
          onChanged: (value) => setStateInternal(() {
            vaultServerExpandedInternal = value;
          }),
          child: buildVaultProviderCardInternal(context, controller, settings),
        )
      else
        SurfaceCard(
          borderWidth: settingsHairlineBorderWidthInternal,
          child: Text(
            appText(
              '当前发布配置未开放 Vault Server 参数。',
              'Vault Server settings are disabled in this release configuration.',
            ),
          ),
        ),
      const SizedBox(height: 16),
      buildCollapsibleGatewaySectionInternal(
        context: context,
        title: appText('LLM 接入点', 'LLM Endpoints'),
        expanded: aiGatewayExpandedInternal,
        onChanged: (value) => setStateInternal(() {
          aiGatewayExpandedInternal = value;
        }),
        child: buildLlmEndpointManagerInternal(context, controller, settings),
      ),
      const SizedBox(height: 16),
      buildCollapsibleGatewaySectionInternal(
        context: context,
        title: appText(
          '外部 ACP Server Endpoint',
          'External ACP Server Endpoints',
        ),
        expanded: externalAcpExpandedInternal,
        onChanged: (value) => setStateInternal(() {
          externalAcpExpandedInternal = value;
        }),
        child: buildExternalAcpEndpointManagerInternal(
          context,
          controller,
          settings,
        ),
      ),
      const SizedBox(height: 16),
      SkillDirectoryAuthorizationCard(controller: controller),
    ];
  }

  Widget buildExternalAcpEndpointManagerInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appText(
            '这里保留 Codex、OpenCode 作为内建接入。更多 Provider 请通过向导新增自定义 ACP Server Endpoint；历史上真正配置过的 Claude / Gemini 会迁移为自定义条目，空白旧预设会自动清理。',
            'Codex and OpenCode stay here as built-in integrations. Add more providers through the custom ACP endpoint wizard; configured legacy Claude and Gemini entries are migrated into custom entries, while empty legacy presets are cleaned up automatically.',
          ),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const ValueKey('external-acp-provider-add-button'),
            onPressed: () => showAddExternalAcpProviderWizardInternal(
              context,
              controller,
              settings,
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(
              appText('添加更多自定义配置', 'Add more custom configurations'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...settings.externalAcpEndpoints.map(
          (profile) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: buildExternalAcpProviderCardInternal(
              context,
              controller,
              settings,
              profile,
            ),
          ),
        ),
      ],
    );
  }

  Widget buildExternalAcpProviderCardInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    ExternalAcpEndpointProfile profile,
  ) {
    final provider = profile.toProvider();
    final endpoint = profile.endpoint.trim();
    final configured = endpoint.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  provider.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (!profile.isPreset) ...[
                IconButton(
                  tooltip: appText('删除 Provider', 'Remove provider'),
                  onPressed: () => saveSettingsInternal(
                    controller,
                    settings.copyWith(
                      externalAcpEndpoints: settings.externalAcpEndpoints
                          .where(
                            (item) => item.providerKey != profile.providerKey,
                          )
                          .toList(growable: false),
                    ),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                const SizedBox(width: 4),
              ],
              StatusChipInternal(
                label: configured
                    ? appText('已配置', 'Configured')
                    : appText('未配置', 'Empty'),
                tone: configured
                    ? StatusChipToneInternal.ready
                    : StatusChipToneInternal.idle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          EditableFieldInternal(
            label: appText('显示名称', 'Display name'),
            value: profile.label,
            onSubmitted: (value) => saveSettingsInternal(
              controller,
              settings.copyWithExternalAcpEndpointForProvider(
                provider,
                profile.copyWith(label: value),
              ),
            ),
          ),
          EditableFieldInternal(
            label: appText('ACP Server Endpoint', 'ACP Server Endpoint'),
            value: endpoint,
            onSubmitted: (value) => saveSettingsInternal(
              controller,
              settings.copyWithExternalAcpEndpointForProvider(
                provider,
                profile.copyWith(endpoint: value),
              ),
            ),
          ),
          Text(
            appText(
              '示例：ws://127.0.0.1:9001、wss://acp.example.com/rpc、http://127.0.0.1:8080、https://agent.example.com',
              'Examples: ws://127.0.0.1:9001, wss://acp.example.com/rpc, http://127.0.0.1:8080, https://agent.example.com',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> showAddExternalAcpProviderWizardInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final nameController = TextEditingController();
    final endpointController = TextEditingController();
    var attemptedSubmit = false;
    try {
      final profile = await showDialog<ExternalAcpEndpointProfile>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final name = nameController.text.trim();
              final endpoint = endpointController.text.trim();
              final endpointValid =
                  endpoint.isEmpty || isSupportedExternalAcpEndpoint(endpoint);
              final canSubmit =
                  name.isNotEmpty && endpoint.isNotEmpty && endpointValid;
              return AlertDialog(
                title: Text(
                  appText('添加自定义 ACP Endpoint', 'Add custom ACP endpoint'),
                ),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appText(
                          '通过向导新增更多外部 Agent Provider。先填写显示名称，再输入可访问的 ACP Server Endpoint。',
                          'Use this wizard to add more external agent providers. Start with a display name, then enter a reachable ACP server endpoint.',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        appText('步骤 1 · 显示名称', 'Step 1 · Display name'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('external-acp-wizard-name-field'),
                        controller: nameController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: appText(
                            '例如：Claude Sonnet / Lab Agent',
                            'For example: Claude Sonnet / Lab Agent',
                          ),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        appText(
                          '步骤 2 · ACP Server Endpoint',
                          'Step 2 · ACP Server Endpoint',
                        ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey(
                          'external-acp-wizard-endpoint-field',
                        ),
                        controller: endpointController,
                        decoration: InputDecoration(
                          hintText: 'ws://127.0.0.1:9001',
                          errorText: attemptedSubmit && endpoint.isEmpty
                              ? appText(
                                  '请输入 ACP Server Endpoint。',
                                  'Enter an ACP server endpoint.',
                                )
                              : attemptedSubmit && !endpointValid
                              ? appText(
                                  '仅支持 ws / wss / http / https。',
                                  'Only ws / wss / http / https are supported.',
                                )
                              : null,
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        appText(
                          '支持协议：ws、wss、http、https。新增后会出现在下方列表，并和助手页的 provider 菜单保持一致。',
                          'Supported schemes: ws, wss, http, https. The new entry appears in the list below and stays aligned with the assistant provider menu.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(appText('取消', 'Cancel')),
                  ),
                  FilledButton(
                    key: const ValueKey('external-acp-wizard-confirm-button'),
                    onPressed: canSubmit
                        ? () {
                            Navigator.of(dialogContext).pop(
                              buildCustomExternalAcpEndpointProfile(
                                settings.externalAcpEndpoints,
                                label: name,
                                endpoint: endpoint,
                              ),
                            );
                          }
                        : () {
                            setDialogState(() {
                              attemptedSubmit = true;
                            });
                          },
                    child: Text(appText('添加', 'Add')),
                  ),
                ],
              );
            },
          );
        },
      );
      if (profile == null) {
        return;
      }
      await saveSettingsInternal(
        controller,
        settings.copyWith(
          externalAcpEndpoints: <ExternalAcpEndpointProfile>[
            ...settings.externalAcpEndpoints,
            profile,
          ],
        ),
      );
    } finally {
      nameController.dispose();
      endpointController.dispose();
    }
  }

  Widget buildLlmEndpointManagerInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final visibleCount = resolvedVisibleLlmEndpointCountInternal(
      controller,
      settings,
    );
    if (selectedLlmEndpointIndexInternal >= visibleCount) {
      selectedLlmEndpointIndexInternal = visibleCount - 1;
    }
    final activeSlot =
        llmEndpointSlotsInternal[selectedLlmEndpointIndexInternal];
    final canExpand = visibleCount < llmEndpointSlotsInternal.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List<Widget>.generate(visibleCount, (index) {
            return ChoiceChip(
              key: ValueKey('llm-endpoint-chip-$index'),
              selected: index == selectedLlmEndpointIndexInternal,
              avatar: const Icon(Icons.link_rounded, size: 18),
              label: Text(
                llmEndpointChipLabelInternal(controller, settings, index),
              ),
              onSelected: (_) => setStateInternal(() {
                selectedLlmEndpointIndexInternal = index;
              }),
            );
          }),
        ),
        if (canExpand) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const ValueKey('llm-endpoint-add-button'),
              onPressed: () => setStateInternal(() {
                final nextCount = (llmEndpointSlotLimitInternal + 1).clamp(
                  1,
                  llmEndpointSlotsInternal.length,
                );
                llmEndpointSlotLimitInternal = nextCount;
                selectedLlmEndpointIndexInternal = nextCount - 1;
              }),
              icon: const Icon(Icons.add_rounded),
              label: Text(appText('添加连接源', 'Add source')),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SurfaceCard(
          key: ValueKey('llm-endpoint-panel-${activeSlot.name}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appText('连接源详情', 'Source details'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              buildLlmEndpointBodyInternal(
                context,
                controller,
                settings,
                slot: activeSlot,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String llmEndpointChipLabelInternal(
    AppController controller,
    SettingsSnapshot settings,
    int index,
  ) {
    final slot = llmEndpointSlotsInternal[index];
    final configured = isLlmEndpointSlotConfiguredInternal(
      controller,
      settings,
      slot,
    );
    final label = switch (slot) {
      LlmEndpointSlotInternal.aiGateway => appText(
        '主 LLM API',
        'Primary LLM API',
      ),
      LlmEndpointSlotInternal.ollamaLocal => appText(
        'Ollama 本地',
        'Ollama Local',
      ),
      LlmEndpointSlotInternal.ollamaCloud => appText(
        'Ollama Cloud',
        'Ollama Cloud',
      ),
    };
    return appText(
      configured ? label : '$label（空）',
      configured ? label : '$label (empty)',
    );
  }

  Widget buildLlmEndpointBodyInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings, {
    required LlmEndpointSlotInternal slot,
  }) {
    return switch (slot) {
      LlmEndpointSlotInternal.aiGateway => buildAiGatewayCardBodyInternal(
        context,
        controller,
        settings,
      ),
      LlmEndpointSlotInternal.ollamaLocal =>
        buildOllamaLocalEndpointBodyInternal(context, controller, settings),
      LlmEndpointSlotInternal.ollamaCloud =>
        buildOllamaCloudEndpointBodyInternal(context, controller, settings),
    };
  }

  Widget buildCollapsibleGatewaySectionInternal({
    required BuildContext context,
    required String title,
    required bool expanded,
    required ValueChanged<bool> onChanged,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return SurfaceCard(
      borderWidth: settingsHairlineBorderWidthInternal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onChanged(!expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: expanded
                        ? appText('折叠', 'Collapse')
                        : appText('展开', 'Expand'),
                    onPressed: () => onChanged(!expanded),
                    icon: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: const Icon(Icons.expand_more_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: expanded ? child : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
