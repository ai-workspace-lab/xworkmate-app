import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'top_bar.dart';

class SettingsPageBodyShell extends StatefulWidget {
  const SettingsPageBodyShell({
    super.key,
    required this.padding,
    required this.breadcrumbs,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.bodyChildren,
    this.leading,
    this.globalApplyBar,
  });

  final EdgeInsetsGeometry padding;
  final List<AppBreadcrumbItem> breadcrumbs;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Widget? globalApplyBar;
  final List<Widget> bodyChildren;

  /// Placed before the header (the hidden sidebar's way back).
  final Widget? leading;

  @override
  State<SettingsPageBodyShell> createState() => _SettingsPageBodyShellState();
}

class _SettingsPageBodyShellState extends State<SettingsPageBodyShell> {
  bool _isHeaderCollapsed = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isHeaderCollapsed) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?widget.leading,
                Expanded(
                  child: TopBar(
              breadcrumbs: widget.breadcrumbs,
              title: widget.title,
              subtitle: widget.subtitle,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  widget.trailing,
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () => setState(() => _isHeaderCollapsed = true),
                    icon: const Icon(Icons.expand_less),
                    tooltip: '折叠顶部面板',
                  ),
                ],
              ),
            ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            if (widget.globalApplyBar != null) ...[
              widget.globalApplyBar!,
              const SizedBox(height: AppSpacing.xl),
            ],
          ] else ...[
            Row(
              children: [
                ?widget.leading,
                Expanded(
                  child: AppBreadcrumbs(items: widget.breadcrumbs),
                ),
                IconButton.filledTonal(
                  onPressed: () => setState(() => _isHeaderCollapsed = false),
                  icon: const Icon(Icons.expand_more),
                  tooltip: '展开顶部面板',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          ...widget.bodyChildren,
        ],
      ),
    );
  }
}
