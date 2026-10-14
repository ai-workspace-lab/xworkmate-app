import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../models/app_models.dart';
import '../bot_team/bot_team_models.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';

class AssistantTaskDialogModeControlsInternal extends StatelessWidget {
  const AssistantTaskDialogModeControlsInternal({
    super.key,
    required this.controller,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _TaskDialogProductModeMenuButtonInternal(controller: controller);
  }
}

class _TaskDialogProductModeMenuButtonInternal extends StatelessWidget {
  const _TaskDialogProductModeMenuButtonInternal({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final mode = controller.assistantProductModeForSession(
      controller.currentSessionKey,
    );
    final theme = Theme.of(context);
    final palette = context.palette;
    // Size the chip for the longest role name so it does not jump as the
    // role changes.
    final labelMetrics = TextPainter(
      text: TextSpan(text: 'Researcher', style: theme.textTheme.labelMedium),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return PopupMenuButton<AssistantMode>(
      key: const Key('assistant-product-mode-button'),
      tooltip: appText('任务角色', 'Task role'),
      onSelected: (value) =>
          unawaited(controller.setAssistantProductMode(value)),
      itemBuilder: (_) => [
        for (final value in AssistantMode.values) ...[
          if (value == AssistantMode.worker) const PopupMenuDivider(),
          PopupMenuItem<AssistantMode>(
            key: Key('assistant-product-mode-${value.name}'),
            value: value,
            child: Row(
              children: [
                Icon(
                  roleIconInternal(value),
                  size: 20,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        roleSummaryInternal(value),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (value == mode)
                  Icon(Icons.check_rounded, size: 18, color: palette.accent)
                else
                  const SizedBox(width: 18),
              ],
            ),
          ),
        ],
      ],
      child: _TaskDialogSelectorChipInternal(
        leading: Icon(
          roleIconInternal(mode),
          size: 14,
          color: palette.textMuted,
        ),
        label: mode.label,
        labelWidth: labelMetrics.width,
        tooltip: appText('任务角色', 'Task role'),
      ),
    );
  }
}

/// Chat answers here through the Gateway; the other roles share the Bot
/// team's icons and descriptions.
IconData roleIconInternal(AssistantMode mode) =>
    BotRole.values.byName(mode.name).icon;

String roleSummaryInternal(AssistantMode mode) => mode.runsOnBotTeam
    ? BotRole.values.byName(mode.name).summary
    : appText('直接对话，立刻回答', 'Talk here and get the answer right away');

class _TaskDialogSelectorChipInternal extends StatelessWidget {
  const _TaskDialogSelectorChipInternal({
    required this.leading,
    required this.label,
    required this.tooltip,
    this.labelWidth,
  });

  final Widget leading;
  final String label;
  final String tooltip;
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: palette.strokeSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(width: 6),
            SizedBox(
              width: labelWidth,
              child: Text(
                label,
                style: theme.textTheme.labelMedium,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: palette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
