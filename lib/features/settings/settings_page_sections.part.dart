part of 'settings_page.dart';

extension _SettingsPageSectionsMixin on _SettingsPageState {
  List<Widget> _buildContentForCurrentState(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
  ) {
    if (_detail != null) {
      return _buildDetailContent(
        context,
        controller,
        settings,
        uiFeatures,
        _detail!,
      );
    }

    return switch (_tab) {
      SettingsTab.general => _buildGeneral(
        context,
        controller,
        settings,
        uiFeatures,
      ),
      SettingsTab.workspace => _buildWorkspace(context, controller, settings),
      SettingsTab.gateway => _buildGateway(
        context,
        controller,
        settings,
        uiFeatures,
      ),
      SettingsTab.agents => _buildAgents(context, controller, settings),
      SettingsTab.appearance => _buildAppearance(context, controller),
      SettingsTab.diagnostics => _buildDiagnostics(context, controller),
      SettingsTab.experimental => _buildExperimental(
        context,
        controller,
        settings,
        uiFeatures,
      ),
      SettingsTab.about => _buildAbout(context, controller),
    };
  }

  List<Widget> _buildDetailContent(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
    SettingsDetailPage detail,
  ) {
    return switch (detail) {
      SettingsDetailPage.gatewayConnection => <Widget>[
        _buildDetailIntro(
          context,
          title: detail.label,
          description: appText(
            '集中编辑 Gateway 连接、设备配对和会话级连接入口。',
            'Edit gateway connection, device pairing, and session-level connection entry points in one place.',
          ),
        ),
        const SizedBox(height: 16),
        _buildOpenClawGatewayCard(context, controller, settings),
        if (uiFeatures.supportsVaultServer) ...[
          const SizedBox(height: 16),
          _buildVaultProviderCard(context, controller, settings),
        ],
        const SizedBox(height: 16),
        _buildLlmEndpointManager(context, controller, settings),
      ],
      SettingsDetailPage.aiGatewayIntegration => <Widget>[
        _buildDetailIntro(
          context,
          title: detail.label,
          description: appText(
            '把主 LLM API 与可选兼容端点统一收口成接入点列表。默认先显示主接入点，需要时可通过 + 扩展更多端点。',
            'Manage the primary LLM API and optional compatible endpoints from one endpoint list. Start with the primary entry and expand more endpoints with + when needed.',
          ),
        ),
        const SizedBox(height: 16),
        _buildLlmEndpointManager(context, controller, settings),
      ],
      SettingsDetailPage.vaultProvider => <Widget>[
        _buildDetailIntro(
          context,
          title: detail.label,
          description: appText(
            '只在这里维护 Vault 地址、命名空间和安全 token 引用。',
            'Maintain Vault endpoint, namespace, and secure token references here.',
          ),
        ),
        const SizedBox(height: 16),
        if (uiFeatures.supportsVaultServer)
          _buildVaultProviderCard(context, controller, settings)
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
        _buildDetailIntro(
          context,
          title: detail.label,
          description: appText(
            '多 Agent 协作、角色编排和外部 Agent / ACP 连接的详细参数集中在这里。',
            'Detailed multi-agent collaboration, role orchestration, and external Agent / ACP connection settings are edited here.',
          ),
        ),
        const SizedBox(height: 16),
        ..._buildAgents(context, controller, settings),
        const SizedBox(height: 16),
        CodexIntegrationCard(controller: controller),
      ],
      SettingsDetailPage.diagnosticsAdvanced => <Widget>[
        _buildDetailIntro(
          context,
          title: detail.label,
          description: appText(
            '高级诊断集中展示网关诊断、运行日志和设备信息。',
            'Advanced diagnostics centralize gateway diagnostics, runtime logs, and device information.',
          ),
        ),
        const SizedBox(height: 16),
        ..._buildDiagnostics(context, controller),
      ],
    };
  }

