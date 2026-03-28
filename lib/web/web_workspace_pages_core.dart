// ignore_for_file: unused_import, unnecessary_import

import 'package:flutter/material.dart';
import '../app/app_controller_web.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../widgets/desktop_workspace_scaffold.dart';
import '../widgets/metric_card.dart';
import '../widgets/section_tabs.dart';
import '../widgets/status_badge.dart';
import '../widgets/surface_card.dart';
import '../widgets/top_bar.dart';
import 'web_workspace_pages_tasks.dart';
import 'web_workspace_pages_skills.dart';
import 'web_workspace_pages_nodes.dart';
import 'web_workspace_pages_secrets.dart';
import 'web_workspace_pages_ai_gateway.dart';

List<AppBreadcrumbItem> buildWebBreadcrumbsInternal(
  AppController controller, {
  required String rootLabel,
  String? sectionLabel,
}) {
  final items = <AppBreadcrumbItem>[
    AppBreadcrumbItem(
      label: appText('主页', 'Home'),
      icon: Icons.home_rounded,
      onTap: controller.navigateHome,
    ),
    AppBreadcrumbItem(label: rootLabel),
  ];
  if (sectionLabel != null && sectionLabel.trim().isNotEmpty) {
    items.add(AppBreadcrumbItem(label: sectionLabel));
  }
  return items;
}
