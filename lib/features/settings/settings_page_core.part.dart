part of 'settings_page.dart';

const _storedSecretMask = '****';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.initialTab = SettingsTab.general,
    this.initialDetail,
    this.navigationContext,
  });

  final AppController controller;
  final SettingsTab initialTab;
  final SettingsDetailPage? initialDetail;
  final SettingsNavigationContext? navigationContext;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsTab _tab;
  SettingsDetailPage? _detail;
  SettingsNavigationContext? _navigationContext;
  late final TextEditingController _aiGatewayNameController;
  late final TextEditingController _aiGatewayUrlController;
  late final TextEditingController _aiGatewayApiKeyRefController;
  late final TextEditingController _aiGatewayApiKeyController;
  late final TextEditingController _aiGatewayModelSearchController;
  late final TextEditingController _gatewaySetupCodeController;
  late final TextEditingController _gatewayHostController;
  late final TextEditingController _gatewayPortController;
  late final List<TextEditingController> _gatewayTokenControllers;
  late final List<TextEditingController> _gatewayPasswordControllers;
  late final TextEditingController _vaultTokenController;
  late final TextEditingController _ollamaApiKeyController;
  late final TextEditingController _runtimeLogFilterController;
  bool _gatewayTesting = false;
  String _gatewayTestState = 'idle';
  String _gatewayTestMessage = '';
  String _gatewayTestEndpoint = '';
  bool _openClawGatewayExpanded = true;
  bool _vaultServerExpanded = true;
  bool _aiGatewayExpanded = true;
  int _selectedGatewayProfileIndex = kGatewayLocalProfileIndex;
  String _gatewaySetupCodeSyncedValue = '';
  String _gatewayHostSyncedValue = '';
  String _gatewayPortSyncedValue = '';
  late final List<_SecretFieldUiState> _gatewayTokenStates;
  late final List<_SecretFieldUiState> _gatewayPasswordStates;
  bool _aiGatewayTesting = false;
  String _aiGatewayTestState = 'idle';
  String _aiGatewayTestMessage = '';
  String _aiGatewayTestEndpoint = '';
  _GatewayIntegrationSubTab _integrationSubTab =
      _GatewayIntegrationSubTab.gateway;
  int _llmEndpointSlotLimit = 1;
  int _selectedLlmEndpointIndex = 0;
  String _aiGatewayNameSyncedValue = '';
  String _aiGatewayUrlSyncedValue = '';
  String _aiGatewayApiKeyRefSyncedValue = '';
  _SecretFieldUiState _aiGatewayApiKeyState = const _SecretFieldUiState();
  _SecretFieldUiState _vaultTokenState = const _SecretFieldUiState();
  _SecretFieldUiState _ollamaApiKeyState = const _SecretFieldUiState();

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _detail = widget.initialDetail;
    _navigationContext = widget.navigationContext;
    _aiGatewayNameController = TextEditingController();
    _aiGatewayUrlController = TextEditingController();
    _aiGatewayApiKeyRefController = TextEditingController();
    _aiGatewayApiKeyController = TextEditingController();
    _aiGatewayModelSearchController = TextEditingController();
    _gatewaySetupCodeController = TextEditingController();
    _gatewayHostController = TextEditingController();
    _gatewayPortController = TextEditingController();
    _gatewayTokenControllers = List<TextEditingController>.generate(
      kGatewayProfileListLength,
      (_) => TextEditingController(),
      growable: false,
    );
    _gatewayPasswordControllers = List<TextEditingController>.generate(
      kGatewayProfileListLength,
      (_) => TextEditingController(),
      growable: false,
    );
    _gatewayTokenStates = List<_SecretFieldUiState>.filled(
      kGatewayProfileListLength,
      const _SecretFieldUiState(),
      growable: false,
    );
    _gatewayPasswordStates = List<_SecretFieldUiState>.filled(
      kGatewayProfileListLength,
      const _SecretFieldUiState(),
      growable: false,
    );
    _vaultTokenController = TextEditingController();
    _ollamaApiKeyController = TextEditingController();
    _runtimeLogFilterController = TextEditingController();
  }

  void _setState(VoidCallback fn) => setState(fn);

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != _tab) {
      _tab = widget.initialTab;
    }
    if (widget.initialDetail != _detail) {
      _detail = widget.initialDetail;
    }
    if (widget.navigationContext != _navigationContext) {
      _navigationContext = widget.navigationContext;
    }
    _applyGatewayNavigationHints();
  }

  void _applyGatewayNavigationHints() {
    final detail = _detail;
    final navigationContext = _navigationContext;
    if (detail != SettingsDetailPage.gatewayConnection ||
        navigationContext == null) {
      return;
    }
    final gatewayProfileIndex = navigationContext.gatewayProfileIndex;
    if (gatewayProfileIndex == null) {
      return;
    }
    _selectedGatewayProfileIndex = gatewayProfileIndex.clamp(
      0,
      kGatewayProfileListLength - 1,
    );
  }

  bool _prefersGatewaySetupCodeForCurrentContext(BuildContext context) {
    return resolveUiFeaturePlatformFromContext(context) ==
            UiFeaturePlatform.mobile &&
        _detail == SettingsDetailPage.gatewayConnection &&
        _navigationContext?.prefersGatewaySetupCode == true &&
        _selectedGatewayProfileIndex != kGatewayLocalProfileIndex;
  }

  @override
  void dispose() {
    _aiGatewayNameController.dispose();
    _aiGatewayUrlController.dispose();
    _aiGatewayApiKeyRefController.dispose();
    _aiGatewayApiKeyController.dispose();
    _aiGatewayModelSearchController.dispose();
    _gatewaySetupCodeController.dispose();
    _gatewayHostController.dispose();
    _gatewayPortController.dispose();
    for (final controller in _gatewayTokenControllers) {
      controller.dispose();
    }
    for (final controller in _gatewayPasswordControllers) {
      controller.dispose();
    }
    _vaultTokenController.dispose();
    _ollamaApiKeyController.dispose();
    _runtimeLogFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final featurePlatform = resolveUiFeaturePlatformFromContext(context);
        final uiFeatures = controller.featuresFor(featurePlatform);
        final availableTabs = uiFeatures.availableSettingsTabs;
        _tab = uiFeatures.sanitizeSettingsTab(controller.settingsTab);
        _detail = controller.settingsDetail;
        _navigationContext = controller.settingsNavigationContext;
        _applyGatewayNavigationHints();
        final settings = controller.settingsDraft;
        final showingDetail = _detail != null;
        final showGlobalApplyBar =
            _tab != SettingsTab.gateway ||
            _integrationSubTab == _GatewayIntegrationSubTab.acp;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                breadcrumbs: buildSettingsBreadcrumbs(
                  controller,
                  tab: _tab,
                  detail: _detail,
                  navigationContext: _navigationContext,
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
                              _detail = null;
                              _navigationContext = null;
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
              ),
              const SizedBox(height: 24),
              if (showGlobalApplyBar) ...[
                _buildGlobalApplyBar(context, controller),
                const SizedBox(height: 16),
              ],
              if (!showingDetail) ...[
                SectionTabs(
                  items: availableTabs.map((item) => item.label).toList(),
                  value: _tab.label,
                  onChanged: (value) => setState(() {
                    _tab = availableTabs.firstWhere(
                      (item) => item.label == value,
                    );
                    _detail = null;
                    _navigationContext = null;
                    controller.setSettingsTab(_tab);
                  }),
                ),
                const SizedBox(height: 24),
              ],
              ..._buildContentForCurrentState(
                context,
                controller,
                settings,
                uiFeatures,
              ),
            ],
          ),
        );
      },
    );
  }
}
