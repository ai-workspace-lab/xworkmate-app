import 'package:flutter/material.dart';

import '../features/assistant/assistant_page.dart';
import '../features/mobile/mobile_assistant_page.dart';
import '../features/mobile/mobile_settings_page.dart';
import '../features/settings/settings_page.dart';
import '../models/app_models.dart';
import 'app_controller.dart';

enum WorkspacePageSurface { desktop, mobile }

class MobileWorkspaceActions {
  const MobileWorkspaceActions({this.onConnectBridge});

  final VoidCallback? onConnectBridge;

  void connectBridge() => onConnectBridge?.call();
}

typedef WorkspacePageBuilder =
    Widget Function(
      AppController controller,
      ValueChanged<DetailPanelData> onOpenDetail,
    );

typedef MobileWorkspacePageBuilder =
    Widget Function(
      AppController controller,
      ValueChanged<DetailPanelData> onOpenDetail,
      MobileWorkspaceActions mobileActions,
    );

class WorkspacePageSpec {
  const WorkspacePageSpec({
    required this.destination,
    required this.desktopBuilder,
    required this.mobileBuilder,
  });

  final WorkspaceDestination destination;
  final WorkspacePageBuilder desktopBuilder;
  final MobileWorkspacePageBuilder mobileBuilder;
}

final Map<WorkspaceDestination, WorkspacePageSpec> workspacePageSpecsInternal =
    <WorkspaceDestination, WorkspacePageSpec>{
      WorkspaceDestination.assistant: WorkspacePageSpec(
        destination: WorkspaceDestination.assistant,
        desktopBuilder: (controller, onOpenDetail) => AssistantPage(
          controller: controller,
          onOpenDetail: onOpenDetail,
          showStandaloneTaskRail: false,
        ),
        mobileBuilder: (controller, onOpenDetail, mobileActions) =>
            MobileAssistantPage(
              controller: controller,
              onOpenDetail: onOpenDetail,
              mobileActions: mobileActions,
            ),
      ),
      WorkspaceDestination.settings: WorkspacePageSpec(
        destination: WorkspaceDestination.settings,
        desktopBuilder: (controller, onOpenDetail) => SettingsPage(
          controller: controller,
          initialTab: controller.settingsTab,
        ),
        mobileBuilder: (controller, onOpenDetail, mobileActions) =>
            MobileSettingsPage(controller: controller),
      ),
    };

Widget buildWorkspacePage({
  required WorkspaceDestination destination,
  required AppController controller,
  required ValueChanged<DetailPanelData> onOpenDetail,
  required WorkspacePageSurface surface,
  MobileWorkspaceActions mobileActions = const MobileWorkspaceActions(),
}) {
  final spec = workspacePageSpecsInternal[destination]!;
  return switch (surface) {
    WorkspacePageSurface.desktop => spec.desktopBuilder(
      controller,
      onOpenDetail,
    ),
    WorkspacePageSurface.mobile => spec.mobileBuilder(
      controller,
      onOpenDetail,
      mobileActions,
    ),
  };
}
