part of 'settings_page.dart';

extension _SettingsPageGatewayConnectionMixin on _SettingsPageState {
  Widget _buildOpenClawGatewayCard(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    return SurfaceCard(
      child: _buildOpenClawGatewayCardBody(context, controller, settings),
    );
  }

  Widget _buildOpenClawGatewayCardBody(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    _syncGatewayDraftControllers(settings);
    final theme = Theme.of(context);
    final gatewayProfiles = settings.gatewayProfiles;
    final selectedProfileIndex = _selectedGatewayProfileIndex.clamp(
      0,
      gatewayProfiles.length - 1,
    );
    final gatewayProfile = gatewayProfiles[selectedProfileIndex];
    final gatewayMode = _gatewayProfileModeForSlot(
      selectedProfileIndex,
      gatewayProfile,
    );
    final gatewayTokenController =
        _gatewayTokenControllers[selectedProfileIndex];
    final gatewayPasswordController =
        _gatewayPasswordControllers[selectedProfileIndex];
    final gatewayTokenState = _gatewayTokenStates[selectedProfileIndex];
    final gatewayPasswordState = _gatewayPasswordStates[selectedProfileIndex];
    final uiFeatures = controller.featuresFor(
      resolveUiFeaturePlatformFromContext(context),
    );
    final setupCodeFeatureEnabled = uiFeatures.supportsGatewaySetupCode;
    final forceSetupCodeMode = _prefersGatewaySetupCodeForCurrentContext(
      context,
    );
    final useSetupCode = selectedProfileIndex == kGatewayLocalProfileIndex
        ? false
        : forceSetupCodeMode ||
              (setupCodeFeatureEnabled && gatewayProfile.useSetupCode);
    final gatewayTls = gatewayMode == RuntimeConnectionMode.local
        ? false
        : gatewayProfile.tls;
    final hasStoredGatewayToken = controller.hasStoredGatewayTokenForProfile(
      selectedProfileIndex,
    );
    final hasStoredGatewayPassword = controller
        .hasStoredGatewayPasswordForProfile(selectedProfileIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appText(
            '这里维护外部 Gateway / ACP endpoint 连接源 profile。工作模式在会话区单独切换：single-agent 通过标准 ACP 协议直连外部 Agent；local/remote 继续走 Gateway。保存：仅保存配置，不立即生效。应用：立即按当前配置生效。',
            'This card edits external Gateway / ACP endpoint profiles. Work mode is switched in the session UI: single-agent connects to an external Agent over the standard ACP protocol, while local/remote continue through Gateway. Save persists configuration only, while Apply makes it take effect immediately.',
          ),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List<Widget>.generate(gatewayProfiles.length, (index) {
            final profile = gatewayProfiles[index];
            final configured =
                profile.setupCode.trim().isNotEmpty ||
                profile.host.trim().isNotEmpty;
            return ChoiceChip(
              key: ValueKey('gateway-profile-chip-$index'),
              selected: index == selectedProfileIndex,
              avatar: Icon(switch (index) {
                kGatewayLocalProfileIndex => Icons.computer_rounded,
                kGatewayRemoteProfileIndex => Icons.cloud_outlined,
                _ => Icons.link_rounded,
              }, size: 18),
              label: Text(
                _gatewayProfileChipLabel(index, configured: configured),
              ),
              onSelected: (_) {
                _setState(() {
                  _selectedGatewayProfileIndex = index;
                  _gatewayTestState = 'idle';
                  _gatewayTestMessage = '';
                  _gatewayTestEndpoint = '';
                });
              },
            );
          }),
        ),
        const SizedBox(height: 12),
        Text(
          _gatewayProfileSlotDescription(selectedProfileIndex),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (selectedProfileIndex != kGatewayLocalProfileIndex &&
            !forceSetupCodeMode &&
            setupCodeFeatureEnabled) ...[
          SectionTabs(
            items: [appText('配置码', 'Setup Code'), appText('手动配置', 'Manual')],
            value: useSetupCode
                ? appText('配置码', 'Setup Code')
                : appText('手动配置', 'Manual'),
            size: SectionTabsSize.small,
            onChanged: (value) {
              final nextUseSetupCode = value == appText('配置码', 'Setup Code');
              unawaited(
                _saveGatewayProfile(
                  controller,
                  settings,
                  gatewayProfile.copyWith(useSetupCode: nextUseSetupCode),
                ).catchError((_) {}),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        if (selectedProfileIndex != kGatewayLocalProfileIndex &&
            useSetupCode) ...[
          TextField(
            key: const ValueKey('gateway-setup-code-field'),
            controller: _gatewaySetupCodeController,
            autofocus: forceSetupCodeMode,
            minLines: 4,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: appText('配置码', 'Setup Code'),
              hintText: appText(
                '粘贴 Gateway 配置码或 JSON 负载',
                'Paste gateway setup code or JSON payload',
              ),
            ),
            onChanged: (_) => unawaited(
              _saveGatewayDraft(controller, settings).catchError((_) {}),
            ),
            onSubmitted: (_) => _saveGatewayDraft(controller, settings),
          ),
        ] else ...[
          TextField(
            key: const ValueKey('gateway-host-field'),
            controller: _gatewayHostController,
            decoration: InputDecoration(labelText: appText('主机', 'Host')),
            onChanged: (_) => unawaited(
              _saveGatewayDraft(controller, settings).catchError((_) {}),
            ),
            onSubmitted: (_) => _saveGatewayDraft(controller, settings),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: const ValueKey('gateway-port-field'),
                  controller: _gatewayPortController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: appText('端口', 'Port')),
                  onChanged: (_) => unawaited(
                    _saveGatewayDraft(controller, settings).catchError((_) {}),
                  ),
                  onSubmitted: (_) => _saveGatewayDraft(controller, settings),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Opacity(
                  opacity: gatewayMode == RuntimeConnectionMode.local ? 0.6 : 1,
                  child: _InlineSwitchField(
                    label: 'TLS',
                    value: gatewayTls,
                    onChanged: (value) {
                      if (gatewayMode == RuntimeConnectionMode.local) {
                        return;
                      }
                      unawaited(
                        _saveGatewayProfile(
                          controller,
                          settings,
                          gatewayProfile.copyWith(tls: value),
                        ).catchError((_) {}),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _buildSecureField(
          fieldKey: const ValueKey('gateway-shared-token-field'),
          controller: gatewayTokenController,
          label: appText('共享 Token', 'Shared Token'),
          hasStoredValue: hasStoredGatewayToken,
          fieldState: gatewayTokenState,
          onStateChanged: (value) => _setState(
            () => _gatewayTokenStates[selectedProfileIndex] = value,
          ),
          loadValue: () => controller.settingsController.loadGatewayToken(
            profileIndex: selectedProfileIndex,
          ),
          onSubmitted: (value) async => controller.saveGatewayTokenDraft(
            value,
            profileIndex: selectedProfileIndex,
          ),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示；可直接测试，也可通过本区保存/应用提交。',
            'Stored securely. Test directly or submit with local Save / Apply actions.',
          ),
          emptyHelperText: appText(
            '输入后先进入草稿；通过本区保存/应用提交。',
            'Values stage into draft first; submit with local Save / Apply actions.',
          ),
        ),
        const SizedBox(height: 12),
        _buildSecureField(
          fieldKey: const ValueKey('gateway-password-field'),
          controller: gatewayPasswordController,
          label: appText('密码', 'Password'),
          hasStoredValue: hasStoredGatewayPassword,
          fieldState: gatewayPasswordState,
          onStateChanged: (value) => _setState(
            () => _gatewayPasswordStates[selectedProfileIndex] = value,
          ),
          loadValue: () => controller.settingsController.loadGatewayPassword(
            profileIndex: selectedProfileIndex,
          ),
          onSubmitted: (value) async => controller.saveGatewayPasswordDraft(
            value,
            profileIndex: selectedProfileIndex,
          ),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示；可直接测试，也可通过本区保存/应用提交。',
            'Stored securely. Test directly or submit with local Save / Apply actions.',
          ),
          emptyHelperText: appText(
            '输入后先进入草稿；通过本区保存/应用提交。',
            'Values stage into draft first; submit with local Save / Apply actions.',
          ),
        ),
        const SizedBox(height: 16),
        _buildSettingsSectionActions(
          controller: controller,
          testKey: const ValueKey('gateway-test-button'),
          saveKey: const ValueKey('gateway-save-button'),
          applyKey: const ValueKey('gateway-apply-button'),
          testing: _gatewayTesting,
          onTest: () => _testGatewayConnection(controller, settings),
          onSave: () => _saveGatewayAndPersist(controller, settings),
          onApply: () => _saveGatewayAndApply(controller, settings),
        ),
        const SizedBox(height: 16),
        _buildDeviceSecurityCard(context, controller),
        if (_gatewayTestMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildNotice(
            context,
            tone: _gatewayTestState == 'success'
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.errorContainer,
            title: appText('测试连接', 'Test Connection'),
            message: _gatewayTestEndpoint.isEmpty
                ? _gatewayTestMessage
                : '$_gatewayTestMessage\n$_gatewayTestEndpoint',
          ),
        ],
      ],
    );
  }

  Widget _buildVaultProviderCard(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    return SurfaceCard(
      child: _buildVaultProviderCardBody(context, controller, settings),
    );
  }

  Widget _buildVaultProviderCardBody(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final hasStoredVaultToken =
        controller.settingsController.secureRefs['vault_token'] != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditableField(
          label: appText('地址', 'Address'),
          value: settings.vault.address,
          onSubmitted: (value) => _saveSettings(
            controller,
            settings.copyWith(vault: settings.vault.copyWith(address: value)),
          ),
        ),
        _EditableField(
          label: appText('命名空间', 'Namespace'),
          value: settings.vault.namespace,
          onSubmitted: (value) => _saveSettings(
            controller,
            settings.copyWith(vault: settings.vault.copyWith(namespace: value)),
          ),
        ),
        _EditableField(
          label: appText('认证模式', 'Auth Mode'),
          value: settings.vault.authMode,
          onSubmitted: (value) => _saveSettings(
            controller,
            settings.copyWith(vault: settings.vault.copyWith(authMode: value)),
          ),
        ),
        _EditableField(
          label: appText('Token 引用', 'Token Ref'),
          value: settings.vault.tokenRef,
          onSubmitted: (value) => _saveSettings(
            controller,
            settings.copyWith(vault: settings.vault.copyWith(tokenRef: value)),
          ),
        ),
        _buildSecureField(
          controller: _vaultTokenController,
          label:
              '${appText('Vault Token', 'Vault Token')} (${settings.vault.tokenRef})',
          hasStoredValue: hasStoredVaultToken,
          fieldState: _vaultTokenState,
          onStateChanged: (value) => _setState(() => _vaultTokenState = value),
          loadValue: controller.settingsController.loadVaultToken,
          onSubmitted: (value) async => controller.saveVaultTokenDraft(value),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示，点击查看后读取真实值。',
            'Stored securely. Shows as **** until you reveal it.',
          ),
          emptyHelperText: appText(
            '输入后先进入草稿；保存后才会写入安全存储。',
            'Values stage into draft first and only persist to secure storage after Save.',
          ),
        ),
        const SizedBox(height: 12),
        _buildSettingsSectionActions(
          controller: controller,
          testKey: const ValueKey('vault-test-button'),
          saveKey: const ValueKey('vault-save-button'),
          applyKey: const ValueKey('vault-apply-button'),
          onTest: () => _testVaultConnection(controller, settings),
          onSave: () => _handleTopLevelSave(controller),
          onApply: () => _handleTopLevelApply(controller),
          testLabel:
              '${appText('测试连接', 'Test Connection')} · ${controller.settingsController.vaultStatus}',
        ),
      ],
    );
  }
}
