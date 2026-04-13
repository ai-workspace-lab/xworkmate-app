import 'package:flutter/material.dart';

import '../features/assistant/assistant_page.dart';
import '../features/settings/settings_page.dart';
import '../models/app_models.dart';
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
      showStandaloneTaskRail: false,
    ),
    mobileBuilder: (controller, onOpenDetail) => AssistantPage(
      controller: controller,
      onOpenDetail: onOpenDetail,
      showStandaloneTaskRail: false,
    ),
  ),
  WorkspaceDestination.settings: WorkspacePageSpec(
    destination: WorkspaceDestination.settings,
    desktopBuilder: (controller, onOpenDetail) => SettingsPage(
      controller: controller,
      initialTab: controller.settingsTab,
      initialDetail: controller.settingsDetail,
      navigationContext: controller.settingsNavigationContext,
    ),
    mobileBuilder: (controller, onOpenDetail) => SettingsPage(
      controller: controller,
      initialTab: controller.settingsTab,
      initialDetail: controller.settingsDetail,
      navigationContext: controller.settingsNavigationContext,
    ),
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
