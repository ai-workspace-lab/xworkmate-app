import 'package:flutter/material.dart';

import 'top_bar.dart';

class SettingsPageBodyShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TopBar(
            breadcrumbs: breadcrumbs,
            title: title,
            subtitle: subtitle,
            trailing: trailing,
          ),
          const SizedBox(height: 24),
          if (globalApplyBar != null) ...[
            globalApplyBar!,
            const SizedBox(height: 16),
          ],
          ...bodyChildren,
        ],
      ),
    );
  }
}
