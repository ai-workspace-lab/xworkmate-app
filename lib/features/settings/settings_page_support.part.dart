part of 'settings_page.dart';

extension _SettingsPageSupportMixin on _SettingsPageState {
  List<Widget> _buildAbout(BuildContext context, AppController controller) {
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('关于', 'About'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _InfoRow(label: appText('应用', 'App'), value: kSystemAppName),
            _InfoRow(
              label: appText('版本', 'Version'),
              value: controller.runtime.packageInfo.version,
            ),
            _InfoRow(
              label: appText('构建号', 'Build'),
              value: controller.runtime.packageInfo.buildNumber,
            ),
            _InfoRow(
              label: appText('包名', 'Package'),
              value: controller.runtime.packageInfo.packageName,
            ),
            if (kAppStoreDistribution) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  appText(
                    '当前构建启用了 App Store 分发策略：Apple 渠道会隐藏实验入口，并禁用外部 CLI / 本地 Runtime 能力。',
                    'This build enables the App Store distribution policy: Apple storefront builds hide experimental surfaces and disable external CLI / local runtime capabilities.',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('隐私政策', 'Privacy Policy'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              appText(
                '说明本应用会保存哪些本地设置、哪些用户数据会按你的操作发送到外部网关或 LLM 端点，以及如何清除本地数据。',
                'Explains which settings stay on-device, which user data is sent to your configured gateway or LLM endpoints, and how to clear local data.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              key: const ValueKey('settings-open-privacy-policy'),
              onPressed: () => _showPrivacyPolicyDialog(context),
              icon: const Icon(Icons.privacy_tip_outlined),
              label: Text(appText('查看隐私政策', 'View Privacy Policy')),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _showPrivacyPolicyDialog(BuildContext context) {
    final theme = Theme.of(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(appText('隐私政策', 'Privacy Policy')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Text(
                appText(_privacyPolicyZh, _privacyPolicyEn),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(appText('关闭', 'Close')),
            ),
          ],
        );
      },
    );
  }

  static const String _privacyPolicyZh = '''
XWorkmate 隐私政策

1. 本地保存
- 应用会在本机保存你主动配置的工作区设置、界面偏好、线程草稿和诊断状态。
- 共享 Token、密码、API Key 等敏感信息使用系统安全存储；不会写入普通 SharedPreferences。

2. 发送到外部服务的数据
- 只有在你主动发起连接、发送消息、上传附件或测试连接时，应用才会把当前输入内容发送到你配置的 OpenClaw Gateway 或 LLM API Endpoint。
- 发送内容可能包括：提示词、会话上下文、你明确选择的附件路径与文件内容、以及完成请求所需的认证头。

3. 不会做的事情
- 不会接入广告 SDK，不会做跨应用追踪，不会在未操作时自动读取工作区文件。
- 不会把你的网关密码、共享 Token 或 LLM API Token 上传到本项目默认的开发者服务。

4. 第三方处理
- 你配置的 OpenClaw Gateway、LLM API Endpoint、对象存储或其它外部服务，将按你自己的服务条款处理收到的数据。
- 你需要确认这些外部服务具备你要求的合规能力。

5. 删除与撤回
- 你可以在“设置 -> 诊断/集成”中清除本地线程、移除本地配置，并删除已保存的安全凭据。
- 如果你希望删除已经发送到外部服务的数据，需要在对应外部服务侧执行删除或撤回。
''';

  static const String _privacyPolicyEn = '''
XWorkmate Privacy Policy

1. Local storage
- The app stores the settings, UI preferences, draft threads, and diagnostic state that you explicitly save on this device.
- Shared tokens, passwords, and API keys are stored in platform secure storage instead of plain SharedPreferences.

2. Data sent to external services
- Data is only sent when you explicitly connect, send a message, attach a file, or run a connection test against your configured OpenClaw Gateway or LLM API endpoint.
- Sent data can include prompts, conversation context, user-selected attachment paths and file contents, and the authentication headers required to complete the request.

3. What the app does not do
- It does not include advertising SDKs, cross-app tracking, or automatic workspace file reads without a user action.
- It does not upload your gateway passwords, shared tokens, or LLM API tokens to developer-operated services by default.

4. Third-party processing
- Your configured OpenClaw Gateway, LLM API endpoint, object storage, or other external services process the data you send under their own terms.
- You are responsible for confirming that those external services meet your compliance requirements.

5. Deletion and withdrawal
- You can clear local threads, remove local settings, and delete stored secrets from Settings.
- If you need data removed from an external service, you must request deletion from that external service directly.
''';

  Future<void> _saveSettings(
    AppController controller,
    SettingsSnapshot snapshot,
  ) {
    return controller.saveSettingsDraft(snapshot);
  }

  Future<void> _handleTopLevelSave(AppController controller) async {
    await _captureVisibleSecretDrafts(controller);
    await controller.persistSettingsDraft();
    if (!mounted) {
      return;
    }
    _setState(() {
      _resetSecureFieldUiAfterPersist(controller);
    });
  }

  Future<void> _handleTopLevelApply(AppController controller) async {
    await _captureVisibleSecretDrafts(controller);
    await controller.applySettingsDraft();
    if (!mounted) {
      return;
    }
    _setState(() {
      _resetSecureFieldUiAfterPersist(controller);
    });
  }

  Future<void> _captureVisibleSecretDrafts(AppController controller) async {
    for (var index = 0; index < kGatewayProfileListLength; index += 1) {
      final gatewayToken = _secretOverride(
        _gatewayTokenControllers[index],
        _gatewayTokenStates[index],
      );
      if (gatewayToken.isNotEmpty) {
        controller.saveGatewayTokenDraft(gatewayToken, profileIndex: index);
      }
      final gatewayPassword = _secretOverride(
        _gatewayPasswordControllers[index],
        _gatewayPasswordStates[index],
      );
      if (gatewayPassword.isNotEmpty) {
        controller.saveGatewayPasswordDraft(
          gatewayPassword,
          profileIndex: index,
        );
      }
    }
    final aiGatewayApiKey = _secretOverride(
      _aiGatewayApiKeyController,
      _aiGatewayApiKeyState,
    );
    if (aiGatewayApiKey.isNotEmpty) {
      controller.saveAiGatewayApiKeyDraft(aiGatewayApiKey);
    }
    final vaultToken = _secretOverride(_vaultTokenController, _vaultTokenState);
    if (vaultToken.isNotEmpty) {
      controller.saveVaultTokenDraft(vaultToken);
    }
    final ollamaApiKey = _secretOverride(
      _ollamaApiKeyController,
      _ollamaApiKeyState,
    );
    if (ollamaApiKey.isNotEmpty) {
      controller.saveOllamaCloudApiKeyDraft(ollamaApiKey);
    }
  }

  void _resetSecureFieldUiAfterPersist(AppController controller) {
    final hasStoredAiGatewayApiKey =
        controller.settingsController.secureRefs['ai_gateway_api_key'] != null;
    final hasStoredVaultToken =
        controller.settingsController.secureRefs['vault_token'] != null;
    final hasStoredOllamaApiKey =
        controller.settingsController.secureRefs['ollama_cloud_api_key'] !=
        null;
    for (var index = 0; index < kGatewayProfileListLength; index += 1) {
      _gatewayTokenStates[index] = const _SecretFieldUiState();
      _gatewayPasswordStates[index] = const _SecretFieldUiState();
      _primeSecureFieldController(
        _gatewayTokenControllers[index],
        hasStoredValue: controller.hasStoredGatewayTokenForProfile(index),
        fieldState: _gatewayTokenStates[index],
      );
      _primeSecureFieldController(
        _gatewayPasswordControllers[index],
        hasStoredValue: controller.hasStoredGatewayPasswordForProfile(index),
        fieldState: _gatewayPasswordStates[index],
      );
    }
    _aiGatewayApiKeyState = const _SecretFieldUiState();
    _vaultTokenState = const _SecretFieldUiState();
    _ollamaApiKeyState = const _SecretFieldUiState();
    _primeSecureFieldController(
      _aiGatewayApiKeyController,
      hasStoredValue: hasStoredAiGatewayApiKey,
      fieldState: _aiGatewayApiKeyState,
    );
    _primeSecureFieldController(
      _vaultTokenController,
      hasStoredValue: hasStoredVaultToken,
      fieldState: _vaultTokenState,
    );
    _primeSecureFieldController(
      _ollamaApiKeyController,
      hasStoredValue: hasStoredOllamaApiKey,
      fieldState: _ollamaApiKeyState,
    );
  }

  void _syncGatewayDraftControllers(SettingsSnapshot settings) {
    final current = _selectedGatewayProfile(settings);
    _syncDraftControllerValue(
      _gatewaySetupCodeController,
      current.setupCode,
      syncedValue: _gatewaySetupCodeSyncedValue,
      onSyncedValueChanged: (value) => _gatewaySetupCodeSyncedValue = value,
    );
    _syncDraftControllerValue(
      _gatewayHostController,
      current.host,
      syncedValue: _gatewayHostSyncedValue,
      onSyncedValueChanged: (value) => _gatewayHostSyncedValue = value,
    );
    _syncDraftControllerValue(
      _gatewayPortController,
      '${current.port}',
      syncedValue: _gatewayPortSyncedValue,
      onSyncedValueChanged: (value) => _gatewayPortSyncedValue = value,
    );
  }

  GatewayConnectionProfile _selectedGatewayProfile(SettingsSnapshot settings) {
    final profiles = settings.gatewayProfiles;
    final index = _selectedGatewayProfileIndex.clamp(0, profiles.length - 1);
    return profiles[index];
  }

  RuntimeConnectionMode _gatewayProfileModeForSlot(
    int index,
    GatewayConnectionProfile profile,
  ) {
    if (index == kGatewayLocalProfileIndex) {
      return RuntimeConnectionMode.local;
    }
    if (index == kGatewayRemoteProfileIndex) {
      return RuntimeConnectionMode.remote;
    }
    return switch (profile.mode) {
      RuntimeConnectionMode.local => RuntimeConnectionMode.local,
      RuntimeConnectionMode.remote => RuntimeConnectionMode.remote,
      RuntimeConnectionMode.unconfigured =>
        profile.host.trim().isNotEmpty || profile.setupCode.trim().isNotEmpty
            ? RuntimeConnectionMode.remote
            : RuntimeConnectionMode.unconfigured,
    };
  }

  String _gatewayProfileSlotLabel(int index) {
    return switch (index) {
      kGatewayLocalProfileIndex => appText(
        '本地 OpenClaw Gateway',
        'Local OpenClaw Gateway',
      ),
      kGatewayRemoteProfileIndex => appText(
        '远程 OpenClaw Gateway',
        'Remote OpenClaw Gateway',
      ),
      _ => appText(
        '自定义连接源 ${index - kGatewayCustomProfileStartIndex + 1}',
        'Custom source ${index - kGatewayCustomProfileStartIndex + 1}',
      ),
    };
  }

  String _gatewayProfileChipLabel(int index, {required bool configured}) {
    final label = switch (index) {
      kGatewayLocalProfileIndex => _gatewayProfileSlotLabel(index),
      kGatewayRemoteProfileIndex => _gatewayProfileSlotLabel(index),
      _ => appText(
        '连接源 ${index - kGatewayCustomProfileStartIndex + 1}',
        'Source ${index - kGatewayCustomProfileStartIndex + 1}',
      ),
    };
    return appText(
      configured ? label : '$label（空）',
      configured ? label : '$label (empty)',
    );
  }

  String _gatewayProfileSlotDescription(int index) {
    return switch (index) {
      kGatewayLocalProfileIndex => appText(
        '固定本地连接源，默认 127.0.0.1:18789。这里只维护本地源参数，不切换当前工作模式。',
        'Fixed local source with default 127.0.0.1:18789. This card edits the local source only and does not switch the current work mode.',
      ),
      kGatewayRemoteProfileIndex => appText(
        '固定远程连接源，默认 openclaw.svc.plus:443。这里只维护远程源参数，不切换当前工作模式。',
        'Fixed remote source with default openclaw.svc.plus:443. This card edits the remote source only and does not switch the current work mode.',
      ),
      _ => appText(
        '预留自定义 OpenClaw 连接源槽位。当前版本先做配置存储，不绑定固定工作模式。',
        'Reserved custom OpenClaw source slot. In this build it stores connection settings only and is not bound to a fixed work mode.',
      ),
    };
  }

  GatewayConnectionProfile _buildGatewayDraftProfile(
    SettingsSnapshot settings,
  ) {
    final current = _selectedGatewayProfile(settings);
    final mode = _gatewayProfileModeForSlot(
      _selectedGatewayProfileIndex,
      current,
    );
    final forceSetupCodeMode =
        _navigationContext?.prefersGatewaySetupCode == true &&
        _detail == SettingsDetailPage.gatewayConnection &&
        _selectedGatewayProfileIndex != kGatewayLocalProfileIndex;
    final useSetupCode = mode == RuntimeConnectionMode.local
        ? false
        : forceSetupCodeMode || current.useSetupCode;
    final tls = mode == RuntimeConnectionMode.local ? false : current.tls;
    final parsedPort = int.tryParse(_gatewayPortController.text.trim());
    final decoded = useSetupCode
        ? decodeGatewaySetupCode(_gatewaySetupCodeController.text)
        : null;
    final fallbackPort = switch (mode) {
      RuntimeConnectionMode.local => 18789,
      RuntimeConnectionMode.remote => tls ? 443 : current.port,
      RuntimeConnectionMode.unconfigured => 443,
    };
    return current.copyWith(
      mode: mode,
      useSetupCode: useSetupCode,
      setupCode: useSetupCode ? _gatewaySetupCodeController.text.trim() : '',
      host: useSetupCode
          ? (decoded?.host ?? current.host)
          : _gatewayHostController.text.trim(),
      port: useSetupCode
          ? (decoded?.port ?? current.port)
          : (parsedPort ?? fallbackPort),
      tls: useSetupCode ? (decoded?.tls ?? tls) : tls,
    );
  }

  Future<void> _saveGatewayProfile(
    AppController controller,
    SettingsSnapshot settings,
    GatewayConnectionProfile profile,
  ) async {
    final nextSettings = settings.copyWithGatewayProfileAt(
      _selectedGatewayProfileIndex,
      profile,
    );
    await _saveSettings(controller, nextSettings);
    if (!mounted) {
      return;
    }
    _setState(() {
      _gatewaySetupCodeSyncedValue = profile.setupCode;
      _gatewayHostSyncedValue = profile.host;
      _gatewayPortSyncedValue = '${profile.port}';
      _gatewayTestState = 'idle';
      _gatewayTestMessage = '';
      _gatewayTestEndpoint = '';
    });
  }

  Future<void> _saveGatewayDraft(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final profile = _buildGatewayDraftProfile(settings);
    await _saveGatewayProfile(controller, settings, profile);
  }

  Future<void> _saveGatewayAndPersist(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    await _saveGatewayDraft(controller, settings);
    await _handleTopLevelSave(controller);
  }

  Future<void> _saveGatewayAndApply(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    await _saveGatewayDraft(controller, settings);
    await _handleTopLevelApply(controller);
  }

  Future<void> _saveAiGatewayAndPersist(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    await _saveAiGatewayDraft(controller, settings);
    await _handleTopLevelSave(controller);
  }

  Future<void> _saveAiGatewayAndApply(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    await _saveAiGatewayDraft(controller, settings);
    await _handleTopLevelApply(controller);
  }

  Future<void> _saveMultiAgentConfig(
    AppController controller,
    MultiAgentConfig config,
  ) {
    return controller.saveSettingsDraft(
      controller.settingsDraft.copyWith(multiAgent: config),
    );
  }

  AiGatewayProfile _buildAiGatewayDraft(SettingsSnapshot settings) {
    final draftName = _aiGatewayNameController.text.trim();
    final draftBaseUrl = _aiGatewayUrlController.text.trim();
    final draftApiKeyRef = _aiGatewayApiKeyRefController.text.trim();
    final current = settings.aiGateway;
    final defaults = AiGatewayProfile.defaults();
    final connectionChanged =
        draftBaseUrl != current.baseUrl || draftApiKeyRef != current.apiKeyRef;
    return current.copyWith(
      name: draftName,
      baseUrl: draftBaseUrl,
      apiKeyRef: draftApiKeyRef,
      availableModels: connectionChanged
          ? defaults.availableModels
          : current.availableModels,
      selectedModels: connectionChanged
          ? defaults.selectedModels
          : current.selectedModels,
      syncState: connectionChanged ? defaults.syncState : current.syncState,
      syncMessage: connectionChanged
          ? defaults.syncMessage
          : current.syncMessage,
    );
  }

  Future<void> _saveAiGatewayDraft(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final draft = _buildAiGatewayDraft(settings);
    await _saveSettings(controller, settings.copyWith(aiGateway: draft));
    if (!mounted) {
      return;
    }
    _setState(() {
      _aiGatewayNameSyncedValue = draft.name;
      _aiGatewayUrlSyncedValue = draft.baseUrl;
      _aiGatewayApiKeyRefSyncedValue = draft.apiKeyRef;
      _aiGatewayTestState = draft.syncState;
      _aiGatewayTestMessage = '';
      _aiGatewayTestEndpoint = '';
    });
  }

  Future<void> _testAiGatewayConnection(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final draft = _buildAiGatewayDraft(settings);
    final apiKey = _secretOverride(
      _aiGatewayApiKeyController,
      _aiGatewayApiKeyState,
    );
    _setState(() => _aiGatewayTesting = true);
    try {
      final result = await controller.settingsController
          .testAiGatewayConnection(draft, apiKeyOverride: apiKey);
      if (!mounted) {
        return;
      }
      _setState(() {
        _aiGatewayTestState = result.state;
        _aiGatewayTestMessage = result.message;
        _aiGatewayTestEndpoint = result.endpoint;
      });
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) {
        _setState(() => _aiGatewayTesting = false);
      }
    }
  }

  Future<void> _testVaultConnection(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final token = _secretOverride(_vaultTokenController, _vaultTokenState);
    final message = await controller.testVaultConnectionDraft(
      snapshot: settings,
      tokenOverride: token,
    );
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _testGatewayConnection(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final gatewayDraft = _buildGatewayDraftProfile(settings);
    final selectedProfileIndex = _selectedGatewayProfileIndex.clamp(
      0,
      settings.gatewayProfiles.length - 1,
    );
    final gatewayTokenController =
        _gatewayTokenControllers[selectedProfileIndex];
    final gatewayPasswordController =
        _gatewayPasswordControllers[selectedProfileIndex];
    final gatewayTokenState = _gatewayTokenStates[selectedProfileIndex];
    final gatewayPasswordState = _gatewayPasswordStates[selectedProfileIndex];
    final executionTarget = switch (gatewayDraft.mode) {
      RuntimeConnectionMode.local => AssistantExecutionTarget.local,
      RuntimeConnectionMode.remote => AssistantExecutionTarget.remote,
      RuntimeConnectionMode.unconfigured => AssistantExecutionTarget.remote,
    };
    var token = _secretOverride(gatewayTokenController, gatewayTokenState);
    var password = _secretOverride(
      gatewayPasswordController,
      gatewayPasswordState,
    );
    if (token.isEmpty) {
      token = await controller.settingsController.loadGatewayToken(
        profileIndex: selectedProfileIndex,
      );
    }
    if (password.isEmpty) {
      password = await controller.settingsController.loadGatewayPassword(
        profileIndex: selectedProfileIndex,
      );
    }
    _setState(() => _gatewayTesting = true);
    try {
      final result = await controller.testGatewayConnectionDraft(
        profile: gatewayDraft,
        executionTarget: executionTarget,
        tokenOverride: token,
        passwordOverride: password,
      );
      if (!mounted) {
        return;
      }
      _setState(() {
        _gatewayTestState = result.state;
        _gatewayTestMessage = result.message;
        _gatewayTestEndpoint = result.endpoint;
      });
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) {
        _setState(() => _gatewayTesting = false);
      }
    }
  }

  Widget _buildSettingsSectionActions({
    required AppController controller,
    required Key testKey,
    required Key saveKey,
    required Key applyKey,
    required Future<void> Function() onTest,
    required Future<void> Function() onSave,
    required Future<void> Function() onApply,
    bool testing = false,
    String? testLabel,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton(
          key: testKey,
          onPressed: testing ? null : () => onTest(),
          child: Text(
            testing
                ? appText('测试中...', 'Testing...')
                : (testLabel ?? appText('测试连接', 'Test Connection')),
          ),
        ),
        OutlinedButton(
          key: saveKey,
          onPressed: () => onSave(),
          child: Text(appText('保存', 'Save')),
        ),
        FilledButton.tonal(
          key: applyKey,
          onPressed: () => onApply(),
          child: Text(appText('应用', 'Apply')),
        ),
      ],
    );
  }

  List<String> _filterAiGatewayModels(List<String> models) {
    final query = _aiGatewayModelSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return models;
    }
    return models
        .where((modelId) => modelId.toLowerCase().contains(query))
        .toList(growable: false);
  }

