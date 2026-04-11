// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../app/ui_feature_manifest.dart';
import '../../app/workspace_page_registry.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_drawer.dart';
import 'mobile_gateway_pairing_guide_page.dart';
import 'mobile_shell_strip.dart';
import 'mobile_shell_sheet.dart';
import 'mobile_shell_workspace.dart';
import 'mobile_shell_nav.dart';

enum MobileShellTab { assistant, tasks, workspace, secrets, settings }

extension MobileShellTabPresentationInternal on MobileShellTab {
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

const tealSoftInternal = Color(0xFFDDF3EF);
const tealLineInternal = Color(0xFF49A892);
const violetSoftInternal = Color(0xFFECE2FF);
const violetLineInternal = Color(0xFF7A61B6);

class MobileShell extends StatefulWidget {
  const MobileShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<MobileShell> createState() => MobileShellStateInternal();
}

class MobileShellStateInternal extends State<MobileShell> {
  bool showWorkspaceHubInternal = false;
  late WorkspaceDestination lastDestinationInternal;

  @override
  void initState() {
    super.initState();
    lastDestinationInternal = widget.controller.destination;
    widget.controller.addListener(handleControllerChangedInternal);
  }

  @override
  void didUpdateWidget(covariant MobileShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(handleControllerChangedInternal);
    lastDestinationInternal = widget.controller.destination;
    widget.controller.addListener(handleControllerChangedInternal);
  }

  @override
  void dispose() {
    widget.controller.removeListener(handleControllerChangedInternal);
    super.dispose();
  }

  void handleControllerChangedInternal() {
    final destination = widget.controller.destination;
    if (destination == lastDestinationInternal) {
      return;
    }
    lastDestinationInternal = destination;
    if (showWorkspaceHubInternal && mounted) {
      setState(() {
        showWorkspaceHubInternal = false;
      });
    }
  }

  MobileShellTab tabForDestinationInternal(WorkspaceDestination destination) {
    return switch (destination) {
      WorkspaceDestination.assistant => MobileShellTab.assistant,
      WorkspaceDestination.tasks => MobileShellTab.tasks,
      WorkspaceDestination.skills ||
      WorkspaceDestination.nodes ||
      WorkspaceDestination.agents ||
      WorkspaceDestination.mcpServer ||
      WorkspaceDestination.clawHub ||
      WorkspaceDestination.aiGateway => MobileShellTab.workspace,
      WorkspaceDestination.secrets => MobileShellTab.secrets,
      WorkspaceDestination.settings => MobileShellTab.settings,
      WorkspaceDestination.account => MobileShellTab.settings,
    };
  }

  void selectTabInternal(MobileShellTab tab) {
    switch (tab) {
      case MobileShellTab.assistant:
        setState(() => showWorkspaceHubInternal = false);
        widget.controller.navigateTo(WorkspaceDestination.assistant);
        return;
      case MobileShellTab.tasks:
        setState(() => showWorkspaceHubInternal = false);
        widget.controller.navigateTo(WorkspaceDestination.tasks);
        return;
      case MobileShellTab.workspace:
        prefetchMobileSafeStateInternal();
        setState(() => showWorkspaceHubInternal = true);
        return;
      case MobileShellTab.secrets:
        setState(() => showWorkspaceHubInternal = false);
        widget.controller.navigateTo(WorkspaceDestination.secrets);
        return;
      case MobileShellTab.settings:
        setState(() => showWorkspaceHubInternal = false);
        widget.controller.navigateTo(WorkspaceDestination.settings);
        return;
    }
  }

  void openWorkspaceDestinationInternal(WorkspaceDestination destination) {
    setState(() => showWorkspaceHubInternal = false);
    widget.controller.navigateTo(destination);
  }

  void openDetailSheetInternal(DetailPanelData detail) {
    widget.controller.openDetail(detail);
  }

  void prefetchMobileSafeStateInternal() {
    if (!widget.controller.runtime.isConnected) {
      return;
    }
    unawaited(widget.controller.refreshGatewayHealth());
    unawaited(widget.controller.refreshDevices(quiet: true));
  }

