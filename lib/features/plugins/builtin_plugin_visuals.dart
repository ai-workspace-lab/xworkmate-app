import 'package:flutter/material.dart';

import 'builtin_plugin_catalog.dart';

/// Brand color for each built-in plugin kind, used by the composer plugin
/// menu and selected-plugin chips (document blue, spreadsheet green, deck
/// orange, image purple, video red — matching common office-suite branding).
Color builtinPluginBrandColor(BuiltinPluginKind kind) => switch (kind) {
  BuiltinPluginKind.document => const Color(0xFF3B82F6),
  BuiltinPluginKind.spreadsheet => const Color(0xFF1F9D5B),
  BuiltinPluginKind.presentation => const Color(0xFFE8710A),
  BuiltinPluginKind.image => const Color(0xFF8B5CF6),
  BuiltinPluginKind.video => const Color(0xFFE0453A),
};

/// Rounded-square brand icon tile, the visual anchor of plugin rows/chips.
class BuiltinPluginIconTile extends StatelessWidget {
  const BuiltinPluginIconTile({
    super.key,
    required this.plugin,
    this.size = 24,
  });

  final BuiltinPluginDescriptor plugin;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: builtinPluginBrandColor(plugin.kind),
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Icon(plugin.icon, size: size * 0.62, color: Colors.white),
    );
  }
}
