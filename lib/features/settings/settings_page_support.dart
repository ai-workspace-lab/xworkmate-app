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
import 'settings_page_gateway_llm.dart';
import 'settings_page_presentation.dart';
import 'settings_page_multi_agent.dart';
import 'settings_page_device.dart';
import 'settings_page_widgets.dart';

extension SettingsPageSupportMixinInternal on SettingsPageStateInternal {
  List<Widget> buildAboutInternal(
    BuildContext context,
    AppController controller,
  ) {
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
            InfoRowInternal(label: appText('应用', 'App'), value: kSystemAppName),
            InfoRowInternal(
              label: appText('版本', 'Version'),
              value: controller.runtime.packageInfo.version,
            ),
            InfoRowInternal(
              label: appText('构建号', 'Build'),
              value: controller.runtime.packageInfo.buildNumber,
            ),
            InfoRowInternal(
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
              onPressed: () => showPrivacyPolicyDialogInternal(context),
              icon: const Icon(Icons.privacy_tip_outlined),
              label: Text(appText('查看隐私政策', 'View Privacy Policy')),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> showPrivacyPolicyDialogInternal(BuildContext context) {
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
                appText(privacyPolicyZhInternal, privacyPolicyEnInternal),
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

  static const String privacyPolicyZhInternal = '''
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

  static const String privacyPolicyEnInternal = '''
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

  Future<void> saveSettingsInternal(
    AppController controller,
    SettingsSnapshot snapshot,
  ) {
    return controller.saveSettingsDraft(snapshot);
  }

  Future<void> handleTopLevelApplyInternal(AppController controller) async {
    await captureVisibleSecretDraftsInternal(controller);
    await controller.applySettingsDraft();
    if (!mounted) {
      return;
    }
    setStateInternal(() {
      resetSecureFieldUiAfterPersistInternal(controller);
    });
  }

  Future<void> captureVisibleSecretDraftsInternal(
    AppController controller,
  ) async {
    for (var index = 0; index < kGatewayProfileListLength; index += 1) {
      final gatewayToken = secretOverrideInternal(
        gatewayTokenControllersInternal[index],
        gatewayTokenStatesInternal[index],
      );
      if (gatewayToken.isNotEmpty) {
        controller.saveGatewayTokenDraft(gatewayToken, profileIndex: index);
      }
      final gatewayPassword = secretOverrideInternal(
        gatewayPasswordControllersInternal[index],
        gatewayPasswordStatesInternal[index],
      );
      if (gatewayPassword.isNotEmpty) {
        controller.saveGatewayPasswordDraft(
          gatewayPassword,
          profileIndex: index,
        );
      }
    }
    final aiGatewayApiKey = secretOverrideInternal(
      aiGatewayApiKeyControllerInternal,
      aiGatewayApiKeyStateInternal,
    );
    if (aiGatewayApiKey.isNotEmpty) {
      controller.saveAiGatewayApiKeyDraft(aiGatewayApiKey);
    }
    final vaultToken = secretOverrideInternal(
      vaultTokenControllerInternal,
      vaultTokenStateInternal,
    );
    if (vaultToken.isNotEmpty) {
      controller.saveVaultTokenDraft(vaultToken);
    }
    final ollamaApiKey = secretOverrideInternal(
      ollamaApiKeyControllerInternal,
      ollamaApiKeyStateInternal,
    );
    if (ollamaApiKey.isNotEmpty) {
      controller.saveOllamaCloudApiKeyDraft(ollamaApiKey);
    }
  }

  void resetSecureFieldUiAfterPersistInternal(AppController controller) {
    final aiGatewayRef = controller.settings.aiGateway.apiKeyRef.trim().isEmpty
        ? 'ai_gateway_api_key'
        : controller.settings.aiGateway.apiKeyRef.trim();
    final vaultTokenRef = controller.settings.vault.tokenRef.trim().isEmpty
        ? 'vault_token'
        : controller.settings.vault.tokenRef.trim();
    final hasStoredAiGatewayApiKey =
        controller.settingsController.secureRefs[aiGatewayRef] != null ||
        (aiGatewayRef == 'ai_gateway_api_key' &&
            controller.settingsController.secureRefs['ai_gateway_api_key'] !=
                null) ||
        controller
                .settingsController
                .secureRefs[kAccountManagedSecretTargetAIGatewayAccessToken] !=
            null;
    final hasStoredVaultToken =
        controller.settingsController.secureRefs[vaultTokenRef] != null ||
        (vaultTokenRef == 'vault_token' &&
            controller.settingsController.secureRefs['vault_token'] != null);
    final hasStoredOllamaApiKey =
        controller.settingsController.secureRefs['ollama_cloud_api_key'] !=
        null;
    for (var index = 0; index < kGatewayProfileListLength; index += 1) {
      gatewayTokenStatesInternal[index] = const SecretFieldUiStateInternal();
      gatewayPasswordStatesInternal[index] = const SecretFieldUiStateInternal();
      primeSecureFieldControllerInternal(
        gatewayTokenControllersInternal[index],
        hasStoredValue: controller.hasStoredGatewayTokenForProfile(index),
        fieldState: gatewayTokenStatesInternal[index],
      );
      primeSecureFieldControllerInternal(
        gatewayPasswordControllersInternal[index],
        hasStoredValue: controller.hasStoredGatewayPasswordForProfile(index),
        fieldState: gatewayPasswordStatesInternal[index],
      );
    }
    aiGatewayApiKeyStateInternal = const SecretFieldUiStateInternal();
    vaultTokenStateInternal = const SecretFieldUiStateInternal();
    ollamaApiKeyStateInternal = const SecretFieldUiStateInternal();
    primeSecureFieldControllerInternal(
      aiGatewayApiKeyControllerInternal,
      hasStoredValue: hasStoredAiGatewayApiKey,
      fieldState: aiGatewayApiKeyStateInternal,
    );
    primeSecureFieldControllerInternal(
      vaultTokenControllerInternal,
      hasStoredValue: hasStoredVaultToken,
      fieldState: vaultTokenStateInternal,
    );
    primeSecureFieldControllerInternal(
      ollamaApiKeyControllerInternal,
      hasStoredValue: hasStoredOllamaApiKey,
      fieldState: ollamaApiKeyStateInternal,
    );
  }

  void syncGatewayDraftControllersInternal(SettingsSnapshot settings) {
    final current = selectedGatewayProfileInternal(settings);
    syncDraftControllerValueInternal(
      gatewaySetupCodeControllerInternal,
      current.setupCode,
      syncedValue: gatewaySetupCodeSyncedValueInternal,
      onSyncedValueChanged: (value) =>
          gatewaySetupCodeSyncedValueInternal = value,
    );
    syncDraftControllerValueInternal(
      gatewayHostControllerInternal,
      current.host,
      syncedValue: gatewayHostSyncedValueInternal,
      onSyncedValueChanged: (value) => gatewayHostSyncedValueInternal = value,
    );
    syncDraftControllerValueInternal(
      gatewayPortControllerInternal,
      '${current.port}',
      syncedValue: gatewayPortSyncedValueInternal,
      onSyncedValueChanged: (value) => gatewayPortSyncedValueInternal = value,
    );
    syncDraftControllerValueInternal(
      gatewayTokenRefControllersInternal[selectedGatewayProfileIndexInternal],
      current.tokenRef,
      syncedValue:
          gatewayTokenRefSyncedValuesInternal[selectedGatewayProfileIndexInternal],
      onSyncedValueChanged: (value) =>
          gatewayTokenRefSyncedValuesInternal[selectedGatewayProfileIndexInternal] =
              value,
    );
    syncDraftControllerValueInternal(
      gatewayPasswordRefControllersInternal[selectedGatewayProfileIndexInternal],
      current.passwordRef,
      syncedValue:
          gatewayPasswordRefSyncedValuesInternal[selectedGatewayProfileIndexInternal],
      onSyncedValueChanged: (value) =>
          gatewayPasswordRefSyncedValuesInternal[selectedGatewayProfileIndexInternal] =
              value,
    );
  }

  void syncExternalAcpDraftControllersInternal(SettingsSnapshot settings) {
    final activeKeys = settings.externalAcpEndpoints
        .map((item) => item.providerKey)
        .toSet();
    for (final profile in settings.externalAcpEndpoints) {
      final key = profile.providerKey;
      final labelController = externalAcpLabelControllersInternal.putIfAbsent(
        key,
        () => TextEditingController(),
      );
      final endpointController = externalAcpEndpointControllersInternal
          .putIfAbsent(key, () => TextEditingController());
      final authController = externalAcpAuthControllersInternal.putIfAbsent(
        key,
        () => TextEditingController(),
      );
      syncDraftControllerValueInternal(
        labelController,
        profile.label,
        syncedValue: externalAcpLabelSyncedValuesInternal[key] ?? '',
        onSyncedValueChanged: (value) =>
            externalAcpLabelSyncedValuesInternal[key] = value,
      );
      syncDraftControllerValueInternal(
        endpointController,
        profile.endpoint,
        syncedValue: externalAcpEndpointSyncedValuesInternal[key] ?? '',
        onSyncedValueChanged: (value) =>
            externalAcpEndpointSyncedValuesInternal[key] = value,
      );
      syncDraftControllerValueInternal(
        authController,
        profile.authRef,
        syncedValue: externalAcpAuthSyncedValuesInternal[key] ?? '',
        onSyncedValueChanged: (value) =>
            externalAcpAuthSyncedValuesInternal[key] = value,
      );
    }
    disposeRemovedExternalAcpDraftsInternal(
      externalAcpLabelControllersInternal,
      activeKeys,
    );
    disposeRemovedExternalAcpDraftsInternal(
      externalAcpEndpointControllersInternal,
      activeKeys,
    );
    disposeRemovedExternalAcpDraftsInternal(
      externalAcpAuthControllersInternal,
      activeKeys,
    );
    externalAcpLabelSyncedValuesInternal.removeWhere(
      (key, _) => !activeKeys.contains(key),
    );
    externalAcpEndpointSyncedValuesInternal.removeWhere(
      (key, _) => !activeKeys.contains(key),
    );
    externalAcpAuthSyncedValuesInternal.removeWhere(
      (key, _) => !activeKeys.contains(key),
    );
    externalAcpMessageByProviderInternal.removeWhere(
      (key, _) => !activeKeys.contains(key),
    );
    externalAcpTestingProvidersInternal.removeWhere(
      (key) => !activeKeys.contains(key),
    );
  }

  void syncAcpBridgeServerModeDraftControllersInternal(
    SettingsSnapshot settings,
  ) {
    final selfHosted = settings.acpBridgeServerModeConfig.selfHosted;
    syncDraftControllerValueInternal(
      acpBridgeServerUrlControllerInternal,
      selfHosted.serverUrl,
      syncedValue: acpBridgeServerUrlSyncedValueInternal,
      onSyncedValueChanged: (value) =>
          acpBridgeServerUrlSyncedValueInternal = value,
    );
    syncDraftControllerValueInternal(
      acpBridgeServerUsernameControllerInternal,
      selfHosted.username,
      syncedValue: acpBridgeServerUsernameSyncedValueInternal,
      onSyncedValueChanged: (value) =>
          acpBridgeServerUsernameSyncedValueInternal = value,
    );
    acpBridgeServerPasswordRefSyncedValueInternal = selfHosted.passwordRef;
  }

  void disposeRemovedExternalAcpDraftsInternal(
    Map<String, TextEditingController> controllers,
    Set<String> activeKeys,
  ) {
    final removedKeys = controllers.keys
        .where((key) => !activeKeys.contains(key))
        .toList(growable: false);
    for (final key in removedKeys) {
      controllers.remove(key)?.dispose();
    }
  }

  GatewayConnectionProfile selectedGatewayProfileInternal(
    SettingsSnapshot settings,
  ) {
    final profiles = settings.gatewayProfiles;
    final index = selectedGatewayProfileIndexInternal.clamp(
      0,
      profiles.length - 1,
    );
    return profiles[index];
  }

  RuntimeConnectionMode gatewayProfileModeForSlotInternal(
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

  String gatewayProfileSlotLabelInternal(int index) {
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

  String gatewayProfileChipLabelInternal(
    int index, {
    required bool configured,
  }) {
    final label = switch (index) {
      kGatewayLocalProfileIndex => gatewayProfileSlotLabelInternal(index),
      kGatewayRemoteProfileIndex => gatewayProfileSlotLabelInternal(index),
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

  String gatewayProfileSlotDescriptionInternal(int index) {
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

  GatewayConnectionProfile buildGatewayDraftProfileInternal(
    SettingsSnapshot settings,
  ) {
    final current = selectedGatewayProfileInternal(settings);
    final mode = gatewayProfileModeForSlotInternal(
      selectedGatewayProfileIndexInternal,
      current,
    );
    final forceSetupCodeMode =
        navigationContextInternal?.prefersGatewaySetupCode == true &&
        detailInternal == SettingsDetailPage.gatewayConnection &&
        selectedGatewayProfileIndexInternal != kGatewayLocalProfileIndex;
    final useSetupCode = mode == RuntimeConnectionMode.local
        ? false
        : forceSetupCodeMode || current.useSetupCode;
    final tls = mode == RuntimeConnectionMode.local ? false : current.tls;
    final parsedPort = int.tryParse(gatewayPortControllerInternal.text.trim());
    final decoded = useSetupCode
        ? decodeGatewaySetupCode(gatewaySetupCodeControllerInternal.text)
        : null;
    final fallbackPort = switch (mode) {
      RuntimeConnectionMode.local => 18789,
      RuntimeConnectionMode.remote => tls ? 443 : current.port,
      RuntimeConnectionMode.unconfigured => 443,
    };
    return current.copyWith(
      mode: mode,
      useSetupCode: useSetupCode,
      setupCode: useSetupCode
          ? gatewaySetupCodeControllerInternal.text.trim()
          : '',
      host: useSetupCode
          ? (decoded?.host ?? current.host)
          : gatewayHostControllerInternal.text.trim(),
      port: useSetupCode
          ? (decoded?.port ?? current.port)
          : (parsedPort ?? fallbackPort),
      tls: useSetupCode ? (decoded?.tls ?? tls) : tls,
      tokenRef:
          gatewayTokenRefControllersInternal[selectedGatewayProfileIndexInternal]
              .text
              .trim(),
      passwordRef:
          gatewayPasswordRefControllersInternal[selectedGatewayProfileIndexInternal]
              .text
              .trim(),
    );
  }

  Future<void> saveGatewayProfileInternal(
    AppController controller,
    SettingsSnapshot settings,
    GatewayConnectionProfile profile,
  ) async {
    final executionTarget =
        selectedGatewayProfileIndexInternal == kGatewayLocalProfileIndex
        ? AssistantExecutionTarget.local
        : AssistantExecutionTarget.remote;
    final nextSettings = settings
        .copyWithGatewayProfileAt(selectedGatewayProfileIndexInternal, profile)
        .markGatewayTargetSaved(executionTarget);
    await saveSettingsInternal(controller, nextSettings);
    if (!mounted) {
      return;
    }
    setStateInternal(() {
      gatewaySetupCodeSyncedValueInternal = profile.setupCode;
      gatewayHostSyncedValueInternal = profile.host;
      gatewayPortSyncedValueInternal = '${profile.port}';
      gatewayTokenRefSyncedValuesInternal[selectedGatewayProfileIndexInternal] =
          profile.tokenRef;
      gatewayPasswordRefSyncedValuesInternal[selectedGatewayProfileIndexInternal] =
          profile.passwordRef;
      gatewayTestStateInternal = 'idle';
      gatewayTestMessageInternal = '';
      gatewayTestEndpointInternal = '';
    });
  }

  Future<void> saveGatewayDraftInternal(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final profile = buildGatewayDraftProfileInternal(settings);
    await saveGatewayProfileInternal(controller, settings, profile);
  }

  Future<void> saveGatewayAndApplyInternal(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    await saveGatewayDraftInternal(controller, settings);
    await handleTopLevelApplyInternal(controller);
  }

  Future<void> saveAiGatewayAndApplyInternal(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    await saveAiGatewayDraftInternal(controller, settings);
    await handleTopLevelApplyInternal(controller);
  }

  Future<void> saveMultiAgentConfigInternal(
    AppController controller,
    MultiAgentConfig config,
  ) {
    return controller.saveSettingsDraft(
      controller.settingsDraft.copyWith(multiAgent: config),
    );
  }

  AiGatewayProfile buildAiGatewayDraftInternal(SettingsSnapshot settings) {
    final draftName = aiGatewayNameControllerInternal.text.trim();
    final draftBaseUrl = aiGatewayUrlControllerInternal.text.trim();
    final draftApiKeyRef = aiGatewayApiKeyRefControllerInternal.text.trim();
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

  Future<void> saveAiGatewayDraftInternal(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final draft = buildAiGatewayDraftInternal(settings);
    await saveSettingsInternal(controller, settings.copyWith(aiGateway: draft));
    if (!mounted) {
      return;
    }
    setStateInternal(() {
      aiGatewayNameSyncedValueInternal = draft.name;
      aiGatewayUrlSyncedValueInternal = draft.baseUrl;
      aiGatewayApiKeyRefSyncedValueInternal = draft.apiKeyRef;
      aiGatewayTestStateInternal = draft.syncState;
      aiGatewayTestMessageInternal = '';
      aiGatewayTestEndpointInternal = '';
    });
  }

  Future<void> testAiGatewayConnectionInternal(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final draft = buildAiGatewayDraftInternal(settings);
    final apiKey = secretOverrideInternal(
      aiGatewayApiKeyControllerInternal,
      aiGatewayApiKeyStateInternal,
    );
    setStateInternal(() => aiGatewayTestingInternal = true);
    try {
      final result = await controller.settingsController
          .testAiGatewayConnection(draft, apiKeyOverride: apiKey);
      if (!mounted) {
        return;
      }
      setStateInternal(() {
        aiGatewayTestStateInternal = result.state;
        aiGatewayTestMessageInternal = result.message;
        aiGatewayTestEndpointInternal = result.endpoint;
      });
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) {
        setStateInternal(() => aiGatewayTestingInternal = false);
      }
    }
  }

  Future<void> testVaultConnectionInternal(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final token = secretOverrideInternal(
      vaultTokenControllerInternal,
      vaultTokenStateInternal,
    );
    final message = await controller.testVaultConnectionDraft(
      snapshot: settings,
      tokenOverride: token,
    );
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> testGatewayConnectionInternal(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final gatewayDraft = buildGatewayDraftProfileInternal(settings);
    final selectedProfileIndex = selectedGatewayProfileIndexInternal.clamp(
      0,
      settings.gatewayProfiles.length - 1,
    );
    final gatewayTokenController =
        gatewayTokenControllersInternal[selectedProfileIndex];
    final gatewayPasswordController =
        gatewayPasswordControllersInternal[selectedProfileIndex];
    final gatewayTokenState = gatewayTokenStatesInternal[selectedProfileIndex];
    final gatewayPasswordState =
        gatewayPasswordStatesInternal[selectedProfileIndex];
    final executionTarget = switch (gatewayDraft.mode) {
      RuntimeConnectionMode.local => AssistantExecutionTarget.local,
      RuntimeConnectionMode.remote => AssistantExecutionTarget.remote,
      RuntimeConnectionMode.unconfigured => AssistantExecutionTarget.remote,
    };
    var token = secretOverrideInternal(
      gatewayTokenController,
      gatewayTokenState,
    );
    var password = secretOverrideInternal(
      gatewayPasswordController,
      gatewayPasswordState,
    );
    if (token.isEmpty) {
      token = await controller.settingsController.loadEffectiveGatewayToken(
        profileIndex: selectedProfileIndex,
      );
    }
    if (password.isEmpty) {
      password = await controller.settingsController
          .loadEffectiveGatewayPassword(profileIndex: selectedProfileIndex);
    }
    setStateInternal(() => gatewayTestingInternal = true);
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
      setStateInternal(() {
        gatewayTestStateInternal = result.state;
        gatewayTestMessageInternal = result.message;
        gatewayTestEndpointInternal = result.endpoint;
      });
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) {
        setStateInternal(() => gatewayTestingInternal = false);
      }
    }
  }

  Widget buildSettingsSectionActionsInternal({
    required AppController controller,
    required Key testKey,
    required Key applyKey,
    required Future<void> Function() onTest,
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
        FilledButton.tonal(
          key: applyKey,
          onPressed: () => onApply(),
          child: Text(appText('保存并生效', 'Save & apply')),
        ),
      ],
    );
  }

  List<String> filterAiGatewayModelsInternal(List<String> models) {
    final query = aiGatewayModelSearchControllerInternal.text
        .trim()
        .toLowerCase();
    if (query.isEmpty) {
      return models;
    }
    return models
        .where((modelId) => modelId.toLowerCase().contains(query))
        .toList(growable: false);
  }

  Widget buildSecureFieldInternal({
    Key? fieldKey,
    required TextEditingController controller,
    required String label,
    required bool hasStoredValue,
    required SecretFieldUiStateInternal fieldState,
    required ValueChanged<SecretFieldUiStateInternal> onStateChanged,
    required Future<String> Function() loadValue,
    required Future<void> Function(String) onSubmitted,
    required String storedHelperText,
    required String emptyHelperText,
  }) {
    primeSecureFieldControllerInternal(
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
                onPressed: () => toggleSecureFieldVisibilityInternal(
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
        if (value == storedSecretMaskInternal) {
          return;
        }
        final nextHasDraft = value.trim().isNotEmpty;
        if (nextHasDraft == fieldState.hasDraft) {
          return;
        }
        onStateChanged(fieldState.copyWith(hasDraft: nextHasDraft));
      },
      onSubmitted: (_) => persistSecureFieldIfNeededInternal(
        controller: controller,
        hasStoredValue: hasStoredValue,
        fieldState: fieldState,
        onStateChanged: onStateChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }

  Future<void> toggleSecureFieldVisibilityInternal({
    required TextEditingController controller,
    required bool hasStoredValue,
    required SecretFieldUiStateInternal fieldState,
    required ValueChanged<SecretFieldUiStateInternal> onStateChanged,
    required Future<String> Function() loadValue,
  }) async {
    if (fieldState.showPlaintext) {
      if (fieldState.hasDraft) {
        onStateChanged(fieldState.copyWith(showPlaintext: false));
        return;
      }
      if (hasStoredValue) {
        syncControllerValueInternal(controller, storedSecretMaskInternal);
      } else {
        controller.clear();
      }
      onStateChanged(const SecretFieldUiStateInternal());
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
      syncControllerValueInternal(controller, value);
    } else {
      controller.clear();
    }
    onStateChanged(
      const SecretFieldUiStateInternal(showPlaintext: true, hasDraft: false),
    );
  }

  Future<void> persistSecureFieldIfNeededInternal({
    required TextEditingController controller,
    required bool hasStoredValue,
    required SecretFieldUiStateInternal fieldState,
    required ValueChanged<SecretFieldUiStateInternal> onStateChanged,
    required Future<void> Function(String) onSubmitted,
  }) async {
    final value = normalizeSecretValueInternal(controller.text);
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
    syncControllerValueInternal(controller, storedSecretMaskInternal);
    onStateChanged(const SecretFieldUiStateInternal());
  }

  void primeSecureFieldControllerInternal(
    TextEditingController controller, {
    required bool hasStoredValue,
    required SecretFieldUiStateInternal fieldState,
  }) {
    if (fieldState.showPlaintext || fieldState.hasDraft) {
      return;
    }
    final nextValue = hasStoredValue ? storedSecretMaskInternal : '';
    if (controller.text == nextValue) {
      return;
    }
    syncControllerValueInternal(controller, nextValue);
  }

  String secretOverrideInternal(
    TextEditingController controller,
    SecretFieldUiStateInternal fieldState,
  ) {
    if (!fieldState.showPlaintext && !fieldState.hasDraft) {
      return '';
    }
    return normalizeSecretValueInternal(controller.text);
  }

  String normalizeSecretValueInternal(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == storedSecretMaskInternal) {
      return '';
    }
    return trimmed;
  }

  AiGatewayFeedbackThemeInternal aiGatewayFeedbackThemeInternal(
    BuildContext context,
    String state,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (state) {
      'ready' => AiGatewayFeedbackThemeInternal(
        background: colorScheme.primaryContainer,
        border: colorScheme.primary,
        foreground: colorScheme.onPrimaryContainer,
      ),
      'empty' => AiGatewayFeedbackThemeInternal(
        background: colorScheme.secondaryContainer,
        border: colorScheme.secondary,
        foreground: colorScheme.onSecondaryContainer,
      ),
      'error' || 'invalid' => AiGatewayFeedbackThemeInternal(
        background: colorScheme.errorContainer,
        border: colorScheme.error,
        foreground: colorScheme.onErrorContainer,
      ),
      _ => AiGatewayFeedbackThemeInternal(
        background: colorScheme.surfaceContainerHighest,
        border: colorScheme.outlineVariant,
        foreground: colorScheme.onSurfaceVariant,
      ),
    };
  }

  void syncControllerValueInternal(
    TextEditingController controller,
    String value,
  ) {
    if (controller.text == value) {
      return;
    }
    controller.value = controller.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
  }

  void syncDraftControllerValueInternal(
    TextEditingController controller,
    String value, {
    required String syncedValue,
    required ValueChanged<String> onSyncedValueChanged,
  }) {
    final hasLocalDraft = controller.text != syncedValue;
    if (hasLocalDraft && controller.text != value) {
      return;
    }
    syncControllerValueInternal(controller, value);
    if (syncedValue != value) {
      onSyncedValueChanged(value);
    }
  }

  bool matchesRuntimeLogFilterInternal(RuntimeLogEntry entry) {
    final query = runtimeLogFilterControllerInternal.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final haystack = '${entry.level} ${entry.category} ${entry.message}'
        .toLowerCase();
    return haystack.contains(query);
  }
}
