import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../theme/app_palette.dart';
import '../widgets/pane_toggle_icon.dart';
import 'app_controller.dart';

/// The way back to a fully hidden navigation sidebar. Pages put it first in
/// their top toolbar, so it never sits on top of their content; it takes no
/// space while the sidebar is showing.
class SidebarRevealToggle extends StatelessWidget {
  const SidebarRevealToggle({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.sidebarState != AppSidebarState.hidden) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Tooltip(
            message: appText('展开导航', 'Show sidebar'),
            child: IconButton(
              key: const Key('sidebar-reveal-button'),
              onPressed: () =>
                  controller.setSidebarState(AppSidebarState.expanded),
              color: context.palette.textSecondary,
              icon: const PaneToggleIcon(side: PaneSide.left, size: 20),
            ),
          ),
        );
      },
    );
  }
}
