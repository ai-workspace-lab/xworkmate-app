part of 'mobile_shell.dart';

enum MobileShellTab { assistant, tasks, workspace, secrets, settings }

extension on MobileShellTab {
  String get label => switch (this) {
    MobileShellTab.assistant => appText('助手', 'Assistant'),
    MobileShellTab.tasks => appText('任务', 'Tasks'),
    MobileShellTab.workspace => appText('工作区', 'Workspace'),
    MobileShellTab.secrets => appText('密钥', 'Secrets'),
    MobileShellTab.settings => appText('设置', 'Settings'),
  };

  IconData get icon => switch (this) {
    MobileShellTab.assistant => Icons.chat_bubble_outline_rounded,
    MobileShellTab.tasks => Icons.layers_rounded,
    MobileShellTab.workspace => Icons.grid_view_rounded,
    MobileShellTab.secrets => Icons.key_rounded,
    MobileShellTab.settings => Icons.settings_rounded,
  };
}

const _tealSoft = Color(0xFFDDF3EF);
const _tealLine = Color(0xFF49A892);
const _violetSoft = Color(0xFFECE2FF);
const _violetLine = Color(0xFF7A61B6);

class MobileShell extends StatefulWidget {
  const MobileShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  bool _showWorkspaceHub = false;
  late WorkspaceDestination _lastDestination;

