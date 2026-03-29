// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../app/app_controller_web.dart';
import '../app/app_metadata.dart';
import '../app/ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../widgets/desktop_workspace_scaffold.dart';
import '../widgets/section_tabs.dart';
import '../widgets/surface_card.dart';
import '../widgets/top_bar.dart';
import 'web_settings_page_sections.dart';
import 'web_settings_page_gateway.dart';
import 'web_settings_page_support.dart';

class WebSettingsPage extends StatefulWidget {
  const WebSettingsPage({
    super.key,
    required this.controller,
    this.showSectionTabs = false,
  });

  final AppController controller;
  final bool showSectionTabs;

  @override
  State<WebSettingsPage> createState() => WebSettingsPageStateInternal();
}

enum WebGatewaySettingsSubTabInternal { gateway, llm, acp }

class WebSettingsPageStateInternal extends State<WebSettingsPage> {
  late final TextEditingController directNameControllerInternal;
  late final TextEditingController directBaseUrlControllerInternal;
  late final TextEditingController directProviderControllerInternal;
  late final TextEditingController directApiKeyControllerInternal;
  late final TextEditingController localHostControllerInternal;
  late final TextEditingController localPortControllerInternal;
  late final TextEditingController localTokenControllerInternal;
  late final TextEditingController localPasswordControllerInternal;
  late final TextEditingController remoteHostControllerInternal;
  late final TextEditingController remotePortControllerInternal;
  late final TextEditingController remoteTokenControllerInternal;
  late final TextEditingController remotePasswordControllerInternal;
  late final TextEditingController sessionRemoteBaseUrlControllerInternal;
  late final TextEditingController sessionApiTokenControllerInternal;
  late final Map<String, TextEditingController>
  externalAcpLabelControllersInternal;
  late final Map<String, TextEditingController>
  externalAcpEndpointControllersInternal;
  late WebSessionPersistenceMode sessionPersistenceModeInternal;
  bool remoteTlsInternal = true;
  WebGatewaySettingsSubTabInternal gatewaySubTabInternal =
      WebGatewaySettingsSubTabInternal.gateway;

  String directMessageInternal = '';
  String localGatewayMessageInternal = '';
  String remoteGatewayMessageInternal = '';
  String sessionPersistenceMessageInternal = '';

  @override
  void initState() {
    super.initState();
    directNameControllerInternal = TextEditingController();
    directBaseUrlControllerInternal = TextEditingController();
    directProviderControllerInternal = TextEditingController();
    directApiKeyControllerInternal = TextEditingController();
    localHostControllerInternal = TextEditingController();
    localPortControllerInternal = TextEditingController();
    localTokenControllerInternal = TextEditingController();
    localPasswordControllerInternal = TextEditingController();
    remoteHostControllerInternal = TextEditingController();
    remotePortControllerInternal = TextEditingController();
    remoteTokenControllerInternal = TextEditingController();
    remotePasswordControllerInternal = TextEditingController();
    sessionRemoteBaseUrlControllerInternal = TextEditingController();
    sessionApiTokenControllerInternal = TextEditingController();
    externalAcpLabelControllersInternal = <String, TextEditingController>{};
    externalAcpEndpointControllersInternal = <String, TextEditingController>{};
    sessionPersistenceModeInternal =
        widget.controller.webSessionPersistence.mode;
    syncControllersInternal();
  }

  void setStateInternal(VoidCallback fn) => setState(fn);

  @override
  void didUpdateWidget(covariant WebSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncControllersInternal();
  }

