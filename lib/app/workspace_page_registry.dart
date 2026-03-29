import 'package:flutter/material.dart';

import '../features/account/account_page.dart';
import '../features/assistant/assistant_page.dart';
import '../features/claw_hub/claw_hub_page.dart';
import '../features/mcp_server/mcp_server_page.dart';
import '../features/modules/modules_page.dart';
import '../features/settings/settings_page.dart';
import '../features/skills/skills_page.dart';
import '../features/tasks/tasks_page.dart';
import '../models/app_models.dart';
import '../widgets/assistant_focus_panel.dart';
import 'app_controller.dart';

enum WorkspacePageSurface { desktop, mobile }

typedef WorkspacePageBuilder =
    Widget Function(
      AppController controller,
      ValueChanged<DetailPanelData> onOpenDetail,
    );

class WorkspacePageSpec {
  const WorkspacePageSpec({
    required this.destination,
    required this.desktopBuilder,
    required this.mobileBuilder,
  });

  final WorkspaceDestination destination;
  final WorkspacePageBuilder desktopBuilder;
  final WorkspacePageBuilder mobileBuilder;
}

final Map<WorkspaceDestination, WorkspacePageSpec>
workspacePageSpecsInternal = <WorkspaceDestination, WorkspacePageSpec>{
  WorkspaceDestination.assistant: WorkspacePageSpec(
    destination: WorkspaceDestination.assistant,
    desktopBuilder: (controller, onOpenDetail) => AssistantPage(
      controller: controller,
      onOpenDetail: onOpenDetail,
      navigationPanelBuilder: controller.sidebarState == AppSidebarState.hidden
          ? null
          : (_) => AssistantFocusPanel(controller: controller),
      showStandaloneTaskRail: false,
      unifiedPaneStartsCollapsed:
          controller.sidebarState == AppSidebarState.collapsed,
    ),
    mobileBuilder: (controller, onOpenDetail) => AssistantPage(
      controller: controller,
      onOpenDetail: onOpenDetail,
      showStandaloneTaskRail: false,
    ),
  ),
  WorkspaceDestination.tasks: WorkspacePageSpec(
    destination: WorkspaceDestination.tasks,
    desktopBuilder: (controller, onOpenDetail) =>
        TasksPage(controller: controller, onOpenDetail: onOpenDetail),
    mobileBuilder: (controller, onOpenDetail) =>
        TasksPage(controller: controller, onOpenDetail: onOpenDetail),
  ),
  WorkspaceDestination.skills: WorkspacePageSpec(
    destination: WorkspaceDestination.skills,
    desktopBuilder: (controller, onOpenDetail) =>
        SkillsPage(controller: controller, onOpenDetail: onOpenDetail),
    mobileBuilder: (controller, onOpenDetail) =>
        SkillsPage(controller: controller, onOpenDetail: onOpenDetail),
  ),
  WorkspaceDestination.nodes: WorkspacePageSpec(
    destination: WorkspaceDestination.nodes,
    desktopBuilder: (controller, onOpenDetail) => ModulesPage(
      controller: controller,
      onOpenDetail: onOpenDetail,
      initialTab: controller.modulesTab,
    ),
    mobileBuilder: (controller, onOpenDetail) => ModulesPage(
      controller: controller,
      onOpenDetail: onOpenDetail,
      initialTab: controller.modulesTab,
    ),
  ),
  WorkspaceDestination.agents: WorkspacePageSpec(
    destination: WorkspaceDestination.agents,
    desktopBuilder: (controller, onOpenDetail) => ModulesPage(
      controller: controller,
      onOpenDetail: onOpenDetail,
      initialTab: controller.modulesTab,
    ),
    mobileBuilder: (controller, onOpenDetail) => ModulesPage(
      controller: controller,
      onOpenDetail: onOpenDetail,
      initialTab: controller.modulesTab,
    ),
  ),
  WorkspaceDestination.mcpServer: WorkspacePageSpec(
    destination: WorkspaceDestination.mcpServer,
    desktopBuilder: (controller, onOpenDetail) =>
        McpServerPage(controller: controller, onOpenDetail: onOpenDetail),
    mobileBuilder: (controller, onOpenDetail) =>
        McpServerPage(controller: controller, onOpenDetail: onOpenDetail),
  ),
  WorkspaceDestination.clawHub: WorkspacePageSpec(
    destination: WorkspaceDestination.clawHub,
    desktopBuilder: (controller, onOpenDetail) =>
        ClawHubPage(controller: controller, onOpenDetail: onOpenDetail),
    mobileBuilder: (controller, onOpenDetail) =>
        ClawHubPage(controller: controller, onOpenDetail: onOpenDetail),
  ),
  WorkspaceDestination.secrets: WorkspacePageSpec(
    destination: WorkspaceDestination.secrets,
    desktopBuilder: (controller, onOpenDetail) =>
        SettingsPage(controller: controller, initialTab: SettingsTab.gateway),
    mobileBuilder: (controller, onOpenDetail) =>
        SettingsPage(controller: controller, initialTab: SettingsTab.gateway),
  ),
  WorkspaceDestination.aiGateway: WorkspacePageSpec(
    destination: WorkspaceDestination.aiGateway,
    desktopBuilder: (controller, onOpenDetail) =>
        SettingsPage(controller: controller, initialTab: SettingsTab.gateway),
    mobileBuilder: (controller, onOpenDetail) =>
        SettingsPage(controller: controller, initialTab: SettingsTab.gateway),
  ),
  WorkspaceDestination.settings: WorkspacePageSpec(
    destination: WorkspaceDestination.settings,
    desktopBuilder: (controller, onOpenDetail) => SettingsPage(
      controller: controller,
      initialTab: controller.settingsTab,
      initialDetail: controller.settingsDetail,
      navigationContext: controller.settingsNavigationContext,
      showSectionTabs: false,
    ),
    mobileBuilder: (controller, onOpenDetail) => SettingsPage(
      controller: controller,
      initialTab: controller.settingsTab,
      initialDetail: controller.settingsDetail,
      navigationContext: controller.settingsNavigationContext,
      showSectionTabs: false,
    ),
  ),
  WorkspaceDestination.account: WorkspacePageSpec(
    destination: WorkspaceDestination.account,
    desktopBuilder: (controller, onOpenDetail) =>
        AccountPage(controller: controller),
    mobileBuilder: (controller, onOpenDetail) =>
        AccountPage(controller: controller),
  ),
};

Widget buildWorkspacePage({
  required WorkspaceDestination destination,
  required AppController controller,
  required ValueChanged<DetailPanelData> onOpenDetail,
  required WorkspacePageSurface surface,
}) {
  final spec = workspacePageSpecsInternal[destination]!;
  return switch (surface) {
    WorkspacePageSurface.desktop => spec.desktopBuilder(
      controller,
      onOpenDetail,
    ),
    WorkspacePageSurface.mobile => spec.mobileBuilder(controller, onOpenDetail),
  };
}