  Widget _buildSecureField({
    Key? fieldKey,
    required TextEditingController controller,
    required String label,
    required bool hasStoredValue,
    required _SecretFieldUiState fieldState,
    required ValueChanged<_SecretFieldUiState> onStateChanged,
    required Future<String> Function() loadValue,
    required Future<void> Function(String) onSubmitted,
    required String storedHelperText,
    required String emptyHelperText,
  }) {
    _primeSecureFieldController(
      controller,
      hasStoredValue: hasStoredValue,
      fieldState: fieldState,
    );
    final showMaskedPlaceholder =
        hasStoredValue && !fieldState.showPlaintext && !fieldState.hasDraft;
    return TextField(
      key: fieldKey,
      controller: controller,
      obscureText: !fieldState.showPlaintext && fieldState.hasDraft,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        helperText: hasStoredValue ? storedHelperText : emptyHelperText,
        suffixIcon: fieldState.loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                tooltip: fieldState.showPlaintext
                    ? appText('隐藏', 'Hide')
                    : appText('查看', 'Reveal'),
                onPressed: () => _toggleSecureFieldVisibility(
                  controller: controller,
                  hasStoredValue: hasStoredValue,
                  fieldState: fieldState,
                  onStateChanged: onStateChanged,
                  loadValue: loadValue,
                ),
                icon: Icon(
                  fieldState.showPlaintext
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
              ),
      ),
      onTap: () {
        if (!showMaskedPlaceholder) {
          return;
        }
        controller.clear();
        onStateChanged(fieldState.copyWith(hasDraft: true));
      },
      onChanged: (value) {
        if (value == _storedSecretMask) {
          return;
        }
        final nextHasDraft = value.trim().isNotEmpty;
        if (nextHasDraft == fieldState.hasDraft) {
          return;
        }
        onStateChanged(fieldState.copyWith(hasDraft: nextHasDraft));
      },
      onSubmitted: (_) => _persistSecureFieldIfNeeded(
        controller: controller,
        hasStoredValue: hasStoredValue,
        fieldState: fieldState,
        onStateChanged: onStateChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }

  Future<void> _toggleSecureFieldVisibility({
    required TextEditingController controller,
    required bool hasStoredValue,
    required _SecretFieldUiState fieldState,
    required ValueChanged<_SecretFieldUiState> onStateChanged,
    required Future<String> Function() loadValue,
  }) async {
    if (fieldState.showPlaintext) {
      if (fieldState.hasDraft) {
        onStateChanged(fieldState.copyWith(showPlaintext: false));
        return;
      }
      if (hasStoredValue) {
        _syncControllerValue(controller, _storedSecretMask);
      } else {
        controller.clear();
      }
      onStateChanged(const _SecretFieldUiState());
      return;
    }
    if (fieldState.hasDraft || !hasStoredValue) {
      onStateChanged(fieldState.copyWith(showPlaintext: true, loading: false));
      return;
    }
    onStateChanged(fieldState.copyWith(loading: true));
    final value = (await loadValue()).trim();
    if (!mounted) {
      return;
    }
    if (value.isNotEmpty) {
      _syncControllerValue(controller, value);
    } else {
      controller.clear();
    }
    onStateChanged(
      const _SecretFieldUiState(showPlaintext: true, hasDraft: false),
    );
  }

  Future<void> _persistSecureFieldIfNeeded({
    required TextEditingController controller,
    required bool hasStoredValue,
    required _SecretFieldUiState fieldState,
    required ValueChanged<_SecretFieldUiState> onStateChanged,
    required Future<void> Function(String) onSubmitted,
  }) async {
    final value = _normalizeSecretValue(controller.text);
    if (value.isEmpty) {
      return;
    }
    if (!fieldState.hasDraft && hasStoredValue) {
      return;
    }
    await onSubmitted(value);
    if (!mounted) {
      return;
    }
    _syncControllerValue(controller, _storedSecretMask);
    onStateChanged(const _SecretFieldUiState());
  }

  void _primeSecureFieldController(
    TextEditingController controller, {
    required bool hasStoredValue,
    required _SecretFieldUiState fieldState,
  }) {
    if (fieldState.showPlaintext || fieldState.hasDraft) {
      return;
    }
    final nextValue = hasStoredValue ? _storedSecretMask : '';
    if (controller.text == nextValue) {
      return;
    }
    _syncControllerValue(controller, nextValue);
  }

  String _secretOverride(
    TextEditingController controller,
    _SecretFieldUiState fieldState,
  ) {
    if (!fieldState.showPlaintext && !fieldState.hasDraft) {
      return '';
    }
    return _normalizeSecretValue(controller.text);
  }

  String _normalizeSecretValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == _storedSecretMask) {
      return '';
    }
    return trimmed;
  }

  _AiGatewayFeedbackTheme _aiGatewayFeedbackTheme(
    BuildContext context,
    String state,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (state) {
      'ready' => _AiGatewayFeedbackTheme(
        background: colorScheme.primaryContainer,
        border: colorScheme.primary,
        foreground: colorScheme.onPrimaryContainer,
      ),
      'empty' => _AiGatewayFeedbackTheme(
        background: colorScheme.secondaryContainer,
        border: colorScheme.secondary,
        foreground: colorScheme.onSecondaryContainer,
      ),
      'error' || 'invalid' => _AiGatewayFeedbackTheme(
        background: colorScheme.errorContainer,
        border: colorScheme.error,
        foreground: colorScheme.onErrorContainer,
      ),
      _ => _AiGatewayFeedbackTheme(
        background: colorScheme.surfaceContainerHighest,
        border: colorScheme.outlineVariant,
        foreground: colorScheme.onSurfaceVariant,
      ),
    };
  }

  void _syncControllerValue(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = controller.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
  }

  void _syncDraftControllerValue(
    TextEditingController controller,
    String value, {
    required String syncedValue,
    required ValueChanged<String> onSyncedValueChanged,
  }) {
    final hasLocalDraft = controller.text != syncedValue;
    if (hasLocalDraft && controller.text != value) {
      return;
    }
    _syncControllerValue(controller, value);
    if (syncedValue != value) {
      onSyncedValueChanged(value);
    }
  }

  bool _matchesRuntimeLogFilter(RuntimeLogEntry entry) {
    final query = _runtimeLogFilterController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final haystack = '${entry.level} ${entry.category} ${entry.message}'
        .toLowerCase();
    return haystack.contains(query);
  }
}