  Widget _buildDetailIntro(
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

  Widget _buildGlobalApplyBar(BuildContext context, AppController controller) {
    final theme = Theme.of(context);
    final hasDraft = controller.hasSettingsDraftChanges;
    final hasPendingApply = controller.hasPendingSettingsApply;
    final message = controller.settingsDraftStatusMessage;
    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appText('设置提交流程', 'Settings Submission'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  message.isNotEmpty
                      ? message
                      : hasDraft
                      ? appText(
                          '当前存在未保存草稿。保存：仅保存配置，不立即生效。',
                          'There are unsaved drafts. Save persists configuration only and does not apply it immediately.',
                        )
                      : hasPendingApply
                      ? appText(
                          '当前存在已保存但未应用的更改。应用：立即按当前配置生效。',
                          'There are saved changes waiting to be applied. Apply makes the current configuration take effect immediately.',
                        )
                      : (message.isEmpty
                            ? appText(
                                '当前没有待提交更改。',
                                'There are no pending settings changes.',
                              )
                            : message),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton(
                key: const ValueKey('settings-global-save-button'),
                onPressed: hasDraft
                    ? () => _handleTopLevelSave(controller)
                    : null,
                child: Text(appText('保存', 'Save')),
              ),
              FilledButton.tonal(
                key: const ValueKey('settings-global-apply-button'),
                onPressed: (!hasDraft && !hasPendingApply)
                    ? null
                    : () => _handleTopLevelApply(controller),
                child: Text(appText('应用', 'Apply')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGeneral(
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
            _SwitchRow(
              label: appText('启用工作台外壳', 'Active workspace shell'),
              value: settings.appActive,
              onChanged: (value) => _saveSettings(
                controller,
                settings.copyWith(appActive: value),
              ),
            ),
            _SwitchRow(
              label: appText('开机启动', 'Launch at login'),
              value: settings.launchAtLogin,
              onChanged: (value) => _saveSettings(
                controller,
                settings.copyWith(launchAtLogin: value),
              ),
            ),
            _SwitchRow(
              label: controller.supportsDesktopIntegration
                  ? appText('显示托盘图标', 'Show tray icon')
                  : appText('显示 Dock 图标', 'Show dock icon'),
              value: settings.showDockIcon,
              onChanged: (value) => _saveSettings(
                controller,
                settings.copyWith(showDockIcon: value),
              ),
            ),
            if (uiFeatures.supportsAccountAccess)
              _SwitchRow(
                label: appText('账号本地模式', 'Account local mode'),
                value: settings.accountLocalMode,
                onChanged: (value) => _saveSettings(
                  controller,
                  settings.copyWith(accountLocalMode: value),
                ),
              ),
          ],
        ),
      ),
      if (controller.supportsDesktopIntegration)
        _buildLinuxDesktopIntegration(context, controller, settings),
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
              _EditableField(
                label: appText('账号服务地址', 'Account Base URL'),
                value: settings.accountBaseUrl,
                onSubmitted: (value) => _saveSettings(
                  controller,
                  settings.copyWith(accountBaseUrl: value),
                ),
              ),
              _EditableField(
                label: appText('账号用户名', 'Account Username'),
                value: settings.accountUsername,
                onSubmitted: (value) => _saveSettings(
                  controller,
                  settings.copyWith(accountUsername: value),
                ),
              ),
              _EditableField(
                label: appText('工作区名称', 'Workspace Label'),
                value: settings.accountWorkspace,
                onSubmitted: (value) => _saveSettings(
                  controller,
                  settings.copyWith(accountWorkspace: value),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _buildLinuxDesktopIntegration(
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
          _InfoRow(
            label: appText('桌面环境', 'Desktop'),
            value: desktop.environment.label,
          ),
          _InfoRow(
            label: 'NetworkManager',
            value: desktop.networkManagerAvailable
                ? appText('可用', 'Available')
                : appText('不可用', 'Unavailable'),
          ),
          _InfoRow(
            label: appText('当前模式', 'Current Mode'),
            value: desktop.mode.label,
          ),
          _InfoRow(
            label: appText('隧道状态', 'Tunnel'),
            value: desktop.tunnel.connected
                ? appText('已连接', 'Connected')
                : desktop.tunnel.available
                ? appText('可连接', 'Ready')
                : appText('未检测到配置', 'No profile detected'),
          ),
          _InfoRow(
            label: appText('系统代理', 'System Proxy'),
            value: desktop.systemProxy.enabled
                ? '${desktop.systemProxy.host}:${desktop.systemProxy.port}'
                : appText('未启用', 'Disabled'),
          ),
          _SwitchRow(
            label: appText('开机启动', 'Launch at login'),
            value: settings.launchAtLogin,
            onChanged: (value) => _saveSettings(
              controller,
              settings.copyWith(launchAtLogin: value),
            ),
          ),
          _SwitchRow(
            label: appText('托盘菜单', 'Tray menu'),
            value: config.trayEnabled,
            onChanged: (value) => _saveSettings(
              controller,
              settings.copyWith(
                linuxDesktop: config.copyWith(trayEnabled: value),
              ),
            ),
          ),
          _EditableField(
            label: appText('隧道连接名称', 'Tunnel Connection Name'),
            value: config.vpnConnectionName,
            onSubmitted: (value) => _saveSettings(
              controller,
              settings.copyWith(
                linuxDesktop: config.copyWith(vpnConnectionName: value.trim()),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _EditableField(
                  label: appText('代理主机', 'Proxy Host'),
                  value: config.proxyHost,
                  onSubmitted: (value) => _saveSettings(
                    controller,
                    settings.copyWith(
                      linuxDesktop: config.copyWith(proxyHost: value.trim()),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _EditableField(
                  label: appText('代理端口', 'Proxy Port'),
                  value: config.proxyPort.toString(),
                  onSubmitted: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed == null || parsed <= 0) {
                      return;
                    }
                    _saveSettings(
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
            _buildNotice(
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

  List<Widget> _buildWorkspace(
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
            _EditableField(
              label: appText('工作区路径', 'Workspace Path'),
              value: settings.workspacePath,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(workspacePath: value),
              ),
            ),
            _EditableField(
              label: appText('远程项目根目录', 'Remote Project Root'),
              value: settings.remoteProjectRoot,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(remoteProjectRoot: value),
              ),
            ),
            _EditableField(
              label: appText('CLI 路径', 'CLI Path'),
              value: settings.cliPath,
              onSubmitted: (value) =>
                  _saveSettings(controller, settings.copyWith(cliPath: value)),
            ),
            _EditableField(
              label: appText('默认模型', 'Default Model'),
              value: settings.defaultModel,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(defaultModel: value),
              ),
            ),
            _EditableField(
              label: appText('默认提供方', 'Default Provider'),
              value: settings.defaultProvider,
              onSubmitted: (value) => _saveSettings(
                controller,
                settings.copyWith(defaultProvider: value),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}
