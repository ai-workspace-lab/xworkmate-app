part of 'runtime_controllers.dart';

class InstancesController extends ChangeNotifier {
  InstancesController(this._runtime);

  final GatewayRuntime _runtime;

  List<GatewayInstanceSummary> _items = const <GatewayInstanceSummary>[];
  bool _loading = false;
  String? _error;

  List<GatewayInstanceSummary> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> refresh() async {
    if (!_runtime.isConnected) {
      _items = const <GatewayInstanceSummary>[];
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _runtime.listInstances();
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

class SkillsController extends ChangeNotifier {
  SkillsController(this._runtime);

  final GatewayRuntime _runtime;

  List<GatewaySkillSummary> _items = const <GatewaySkillSummary>[];
  bool _loading = false;
  String? _error;

  List<GatewaySkillSummary> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> refresh({String? agentId}) async {
    if (!_runtime.isConnected) {
      _items = const <GatewaySkillSummary>[];
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _runtime.listSkills(agentId: agentId);
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

class ConnectorsController extends ChangeNotifier {
  ConnectorsController(this._runtime);

  final GatewayRuntime _runtime;

  List<GatewayConnectorSummary> _items = const <GatewayConnectorSummary>[];
  bool _loading = false;
  String? _error;

  List<GatewayConnectorSummary> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> refresh() async {
    if (!_runtime.isConnected) {
      _items = const <GatewayConnectorSummary>[];
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _runtime.listConnectors();
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

class ModelsController extends ChangeNotifier {
  ModelsController(this._runtime, this._settingsController);

  final GatewayRuntime _runtime;
  final SettingsController _settingsController;

  List<GatewayModelSummary> _items = const <GatewayModelSummary>[];
  bool _loading = false;
  String? _error;

  List<GatewayModelSummary> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  void restoreFromSettings(AiGatewayProfile profile) {
    final models = _modelsFromProfile(profile);
    if (models.length == _items.length &&
        models.every(
          (item) => _items.any((current) => current.id == item.id),
        )) {
      return;
    }
    _items = models;
    notifyListeners();
  }

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final profile = _settingsController.snapshot.aiGateway;
      if (profile.baseUrl.trim().isNotEmpty) {
        final synced = await _settingsController.syncAiGatewayCatalog(profile);
        _items = _modelsFromProfile(synced);
      } else if (_runtime.isConnected) {
        _items = await _runtime.listModels();
      } else {
        _items = _modelsFromProfile(profile);
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  List<GatewayModelSummary> _modelsFromProfile(AiGatewayProfile profile) {
    final selected = profile.selectedModels
        .where(profile.availableModels.contains)
        .toList(growable: false);
    final candidates = selected.isNotEmpty
        ? selected
        : profile.availableModels.take(5).toList(growable: false);
    return candidates
        .map(
          (item) => GatewayModelSummary(
            id: item,
            name: item,
            provider: 'LLM API',
            contextWindow: null,
            maxOutputTokens: null,
          ),
        )
        .toList(growable: false);
  }
}

class CronJobsController extends ChangeNotifier {
  CronJobsController(this._runtime);

  final GatewayRuntime _runtime;

  List<GatewayCronJobSummary> _items = const <GatewayCronJobSummary>[];
  bool _loading = false;
  String? _error;

  List<GatewayCronJobSummary> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> refresh() async {
    if (!_runtime.isConnected) {
      _items = const <GatewayCronJobSummary>[];
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _runtime.listCronJobs();
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

class DevicesController extends ChangeNotifier {
  DevicesController(this._runtime);

  final GatewayRuntime _runtime;

  GatewayDevicePairingList _items = const GatewayDevicePairingList.empty();
  bool _loading = false;
  String? _error;

  GatewayDevicePairingList get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> refresh({bool quiet = false}) async {
    if (!_runtime.isConnected) {
      _items = const GatewayDevicePairingList.empty();
      if (!quiet) {
        _error = null;
      }
      notifyListeners();
      return;
    }
    if (_loading) {
      return;
    }
    _loading = true;
    if (!quiet) {
      _error = null;
    }
    notifyListeners();
    try {
      _items = await _runtime.listDevicePairing();
    } catch (error) {
      if (!quiet) {
        _error = error.toString();
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> approve(String requestId) async {
    _error = null;
    notifyListeners();
    try {
      await _runtime.approveDevicePairing(requestId);
      await refresh(quiet: true);
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  Future<void> reject(String requestId) async {
    _error = null;
    notifyListeners();
    try {
      await _runtime.rejectDevicePairing(requestId);
      await refresh(quiet: true);
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  Future<void> remove(String deviceId) async {
    _error = null;
    notifyListeners();
    try {
      await _runtime.removePairedDevice(deviceId);
      await refresh(quiet: true);
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  Future<String?> rotateToken({
    required String deviceId,
    required String role,
    List<String> scopes = const <String>[],
  }) async {
    _error = null;
    notifyListeners();
    try {
      final token = await _runtime.rotateDeviceToken(
        deviceId: deviceId,
        role: role,
        scopes: scopes,
      );
      await refresh(quiet: true);
      return token;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> revokeToken({
    required String deviceId,
    required String role,
  }) async {
    _error = null;
    notifyListeners();
    try {
      await _runtime.revokeDeviceToken(deviceId: deviceId, role: role);
      await refresh(quiet: true);
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  void clear() {
    _items = const GatewayDevicePairingList.empty();
    _error = null;
    _loading = false;
    notifyListeners();
  }
}
