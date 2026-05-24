import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/ui_feature_manifest.dart';
import '../../app/workspace_page_registry.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_drawer.dart';
import 'mobile_shell_nav.dart';

enum MobileShellTab { assistant, settings }

extension MobileShellTabPresentationInternal on MobileShellTab {
  String get label => switch (this) {
    MobileShellTab.assistant => appText('助手', 'Assistant'),
    MobileShellTab.settings => appText('设置', 'Settings'),
  };

  IconData get icon => switch (this) {
    MobileShellTab.assistant => Icons.chat_bubble_outline_rounded,
    MobileShellTab.settings => Icons.settings_rounded,
  };
}

class MobileShell extends StatefulWidget {
  const MobileShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<MobileShell> createState() => MobileShellStateInternal();
}

class MobileShellStateInternal extends State<MobileShell> {
  MobileShellTab tabForDestinationInternal(WorkspaceDestination destination) {
    return switch (destination) {
      WorkspaceDestination.assistant => MobileShellTab.assistant,
      WorkspaceDestination.settings => MobileShellTab.settings,
    };
  }

  void selectTabInternal(MobileShellTab tab) {
    switch (tab) {
      case MobileShellTab.assistant:
        widget.controller.navigateTo(WorkspaceDestination.assistant);
        return;
      case MobileShellTab.settings:
        widget.controller.navigateTo(WorkspaceDestination.settings);
        return;
    }
  }

  void openDetailSheetInternal(DetailPanelData detail) {
    widget.controller.openDetail(detail);
  }

  Future<void> showBridgeSetupCodeSheetInternal() async {
    final codeController = TextEditingController();
    final setupCode = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final palette = sheetContext.palette;
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
          child: DecoratedBox(
            key: const Key('mobile-bridge-code-sheet'),
            decoration: BoxDecoration(
              color: palette.surfacePrimary,
              borderRadius: BorderRadius.circular(AppRadius.dialog),
              border: Border.all(color: palette.strokeSoft),
              boxShadow: [palette.chromeShadowAmbient],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            appText('连接 Bridge', 'Connect Bridge'),
                            style: Theme.of(sheetContext).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          key: const Key('mobile-bridge-code-sheet-close'),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      appText(
                        '输入 xworkmate-bridge 提供的配置码，移动端会直接发起连接。',
                        'Enter the setup code from xworkmate-bridge to connect from mobile.',
                      ),
                      style: Theme.of(sheetContext).textTheme.bodyMedium
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('mobile-bridge-code-input'),
                      controller: codeController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: appText('配置码', 'Setup Code'),
                        hintText: appText('粘贴配置码', 'Paste setup code'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('mobile-bridge-code-submit'),
                        onPressed: () => Navigator.of(
                          sheetContext,
                        ).pop(codeController.text.trim()),
                        icon: const Icon(Icons.link_rounded),
                        label: Text(appText('连接 Bridge', 'Connect Bridge')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    codeController.dispose();
    final normalized = setupCode?.trim() ?? '';
    if (normalized.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.controller.connectWithSetupCode(setupCode: normalized);
      if (!mounted) {
        return;
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            appText(
              '已开始连接 xworkmate-bridge。',
              'Started connecting to xworkmate-bridge.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            appText(
              '连接失败，请检查配置码或 Bridge 状态。\n$error',
              'Connection failed. Check the setup code or Bridge status.\n$error',
            ),
          ),
        ),
      );
    }
  }

  Widget buildCurrentPageInternal() {
    return buildWorkspacePage(
      destination: widget.controller.destination,
      controller: widget.controller,
      onOpenDetail: openDetailSheetInternal,
      surface: WorkspacePageSurface.mobile,
      mobileActions: MobileWorkspaceActions(
        onConnectBridge: () => unawaited(showBridgeSetupCodeSheetInternal()),
      ),
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
          if (features.isEnabledPath(UiFeatureKeys.navigationSettings))
            MobileShellTab.settings,
        ];
        final currentTab = tabForDestinationInternal(
          widget.controller.destination,
        );
        final resolvedCurrentTab = availableTabs.contains(currentTab)
            ? currentTab
            : (availableTabs.isEmpty ? currentTab : availableTabs.first);
        final destinationKey = ValueKey<String>(
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
