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

class _MobileSafeStrip extends StatelessWidget {
  const _MobileSafeStrip({
    required this.controller,
    required this.onOpenSafeSheet,
    required this.onOpenGatewayConnect,
  });

  final AppController controller;
  final VoidCallback onOpenSafeSheet;
  final VoidCallback onOpenGatewayConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final connection = controller.connection;
    final devices = controller.devices;
    final hasPendingRun =
        controller.hasAssistantPendingRun || controller.activeRunId != null;
    final securePathLabel = _mobileSecurePathLabel(
      profile: controller.settings.primaryRemoteGatewayProfile,
      connection: connection,
    );

    Future<void> handlePrimaryConnect() async {
      if (controller.canQuickConnectGateway) {
        await controller.connectSavedGateway();
        await controller.refreshDevices(quiet: true);
        return;
      }
      onOpenGatewayConnect();
    }

    return Container(
      key: const ValueKey('mobile-safe-strip'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: palette.surfacePrimary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.dialog),
        border: Border.all(color: palette.strokeSoft),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mobile-safe',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appText(
                        '结构化审批、配对和安全运行入口',
                        'Structured approvals, pairing, and run-safe controls',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _MobileFactChip(
                icon: connection.status == RuntimeConnectionStatus.connected
                    ? Icons.verified_outlined
                    : Icons.shield_outlined,
                label: connection.status.label,
                color: connection.status == RuntimeConnectionStatus.connected
                    ? palette.success
                    : palette.textSecondary,
                background:
                    connection.status == RuntimeConnectionStatus.connected
                    ? palette.success.withValues(alpha: 0.14)
                    : palette.surfaceSecondary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MobileFactChip(
                icon: Icons.lock_outline_rounded,
                label: securePathLabel,
                color: palette.accent,
                background: palette.accentMuted,
              ),
              _MobileFactChip(
                icon: Icons.computer_outlined,
                label: _mobileTargetLabel(controller),
                color: palette.textPrimary,
                background: palette.surfaceSecondary,
              ),
              if (devices.pending.isNotEmpty)
                _MobileFactChip(
                  icon: Icons.approval_outlined,
                  label: appText(
                    '${devices.pending.length} 个待审批',
                    '${devices.pending.length} pending',
                  ),
                  color: palette.warning,
                  background: palette.warning.withValues(alpha: 0.12),
                ),
              if (devices.paired.isNotEmpty)
                _MobileFactChip(
                  icon: Icons.devices_outlined,
                  label: appText(
                    '${devices.paired.length} 台已配对',
                    '${devices.paired.length} paired',
                  ),
                  color: palette.success,
                  background: palette.success.withValues(alpha: 0.12),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                key: const ValueKey('mobile-safe-open-button'),
                onPressed: onOpenSafeSheet,
                child: Text(appText('安全审批', 'Mobile-safe')),
              ),
              if (controller.runtime.isConnected)
                OutlinedButton(
                  key: const ValueKey('mobile-safe-refresh-button'),
                  onPressed: () async {
                    await controller.refreshGatewayHealth();
                    await controller.refreshDevices(quiet: true);
                  },
                  child: Text(appText('刷新', 'Refresh')),
                )
              else
                FilledButton(
                  key: const ValueKey('mobile-safe-connect-button'),
                  onPressed: () => unawaited(handlePrimaryConnect()),
                  child: Text(
                    controller.canQuickConnectGateway
                        ? appText('快速连接', 'Quick Connect')
                        : appText('配对网关', 'Pair Gateway'),
                  ),
                ),
              if (hasPendingRun)
                OutlinedButton(
                  key: const ValueKey('mobile-safe-stop-run-button'),
                  onPressed: controller.abortRun,
                  child: Text(appText('停止运行', 'Stop Run')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileSafeSheet extends StatelessWidget {
  const _MobileSafeSheet({
    required this.controller,
    required this.onClose,
    required this.onOpenGatewayConnect,
  });

  final AppController controller;
  final VoidCallback onClose;
  final VoidCallback onOpenGatewayConnect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('mobile-safe-sheet'),
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: palette.surfacePrimary.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(AppRadius.dialog + 2),
          border: Border.all(color: palette.strokeSoft),
          boxShadow: [palette.chromeShadowAmbient],
        ),
        child: SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final theme = Theme.of(context);
              final connection = controller.connection;
              final devices = controller.devices;
              final hasPendingRun =
                  controller.hasAssistantPendingRun ||
                  controller.activeRunId != null;
              final securePathLabel = _mobileSecurePathLabel(
                profile: controller.settings.primaryRemoteGatewayProfile,
                connection: connection,
              );
              final localDeviceLabel =
                  connection.deviceId ?? appText('未初始化', 'Not initialized');
              final devicesError = controller.devicesController.error;

              Future<void> handleConnect() async {
                if (controller.canQuickConnectGateway) {
                  await controller.connectSavedGateway();
                  await controller.refreshDevices(quiet: true);
                  return;
                }
                onOpenGatewayConnect();
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mobile-safe',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: palette.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                appText(
                                  '移动端只提供结构化审批、配对管理和运行保护动作，不暴露全局 shell 放权。',
                                  'Mobile only exposes structured approvals, pairing controls, and run-safe actions. No global shell approvals.',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _MobileSafeSection(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appText('安全直连', 'Secure Direct'),
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _MobileFactChip(
                                icon: Icons.lock_outline_rounded,
                                label: securePathLabel,
                                color: palette.accent,
                                background: palette.accentMuted,
                              ),
                              _MobileFactChip(
                                icon: Icons.monitor_heart_outlined,
                                label: connection.status.label,
                                color:
                                    connection.status ==
                                        RuntimeConnectionStatus.connected
                                    ? palette.success
                                    : palette.textSecondary,
                                background:
                                    connection.status ==
                                        RuntimeConnectionStatus.connected
                                    ? palette.success.withValues(alpha: 0.14)
                                    : palette.surfaceSecondary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _mobileTargetLabel(controller),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            appText(
                              '本机设备 ID：$localDeviceLabel',
                              'Local device ID: $localDeviceLabel',
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (controller.runtime.isConnected) ...[
                                OutlinedButton(
                                  onPressed: () async {
                                    await controller.refreshGatewayHealth();
                                    await controller.refreshDevices(
                                      quiet: true,
                                    );
                                  },
                                  child: Text(appText('刷新', 'Refresh')),
                                ),
                                OutlinedButton(
                                  onPressed: controller.disconnectGateway,
                                  child: Text(appText('断开', 'Disconnect')),
                                ),
                              ] else
                                FilledButton(
                                  key: const ValueKey(
                                    'mobile-safe-sheet-connect-button',
                                  ),
                                  onPressed: () => unawaited(handleConnect()),
                                  child: Text(
                                    controller.canQuickConnectGateway
                                        ? appText('快速连接', 'Quick Connect')
                                        : appText('配对网关', 'Pair Gateway'),
                                  ),
                                ),
                              if (hasPendingRun)
                                FilledButton.tonal(
                                  onPressed: controller.abortRun,
                                  child: Text(appText('停止运行', 'Stop Run')),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (connection.pairingRequired) ...[
                      const SizedBox(height: 12),
                      _MobileSafetyNotice(
                        tone: palette.warning.withValues(alpha: 0.12),
                        borderColor: palette.warning.withValues(alpha: 0.32),
                        icon: Icons.approval_outlined,
                        title: appText('需要设备审批', 'Pairing Required'),
                        message: appText(
                          '当前设备已经向 Gateway 发起配对。请在已授权的 operator 设备上审批，然后重新连接。',
                          'This device already requested pairing. Approve it from an authorized operator device, then reconnect.',
                        ),
                      ),
                    ] else if (connection.gatewayTokenMissing) ...[
                      const SizedBox(height: 12),
                      _MobileSafetyNotice(
                        tone: palette.danger.withValues(alpha: 0.1),
                        borderColor: palette.danger.withValues(alpha: 0.2),
                        icon: Icons.key_off_outlined,
                        title: appText('缺少共享 Token', 'Shared Token Missing'),
                        message: appText(
                          '首次连接需要共享 Token；配对完成后可继续使用 device token。',
                          'The first connection needs a shared token; after pairing, the device token can continue.',
                        ),
                      ),
                    ],
                    if ((devicesError ?? '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _MobileSafetyNotice(
                        tone: palette.danger.withValues(alpha: 0.1),
                        borderColor: palette.danger.withValues(alpha: 0.2),
                        icon: Icons.error_outline_rounded,
                        title: appText('设备列表错误', 'Devices Error'),
                        message: devicesError!,
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      appText('待审批请求', 'Pending Requests'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (!controller.runtime.isConnected)
                      Text(
                        appText(
                          '连接 Gateway 后加载待审批设备与已配对设备。',
                          'Connect the gateway to load pending and paired devices.',
                        ),
                        style: theme.textTheme.bodyMedium,
                      )
                    else if (devices.pending.isEmpty)
                      Text(
                        appText('当前没有待审批设备。', 'No pending pairing requests.'),
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      Column(
                        key: const ValueKey('mobile-safe-pending-section'),
                        children: devices.pending
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _MobilePendingApprovalCard(
                                  controller: controller,
                                  item: item,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      appText('已配对设备', 'Paired Devices'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (!controller.runtime.isConnected)
                      Text(
                        appText(
                          '连接 Gateway 后可查看 paired device，并在移动端直接吊销。',
                          'Connect the gateway to view paired devices and revoke them from mobile.',
                        ),
                        style: theme.textTheme.bodyMedium,
                      )
                    else if (devices.paired.isEmpty)
                      Text(
                        appText('当前没有已配对设备。', 'No paired devices yet.'),
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      Column(
                        key: const ValueKey('mobile-safe-paired-section'),
                        children: devices.paired
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _MobilePairedDeviceCard(
                                  controller: controller,
                                  item: item,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MobileSafeSection extends StatelessWidget {
  const _MobileSafeSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: child,
    );
  }
}

class _MobileFactChip extends StatelessWidget {
  const _MobileFactChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _MobileSafetyNotice extends StatelessWidget {
  const _MobileSafetyNotice({
    required this.tone,
    required this.borderColor,
    required this.icon,
    required this.title,
    required this.message,
  });

  final Color tone;
  final Color borderColor;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.textPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePendingApprovalCard extends StatelessWidget {
  const _MobilePendingApprovalCard({
    required this.controller,
    required this.item,
  });

  final AppController controller;
  final GatewayPendingDevice item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final metadata = <String>[
      if ((item.role ?? '').isNotEmpty) 'role: ${item.role}',
      if (item.scopes.isNotEmpty) item.scopes.join(', '),
      if ((item.remoteIp ?? '').isNotEmpty) item.remoteIp!,
      _mobileRelativeTime(item.requestedAtMs),
      if (item.isRepair) appText('修复请求', 'repair'),
    ];

    return _MobileSafeSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      item.deviceId,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (item.isRepair)
                _MobileFactChip(
                  icon: Icons.build_circle_outlined,
                  label: appText('修复', 'Repair'),
                  color: palette.warning,
                  background: palette.warning.withValues(alpha: 0.12),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            metadata.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () =>
                    controller.approveDevicePairing(item.requestId),
                child: Text(appText('批准配对', 'Approve Pairing')),
              ),
              OutlinedButton(
                onPressed: () async {
                  final confirmed = await _confirmMobileAction(
                    context,
                    title: appText('拒绝配对请求', 'Reject Pairing Request'),
                    message: appText(
                      '确定拒绝 ${item.label} 的配对请求吗？',
                      'Reject the pairing request from ${item.label}?',
                    ),
                  );
                  if (confirmed == true) {
                    await controller.rejectDevicePairing(item.requestId);
                  }
                },
                child: Text(appText('拒绝配对', 'Reject Pairing')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobilePairedDeviceCard extends StatelessWidget {
  const _MobilePairedDeviceCard({required this.controller, required this.item});

  final AppController controller;
  final GatewayPairedDevice item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final metadata = <String>[
      if (item.roles.isNotEmpty) 'roles: ${item.roles.join(', ')}',
      if (item.scopes.isNotEmpty) 'scopes: ${item.scopes.join(', ')}',
      if ((item.remoteIp ?? '').isNotEmpty) item.remoteIp!,
      if (item.currentDevice) appText('当前设备', 'current device'),
    ];

    return _MobileSafeSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      item.deviceId,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (item.currentDevice)
                _MobileFactChip(
                  icon: Icons.smartphone_outlined,
                  label: appText('当前设备', 'Current'),
                  color: palette.success,
                  background: palette.success.withValues(alpha: 0.12),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            metadata.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          if (item.tokens.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              appText(
                '角色令牌：${item.tokens.first.role}',
                'Role token: ${item.tokens.first.role}',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () async {
              final confirmed = await _confirmMobileAction(
                context,
                title: appText('吊销已配对设备', 'Revoke Paired Device'),
                message: appText(
                  '确定吊销 ${item.label} 吗？该设备之后需要重新配对。',
                  'Revoke ${item.label}? The device will need pairing again.',
                ),
              );
              if (confirmed == true) {
                await controller.removePairedDevice(item.deviceId);
              }
            },
            child: Text(appText('吊销设备', 'Revoke Device')),
          ),
        ],
      ),
    );
  }
}

Future<bool?> _confirmMobileAction(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(appText('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(appText('确认', 'Confirm')),
          ),
        ],
      );
    },
  );
}

String _mobileSecurePathLabel({
  required GatewayConnectionProfile profile,
  required GatewayConnectionSnapshot connection,
}) {
  final mode = connection.mode == RuntimeConnectionMode.unconfigured
      ? profile.mode
      : connection.mode;
  return switch (mode) {
    RuntimeConnectionMode.local => appText('Loopback WS', 'Loopback WS'),
    RuntimeConnectionMode.remote =>
      profile.tls
          ? appText('Secure Direct TLS', 'Secure Direct TLS')
          : appText('Remote Non-TLS', 'Remote Non-TLS'),
    RuntimeConnectionMode.unconfigured => appText(
      'Gateway 未配置',
      'Gateway Not Configured',
    ),
  };
}

String _mobileTargetLabel(AppController controller) {
  final connection = controller.connection;
  if ((connection.remoteAddress ?? '').isNotEmpty) {
    return connection.remoteAddress!;
  }
  final profile = controller.settings.primaryRemoteGatewayProfile;
  final host = profile.host.trim();
  if (host.isNotEmpty && profile.port > 0) {
    return '$host:${profile.port}';
  }
  return appText('未连接目标', 'No target');
}

String _mobileRelativeTime(int? timestampMs) {
  if (timestampMs == null || timestampMs <= 0) {
    return appText('刚刚', 'just now');
  }
  final delta = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(timestampMs),
  );
  if (delta.inMinutes < 1) {
    return appText('刚刚', 'just now');
  }
  if (delta.inHours < 1) {
    return appText('${delta.inMinutes} 分钟前', '${delta.inMinutes}m ago');
  }
  if (delta.inDays < 1) {
    return appText('${delta.inHours} 小时前', '${delta.inHours}h ago');
  }
  return appText('${delta.inDays} 天前', '${delta.inDays}d ago');
}

class _MobileWorkspaceLauncher extends StatelessWidget {
  const _MobileWorkspaceLauncher({
    required this.controller,
    required this.onOpenGatewayConnect,
    required this.onSelectDestination,
  });

  final AppController controller;
  final VoidCallback onOpenGatewayConnect;
  final ValueChanged<WorkspaceDestination> onSelectDestination;

  @override
  Widget build(BuildContext context) {
    final connection = controller.connection;
    final palette = context.palette;
    final features = controller.featuresFor(UiFeaturePlatform.mobile);
    final entries =
        <_WorkspaceEntry>[
              _WorkspaceEntry(
                destination: WorkspaceDestination.skills,
                subtitle: appText('技能包与依赖状态', 'Packages and dependency status'),
                iconColor: palette.accent,
                iconBackground: palette.accentMuted,
              ),
              _WorkspaceEntry(
                destination: WorkspaceDestination.nodes,
                subtitle: appText('边缘节点与实例', 'Edge nodes and instances'),
                iconColor: _tealLine,
                iconBackground: _tealSoft,
              ),
              _WorkspaceEntry(
                destination: WorkspaceDestination.agents,
                subtitle: appText('代理运行态与配置', 'Agent state and configuration'),
                iconColor: palette.warning,
                iconBackground: palette.warning.withValues(alpha: 0.12),
              ),
              _WorkspaceEntry(
                destination: WorkspaceDestination.mcpServer,
                subtitle: appText('MCP 连接与工具注册', 'MCP endpoints and tools'),
                iconColor: palette.accent,
                iconBackground: palette.accentMuted,
              ),
              _WorkspaceEntry(
                destination: WorkspaceDestination.clawHub,
                subtitle: appText('技能与模板市场', 'Marketplace and templates'),
                iconColor: _violetLine,
                iconBackground: _violetSoft,
              ),
              _WorkspaceEntry(
                destination: WorkspaceDestination.aiGateway,
                subtitle: appText('模型与代理网关', 'Models and agent gateway'),
                iconColor: palette.accent,
                iconBackground: palette.accentMuted,
              ),
              _WorkspaceEntry(
                destination: WorkspaceDestination.account,
                subtitle: appText(
                  '身份、工作区与会话',
                  'Identity, workspace and sessions',
                ),
                iconColor: palette.success,
                iconBackground: palette.success.withValues(alpha: 0.12),
              ),
            ]
            .where(
              (entry) =>
                  features.allowedDestinations.contains(entry.destination),
            )
            .toList(growable: false);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LauncherHeader(
            title: appText('工作区', 'Workspace'),
            subtitle: appText(
              'Android 与 iOS 统一移动入口，集中访问全部核心模块。',
              'Shared mobile entry for Android and iOS with access to all core modules.',
            ),
            primaryLabel: connection.status == RuntimeConnectionStatus.connected
                ? appText('查看连接', 'Connection')
                : appText('连接 Gateway', 'Connect Gateway'),
            secondaryLabel: appText('返回助手', 'Open Assistant'),
            onPrimaryPressed: onOpenGatewayConnect,
            onSecondaryPressed: () =>
                onSelectDestination(WorkspaceDestination.assistant),
          ),
          const SizedBox(height: 18),
          _WorkspaceHero(
            connection: connection,
            activeAgentName: controller.activeAgentName,
            sessionCount: controller.sessions.length,
            runningTaskCount: controller.tasksController.running.length,
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 2 : 1;
              final width = columns == 2
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: entries
                    .map(
                      (entry) => SizedBox(
                        width: width,
                        child: _WorkspaceShortcutCard(
                          entry: entry,
                          onTap: () => onSelectDestination(entry.destination),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WorkspaceEntry {
  const _WorkspaceEntry({
    required this.destination,
    required this.subtitle,
    required this.iconColor,
    required this.iconBackground,
  });

  final WorkspaceDestination destination;
  final String subtitle;
  final Color iconColor;
  final Color iconBackground;
}

class _LauncherHeader extends StatelessWidget {
  const _LauncherHeader({
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimaryPressed,
    required this.onSecondaryPressed,
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _GradientActionButton(
              label: primaryLabel,
              onPressed: onPrimaryPressed,
            ),
            OutlinedButton.icon(
              onPressed: onSecondaryPressed,
              icon: const Icon(Icons.arrow_outward_rounded),
              label: Text(secondaryLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class _WorkspaceHero extends StatelessWidget {
  const _WorkspaceHero({
    required this.connection,
    required this.activeAgentName,
    required this.sessionCount,
    required this.runningTaskCount,
  });

  final GatewayConnectionSnapshot connection;
  final String activeAgentName;
  final int sessionCount;
  final int runningTaskCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final statusLabel = connection.status == RuntimeConnectionStatus.connected
        ? appText('会话已就绪', 'Session Ready')
        : appText('等待接入', 'Awaiting Connection');
    final statusColor = connection.status == RuntimeConnectionStatus.connected
        ? palette.success
        : palette.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusLabel,
            style: theme.textTheme.labelLarge?.copyWith(color: statusColor),
          ),
          const SizedBox(height: 10),
          Text(
            connection.remoteAddress ?? 'xworkmate.svc.plus',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            activeAgentName,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _HeroMetric(
                label: appText('会话', 'Sessions'),
                value: '$sessionCount',
                icon: Icons.chat_bubble_outline_rounded,
              ),
              _HeroMetric(
                label: appText('运行任务', 'Running'),
                value: '$runningTaskCount',
                icon: Icons.play_circle_outline_rounded,
              ),
              _HeroMetric(
                label: appText('状态', 'Status'),
                value: connection.status.label,
                icon: Icons.monitor_heart_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: palette.accent),
          const SizedBox(width: 8),
          Text(
            '$label · $value',
            style: theme.textTheme.labelLarge?.copyWith(
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceShortcutCard extends StatelessWidget {
  const _WorkspaceShortcutCard({required this.entry, required this.onTap});

  final _WorkspaceEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.surfacePrimary,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: entry.iconBackground,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Icon(
                  entry.destination.icon,
                  color: entry.iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.destination.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.chevron_right_rounded, color: palette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientActionButton extends StatelessWidget {
  const _GradientActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.accent, palette.accentHover],
        ),
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          minimumSize: const Size(0, AppSizes.buttonHeightMobile),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        ),
        child: Text(label),
      ),
    );
  }
}

class _BottomPillNav extends StatelessWidget {
  const _BottomPillNav({
    required this.currentTab,
    required this.tabs,
    required this.onChanged,
  });

  final MobileShellTab currentTab;
  final List<MobileShellTab> tabs;
  final ValueChanged<MobileShellTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: palette.surfacePrimary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.dialog),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        children: tabs
            .map(
              (tab) => Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(tab),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: currentTab == tab
                          ? palette.surfaceSecondary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tab.icon,
                          size: 20,
                          color: currentTab == tab
                              ? palette.accent
                              : palette.textPrimary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tab.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: currentTab == tab
                                    ? palette.accent
                                    : palette.textPrimary,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