  @override
  void initState() {
    super.initState();
    _lastDestination = widget.controller.destination;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant MobileShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_handleControllerChanged);
    _lastDestination = widget.controller.destination;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final destination = widget.controller.destination;
    if (destination == _lastDestination) {
      return;
    }
    _lastDestination = destination;
    if (_showWorkspaceHub && mounted) {
      setState(() {
        _showWorkspaceHub = false;
      });
    }
  }

  MobileShellTab _tabForDestination(WorkspaceDestination destination) {
    return switch (destination) {
      WorkspaceDestination.assistant => MobileShellTab.assistant,
      WorkspaceDestination.tasks => MobileShellTab.tasks,
      WorkspaceDestination.skills ||
      WorkspaceDestination.nodes ||
      WorkspaceDestination.agents ||
      WorkspaceDestination.mcpServer ||
      WorkspaceDestination.clawHub ||
      WorkspaceDestination.aiGateway ||
      WorkspaceDestination.account => MobileShellTab.workspace,
      WorkspaceDestination.secrets => MobileShellTab.secrets,
      WorkspaceDestination.settings => MobileShellTab.settings,
    };
  }

  void _selectTab(MobileShellTab tab) {
    switch (tab) {
      case MobileShellTab.assistant:
        setState(() => _showWorkspaceHub = false);
        widget.controller.navigateTo(WorkspaceDestination.assistant);
        return;
      case MobileShellTab.tasks:
        setState(() => _showWorkspaceHub = false);
        widget.controller.navigateTo(WorkspaceDestination.tasks);
        return;
      case MobileShellTab.workspace:
        _prefetchMobileSafeState();
        setState(() => _showWorkspaceHub = true);
        return;
      case MobileShellTab.secrets:
        setState(() => _showWorkspaceHub = false);
        widget.controller.navigateTo(WorkspaceDestination.secrets);
        return;
      case MobileShellTab.settings:
        setState(() => _showWorkspaceHub = false);
        widget.controller.navigateTo(WorkspaceDestination.settings);
        return;
    }
  }

  void _openWorkspaceDestination(WorkspaceDestination destination) {
    setState(() => _showWorkspaceHub = false);
    widget.controller.navigateTo(destination);
  }

  void _openDetailSheet(DetailPanelData detail) {
    widget.controller.openDetail(detail);
  }

  void _prefetchMobileSafeState() {
    if (!widget.controller.runtime.isConnected) {
      return;
    }
    unawaited(widget.controller.refreshGatewayHealth());
    unawaited(widget.controller.refreshDevices(quiet: true));
  }

  void _showConnectSheet() {
    widget.controller.openSettings(
      detail: SettingsDetailPage.gatewayConnection,
      navigationContext: SettingsNavigationContext(
        rootLabel: appText('移动端', 'Mobile'),
        destination: WorkspaceDestination.settings,
        sectionLabel: appText('集成', 'Integrations'),
        gatewayProfileIndex: kGatewayRemoteProfileIndex,
        prefersGatewaySetupCode: false,
      ),
    );
  }

  Future<void> _openGatewaySetupCodeEntry({String? prefilledSetupCode}) async {
    final setupCode = prefilledSetupCode?.trim() ?? '';
    if (setupCode.isNotEmpty) {
      final current = widget
          .controller
          .settingsDraft
          .gatewayProfiles[kGatewayRemoteProfileIndex];
      await widget.controller.saveSettingsDraft(
        widget.controller.settingsDraft.copyWithGatewayProfileAt(
          kGatewayRemoteProfileIndex,
          current.copyWith(useSetupCode: true, setupCode: setupCode),
        ),
      );
    }
    widget.controller.openSettings(
      detail: SettingsDetailPage.gatewayConnection,
      navigationContext: SettingsNavigationContext(
        rootLabel: appText('移动端', 'Mobile'),
        destination: WorkspaceDestination.settings,
        sectionLabel: appText('集成', 'Integrations'),
        gatewayProfileIndex: kGatewayRemoteProfileIndex,
        prefersGatewaySetupCode: true,
      ),
    );
  }

  Future<void> _connectWithScannedSetupCode(String setupCode) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.controller.connectWithSetupCode(setupCode: setupCode);
      if (!mounted) {
        return;
      }
      _prefetchMobileSafeState();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            appText(
              '已写入配置码并开始连接 Gateway。',
              'Setup code applied and Gateway connection started.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (widget.controller.connection.pairingRequired) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              appText(
                '配置码有效，已向 Gateway 发起配对请求。请先在已授权设备上审批。',
                'Setup code accepted. This device has requested pairing and now waits for approval.',
              ),
            ),
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showMobileSafeSheet();
          }
        });
        return;
      }
      await _openGatewaySetupCodeEntry(prefilledSetupCode: setupCode);
      if (!mounted) {
        return;
      }
      final message = error.toString().trim();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            appText(
              '扫码成功，但自动连接失败。已为你填入配置码，请检查后重试。\n$message',
              'QR captured, but automatic connect failed. The setup code has been prefilled for review.\n$message',
            ),
          ),
        ),
      );
    }
  }

  void _showPairingGuidePage() {
    unawaited(_showPairingGuidePageFlow());
  }

  Future<void> _showPairingGuidePageFlow() async {
    final supportsQrScan = Theme.of(context).platform == TargetPlatform.iOS;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MobileGatewayPairingGuidePage(
          supportsQrScan: supportsQrScan,
          onManualInput: () => unawaited(_openGatewaySetupCodeEntry()),
          onScannedSetupCode: (setupCode) async {
            await _connectWithScannedSetupCode(setupCode);
          },
        ),
      ),
    );
  }

  void _showMobileSafeSheet() {
    _prefetchMobileSafeState();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: _MobileSafeSheet(
            controller: widget.controller,
            onClose: () => Navigator.of(sheetContext).pop(),
            onOpenGatewayConnect: () {
              Navigator.of(sheetContext).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _showPairingGuidePage();
                }
              });
            },
          ),
        );
      },
    );
  }

  Widget _buildCurrentPage() {
    final features = widget.controller.featuresFor(UiFeaturePlatform.mobile);
    if (_showWorkspaceHub && features.showsWorkspaceHub) {
      return _MobileWorkspaceLauncher(
        controller: widget.controller,
        onOpenGatewayConnect: _showConnectSheet,
        onSelectDestination: _openWorkspaceDestination,
      );
    }

    final destination = widget.controller.destination;
    return buildWorkspacePage(
      destination: destination,
      controller: widget.controller,
      onOpenDetail: _openDetailSheet,
      surface: WorkspacePageSurface.mobile,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final features = widget.controller.featuresFor(
          UiFeaturePlatform.mobile,
        );
        final availableTabs = <MobileShellTab>[
          if (features.isEnabledPath(UiFeatureKeys.navigationAssistant))
            MobileShellTab.assistant,
          if (features.isEnabledPath(UiFeatureKeys.navigationTasks))
            MobileShellTab.tasks,
          if (features.showsWorkspaceHub) MobileShellTab.workspace,
          if (features.isEnabledPath(UiFeatureKeys.navigationSecrets))
            MobileShellTab.secrets,
          if (features.isEnabledPath(UiFeatureKeys.navigationSettings))
            MobileShellTab.settings,
        ];
        final currentTab = _showWorkspaceHub
            ? MobileShellTab.workspace
            : _tabForDestination(widget.controller.destination);
        final resolvedCurrentTab = availableTabs.contains(currentTab)
            ? currentTab
            : (availableTabs.isEmpty ? currentTab : availableTabs.first);
        final destinationKey = _showWorkspaceHub
            ? const ValueKey<String>('mobile-shell-workspace')
            : ValueKey<String>(
                'mobile-shell-${widget.controller.destination.name}',
              );
        final detailPanel = widget.controller.detailPanel;
        final palette = context.palette;
        return Scaffold(
          backgroundColor: palette.canvas,
          body: Stack(
            children: [
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    children: [
                      _MobileSafeStrip(
                        controller: widget.controller,
                        onOpenSafeSheet: _showMobileSafeSheet,
                        onOpenGatewayConnect: _showPairingGuidePage,
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppRadius.sidebar,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: palette.chromeSurface,
                              border: Border.all(color: palette.strokeSoft),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeOutCubic,
                              child: KeyedSubtree(
                                key: destinationKey,
                                child: _buildCurrentPage(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 12, 6, 18),
                        child: _BottomPillNav(
                          currentTab: resolvedCurrentTab,
                          tabs: availableTabs,
                          onChanged: _selectTab,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (detailPanel != null)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: widget.controller.closeDetail,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.14),
                    ),
                  ),
                ),
              if (detailPanel != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: 0.92,
                    child: DetailSheet(
                      data: detailPanel,
                      onClose: widget.controller.closeDetail,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
