part of 'web_settings_page.dart';

class WebSettingsPage extends StatefulWidget {
  const WebSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebSettingsPage> createState() => _WebSettingsPageState();
}

enum _WebGatewaySettingsSubTab { gateway, llm, acp }

class _WebSettingsPageState extends State<WebSettingsPage> {
  late final TextEditingController _directNameController;
  late final TextEditingController _directBaseUrlController;
  late final TextEditingController _directProviderController;
  late final TextEditingController _directApiKeyController;
  late final TextEditingController _localHostController;
  late final TextEditingController _localPortController;
  late final TextEditingController _localTokenController;
  late final TextEditingController _localPasswordController;
  late final TextEditingController _remoteHostController;
  late final TextEditingController _remotePortController;
  late final TextEditingController _remoteTokenController;
  late final TextEditingController _remotePasswordController;
  late final TextEditingController _sessionRemoteBaseUrlController;
  late final TextEditingController _sessionApiTokenController;
  late final Map<String, TextEditingController> _externalAcpLabelControllers;
  late final Map<String, TextEditingController> _externalAcpEndpointControllers;
  late WebSessionPersistenceMode _sessionPersistenceMode;
  bool _remoteTls = true;
  _WebGatewaySettingsSubTab _gatewaySubTab = _WebGatewaySettingsSubTab.gateway;

  String _directMessage = '';
  String _localGatewayMessage = '';
  String _remoteGatewayMessage = '';
  String _sessionPersistenceMessage = '';

  @override
  void initState() {
    super.initState();
    _directNameController = TextEditingController();
    _directBaseUrlController = TextEditingController();
    _directProviderController = TextEditingController();
    _directApiKeyController = TextEditingController();
    _localHostController = TextEditingController();
    _localPortController = TextEditingController();
    _localTokenController = TextEditingController();
    _localPasswordController = TextEditingController();
    _remoteHostController = TextEditingController();
    _remotePortController = TextEditingController();
    _remoteTokenController = TextEditingController();
    _remotePasswordController = TextEditingController();
    _sessionRemoteBaseUrlController = TextEditingController();
    _sessionApiTokenController = TextEditingController();
    _externalAcpLabelControllers = <String, TextEditingController>{};
    _externalAcpEndpointControllers = <String, TextEditingController>{};
    _sessionPersistenceMode = widget.controller.webSessionPersistence.mode;
    _syncControllers();
  }

  void _setState(VoidCallback fn) => setState(fn);

  @override
  void didUpdateWidget(covariant WebSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  @override
  void dispose() {
    _directNameController.dispose();
    _directBaseUrlController.dispose();
    _directProviderController.dispose();
    _directApiKeyController.dispose();
    _localHostController.dispose();
    _localPortController.dispose();
    _localTokenController.dispose();
    _localPasswordController.dispose();
    _remoteHostController.dispose();
    _remotePortController.dispose();
    _remoteTokenController.dispose();
    _remotePasswordController.dispose();
    _sessionRemoteBaseUrlController.dispose();
    _sessionApiTokenController.dispose();
    for (final controller in _externalAcpLabelControllers.values) {
      controller.dispose();
    }
    for (final controller in _externalAcpEndpointControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    final settings = widget.controller.settingsDraft;
    final localProfile = settings.primaryLocalGatewayProfile;
    final remoteProfile = settings.primaryRemoteGatewayProfile;
    _setIfDifferent(_directNameController, settings.aiGateway.name);
    _setIfDifferent(_directBaseUrlController, settings.aiGateway.baseUrl);
    _setIfDifferent(_directProviderController, settings.defaultProvider);
    _setIfDifferent(
      _directApiKeyController,
      widget.controller.storedAiGatewayApiKeyMask == null
          ? ''
          : _directApiKeyController.text,
    );
    _setIfDifferent(_localHostController, localProfile.host);
    _setIfDifferent(_localPortController, '${localProfile.port}');
    _setIfDifferent(_remoteHostController, remoteProfile.host);
    _setIfDifferent(_remotePortController, '${remoteProfile.port}');
    _remoteTls = remoteProfile.tls;
    _setIfDifferent(
      _localTokenController,
      widget.controller.storedRelayTokenMaskForProfile(
                kGatewayLocalProfileIndex,
              ) ==
              null
          ? ''
          : _localTokenController.text,
    );
    _setIfDifferent(
      _localPasswordController,
      widget.controller.storedRelayPasswordMaskForProfile(
                kGatewayLocalProfileIndex,
              ) ==
              null
          ? ''
          : _localPasswordController.text,
    );
    _setIfDifferent(
      _remoteTokenController,
      widget.controller.storedRelayTokenMaskForProfile(
                kGatewayRemoteProfileIndex,
              ) ==
              null
          ? ''
          : _remoteTokenController.text,
    );
    _setIfDifferent(
      _remotePasswordController,
      widget.controller.storedRelayPasswordMaskForProfile(
                kGatewayRemoteProfileIndex,
              ) ==
              null
          ? ''
          : _remotePasswordController.text,
    );
    _sessionPersistenceMode = settings.webSessionPersistence.mode;
    _setIfDifferent(
      _sessionRemoteBaseUrlController,
      settings.webSessionPersistence.remoteBaseUrl,
    );
    _setIfDifferent(
      _sessionApiTokenController,
      widget.controller.storedWebSessionApiTokenMask == null
          ? ''
          : _sessionApiTokenController.text,
    );
    _syncExternalAcpControllers(settings);
  }

  void _syncExternalAcpControllers(SettingsSnapshot settings) {
    final activeKeys = settings.externalAcpEndpoints
        .map((item) => item.providerKey)
        .toSet();
    for (final profile in settings.externalAcpEndpoints) {
      final key = profile.providerKey;
      final labelController = _externalAcpLabelControllers.putIfAbsent(
        key,
        () => TextEditingController(),
      );
      final endpointController = _externalAcpEndpointControllers.putIfAbsent(
        key,
        () => TextEditingController(),
      );
      _setIfDifferent(labelController, profile.label);
      _setIfDifferent(endpointController, profile.endpoint);
    }
    _disposeRemovedControllers(_externalAcpLabelControllers, activeKeys);
    _disposeRemovedControllers(_externalAcpEndpointControllers, activeKeys);
  }

  void _disposeRemovedControllers(
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
            currentTab != SettingsTab.gateway ||
            _gatewaySubTab == _WebGatewaySettingsSubTab.acp;
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
                  _buildGlobalApplyBar(context, controller),
                  const SizedBox(height: 16),
                ],
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
                ...switch (currentTab) {
                  SettingsTab.general => _buildGeneral(
                    context,
                    controller,
                    controller.settingsDraft,
                  ),
                  SettingsTab.gateway => _buildGateway(
                    context,
                    controller,
                    controller.settingsDraft,
                  ),
                  SettingsTab.appearance => _buildAppearance(
                    context,
                    controller,
                  ),
                  _ => _buildAbout(context),
                },
              ],
            ),
          ),
        );
      },
    );
  }
}
