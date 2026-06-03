import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_palette.dart';

class SettingsLogsPanel extends StatefulWidget {
  const SettingsLogsPanel({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsLogsPanel> createState() => _SettingsLogsPanelState();
}

class _SettingsLogsPanelState extends State<SettingsLogsPanel> {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Column(
      key: const ValueKey('settings-logs-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.terminal_outlined, color: palette.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                appText('运行日志', 'Runtime Logs'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 400,
          decoration: BoxDecoration(
            color: palette.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.outlineVariant),
          ),
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.monitor_heart_outlined, size: 48, color: palette.textSecondary.withOpacity(0.5)),
                const SizedBox(height: 16),
                Text(
                  appText('暂无日志数据', 'No log data available'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
