import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import '../../theme/app_palette.dart';
import '../plugins/builtin_plugin_catalog.dart';

/// Settings panel listing the first batch of built-in plugins.
///
/// Read-only scaffold for now: shows each plugin's outputs, pipeline, and
/// required skill packages. Enable/disable persistence lands in M2 (see
/// docs/plans/2026-07-04-builtin-plugins-batch-1.md).
class SettingsPluginsPanel extends StatelessWidget {
  const SettingsPluginsPanel({super.key, this.plugins});

  final List<BuiltinPluginDescriptor>? plugins;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final items = plugins ?? BuiltinPluginCatalog.firstBatch;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appText('内置插件', 'Built-in plugins'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            appText(
              '任意对话内容都可以输出为可编辑的交付物。在对话框的插件入口选择后，'
              '模板会插入输入框并随任务执行。',
              'Turn any conversation into editable deliverables. Pick a '
              'plugin from the composer entry to insert its template into '
              'the input.',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 16.0;
              final columns = constraints.maxWidth >= 720 ? 2 : 1;
              final cardWidth = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - spacing * (columns - 1)) /
                        columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final plugin in items)
                    SizedBox(
                      width: cardWidth,
                      child: _BuiltinPluginCard(
                        key: ValueKey<String>(
                          'settings-plugin-card-${plugin.id}',
                        ),
                        plugin: plugin,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BuiltinPluginCard extends StatelessWidget {
  const _BuiltinPluginCard({super.key, required this.plugin});

  final BuiltinPluginDescriptor plugin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(plugin.icon, color: palette.accent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              plugin.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _PluginTag(
                            label: plugin.status.label,
                            emphasized: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plugin.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final format in plugin.outputFormats)
                  _PluginTag(label: format.toUpperCase()),
                for (final skill in plugin.requiredSkills)
                  _PluginTag(
                    label: skill,
                    icon: Icons.key_rounded,
                  ),
              ],
            ),
            if (plugin.pipelineStepsZh.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (var i = 0; i < plugin.pipelineStepsZh.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${i + 1}. ${plugin.pipelineStepsZh[i]}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PluginTag extends StatelessWidget {
  const _PluginTag({
    required this.label,
    this.icon,
    this.emphasized = false,
  });

  final String label;
  final IconData? icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final color = emphasized ? palette.accent : palette.textSecondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
