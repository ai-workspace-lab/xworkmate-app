// ignore_for_file: unused_import, unnecessary_import

import 'package:flutter/material.dart';
import '../app/app_controller_web.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../widgets/chrome_quick_action_buttons.dart';
import '../widgets/settings_focus_quick_actions.dart';
import '../widgets/surface_card.dart';
import 'web_focus_panel_core.dart';
import 'web_focus_panel_previews.dart';

class AssistantFocusEmptyStateInternal extends StatelessWidget {
  const AssistantFocusEmptyStateInternal({
    super.key,
    required this.message,
    required this.available,
    required this.onAdd,
  });

  final String message;
  final List<AssistantFocusEntry> available;
  final Future<void> Function(AssistantFocusEntry destination) onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surfaceSecondary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
              height: 1.35,
            ),
          ),
        ),
        if (available.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: available
                .map(
                  (destination) => ActionChip(
                    key: ValueKey<String>(
                      'assistant-focus-add-${destination.name}',
                    ),
                    avatar: Icon(destination.icon, size: 16),
                    label: Text(destination.label),
                    onPressed: () async {
                      await onAdd(destination);
                    },
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}
