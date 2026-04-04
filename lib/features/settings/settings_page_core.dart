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
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import 'codex_integration_card.dart';
import 'skill_directory_authorization_card.dart';
import '../../widgets/settings_page_shell.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';
import 'settings_page_sections.dart';
import 'settings_page_gateway.dart';
import 'settings_page_gateway_connection.dart';
import 'settings_page_gateway_llm.dart';
import 'settings_page_presentation.dart';
import 'settings_page_multi_agent.dart';
import 'settings_page_support.dart';
import 'settings_page_device.dart';
import 'settings_page_widgets.dart';

const storedSecretMaskInternal = '****';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.initialTab = SettingsTab.general,
    this.initialDetail,
    this.navigationContext,
    this.showSectionTabs = false,
  });

  final AppController controller;
  final SettingsTab initialTab;
  final SettingsDetailPage? initialDetail;
  final SettingsNavigationContext? navigationContext;
  final bool showSectionTabs;

  @override
  State<SettingsPage> createState() => SettingsPageStateInternal();
}

class SettingsPageStateInternal extends State<SettingsPage> {
  late SettingsTab tabInternal;
  SettingsDetailPage? detailInternal;
  SettingsNavigationContext? navigationContextInternal;
  late final TextEditingController aiGatewayNameControllerInternal;
  late final TextEditingController aiGatewayUrlControllerInternal;
  late final TextEditingController aiGatewayApiKeyRefControllerInternal;
  late final TextEditingController aiGatewayApiKeyControllerInternal;
  late final TextEditingController aiGatewayModelSearchControllerInternal;
  late final TextEditingController gatewaySetupCodeControllerInternal;
  late final TextEditingController gatewayHostControllerInternal;
  late final TextEditingController gatewayPortControllerInternal;
  late final List<TextEditingController> gatewayTokenControllersInternal;
  late final List<TextEditingController> gatewayPasswordControllersInternal;
  late final TextEditingController vaultTokenControllerInternal;
  late final TextEditingController ollamaApiKeyControllerInternal;
  late final TextEditingController runtimeLogFilterControllerInternal;
  late final Map<String, TextEditingController>
  externalAcpLabelControllersInternal;
  late final Map<String, TextEditingController>
  externalAcpEndpointControllersInternal;
  late final Map<String, String> externalAcpLabelSyncedValuesInternal;
  late final Map<String, String> externalAcpEndpointSyncedValuesInternal;
  late final Map<String, String> externalAcpMessageByProviderInternal;
  late final Set<String> externalAcpTestingProvidersInternal;
  bool gatewayTestingInternal = false;
  String gatewayTestStateInternal = 'idle';
  String gatewayTestMessageInternal = '';
  String gatewayTestEndpointInternal = '';
  bool openClawGatewayExpandedInternal = true;
  bool vaultServerExpandedInternal = true;
  bool aiGatewayExpandedInternal = true;
  bool externalAcpExpandedInternal = true;
  bool skillsDirectoryAuthorizationExpandedInternal = true;
  int selectedGatewayProfileIndexInternal = kGatewayLocalProfileIndex;
  String gatewaySetupCodeSyncedValueInternal = '';
  String gatewayHostSyncedValueInternal = '';
  String gatewayPortSyncedValueInternal = '';
  late final List<SecretFieldUiStateInternal> gatewayTokenStatesInternal;
  late final List<SecretFieldUiStateInternal> gatewayPasswordStatesInternal;
  bool aiGatewayTestingInternal = false;
  String aiGatewayTestStateInternal = 'idle';
  String aiGatewayTestMessageInternal = '';
  String aiGatewayTestEndpointInternal = '';
  GatewayIntegrationSubTabInternal integrationSubTabInternal =
      GatewayIntegrationSubTabInternal.gateway;
  int llmEndpointSlotLimitInternal = 1;
  int selectedLlmEndpointIndexInternal = 0;
  String aiGatewayNameSyncedValueInternal = '';
  String aiGatewayUrlSyncedValueInternal = '';
  String aiGatewayApiKeyRefSyncedValueInternal = '';
  SecretFieldUiStateInternal aiGatewayApiKeyStateInternal =
      const SecretFieldUiStateInternal();
  SecretFieldUiStateInternal vaultTokenStateInternal =
      const SecretFieldUiStateInternal();
  SecretFieldUiStateInternal ollamaApiKeyStateInternal =
      const SecretFieldUiStateInternal();

  @override
  void initState() {
    super.initState();
    tabInternal = widget.initialTab;
    detailInternal = widget.initialDetail;
    navigationContextInternal = widget.navigationContext;
    aiGatewayNameControllerInternal = TextEditingController();
    aiGatewayUrlControllerInternal = TextEditingController();
    aiGatewayApiKeyRefControllerInternal = TextEditingController();
    aiGatewayApiKeyControllerInternal = TextEditingController();
    aiGatewayModelSearchControllerInternal = TextEditingController();
    gatewaySetupCodeControllerInternal = TextEditingController();
    gatewayHostControllerInternal = TextEditingController();
    gatewayPortControllerInternal = TextEditingController();
    gatewayTokenControllersInternal = List<TextEditingController>.generate(
      kGatewayProfileListLength,
      (_) => TextEditingController(),
      growable: false,
    );
    gatewayPasswordControllersInternal = List<TextEditingController>.generate(
      kGatewayProfileListLength,
      (_) => TextEditingController(),
      growable: false,
    );
    gatewayTokenStatesInternal = List<SecretFieldUiStateInternal>.filled(
      kGatewayProfileListLength,
      const SecretFieldUiStateInternal(),
      growable: false,
    );
    gatewayPasswordStatesInternal = List<SecretFieldUiStateInternal>.filled(
      kGatewayProfileListLength,
      const SecretFieldUiStateInternal(),
      growable: false,
    );
    vaultTokenControllerInternal = TextEditingController();
    ollamaApiKeyControllerInternal = TextEditingController();
    runtimeLogFilterControllerInternal = TextEditingController();
    externalAcpLabelControllersInternal = <String, TextEditingController>{};
    externalAcpEndpointControllersInternal = <String, TextEditingController>{};
    externalAcpLabelSyncedValuesInternal = <String, String>{};
    externalAcpEndpointSyncedValuesInternal = <String, String>{};
    externalAcpMessageByProviderInternal = <String, String>{};
    externalAcpTestingProvidersInternal = <String>{};
  }

