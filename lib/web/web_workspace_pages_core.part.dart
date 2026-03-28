part of 'web_workspace_pages.dart';

List<AppBreadcrumbItem> _buildWebBreadcrumbs(
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
