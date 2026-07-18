import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../plugins/builtin_plugin_catalog.dart';
import '../plugins/builtin_plugin_visuals.dart';

class MobileBuiltinPluginChoiceChip extends StatelessWidget {
  const MobileBuiltinPluginChoiceChip({
    super.key,
    required this.plugin,
    required this.selected,
    required this.onSelected,
    this.large = false,
  });

  final BuiltinPluginDescriptor plugin;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return FilterChip(
      avatar: BuiltinPluginIconTile(plugin: plugin, size: large ? 26 : 20),
      label: Text(plugin.name),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      backgroundColor: palette.surfaceSecondary,
      selectedColor: palette.accentMuted,
      side: BorderSide(
        color: selected ? palette.accent : Colors.transparent,
        width: 1.2,
      ),
      shape: const StadiumBorder(),
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 8,
        vertical: large ? 12 : 7,
      ),
      labelStyle:
          (large ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
              ?.copyWith(
                color: selected ? palette.accent : palette.textPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
    );
  }
}
