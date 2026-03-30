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
import 'settings_page_gateway_llm.dart';
import 'settings_page_presentation.dart';
import 'settings_page_multi_agent.dart';
import 'settings_page_support.dart';
import 'settings_page_device.dart';
import 'settings_page_widgets.dart';

extension SettingsPageGatewayConnectionMixinInternal
    on SettingsPageStateInternal {
  Widget buildOpenClawGatewayCardInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    return SurfaceCard(
      borderWidth: settingsHairlineBorderWidthInternal,
      child: buildOpenClawGatewayCardBodyInternal(
        context,
        controller,
        settings,
      ),
    );
  }

  Widget buildOpenClawGatewayCardBodyInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    syncGatewayDraftControllersInternal(settings);
    final theme = Theme.of(context);
    final gatewayProfiles = settings.gatewayProfiles;
    final selectedProfileIndex = selectedGatewayProfileIndexInternal.clamp(
      0,
      gatewayProfiles.length - 1,
    );
    final gatewayProfile = gatewayProfiles[selectedProfileIndex];
    final gatewayMode = gatewayProfileModeForSlotInternal(
      selectedProfileIndex,
      gatewayProfile,
    );
    final gatewayTokenController =
        gatewayTokenControllersInternal[selectedProfileIndex];
    final gatewayPasswordController =
        gatewayPasswordControllersInternal[selectedProfileIndex];
    final gatewayTokenState = gatewayTokenStatesInternal[selectedProfileIndex];
    final gatewayPasswordState =
        gatewayPasswordStatesInternal[selectedProfileIndex];
    final uiFeatures = controller.featuresFor(
      resolveUiFeaturePlatformFromContext(context),
    );
    final setupCodeFeatureEnabled = uiFeatures.supportsGatewaySetupCode;
    final forceSetupCodeMode = prefersGatewaySetupCodeForCurrentContextInternal(
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
            '这里维护外部 Gateway / ACP endpoint 连接源 profile。工作模式在会话区单独切换：single-agent 通过标准 ACP 协议直连外部 Agent；local/remote 继续走 Gateway。保存并生效：立即按当前配置更新。',
            'This card edits external Gateway / ACP endpoint profiles. Work mode is switched in the session UI: single-agent connects to an external Agent over the standard ACP protocol, while local/remote continue through Gateway. Save & apply updates the active configuration immediately.',
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
                gatewayProfileChipLabelInternal(index, configured: configured),
              ),
              onSelected: (_) {
                setStateInternal(() {
                  selectedGatewayProfileIndexInternal = index;
                  gatewayTestStateInternal = 'idle';
                  gatewayTestMessageInternal = '';
                  gatewayTestEndpointInternal = '';
                });
              },
            );
          }),
        ),
        const SizedBox(height: 12),
        Text(
          gatewayProfileSlotDescriptionInternal(selectedProfileIndex),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (selectedProfileIndex != kGatewayLocalProfileIndex &&
            !forceSetupCodeMode &&
            setupCodeFeatureEnabled) ...[
          if (widget.showSectionTabs)
            SectionTabs(
              items: [
                appText('配置码', 'Setup Code'),
                appText('手动配置', 'Manual'),
              ],
              value: useSetupCode
                  ? appText('配置码', 'Setup Code')
                  : appText('手动配置', 'Manual'),
              size: SectionTabsSize.small,
              onChanged: (value) {
                final nextUseSetupCode = value == appText('配置码', 'Setup Code');
                unawaited(
                  saveGatewayProfileInternal(
                    controller,
                    settings,
                    gatewayProfile.copyWith(useSetupCode: nextUseSetupCode),
                  ).catchError((_) {}),
                );
              },
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: Text(appText('配置码', 'Setup Code')),
                  selected: useSetupCode,
                  onSelected: (_) => unawaited(
                    saveGatewayProfileInternal(
                      controller,
                      settings,
                      gatewayProfile.copyWith(useSetupCode: true),
                    ).catchError((_) {}),
                  ),
                ),
                FilterChip(
                  label: Text(appText('手动配置', 'Manual')),
                  selected: !useSetupCode,
                  onSelected: (_) => unawaited(
                    saveGatewayProfileInternal(
                      controller,
                      settings,
                      gatewayProfile.copyWith(useSetupCode: false),
                    ).catchError((_) {}),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
        ],
        if (selectedProfileIndex != kGatewayLocalProfileIndex &&
            useSetupCode) ...[
          TextField(
            key: const ValueKey('gateway-setup-code-field'),
            controller: gatewaySetupCodeControllerInternal,
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
              saveGatewayDraftInternal(controller, settings).catchError((_) {}),
            ),
            onSubmitted: (_) => saveGatewayDraftInternal(controller, settings),
          ),
        ] else ...[
          TextField(
            key: const ValueKey('gateway-host-field'),
            controller: gatewayHostControllerInternal,
            decoration: InputDecoration(labelText: appText('主机', 'Host')),
            onChanged: (_) => unawaited(
              saveGatewayDraftInternal(controller, settings).catchError((_) {}),
            ),
            onSubmitted: (_) => saveGatewayDraftInternal(controller, settings),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: const ValueKey('gateway-port-field'),
                  controller: gatewayPortControllerInternal,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: appText('端口', 'Port')),
                  onChanged: (_) => unawaited(
                    saveGatewayDraftInternal(
                      controller,
                      settings,
                    ).catchError((_) {}),
                  ),
                  onSubmitted: (_) =>
                      saveGatewayDraftInternal(controller, settings),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Opacity(
                  opacity: gatewayMode == RuntimeConnectionMode.local ? 0.6 : 1,
                  child: InlineSwitchFieldInternal(
                    label: 'TLS',
                    value: gatewayTls,
                    onChanged: (value) {
                      if (gatewayMode == RuntimeConnectionMode.local) {
                        return;
                      }
                      unawaited(
                        saveGatewayProfileInternal(
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
        buildSecureFieldInternal(
          fieldKey: const ValueKey('gateway-shared-token-field'),
          controller: gatewayTokenController,
          label: appText('共享 Token', 'Shared Token'),
          hasStoredValue: hasStoredGatewayToken,
          fieldState: gatewayTokenState,
          onStateChanged: (value) => setStateInternal(
            () => gatewayTokenStatesInternal[selectedProfileIndex] = value,
          ),
          loadValue: () => controller.settingsController.loadGatewayToken(
            profileIndex: selectedProfileIndex,
          ),
          onSubmitted: (value) async => controller.saveGatewayTokenDraft(
            value,
            profileIndex: selectedProfileIndex,
          ),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示；可直接测试，也可通过本区保存并生效提交。',
            'Stored securely. Test directly or submit with the local Save & apply action.',
          ),
          emptyHelperText: appText(
            '输入后先进入草稿；通过本区保存并生效提交。',
            'Values stage into draft first; submit with the local Save & apply action.',
          ),
        ),
        const SizedBox(height: 12),
        buildSecureFieldInternal(
          fieldKey: const ValueKey('gateway-password-field'),
          controller: gatewayPasswordController,
          label: appText('密码', 'Password'),
          hasStoredValue: hasStoredGatewayPassword,
          fieldState: gatewayPasswordState,
          onStateChanged: (value) => setStateInternal(
            () => gatewayPasswordStatesInternal[selectedProfileIndex] = value,
          ),
          loadValue: () => controller.settingsController.loadGatewayPassword(
            profileIndex: selectedProfileIndex,
          ),
          onSubmitted: (value) async => controller.saveGatewayPasswordDraft(
            value,
            profileIndex: selectedProfileIndex,
          ),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示；可直接测试，也可通过本区保存并生效提交。',
            'Stored securely. Test directly or submit with the local Save & apply action.',
          ),
          emptyHelperText: appText(
            '输入后先进入草稿；通过本区保存并生效提交。',
            'Values stage into draft first; submit with the local Save & apply action.',
          ),
        ),
        const SizedBox(height: 16),
        buildSettingsSectionActionsInternal(
          controller: controller,
          testKey: const ValueKey('gateway-test-button'),
          applyKey: const ValueKey('gateway-apply-button'),
          testing: gatewayTestingInternal,
          onTest: () => testGatewayConnectionInternal(controller, settings),
          onApply: () => saveGatewayAndApplyInternal(controller, settings),
        ),
        const SizedBox(height: 16),
        buildDeviceSecurityCardInternal(context, controller),
        if (gatewayTestMessageInternal.isNotEmpty) ...[
          const SizedBox(height: 12),
          buildNoticeInternal(
            context,
            tone: gatewayTestStateInternal == 'success'
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.errorContainer,
            title: appText('测试连接', 'Test Connection'),
            message: gatewayTestEndpointInternal.isEmpty
                ? gatewayTestMessageInternal
                : '$gatewayTestMessageInternal\n$gatewayTestEndpointInternal',
          ),
        ],
      ],
    );
  }

  Widget buildVaultProviderCardInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    return SurfaceCard(
      borderWidth: settingsHairlineBorderWidthInternal,
      child: buildVaultProviderCardBodyInternal(context, controller, settings),
    );
  }

  Widget buildVaultProviderCardBodyInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final hasStoredVaultToken =
        controller.settingsController.secureRefs['vault_token'] != null;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appText(
            '这里维护 Vault K/V 接入的服务地址与 root token。URL 进入设置草稿；root token 只会进入安全存储，不会写入普通 settings 持久层。',
            'Manage the Vault K/V endpoint and root token here. The URL stays in the settings draft, while the root token is persisted only through secure storage.',
          ),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        EditableFieldInternal(
          fieldKey: const ValueKey('vault-server-url-field'),
          label: 'VAULT_SERVER_URL',
          value: settings.vault.address,
          onSubmitted: (value) => saveSettingsInternal(
            controller,
            settings.copyWith(vault: settings.vault.copyWith(address: value)),
          ),
        ),
        EditableFieldInternal(
          fieldKey: const ValueKey('vault-namespace-field'),
          label: appText('Namespace（可选）', 'Namespace (optional)'),
          value: settings.vault.namespace,
          onSubmitted: (value) => saveSettingsInternal(
            controller,
            settings.copyWith(vault: settings.vault.copyWith(namespace: value)),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            appText(
              '当前固定使用 token 模式，安全引用保持为 vault_token。',
              'The current integration uses token auth, with the secure reference fixed to vault_token.',
            ),
            style: theme.textTheme.bodySmall,
          ),
        ),
        buildSecureFieldInternal(
          fieldKey: const ValueKey('vault-root-access-token-field'),
          controller: vaultTokenControllerInternal,
          label: 'VAULT_SERVER_ROOT_ACCESS_TOKEN (${settings.vault.tokenRef})',
          hasStoredValue: hasStoredVaultToken,
          fieldState: vaultTokenStateInternal,
          onStateChanged: (value) =>
              setStateInternal(() => vaultTokenStateInternal = value),
          loadValue: controller.settingsController.loadVaultToken,
          onSubmitted: (value) async => controller.saveVaultTokenDraft(value),
          storedHelperText: appText(
            '已安全保存；Vault root token 只会在测试连接或显式保存时使用。',
            'Stored securely. The Vault root token is only used for test or save-and-apply flows.',
          ),
          emptyHelperText: appText(
            '输入后先进入草稿；点击“保存并生效”后才会写入安全存储。',
            'Values stage into draft first and only persist to secure storage after Save & apply.',
          ),
        ),
        const SizedBox(height: 12),
        buildSettingsSectionActionsInternal(
          controller: controller,
          testKey: const ValueKey('vault-test-button'),
          applyKey: const ValueKey('vault-apply-button'),
          onTest: () => testVaultConnectionInternal(controller, settings),
          onApply: () => handleTopLevelApplyInternal(controller),
          testLabel:
              '${appText('测试连接', 'Test Connection')} · ${controller.settingsController.vaultStatus}',
        ),
      ],
    );
  }
}
