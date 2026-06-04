// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'app_metadata.dart';
import 'app_capabilities.dart';
import 'app_store_policy.dart';
import 'ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/device_identity_store.dart';

import '../runtime/go_core.dart';
import '../runtime/runtime_bootstrap.dart';
import '../runtime/desktop_platform_service.dart';
import '../runtime/gateway_runtime.dart';
import '../runtime/runtime_controllers.dart';
import '../runtime/runtime_models.dart';
import '../runtime/secure_config_store.dart';
import '../runtime/embedded_agent_launch_policy.dart';
import '../runtime/runtime_coordinator.dart';
import '../runtime/gateway_acp_client.dart';
import '../runtime/codex_runtime.dart';
import '../runtime/codex_config_bridge.dart';
import '../runtime/code_agent_node_orchestrator.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/desktop_thread_artifact_service.dart';
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/platform_environment.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopNavigation on AppController {
  void navigateTo(WorkspaceDestination destination) {
    if (!capabilities.supportsDestination(destination)) {
      return;
    }
    final changed =
        destinationInternal != destination || detailPanelInternal != null;
    if (!changed) {
      return;
    }
    destinationInternal = destination;
    detailPanelInternal = null;
    notifyListeners();
  }

  void navigateHome() {
    final homeDestination =
        capabilities.supportsDestination(WorkspaceDestination.assistant)
        ? WorkspaceDestination.assistant
        : (capabilities.allowedDestinations.isEmpty
              ? WorkspaceDestination.assistant
              : capabilities.allowedDestinations.first);
    final destinationChanged = destinationInternal != homeDestination;
    final detailChanged = detailPanelInternal != null;
    destinationInternal = homeDestination;
    detailPanelInternal = null;
    if (destinationChanged || detailChanged) {
      notifyListeners();
    }
    if (!isAppOwnedAssistantSessionKeyInternal(currentSessionKey)) {
      unawaited(ensureActiveAssistantThreadInternal());
    }
  }

  void openSettings({SettingsTab tab = SettingsTab.gateway}) {
    if (!capabilities.supportsDestination(WorkspaceDestination.settings)) {
      return;
    }
    final resolvedTab = sanitizeSettingsTabInternal(tab);
    final changed =
        destinationInternal != WorkspaceDestination.settings ||
        settingsTabInternal != resolvedTab ||
        detailPanelInternal != null;
    if (!changed) {
      return;
    }
    destinationInternal = WorkspaceDestination.settings;
    settingsTabInternal = resolvedTab;
    detailPanelInternal = null;
    notifyListeners();
  }

  void setSettingsTab(SettingsTab tab, {bool clearDetail = true}) {
    final resolvedTab = sanitizeSettingsTabInternal(tab);
    final changed = settingsTabInternal != resolvedTab;
    if (!changed) {
      return;
    }
    settingsTabInternal = resolvedTab;
    notifyListeners();
  }

  void cycleSidebarState() {
    sidebarStateInternal = switch (sidebarStateInternal) {
      AppSidebarState.expanded => AppSidebarState.collapsed,
      AppSidebarState.collapsed => AppSidebarState.hidden,
      AppSidebarState.hidden => AppSidebarState.expanded,
    };
    notifyListeners();
  }

  void setSidebarState(AppSidebarState state) {
    if (sidebarStateInternal == state) {
      return;
    }
    sidebarStateInternal = state;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (themeModeInternal == mode) {
      return;
    }
    themeModeInternal = mode;
    notifyListeners();
  }

  Future<void> toggleAppLanguage() async {
    await setAppLanguage(
      settings.appLanguage == AppLanguage.zh ? AppLanguage.en : AppLanguage.zh,
    );
  }

  Future<void> setAppLanguage(AppLanguage language) async {
    if (settings.appLanguage == language) {
      return;
    }
    setActiveAppLanguage(language);
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(appLanguage: language),
      refreshAfterSave: false,
    );
  }

  void openDetail(DetailPanelData detailPanel) {
    detailPanelInternal = detailPanel;
    notifyListeners();
  }

  void closeDetail() {
    if (detailPanelInternal == null) {
      return;
    }
    detailPanelInternal = null;
    notifyListeners();
  }
}
