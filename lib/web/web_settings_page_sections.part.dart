part of 'web_settings_page.dart';

extension _WebSettingsPageSectionsMixin on _WebSettingsPageState {
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
                      : appText(
                          '当前没有待提交更改。',
                          'There are no pending settings changes.',
                        ),
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
                onPressed:
                    hasDraft || _gatewaySubTab == _WebGatewaySettingsSubTab.acp
                    ? () => _handleTopLevelSave(controller)
                    : null,
                child: Text(appText('保存', 'Save')),
              ),
              FilledButton.tonal(
                key: const ValueKey('settings-global-apply-button'),
                onPressed:
                    (hasDraft ||
                        hasPendingApply ||
                        _gatewaySubTab == _WebGatewaySettingsSubTab.acp)
                    ? () => _handleTopLevelApply(controller)
                    : null,
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
  ) {
    final targets = controller
        .featuresFor(UiFeaturePlatform.web)
        .availableExecutionTargets
        .toList(growable: false);
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('通用', 'General'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              appText(
                '这里维护 Web 默认执行目标与会话持久化摘要，结构与 App 设置页保持一致。',
                'Maintain the default web execution target and session persistence summary here, aligned with the app settings layout.',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              appText('默认工作模式', 'Default work mode'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<AssistantExecutionTarget>(
              initialValue: settings.assistantExecutionTarget,
              items: targets
                  .map((target) {
                    return DropdownMenuItem<AssistantExecutionTarget>(
                      value: target,
                      child: Text(_targetLabel(target)),
                    );
                  })
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  unawaited(
                    controller.saveSettingsDraft(
                      settings.copyWith(assistantExecutionTarget: value),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            Text(controller.conversationPersistenceSummary),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildGateway(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    return [
      SectionTabs(
        items: <String>[
          'OpenClaw Gateway',
          appText('LLM 接入点', 'LLM Endpoints'),
          appText('ACP 外部接入', 'External ACP'),
        ],
        value: switch (_gatewaySubTab) {
          _WebGatewaySettingsSubTab.gateway => 'OpenClaw Gateway',
          _WebGatewaySettingsSubTab.llm => appText('LLM 接入点', 'LLM Endpoints'),
          _WebGatewaySettingsSubTab.acp => appText('ACP 外部接入', 'External ACP'),
        },
        onChanged: (value) => _setState(() {
          _gatewaySubTab = switch (value) {
            'OpenClaw Gateway' => _WebGatewaySettingsSubTab.gateway,
            _ when value == appText('LLM 接入点', 'LLM Endpoints') =>
              _WebGatewaySettingsSubTab.llm,
            _ => _WebGatewaySettingsSubTab.acp,
          };
        }),
      ),
      const SizedBox(height: 16),
      ...switch (_gatewaySubTab) {
        _WebGatewaySettingsSubTab.gateway => _buildGatewayOverview(
          context,
          controller,
        ),
        _WebGatewaySettingsSubTab.llm => _buildLlmEndpointManager(
          context,
          controller,
          settings,
        ),
        _WebGatewaySettingsSubTab.acp => <Widget>[
          _buildExternalAcpEndpointManager(context, controller),
        ],
      },
    ];
  }

  List<Widget> _buildGatewayOverview(
    BuildContext context,
    AppController controller,
  ) {
    final palette = context.palette;
    return [
      SurfaceCard(
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: palette.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                appText(
                  'Web 版凭证会保存在当前浏览器本地存储中，安全性低于桌面端安全存储。请仅在可信设备上使用。',
                  'Web credentials are persisted in this browser and are less secure than desktop secure storage. Use only on trusted devices.',
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OpenClaw Gateway',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              appText(
                '这里维护 Local / Remote Gateway 与浏览器会话持久化配置。保存：仅保存配置，不立即生效。应用：立即按当前配置生效。',
                'Maintain Local / Remote Gateway and browser session persistence here. Save persists configuration only, while Apply makes it take effect immediately.',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _buildGatewayCard(
        context,
        controller: controller,
        title: appText('Local Gateway', 'Local Gateway'),
        executionTarget: AssistantExecutionTarget.local,
        profileIndex: kGatewayLocalProfileIndex,
        hostController: _localHostController,
        portController: _localPortController,
        tokenController: _localTokenController,
        passwordController: _localPasswordController,
        tokenMask: controller.storedRelayTokenMaskForProfile(
          kGatewayLocalProfileIndex,
        ),
        passwordMask: controller.storedRelayPasswordMaskForProfile(
          kGatewayLocalProfileIndex,
        ),
        tls: false,
        onTlsChanged: null,
        message: _localGatewayMessage,
        onMessageChanged: (value) {
          _setState(() => _localGatewayMessage = value);
        },
      ),
      const SizedBox(height: 12),
      _buildGatewayCard(
        context,
        controller: controller,
        title: appText('Remote Gateway', 'Remote Gateway'),
        executionTarget: AssistantExecutionTarget.remote,
        profileIndex: kGatewayRemoteProfileIndex,
        hostController: _remoteHostController,
        portController: _remotePortController,
        tokenController: _remoteTokenController,
        passwordController: _remotePasswordController,
        tokenMask: controller.storedRelayTokenMaskForProfile(
          kGatewayRemoteProfileIndex,
        ),
        passwordMask: controller.storedRelayPasswordMaskForProfile(
          kGatewayRemoteProfileIndex,
        ),
        tls: _remoteTls,
        onTlsChanged: (value) {
          _setState(() => _remoteTls = value);
        },
        message: _remoteGatewayMessage,
        onMessageChanged: (value) {
          _setState(() => _remoteGatewayMessage = value);
        },
      ),
      const SizedBox(height: 12),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('会话持久化', 'Session persistence'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              appText(
                '默认使用浏览器本地缓存保存 Assistant 会话。若要做 durable store，请配置一个 HTTPS Session API；该 API 可以由 PostgreSQL 等后端数据库承接，但浏览器不会直接连接数据库。',
                'Assistant sessions default to browser-local cache. For durable storage, configure an HTTPS session API. That API can be backed by PostgreSQL, but the browser never connects to the database directly.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<WebSessionPersistenceMode>(
              initialValue: _sessionPersistenceMode,
              items: WebSessionPersistenceMode.values
                  .map(
                    (mode) => DropdownMenuItem<WebSessionPersistenceMode>(
                      value: mode,
                      child: Text(mode.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                _setState(() {
                  _sessionPersistenceMode = value;
                });
              },
              decoration: InputDecoration(
                labelText: appText('保存位置', 'Persistence target'),
              ),
            ),
            if (_sessionPersistenceMode ==
                WebSessionPersistenceMode.remote) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _sessionRemoteBaseUrlController,
                decoration: InputDecoration(
                  labelText: appText(
                    'Session API Base URL',
                    'Session API Base URL',
                  ),
                  hintText: 'https://xworkmate.svc.plus/api/web-sessions',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sessionApiTokenController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: appText('Session API Token', 'Session API token'),
                  helperText: controller.storedWebSessionApiTokenMask == null
                      ? appText(
                          '只保留在当前浏览器会话内存中；刷新页面后需要重新输入。',
                          'Kept only in the current browser session memory; re-enter it after reload.',
                        )
                      : '${appText('当前会话', 'This session')}: ${controller.storedWebSessionApiTokenMask} · ${appText('刷新后需重新输入', 'Re-enter after reload')}',
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () async {
                    await controller.saveWebSessionPersistenceConfiguration(
                      mode: _sessionPersistenceMode,
                      remoteBaseUrl: _sessionRemoteBaseUrlController.text,
                      apiToken: _sessionApiTokenController.text,
                    );
                    if (!mounted) {
                      return;
                    }
                    _setState(() {
                      _sessionPersistenceMessage =
                          controller.sessionPersistenceStatusMessage;
                    });
                  },
                  child: Text(appText('Save', 'Save')),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    await controller.saveWebSessionPersistenceConfiguration(
                      mode: _sessionPersistenceMode,
                      remoteBaseUrl: _sessionRemoteBaseUrlController.text,
                      apiToken: _sessionApiTokenController.text,
                    );
                    if (!mounted) {
                      return;
                    }
                    _setState(() {
                      _sessionPersistenceMessage = appText(
                        '会话存储配置已应用到当前浏览器会话。',
                        'Session persistence settings are now applied to this browser session.',
                      );
                    });
                  },
                  child: Text(appText('Apply', 'Apply')),
                ),
              ],
            ),
            if (_sessionPersistenceMessage.trim().isNotEmpty ||
                controller.sessionPersistenceStatusMessage
                    .trim()
                    .isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                (_sessionPersistenceMessage.trim().isNotEmpty
                        ? _sessionPersistenceMessage
                        : controller.sessionPersistenceStatusMessage)
                    .trim(),
              ),
            ],
          ],
        ),
      ),
    ];
  }
}
