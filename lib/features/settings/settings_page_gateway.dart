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
import 'settings_page_gateway_acp.dart';
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
    final advancedEditable =
        settings.acpBridgeServerModeConfig.mode ==
        AcpBridgeServerMode.advancedCustom;
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
      GatewayIntegrationSubTabInternal.advancedConfig => appText(
        '高级自定义配置',
        'Advanced Custom Configuration',
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
          appText('高级自定义配置', 'Advanced Custom Configuration'),
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
            _
                when value ==
                    appText('SKILLS 目录授权', 'SKILLS Directory Authorization') =>
              GatewayIntegrationSubTabInternal.skills,
            _ => GatewayIntegrationSubTabInternal.advancedConfig,
          };
        }),
      ),
      const SizedBox(height: 16),
      ...switch (integrationSubTabInternal) {
        GatewayIntegrationSubTabInternal.gateway => <Widget>[
          Opacity(
            opacity: advancedEditable ? 1 : 0.72,
            child: IgnorePointer(
              ignoring: !advancedEditable,
              child: buildCollapsibleGatewaySectionInternal(
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
            ),
          ),
        ],
        GatewayIntegrationSubTabInternal.vault => <Widget>[
          if (uiFeatures.supportsVaultServer)
            Opacity(
              opacity: advancedEditable ? 1 : 0.72,
              child: IgnorePointer(
                ignoring: !advancedEditable,
                child: buildCollapsibleGatewaySectionInternal(
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
                ),
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
          Opacity(
            opacity: advancedEditable ? 1 : 0.72,
            child: IgnorePointer(
              ignoring: !advancedEditable,
              child: buildCollapsibleGatewaySectionInternal(
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
            ),
          ),
        ],
        GatewayIntegrationSubTabInternal.acp => <Widget>[
          Opacity(
            opacity: advancedEditable ? 1 : 0.72,
            child: IgnorePointer(
              ignoring: !advancedEditable,
              child: buildCollapsibleGatewaySectionInternal(
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
            ),
          ),
        ],
        GatewayIntegrationSubTabInternal.skills => <Widget>[
          Opacity(
            opacity: advancedEditable ? 1 : 0.72,
            child: IgnorePointer(
              ignoring: !advancedEditable,
              child: buildCollapsibleGatewaySectionInternal(
                context: context,
                title: appText('SKILLS 目录授权', 'SKILLS Directory Authorization'),
                expanded: skillsDirectoryAuthorizationExpandedInternal,
                onChanged: (value) => setStateInternal(() {
                  skillsDirectoryAuthorizationExpandedInternal = value;
                }),
                child: SkillDirectoryAuthorizationCard(
                  controller: controller,
                  showHeader: false,
                ),
              ),
            ),
          ),
        ],
        GatewayIntegrationSubTabInternal.advancedConfig => <Widget>[
          buildOnlineAccountCardInternal(context, controller, settings),
          const SizedBox(height: 16),
          buildAcpBridgeServerModeCardInternal(context, controller, settings),
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
    final advancedEditable =
        settings.acpBridgeServerModeConfig.mode ==
        AcpBridgeServerMode.advancedCustom;
    return [
      Opacity(
        opacity: advancedEditable ? 1 : 0.72,
        child: IgnorePointer(
          ignoring: !advancedEditable,
          child: buildCollapsibleGatewaySectionInternal(
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
        ),
      ),
      const SizedBox(height: 16),
      if (uiFeatures.supportsVaultServer)
        Opacity(
          opacity: advancedEditable ? 1 : 0.72,
          child: IgnorePointer(
            ignoring: !advancedEditable,
            child: buildCollapsibleGatewaySectionInternal(
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
            ),
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
      const SizedBox(height: 16),
      Opacity(
        opacity: advancedEditable ? 1 : 0.72,
        child: IgnorePointer(
          ignoring: !advancedEditable,
          child: buildCollapsibleGatewaySectionInternal(
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
        ),
      ),
      const SizedBox(height: 16),
      Opacity(
        opacity: advancedEditable ? 1 : 0.72,
        child: IgnorePointer(
          ignoring: !advancedEditable,
          child: buildCollapsibleGatewaySectionInternal(
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
        ),
      ),
      const SizedBox(height: 16),
      Opacity(
        opacity: advancedEditable ? 1 : 0.72,
        child: IgnorePointer(
          ignoring: !advancedEditable,
          child: buildCollapsibleGatewaySectionInternal(
            context: context,
            title: appText('SKILLS 目录授权', 'SKILLS Directory Authorization'),
            expanded: skillsDirectoryAuthorizationExpandedInternal,
            onChanged: (value) => setStateInternal(() {
              skillsDirectoryAuthorizationExpandedInternal = value;
            }),
            child: SkillDirectoryAuthorizationCard(
              controller: controller,
              showHeader: false,
            ),
          ),
        ),
      ),
    ];
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onChanged(!expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
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
    );
  }
}
