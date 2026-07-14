import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/workspace_page_registry.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../theme/app_palette.dart';
import '../../widgets/detail_drawer.dart';

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

  void openBridgeIntegrationSettingsInternal() {
    widget.controller.openSettings(tab: SettingsTab.gateway);
    widget.controller.navigateTo(WorkspaceDestination.settings);
  }

  Widget buildCurrentPageInternal() {
    return buildWorkspacePage(
      destination: widget.controller.destination,
      controller: widget.controller,
      onOpenDetail: openDetailSheetInternal,
      surface: WorkspacePageSurface.mobile,
      mobileActions: MobileWorkspaceActions(
        onConnectBridge: openBridgeIntegrationSettingsInternal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final destinationKey = ValueKey<String>(
          'mobile-shell-${widget.controller.destination.name}',
        );
        final detailPanel = widget.controller.detailPanel;
        final palette = context.palette;
        return Scaffold(
          backgroundColor: palette.canvas,
          body: Stack(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child: KeyedSubtree(
                  key: destinationKey,
                  child: buildCurrentPageInternal(),
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
