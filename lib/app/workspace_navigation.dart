import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../widgets/top_bar.dart';
import 'app_controller.dart';

List<AppBreadcrumbItem> buildWorkspaceBreadcrumbs({
  required AppController controller,
  required String rootLabel,
  String? sectionLabel,
  String? detailLabel,
  VoidCallback? onRootTap,
}) {
  final items = <AppBreadcrumbItem>[
    AppBreadcrumbItem(
      label: appText('主页', 'Home'),
      icon: Icons.home_rounded,
      onTap: controller.navigateHome,
    ),
    AppBreadcrumbItem(label: rootLabel, onTap: onRootTap),
  ];
  if (sectionLabel != null && sectionLabel.trim().isNotEmpty) {
    items.add(AppBreadcrumbItem(label: sectionLabel));
  }
  if (detailLabel != null && detailLabel.trim().isNotEmpty) {
    items.add(AppBreadcrumbItem(label: detailLabel));
  }
  return items;
}

List<AppBreadcrumbItem> buildSettingsBreadcrumbs(
  AppController controller, {
  required SettingsTab tab,
  SettingsDetailPage? detail,
  SettingsNavigationContext? navigationContext,
}) {
  if (detail == null) {
    return buildWorkspaceBreadcrumbs(
      controller: controller,
      rootLabel: appText('设置', 'Settings'),
      sectionLabel: tab.label,
    );
  }

  return buildWorkspaceBreadcrumbs(
    controller: controller,
    rootLabel: navigationContext?.rootLabel ?? appText('设置', 'Settings'),
    sectionLabel: navigationContext?.sectionLabel ?? tab.label,
    detailLabel: detail.label,
    onRootTap: navigationContext == null
        ? () => controller.openSettings(tab: tab)
        : () => openSettingsNavigationContext(controller, navigationContext),
  );
}

void openSettingsNavigationContext(
  AppController controller,
  SettingsNavigationContext context,
) {
  if (context.modulesTab != null) {
    controller.openModules(tab: context.modulesTab!);
    return;
  }
  if (context.secretsTab != null) {
    controller.openSecrets(tab: context.secretsTab!);
    return;
  }
  if (context.aiGatewayTab != null) {
    controller.openAiGateway(tab: context.aiGatewayTab!);
    return;
  }
  if (context.settingsTab != null ||
      context.destination == WorkspaceDestination.settings) {
    controller.openSettings(tab: context.settingsTab ?? SettingsTab.general);
    return;
  }
  controller.navigateTo(context.destination);
}
