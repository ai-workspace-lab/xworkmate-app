import 'package:flutter/material.dart';

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
    this.globalApplyBar,
  });

  final EdgeInsetsGeometry padding;
  final List<AppBreadcrumbItem> breadcrumbs;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Widget? globalApplyBar;
  final List<Widget> bodyChildren;

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
            TopBar(
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
            const SizedBox(height: 24),
            if (widget.globalApplyBar != null) ...[
              widget.globalApplyBar!,
              const SizedBox(height: 16),
            ],
          ] else ...[
            Row(
              children: [
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
            const SizedBox(height: 16),
          ],
          ...widget.bodyChildren,
        ],
      ),
    );
  }
}
