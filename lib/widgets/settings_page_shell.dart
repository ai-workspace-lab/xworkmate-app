import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'surface_card.dart';
import 'top_bar.dart';

List<Widget> buildOrderedSettingsSections({
  required List<SettingsTab> availableTabs,
  required SettingsTab currentTab,
  required List<Widget> Function(SettingsTab tab) buildTabContent,
  double gap = 24,
}) {
  final orderedTabs = <SettingsTab>[
    currentTab,
    ...availableTabs.where((item) => item != currentTab),
  ];
  final sections = <Widget>[];
  for (final tab in orderedTabs) {
    final content = buildTabContent(tab);
    if (content.isEmpty) {
      continue;
    }
    if (sections.isNotEmpty) {
      sections.add(SizedBox(height: gap));
    }
    sections.addAll(content);
  }
  return sections;
}

class SettingsGlobalApplyCard extends StatelessWidget {
  const SettingsGlobalApplyCard({
    super.key,
    required this.message,
    required this.onApply,
    this.applyLabel = 'Save & apply',
    this.title = 'Settings Submission',
  });

  final String title;
  final String message;
  final String applyLabel;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(message, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonal(
                key: const ValueKey('settings-global-apply-button'),
                onPressed: onApply,
                child: Text(applyLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
