import '../models/app_models.dart';
import 'ui_feature_manifest.dart';

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

  factory AppCapabilities.fromFeatureAccess(UiFeatureAccess access) {
    return AppCapabilities(
      allowedDestinations: access.allowedDestinations,
      supportsFileAttachments: access.supportsFileAttachments,
      supportsLocalGateway: access.supportsLocalGateway,
      supportsRelayGateway: access.supportsRelayGateway,
      supportsDesktopRuntime: access.supportsDesktopRuntime,
      supportsDiagnostics: access.supportsDiagnostics,
    );
  }
}