  @override
  void dispose() {
    directNameControllerInternal.dispose();
    directBaseUrlControllerInternal.dispose();
    directProviderControllerInternal.dispose();
    directApiKeyControllerInternal.dispose();
    localHostControllerInternal.dispose();
    localPortControllerInternal.dispose();
    localTokenControllerInternal.dispose();
    localPasswordControllerInternal.dispose();
    remoteHostControllerInternal.dispose();
    remotePortControllerInternal.dispose();
    remoteTokenControllerInternal.dispose();
    remotePasswordControllerInternal.dispose();
    sessionRemoteBaseUrlControllerInternal.dispose();
    sessionApiTokenControllerInternal.dispose();
    for (final controller in externalAcpLabelControllersInternal.values) {
      controller.dispose();
    }
    for (final controller in externalAcpEndpointControllersInternal.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void syncControllersInternal() {
    final settings = widget.controller.settingsDraft;
    final localProfile = settings.primaryLocalGatewayProfile;
    final remoteProfile = settings.primaryRemoteGatewayProfile;
    setIfDifferentInternal(
      directNameControllerInternal,
      settings.aiGateway.name,
    );
    setIfDifferentInternal(
      directBaseUrlControllerInternal,
      settings.aiGateway.baseUrl,
    );
    setIfDifferentInternal(
      directProviderControllerInternal,
      settings.defaultProvider,
    );
    setIfDifferentInternal(
      directApiKeyControllerInternal,
      widget.controller.storedAiGatewayApiKeyMask == null
          ? ''
          : directApiKeyControllerInternal.text,
    );
    setIfDifferentInternal(localHostControllerInternal, localProfile.host);
    setIfDifferentInternal(localPortControllerInternal, '${localProfile.port}');
    setIfDifferentInternal(remoteHostControllerInternal, remoteProfile.host);
    setIfDifferentInternal(
      remotePortControllerInternal,
      '${remoteProfile.port}',
    );
    remoteTlsInternal = remoteProfile.tls;
    setIfDifferentInternal(
      localTokenControllerInternal,
      widget.controller.storedRelayTokenMaskForProfile(
                kGatewayLocalProfileIndex,
              ) ==
              null
          ? ''
          : localTokenControllerInternal.text,
    );
    setIfDifferentInternal(
      localPasswordControllerInternal,
      widget.controller.storedRelayPasswordMaskForProfile(
                kGatewayLocalProfileIndex,
              ) ==
              null
          ? ''
          : localPasswordControllerInternal.text,
    );
    setIfDifferentInternal(
      remoteTokenControllerInternal,
      widget.controller.storedRelayTokenMaskForProfile(
                kGatewayRemoteProfileIndex,
              ) ==
              null
          ? ''
          : remoteTokenControllerInternal.text,
    );
    setIfDifferentInternal(
      remotePasswordControllerInternal,
      widget.controller.storedRelayPasswordMaskForProfile(
                kGatewayRemoteProfileIndex,
              ) ==
              null
          ? ''
          : remotePasswordControllerInternal.text,
    );
    sessionPersistenceModeInternal = settings.webSessionPersistence.mode;
    setIfDifferentInternal(
      sessionRemoteBaseUrlControllerInternal,
      settings.webSessionPersistence.remoteBaseUrl,
    );
    setIfDifferentInternal(
      sessionApiTokenControllerInternal,
      widget.controller.storedWebSessionApiTokenMask == null
          ? ''
          : sessionApiTokenControllerInternal.text,
    );
    syncExternalAcpControllersInternal(settings);
  }

  void syncExternalAcpControllersInternal(SettingsSnapshot settings) {
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
      setIfDifferentInternal(labelController, profile.label);
      setIfDifferentInternal(endpointController, profile.endpoint);
    }
    disposeRemovedControllersInternal(
      externalAcpLabelControllersInternal,
      activeKeys,
    );
    disposeRemovedControllersInternal(
      externalAcpEndpointControllersInternal,
      activeKeys,
    );
  }

  void disposeRemovedControllersInternal(
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

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final uiFeatures = controller.featuresFor(UiFeaturePlatform.web);
        final availableTabs = uiFeatures.availableSettingsTabs;
        final currentTab = uiFeatures.sanitizeSettingsTab(
          controller.settingsTab,
        );
        final showGlobalApplyBar =
            !widget.showSectionTabs ||
            currentTab != SettingsTab.gateway ||
            gatewaySubTabInternal == WebGatewaySettingsSubTabInternal.acp;
        return DesktopWorkspaceScaffold(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TopBar(
                  breadcrumbs: <AppBreadcrumbItem>[
                    AppBreadcrumbItem(
                      label: appText('主页', 'Home'),
                      icon: Icons.home_rounded,
                      onTap: controller.navigateHome,
                    ),
                    AppBreadcrumbItem(
                      label: appText('设置', 'Settings'),
                      onTap: () => controller.openSettings(tab: currentTab),
                    ),
                    AppBreadcrumbItem(label: currentTab.label),
                  ],
                  title: appText('设置', 'Settings'),
                  subtitle: appText(
                    '配置 XWorkmate Web 工作区、网关默认项、界面与诊断选项',
                    'Configure workspace, gateway defaults, appearance, and diagnostics for XWorkmate Web.',
                  ),
                  trailing: SizedBox(
                    width: 260,
                    child: TextField(
                      key: const ValueKey('web-settings-search-field'),
                      decoration: InputDecoration(
                        hintText: appText('搜索设置', 'Search settings'),
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (showGlobalApplyBar) ...[
                  buildGlobalApplyBarInternal(context, controller),
                  const SizedBox(height: 16),
                ],
                if (widget.showSectionTabs) ...[
                  SectionTabs(
                    items: availableTabs.map((item) => item.label).toList(),
                    value: currentTab.label,
                    onChanged: (label) {
                      final tab = availableTabs.firstWhere(
                        (item) => item.label == label,
                      );
                      controller.setSettingsTab(tab);
                    },
                  ),
                  const SizedBox(height: 24),
                ],
                ...(widget.showSectionTabs
                    ? buildTabContentInternal(
                        context,
                        controller,
                        controller.settingsDraft,
                        currentTab,
                      )
                    : buildOverviewContentInternal(
                        context,
                        controller,
                        controller.settingsDraft,
                        availableTabs,
                        currentTab,
                      )),
              ],
            ),
          ),
        );
      },
    );
  }
}
