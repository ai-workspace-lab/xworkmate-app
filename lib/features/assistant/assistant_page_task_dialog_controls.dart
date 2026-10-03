import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../models/app_models.dart';
import 'assistant_bot_dialog.dart';
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
    // Retain the original mode chip footprint while removing route/provider choices.
    final labelMetrics = TextPainter(
      text: TextSpan(
        text: 'Gateway',
        style: Theme.of(context).textTheme.labelMedium,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return PopupMenuButton<AssistantMode>(
      key: const Key('assistant-product-mode-button'),
      tooltip: appText('任务模式', 'Task mode'),
      onSelected: (value) => unawaited(_select(context, value)),
      itemBuilder: (_) => [
        for (final value in AssistantMode.values)
          CheckedPopupMenuItem<AssistantMode>(
            key: Key('assistant-product-mode-${value.name}'),
            value: value,
            checked: value == mode,
            child: Text(value.label),
          ),
      ],
      child: _TaskDialogSelectorChipInternal(
        leading: Icon(
          Icons.hub_outlined,
          size: 14,
          color: context.palette.textMuted,
        ),
        label: mode.label,
        labelWidth: labelMetrics.width,
        tooltip: appText('任务模式', 'Task mode'),
      ),
    );
  }

  Future<void> _select(BuildContext context, AssistantMode mode) async {
    await controller.setAssistantProductMode(mode);
    if (mode == AssistantMode.autoBot && context.mounted) {
      await showAssistantBotDialog(context, controller);
    }
  }
}

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