  void setStateInternal(VoidCallback fn) => setState(fn);

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != tabInternal) {
      tabInternal = widget.initialTab;
    }
    if (widget.initialDetail != detailInternal) {
      detailInternal = widget.initialDetail;
    }
    if (widget.navigationContext != navigationContextInternal) {
      navigationContextInternal = widget.navigationContext;
    }
    applyGatewayNavigationHintsInternal();
  }

  void applyGatewayNavigationHintsInternal() {
    final detail = detailInternal;
    final navigationContext = navigationContextInternal;
    if (detail != SettingsDetailPage.gatewayConnection ||
        navigationContext == null) {
      return;
    }
    final gatewayProfileIndex = navigationContext.gatewayProfileIndex;
    if (gatewayProfileIndex == null) {
      return;
    }
    selectedGatewayProfileIndexInternal = gatewayProfileIndex.clamp(
      0,
      kGatewayProfileListLength - 1,
    );
  }

  bool prefersGatewaySetupCodeForCurrentContextInternal(BuildContext context) {
    return resolveUiFeaturePlatformFromContext(context) ==
            UiFeaturePlatform.mobile &&
        detailInternal == SettingsDetailPage.gatewayConnection &&
        navigationContextInternal?.prefersGatewaySetupCode == true &&
        selectedGatewayProfileIndexInternal != kGatewayLocalProfileIndex;
  }

  @override
  void dispose() {
    aiGatewayNameControllerInternal.dispose();
    aiGatewayUrlControllerInternal.dispose();
    aiGatewayApiKeyRefControllerInternal.dispose();
    aiGatewayApiKeyControllerInternal.dispose();
    aiGatewayModelSearchControllerInternal.dispose();
    gatewaySetupCodeControllerInternal.dispose();
    gatewayHostControllerInternal.dispose();
    gatewayPortControllerInternal.dispose();
    for (final controller in gatewayTokenControllersInternal) {
      controller.dispose();
    }
    for (final controller in gatewayPasswordControllersInternal) {
      controller.dispose();
    }
    vaultTokenControllerInternal.dispose();
    ollamaApiKeyControllerInternal.dispose();
    runtimeLogFilterControllerInternal.dispose();
    for (final controller in externalAcpLabelControllersInternal.values) {
      controller.dispose();
    }
    for (final controller in externalAcpEndpointControllersInternal.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final palette = context.palette;
        final featurePlatform = resolveUiFeaturePlatformFromContext(context);
        final uiFeatures = controller.featuresFor(featurePlatform);
        tabInternal = uiFeatures.sanitizeSettingsTab(controller.settingsTab);
        detailInternal = controller.settingsDetail;
        navigationContextInternal = controller.settingsNavigationContext;
        applyGatewayNavigationHintsInternal();
        final settings = controller.settingsDraft;
        final showingDetail = detailInternal != null;
        final showGlobalApplyBar =
            !showingDetail &&
            (tabInternal != SettingsTab.gateway ||
                integrationSubTabInternal ==
                    GatewayIntegrationSubTabInternal.acp);
        return Theme(
          data: theme.copyWith(
            inputDecorationTheme: theme.inputDecorationTheme.copyWith(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: BorderSide(
                  color: palette.strokeSoft,
                  width: settingsHairlineBorderWidthInternal,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: BorderSide(
                  color: palette.strokeSoft,
                  width: settingsHairlineBorderWidthInternal,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: BorderSide(
                  color: palette.accent.withValues(alpha: 0.32),
                  width: settingsHairlineBorderWidthInternal,
                ),
              ),
            ),
          ),
          child: SettingsPageBodyShell(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            breadcrumbs: buildSettingsBreadcrumbs(
              controller,
              tab: tabInternal,
              detail: detailInternal,
              navigationContext: navigationContextInternal,
            ),
            title: appText('设置', 'Settings'),
            subtitle: showingDetail
                ? appText(
                    '当前正在编辑详细设置参数，保存后会回写到对应状态页。',
                    'You are editing detailed settings. Saved values flow back to the related status page.',
                  )
                : appText(
                    '配置 $kProductBrandName 工作区、网关默认项、界面与诊断选项',
                    'Configure workspace, gateway defaults, appearance, and diagnostics for $kProductBrandName.',
                  ),
            trailing: SizedBox(
              width: showingDetail ? 168 : 220,
              child: showingDetail
                  ? OutlinedButton.icon(
                      onPressed: () {
                        controller.closeSettingsDetail();
                        setState(() {
                          detailInternal = null;
                          navigationContextInternal = null;
                        });
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: Text(appText('返回概览', 'Back to overview')),
                    )
                  : TextField(
                      decoration: InputDecoration(
                        hintText: appText('搜索设置', 'Search settings'),
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
            ),
            globalApplyBar: showGlobalApplyBar
                ? buildGlobalApplyBarInternal(context, controller)
                : null,
            bodyChildren: buildContentForCurrentStateInternal(
              context,
              controller,
              settings,
              uiFeatures,
            ),
          ),
        );
      },
    );
  }
}
