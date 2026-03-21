import '../models/app_models.dart';

class AppCapabilities {
  const AppCapabilities({
    required this.allowedDestinations,
    required this.supportsFileAttachments,
    required this.supportsLocalGateway,
    required this.supportsRelayGateway,
    required this.supportsDesktopRuntime,
    required this.supportsDiagnostics,
  });

  final Set<WorkspaceDestination> allowedDestinations;
  final bool supportsFileAttachments;
  final bool supportsLocalGateway;
  final bool supportsRelayGateway;
  final bool supportsDesktopRuntime;
  final bool supportsDiagnostics;

  bool supportsDestination(WorkspaceDestination destination) {
    return allowedDestinations.contains(destination);
  }

  static const desktop = AppCapabilities(
    allowedDestinations: <WorkspaceDestination>{
      WorkspaceDestination.assistant,
      WorkspaceDestination.tasks,
      WorkspaceDestination.skills,
      WorkspaceDestination.nodes,
      WorkspaceDestination.agents,
      WorkspaceDestination.mcpServer,
      WorkspaceDestination.clawHub,
      WorkspaceDestination.secrets,
      WorkspaceDestination.aiGateway,
      WorkspaceDestination.settings,
      WorkspaceDestination.account,
    },
    supportsFileAttachments: true,
    supportsLocalGateway: true,
    supportsRelayGateway: true,
    supportsDesktopRuntime: true,
    supportsDiagnostics: true,
  );

  static const web = AppCapabilities(
    allowedDestinations: <WorkspaceDestination>{
      WorkspaceDestination.assistant,
      WorkspaceDestination.settings,
    },
    supportsFileAttachments: false,
    supportsLocalGateway: false,
    supportsRelayGateway: true,
    supportsDesktopRuntime: false,
    supportsDiagnostics: false,
  );
}
