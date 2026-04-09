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
      return [
        buildOnlineAccountCardInternal(context, controller, settings),
        const SizedBox(height: 16),
        buildAcpBridgeServerModeCardInternal(
          context,
          controller,
          settings,
          uiFeatures: uiFeatures,
        ),
        if (uiFeatures.supportsGatewayAdvancedCustomMode) ...[
          const SizedBox(height: 16),
          ...buildGatewayAdvancedSectionsInternal(
            context,
            controller,
            settings,
            uiFeatures,
          ),
        ],
      ];
    }
    final selectedSubTab =
        !uiFeatures.supportsGatewayAdvancedCustomMode &&
            integrationSubTabInternal == GatewayIntegrationSubTabInternal.advancedConfig
        ? GatewayIntegrationSubTabInternal.vault
        : integrationSubTabInternal;
    final effectiveTabLabel = switch (selectedSubTab) {
      GatewayIntegrationSubTabInternal.gateway => appText(
        '用户登录状态',
        'User Login State',
      ),
      GatewayIntegrationSubTabInternal.vault => appText(
        '基础连接配置',
        'Base Connection Configuration',
      ),
      GatewayIntegrationSubTabInternal.llm => appText(
        '高级自定义模式',
        'Advanced Custom Mode',
      ),
      GatewayIntegrationSubTabInternal.acp => appText(
        '高级自定义模式',
        'Advanced Custom Mode',
      ),
      GatewayIntegrationSubTabInternal.skills => appText(
        '高级自定义模式',
        'Advanced Custom Mode',
      ),
      GatewayIntegrationSubTabInternal.advancedConfig => appText(
        '高级自定义模式',
        'Advanced Custom Mode',
      ),
    };
    return [
      SectionTabs(
        items: <String>[
          appText('用户登录状态', 'User Login State'),
          appText('基础连接配置', 'Base Connection Configuration'),
          if (uiFeatures.supportsGatewayAdvancedCustomMode)
            appText('高级自定义模式', 'Advanced Custom Mode'),
        ],
        value: effectiveTabLabel,
        onChanged: (value) => setStateInternal(() {
          integrationSubTabInternal = switch (value) {
            _ when value == appText('用户登录状态', 'User Login State') =>
              GatewayIntegrationSubTabInternal.gateway,
            _
                when value ==
                    appText(
                      '基础连接配置',
                      'Base Connection Configuration',
                    ) =>
              GatewayIntegrationSubTabInternal.vault,
            _
                when value ==
                    appText('高级自定义模式', 'Advanced Custom Mode') =>
              GatewayIntegrationSubTabInternal.advancedConfig,
            _ => GatewayIntegrationSubTabInternal.advancedConfig,
          };
        }),
      ),
      const SizedBox(height: 16),
      ...switch (selectedSubTab) {
        GatewayIntegrationSubTabInternal.gateway => <Widget>[
          buildOnlineAccountCardInternal(context, controller, settings),
        ],
        GatewayIntegrationSubTabInternal.vault => <Widget>[
          buildAcpBridgeServerModeCardInternal(
            context,
            controller,
            settings,
            uiFeatures: uiFeatures,
          ),
        ],
        GatewayIntegrationSubTabInternal.llm => const <Widget>[],
        GatewayIntegrationSubTabInternal.acp => const <Widget>[],
        GatewayIntegrationSubTabInternal.skills => const <Widget>[],
      GatewayIntegrationSubTabInternal.advancedConfig =>
        uiFeatures.supportsGatewayAdvancedCustomMode
        ? <Widget>[
            ...buildGatewayAdvancedSectionsInternal(
                context,
                controller,
                settings,
                uiFeatures,
              ),
            ]
          : <Widget>[],
      },
    ];
  }

  List<Widget> buildGatewayAdvancedSectionsInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
  ) {
    final advancedEditable =
        settings.acpBridgeServerModeConfig.mode ==
        AcpBridgeServerMode.advancedCustom;
    final sections = <Widget>[
      SurfaceCard(
        key: const ValueKey('gateway-advanced-override-intro'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('高级自定义模式', 'Advanced Custom Mode'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              appText(
                '这里的配置只负责覆盖默认配置，不会把基础连接配置替换成另一套平行模式。未覆盖的字段继续继承当前默认连接来源。',
                'These settings only override the default configuration. They do not replace the base connection model with a parallel mode. Any field you do not override keeps inheriting from the current default source.',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              key: const ValueKey('acp-bridge-advanced-reset'),
              onPressed: advancedEditable
                  ? () => resetAcpBridgeServerAdvancedOverridesInternal(
                      controller,
                      settings,
                    )
                  : null,
              child: Text(appText('清空高级覆盖', 'Clear Advanced Overrides')),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
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
    return sections;
  }

  List<Widget> buildUnifiedGatewaySectionsInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
  ) {
    return buildGatewayAdvancedSectionsInternal(
      context,
      controller,
      settings,
      uiFeatures,
    );
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
