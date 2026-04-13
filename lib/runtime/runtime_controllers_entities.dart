// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'gateway_runtime.dart';
import 'runtime_models.dart';
import 'secure_config_store.dart';
import 'runtime_controllers_settings.dart';
import 'runtime_controllers_gateway.dart';
import 'runtime_controllers_derived_tasks.dart';

class SkillsController extends ChangeNotifier {
  SkillsController(this.runtimeInternal);

  final GatewayRuntime runtimeInternal;

  List<GatewaySkillSummary> itemsInternal = const <GatewaySkillSummary>[];
  bool loadingInternal = false;
  String? errorInternal;

  List<GatewaySkillSummary> get items => itemsInternal;
  bool get loading => loadingInternal;
  String? get error => errorInternal;

  Future<void> refresh({String? agentId}) async {
    if (!runtimeInternal.isConnected) {
      itemsInternal = const <GatewaySkillSummary>[];
      errorInternal = null;
      notifyListeners();
      return;
    }
    loadingInternal = true;
    errorInternal = null;
    notifyListeners();
    try {
      itemsInternal = await runtimeInternal.listSkills(agentId: agentId);
    } catch (error) {
      errorInternal = error.toString();
    } finally {
      loadingInternal = false;
      notifyListeners();
    }
  }
}

class ModelsController extends ChangeNotifier {
  ModelsController(this.runtimeInternal, this.settingsControllerInternal);

  final GatewayRuntime runtimeInternal;
  final SettingsController settingsControllerInternal;

  List<GatewayModelSummary> itemsInternal = const <GatewayModelSummary>[];
  bool loadingInternal = false;
  String? errorInternal;

  List<GatewayModelSummary> get items => itemsInternal;
  bool get loading => loadingInternal;
  String? get error => errorInternal;

  void restoreFromSettings(AiGatewayProfile profile) {
    final models = modelsFromProfileInternal(profile);
    if (models.length == itemsInternal.length &&
        models.every(
          (item) => itemsInternal.any((current) => current.id == item.id),
        )) {
      return;
    }
    itemsInternal = models;
    notifyListeners();
  }

  Future<void> refresh() async {
    loadingInternal = true;
    errorInternal = null;
    notifyListeners();
    try {
      final profile = settingsControllerInternal.snapshot.aiGateway;
      if (profile.baseUrl.trim().isNotEmpty) {
        final synced = await settingsControllerInternal.syncAiGatewayCatalog(
          profile,
        );
        itemsInternal = modelsFromProfileInternal(synced);
      } else if (runtimeInternal.isConnected) {
        itemsInternal = await runtimeInternal.listModels();
      } else {
        itemsInternal = modelsFromProfileInternal(profile);
      }
    } catch (error) {
      errorInternal = error.toString();
    } finally {
      loadingInternal = false;
      notifyListeners();
    }
  }

  List<GatewayModelSummary> modelsFromProfileInternal(
    AiGatewayProfile profile,
  ) {
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
  CronJobsController(this.runtimeInternal);

  final GatewayRuntime runtimeInternal;

  List<GatewayCronJobSummary> itemsInternal = const <GatewayCronJobSummary>[];
  bool loadingInternal = false;
  String? errorInternal;

  List<GatewayCronJobSummary> get items => itemsInternal;
  bool get loading => loadingInternal;
  String? get error => errorInternal;

  Future<void> refresh() async {
    if (!runtimeInternal.isConnected) {
      itemsInternal = const <GatewayCronJobSummary>[];
      errorInternal = null;
      notifyListeners();
      return;
    }
    loadingInternal = true;
    errorInternal = null;
    notifyListeners();
    try {
      itemsInternal = await runtimeInternal.listCronJobs();
    } catch (error) {
      errorInternal = error.toString();
    } finally {
      loadingInternal = false;
      notifyListeners();
    }
  }
}

class DevicesController extends ChangeNotifier {
  DevicesController(this.runtimeInternal);

  final GatewayRuntime runtimeInternal;

  GatewayDevicePairingList itemsInternal =
      const GatewayDevicePairingList.empty();
  bool loadingInternal = false;
  String? errorInternal;

  GatewayDevicePairingList get items => itemsInternal;
  bool get loading => loadingInternal;
  String? get error => errorInternal;

  Future<void> refresh({bool quiet = false}) async {
    if (!runtimeInternal.isConnected) {
      itemsInternal = const GatewayDevicePairingList.empty();
      if (!quiet) {
        errorInternal = null;
      }
      notifyListeners();
      return;
    }
    if (loadingInternal) {
      return;
    }
    loadingInternal = true;
    if (!quiet) {
      errorInternal = null;
    }
    notifyListeners();
    try {
      itemsInternal = await runtimeInternal.listDevicePairing();
    } catch (error) {
      if (!quiet) {
        errorInternal = error.toString();
      }
    } finally {
      loadingInternal = false;
      notifyListeners();
    }
  }

  Future<void> approve(String requestId) async {
    errorInternal = null;
    notifyListeners();
    try {
      await runtimeInternal.approveDevicePairing(requestId);
      await refresh(quiet: true);
    } catch (error) {
      errorInternal = error.toString();
      notifyListeners();
    }
  }

  Future<void> reject(String requestId) async {
    errorInternal = null;
    notifyListeners();
    try {
      await runtimeInternal.rejectDevicePairing(requestId);
      await refresh(quiet: true);
    } catch (error) {
      errorInternal = error.toString();
      notifyListeners();
    }
  }

  Future<void> remove(String deviceId) async {
    errorInternal = null;
    notifyListeners();
    try {
      await runtimeInternal.removePairedDevice(deviceId);
      await refresh(quiet: true);
    } catch (error) {
      errorInternal = error.toString();
      notifyListeners();
    }
  }

  Future<String?> rotateToken({
    required String deviceId,
    required String role,
    List<String> scopes = const <String>[],
  }) async {
    errorInternal = null;
    notifyListeners();
    try {
      final token = await runtimeInternal.rotateDeviceToken(
        deviceId: deviceId,
        role: role,
        scopes: scopes,
      );
      await refresh(quiet: true);
      return token;
    } catch (error) {
      errorInternal = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> revokeToken({
    required String deviceId,
    required String role,
  }) async {
    errorInternal = null;
    notifyListeners();
    try {
      await runtimeInternal.revokeDeviceToken(deviceId: deviceId, role: role);
      await refresh(quiet: true);
    } catch (error) {
      errorInternal = error.toString();
      notifyListeners();
    }
  }

  void clear() {
    itemsInternal = const GatewayDevicePairingList.empty();
    errorInternal = null;
    loadingInternal = false;
    notifyListeners();
  }
}
