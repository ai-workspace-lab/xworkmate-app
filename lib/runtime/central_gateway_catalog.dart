import 'runtime_models.dart';

/// Only the deployment's central provider is selectable by product modes.
/// A provider ID and model ID from the remote catalog form the complete ref.
List<String> centralGatewayModelRefs(Iterable<GatewayModelSummary> models) =>
    models
        .where((model) => model.provider.trim() == 'xworkmate')
        .map((model) => model.id.trim())
        .where((id) => id.isNotEmpty)
        .map((id) => id.startsWith('xworkmate/') ? id : 'xworkmate/$id')
        .toSet()
        .toList(growable: false);