  void showConnectSheetInternal() {
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

  Future<void> openGatewaySetupCodeEntryInternal({
    String? prefilledSetupCode,
  }) async {
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

  Future<void> connectWithScannedSetupCodeInternal(String setupCode) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.controller.connectWithSetupCode(setupCode: setupCode);
      if (!mounted) {
        return;
      }
      prefetchMobileSafeStateInternal();
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
            showMobileSafeSheetInternal();
          }
        });
        return;
      }
      await openGatewaySetupCodeEntryInternal(prefilledSetupCode: setupCode);
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

  Future<void> promptBridgeVerificationCodeInternal() async {
    final accountSignedIn =
        (await widget.controller.storeInternal.loadAccountSessionToken())
            ?.trim()
            .isNotEmpty ??
        false;
    if (!mounted) {
      return;
    }
    if (!accountSignedIn) {
      await openGatewaySetupCodeEntryInternal();
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            appText(
              '未登录账号时，请先手动输入配置码。登录 accounts.svc.plus 后可使用验证码接入。',
              'When account sign-in is unavailable, enter a setup code manually. Sign in to accounts.svc.plus first to use bridge verification codes.',
            ),
          ),
        ),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    final codeController = TextEditingController();
    final enteredCode = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(appText('输入验证码', 'Enter Verification Code')),
          content: TextField(
            controller: codeController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: appText('验证码', 'Verification Code'),
              hintText: 'AB12CD34',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(appText('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(codeController.text.trim()),
              child: Text(appText('连接', 'Connect')),
            ),
          ],
        );
      },
    );
    codeController.dispose();
    final resolved = enteredCode?.trim() ?? '';
    if (resolved.isEmpty || !mounted) {
      return;
    }
    await connectWithScannedSetupCodeInternal(resolved);
  }

  void showPairingGuidePageInternal() {
    unawaited(showPairingGuidePageFlowInternal());
  }

  Future<void> showPairingGuidePageFlowInternal() async {
    final supportsQrScan = Theme.of(context).platform == TargetPlatform.iOS;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MobileGatewayPairingGuidePage(
          supportsQrScan: supportsQrScan,
          onManualInput: () => unawaited(openGatewaySetupCodeEntryInternal()),
          onManualCodeInput: () =>
              unawaited(promptBridgeVerificationCodeInternal()),
          onScannedSetupCode: (setupCode) async {
            await connectWithScannedSetupCodeInternal(setupCode);
          },
        ),
      ),
    );
  }

  void showMobileSafeSheetInternal() {
    prefetchMobileSafeStateInternal();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: MobileSafeSheetInternal(
            controller: widget.controller,
            onClose: () => Navigator.of(sheetContext).pop(),
            onOpenGatewayConnect: () {
              Navigator.of(sheetContext).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  showPairingGuidePageInternal();
                }
              });
            },
          ),
        );
      },
    );
  }

  Widget buildCurrentPageInternal() {
    final features = widget.controller.featuresFor(UiFeaturePlatform.mobile);
    if (showWorkspaceHubInternal && features.showsWorkspaceHub) {
      return MobileWorkspaceLauncherInternal(
        controller: widget.controller,
        onOpenGatewayConnect: showConnectSheetInternal,
        onSelectDestination: openWorkspaceDestinationInternal,
      );
    }

    final destination = widget.controller.destination;
    return buildWorkspacePage(
      destination: destination,
      controller: widget.controller,
      onOpenDetail: openDetailSheetInternal,
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
        final currentTab = showWorkspaceHubInternal
            ? MobileShellTab.workspace
            : tabForDestinationInternal(widget.controller.destination);
        final resolvedCurrentTab = availableTabs.contains(currentTab)
            ? currentTab
            : (availableTabs.isEmpty ? currentTab : availableTabs.first);
        final destinationKey = showWorkspaceHubInternal
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
                      MobileSafeStripInternal(
                        controller: widget.controller,
                        onOpenSafeSheet: showMobileSafeSheetInternal,
                        onOpenGatewayConnect: showPairingGuidePageInternal,
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
                                child: buildCurrentPageInternal(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 12, 6, 18),
                        child: BottomPillNavInternal(
                          currentTab: resolvedCurrentTab,
                          tabs: availableTabs,
                          onChanged: selectTabInternal,
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
