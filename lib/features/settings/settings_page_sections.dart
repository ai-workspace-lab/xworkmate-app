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
import '../../widgets/settings_page_shell.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';
import 'settings_page_core.dart';
import 'settings_page_gateway.dart';
import 'settings_page_gateway_connection.dart';
import 'settings_page_gateway_llm.dart';
import 'settings_page_presentation.dart';
import 'settings_page_multi_agent.dart';
import 'settings_page_support.dart';
import 'settings_page_device.dart';
import 'settings_page_widgets.dart';

extension SettingsPageSectionsMixinInternal on SettingsPageStateInternal {
  List<SettingsTab> orderedOverviewTabsInternal(
    AppController controller,
    UiFeatureAccess uiFeatures,
  ) {
    final availableTabs = uiFeatures.availableSettingsTabs;
    final current = uiFeatures.sanitizeSettingsTab(controller.settingsTab);
    return <SettingsTab>[
      current,
      ...availableTabs.where((item) => item != current),
    ];
  }

  List<Widget> buildOverviewContentInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
  ) {
    return buildOrderedSettingsSections(
      availableTabs: uiFeatures.availableSettingsTabs,
      currentTab: uiFeatures.sanitizeSettingsTab(controller.settingsTab),
      buildTabContent: (tab) => switch (tab) {
        SettingsTab.general => buildGeneralInternal(
          context,
          controller,
          settings,
          uiFeatures,
        ),
        SettingsTab.workspace => buildWorkspaceInternal(
          context,
          controller,
          settings,
        ),
        SettingsTab.gateway => buildGatewayInternal(
          context,
          controller,
          settings,
          uiFeatures,
        ),
        SettingsTab.agents => buildAgentsInternal(context, controller, settings),
        SettingsTab.appearance => buildAppearanceInternal(context, controller),
        SettingsTab.diagnostics => buildDiagnosticsInternal(context, controller),
        SettingsTab.experimental => buildExperimentalInternal(
          context,
          controller,
          settings,
          uiFeatures,
        ),
        SettingsTab.about => buildAboutInternal(context, controller),
      },
    );
  }

  List<Widget> buildContentForCurrentStateInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
  ) {
    if (detailInternal != null) {
      return buildDetailContentInternal(
        context,
        controller,
        settings,
        uiFeatures,
        detailInternal!,
      );
    }

    return switch (tabInternal) {
      SettingsTab.general => buildGeneralInternal(
        context,
        controller,
        settings,
        uiFeatures,
      ),
      SettingsTab.workspace => buildWorkspaceInternal(
        context,
        controller,
        settings,
      ),
      SettingsTab.gateway => buildGatewayInternal(
        context,
        controller,
        settings,
        uiFeatures,
      ),
      SettingsTab.agents => buildAgentsInternal(context, controller, settings),
      SettingsTab.appearance => buildAppearanceInternal(context, controller),
      SettingsTab.diagnostics => buildDiagnosticsInternal(context, controller),
      SettingsTab.experimental => buildExperimentalInternal(
        context,
        controller,
        settings,
        uiFeatures,
      ),
      SettingsTab.about => buildAboutInternal(context, controller),
    };
  }

  List<Widget> buildDetailContentInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
    SettingsDetailPage detail,
  ) {
    return switch (detail) {
      SettingsDetailPage.gatewayConnection => <Widget>[
        buildDetailIntroInternal(
          context,
          title: detail.label,
          description: appText(
            '集中编辑 Gateway 连接、设备配对和会话级连接入口。',
            'Edit gateway connection, device pairing, and session-level connection entry points in one place.',
          ),
        ),
        const SizedBox(height: 16),
        buildOpenClawGatewayCardInternal(context, controller, settings),
        if (uiFeatures.supportsVaultServer) ...[
          const SizedBox(height: 16),
          buildVaultProviderCardInternal(context, controller, settings),
        ],
        const SizedBox(height: 16),
        buildLlmEndpointManagerInternal(context, controller, settings),
      ],
      SettingsDetailPage.aiGatewayIntegration => <Widget>[
        buildDetailIntroInternal(
          context,
          title: detail.label,
          description: appText(
            '把主 LLM API 与可选兼容端点统一收口成接入点列表。默认先显示主接入点，需要时可通过 + 扩展更多端点。',
            'Manage the primary LLM API and optional compatible endpoints from one endpoint list. Start with the primary entry and expand more endpoints with + when needed.',
          ),
        ),
        const SizedBox(height: 16),
        buildLlmEndpointManagerInternal(context, controller, settings),
      ],
      SettingsDetailPage.vaultProvider => <Widget>[
        buildDetailIntroInternal(
          context,
          title: detail.label,
          description: appText(
            '在这里维护 Vault 服务地址、可选 namespace，以及只进入安全存储的 root token。',
            'Maintain the Vault server URL, optional namespace, and the root token that only persists in secure storage here.',
          ),
        ),
        const SizedBox(height: 16),
        if (uiFeatures.supportsVaultServer)
          buildVaultProviderCardInternal(context, controller, settings)
        else
          SurfaceCard(
            child: Text(
              appText(
                '当前发布配置未开放 Vault Server 参数。',
                'Vault Server settings are disabled in this release configuration.',
              ),
            ),
          ),
      ],
      SettingsDetailPage.externalAgents => <Widget>[
        buildDetailIntroInternal(
          context,
          title: detail.label,
          description: appText(
            '多 Agent 协作、角色编排和外部 Agent / ACP 连接的详细参数集中在这里。',
            'Detailed multi-agent collaboration, role orchestration, and external Agent / ACP connection settings are edited here.',
          ),
        ),
        const SizedBox(height: 16),
        ...buildAgentsInternal(context, controller, settings),
        const SizedBox(height: 16),
        CodexIntegrationCard(controller: controller),
      ],
      SettingsDetailPage.diagnosticsAdvanced => <Widget>[
        buildDetailIntroInternal(
          context,
          title: detail.label,
          description: appText(
            '高级诊断集中展示网关诊断、运行日志和设备信息。',
            'Advanced diagnostics centralize gateway diagnostics, runtime logs, and device information.',
          ),
        ),
        const SizedBox(height: 16),
        ...buildDiagnosticsInternal(context, controller),
      ],
    };
  }

  Widget buildDetailIntroInternal(
    BuildContext context, {
    required String title,
    required String description,
  }) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget buildGlobalApplyBarInternal(
    BuildContext context,
    AppController controller,
  ) {
    final hasDraft = controller.hasSettingsDraftChanges;
    final hasPendingApply = controller.hasPendingSettingsApply;
    final message = controller.settingsDraftStatusMessage;
    return SettingsGlobalApplyCard(
      title: appText('设置提交流程', 'Settings Submission'),
      message: message.isNotEmpty
          ? message
          : hasDraft
          ? appText(
              '当前存在未保存草稿。保存并生效：按当前配置立即更新。',
              'There are unsaved drafts. Save & apply updates the current configuration immediately.',
            )
          : hasPendingApply
          ? appText(
              '当前存在待生效更改。保存并生效：立即按当前配置更新。',
              'There are saved changes waiting to be applied. Save & apply updates the current configuration immediately.',
            )
          : appText(
              '当前没有待提交更改。',
              'There are no pending settings changes.',
            ),
      applyLabel: appText('保存并生效', 'Save & apply'),
      onApply: (!hasDraft && !hasPendingApply)
          ? null
          : () => handleTopLevelApplyInternal(controller),
    );
  }

  List<Widget> buildGeneralInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
  ) {
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Application', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            SwitchRowInternal(
              label: appText('启用工作台外壳', 'Active workspace shell'),
              value: settings.appActive,
              onChanged: (value) => saveSettingsInternal(
                controller,
                settings.copyWith(appActive: value),
              ),
            ),
            SwitchRowInternal(
              label: appText('开机启动', 'Launch at login'),
              value: settings.launchAtLogin,
              onChanged: (value) => saveSettingsInternal(
                controller,
                settings.copyWith(launchAtLogin: value),
              ),
            ),
            SwitchRowInternal(
              label: controller.supportsDesktopIntegration
                  ? appText('显示托盘图标', 'Show tray icon')
                  : appText('显示 Dock 图标', 'Show dock icon'),
              value: settings.showDockIcon,
              onChanged: (value) => saveSettingsInternal(
                controller,
                settings.copyWith(showDockIcon: value),
              ),
            ),
          ],
        ),
      ),
      if (controller.supportsDesktopIntegration)
        buildLinuxDesktopIntegrationInternal(context, controller, settings),
      if (uiFeatures.supportsAccountAccess)
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appText('账号访问', 'Account Access'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              EditableFieldInternal(
                label: appText('账号服务地址', 'Account Base URL'),
                value: settings.accountBaseUrl,
                onSubmitted: (value) => saveSettingsInternal(
                  controller,
                  settings.copyWith(accountBaseUrl: value),
                ),
              ),
              EditableFieldInternal(
                label: appText('账号用户名', 'Account Username'),
                value: settings.accountUsername,
                onSubmitted: (value) => saveSettingsInternal(
                  controller,
                  settings.copyWith(accountUsername: value),
                ),
              ),
              EditableFieldInternal(
                label: appText('工作区名称', 'Workspace Label'),
                value: settings.accountWorkspace,
                onSubmitted: (value) => saveSettingsInternal(
                  controller,
                  settings.copyWith(accountWorkspace: value),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget buildLinuxDesktopIntegrationInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final desktop = controller.desktopIntegration;
    final config = settings.linuxDesktop;
    final theme = Theme.of(context);
    return SurfaceCard(
      key: const ValueKey('linux-desktop-integration-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appText('Linux 桌面集成', 'Linux Desktop Integration'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            appText(
              '统一管理 GNOME / KDE 的代理模式、隧道连接、托盘菜单与开机自启。',
              'Manage GNOME / KDE proxy mode, tunnel session, tray menu, and autostart from one surface.',
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          InfoRowInternal(
            label: appText('桌面环境', 'Desktop'),
            value: desktop.environment.label,
          ),
          InfoRowInternal(
            label: 'NetworkManager',
            value: desktop.networkManagerAvailable
                ? appText('可用', 'Available')
                : appText('不可用', 'Unavailable'),
          ),
          InfoRowInternal(
            label: appText('当前模式', 'Current Mode'),
            value: desktop.mode.label,
          ),
          InfoRowInternal(
            label: appText('隧道状态', 'Tunnel'),
            value: desktop.tunnel.connected
                ? appText('已连接', 'Connected')
                : desktop.tunnel.available
                ? appText('可连接', 'Ready')
                : appText('未检测到配置', 'No profile detected'),
          ),
          InfoRowInternal(
            label: appText('系统代理', 'System Proxy'),
            value: desktop.systemProxy.enabled
                ? '${desktop.systemProxy.host}:${desktop.systemProxy.port}'
                : appText('未启用', 'Disabled'),
          ),
          SwitchRowInternal(
            label: appText('开机启动', 'Launch at login'),
            value: settings.launchAtLogin,
            onChanged: (value) => saveSettingsInternal(
              controller,
              settings.copyWith(launchAtLogin: value),
            ),
          ),
          SwitchRowInternal(
            label: appText('托盘菜单', 'Tray menu'),
            value: config.trayEnabled,
            onChanged: (value) => saveSettingsInternal(
              controller,
              settings.copyWith(
                linuxDesktop: config.copyWith(trayEnabled: value),
              ),
            ),
          ),
          EditableFieldInternal(
            label: appText('隧道连接名称', 'Tunnel Connection Name'),
            value: config.vpnConnectionName,
            onSubmitted: (value) => saveSettingsInternal(
              controller,
              settings.copyWith(
                linuxDesktop: config.copyWith(vpnConnectionName: value.trim()),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: EditableFieldInternal(
                  label: appText('代理主机', 'Proxy Host'),
                  value: config.proxyHost,
                  onSubmitted: (value) => saveSettingsInternal(
                    controller,
                    settings.copyWith(
                      linuxDesktop: config.copyWith(proxyHost: value.trim()),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: EditableFieldInternal(
                  label: appText('代理端口', 'Proxy Port'),
                  value: config.proxyPort.toString(),
                  onSubmitted: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed == null || parsed <= 0) {
                      return;
                    }
                    saveSettingsInternal(
                      controller,
                      settings.copyWith(
                        linuxDesktop: config.copyWith(proxyPort: parsed),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonal(
                onPressed: controller.desktopPlatformBusy
                    ? null
                    : () => controller.setDesktopVpnMode(VpnMode.proxy),
                child: Text(appText('切换到代理', 'Use Proxy')),
              ),
              FilledButton.tonal(
                onPressed: controller.desktopPlatformBusy
                    ? null
                    : () => controller.setDesktopVpnMode(VpnMode.tunnel),
                child: Text(appText('切换到隧道', 'Use Tunnel')),
              ),
              OutlinedButton(
                onPressed: controller.desktopPlatformBusy
                    ? null
                    : controller.connectDesktopTunnel,
                child: Text(appText('连接隧道', 'Connect Tunnel')),
              ),
              OutlinedButton(
                onPressed: controller.desktopPlatformBusy
                    ? null
                    : controller.disconnectDesktopTunnel,
                child: Text(appText('断开隧道', 'Disconnect Tunnel')),
              ),
              OutlinedButton(
                onPressed: controller.desktopPlatformBusy
                    ? null
                    : controller.refreshDesktopIntegration,
                child: Text(appText('刷新状态', 'Refresh Status')),
              ),
            ],
          ),
          if (desktop.statusMessage.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            buildNoticeInternal(
              context,
              tone: theme.colorScheme.surfaceContainerHighest,
              title: appText('桌面状态', 'Desktop Status'),
              message: desktop.statusMessage,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> buildWorkspaceInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('工作区', 'Workspace'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            EditableFieldInternal(
              label: appText('工作区路径', 'Workspace Path'),
              value: settings.workspacePath,
              onSubmitted: (value) => controller.saveSettingsDraft(
                settings.copyWith(workspacePath: value),
              ),
            ),
            EditableFieldInternal(
              label: appText('CLI 路径', 'CLI Path'),
              value: settings.cliPath,
              onSubmitted: (value) => controller.saveSettingsDraft(
                settings.copyWith(cliPath: value),
              ),
            ),
            EditableFieldInternal(
              label: appText('默认模型', 'Default Model'),
              value: settings.defaultModel,
              onSubmitted: (value) => controller.saveSettingsDraft(
                settings.copyWith(defaultModel: value),
              ),
            ),
            EditableFieldInternal(
              label: appText('默认提供方', 'Default Provider'),
              value: settings.defaultProvider,
              onSubmitted: (value) => controller.saveSettingsDraft(
                settings.copyWith(defaultProvider: value),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}
