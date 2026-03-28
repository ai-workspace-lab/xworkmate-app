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
import 'mobile_shell_core.dart';
import 'mobile_shell_strip.dart';
import 'mobile_shell_sheet.dart';
import 'mobile_shell_workspace.dart';

class BottomPillNavInternal extends StatelessWidget {
  const BottomPillNavInternal({
    super.key,
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
