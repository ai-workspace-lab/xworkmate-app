part of 'app_controller_desktop.dart';

extension AppControllerDesktopGateway on AppController {
  Future<void> connectWithSetupCode({
    required String setupCode,
    String token = '',
    String password = '',
  }) async {
    final decoded = decodeGatewaySetupCode(setupCode);
    final resolvedToken = token.trim().isNotEmpty
        ? token.trim()
        : (decoded?.token.trim() ?? '');
    final resolvedPassword = password.trim().isNotEmpty
        ? password.trim()
        : (decoded?.password.trim() ?? '');
    final resolvedProfileIndex = _gatewayProfileIndexForExecutionTarget(
      _assistantExecutionTargetForMode(
        _modeFromHost(
          decoded?.host ?? settings.primaryRemoteGatewayProfile.host,
        ),
      ),
    );
    await _settingsController.saveGatewaySecrets(
      profileIndex: resolvedProfileIndex,
      token: resolvedToken,
      password: resolvedPassword,
    );
    final resolvedTarget = _assistantExecutionTargetForMode(
      _modeFromHost(decoded?.host ?? settings.primaryRemoteGatewayProfile.host),
    );
    final currentProfile = _gatewayProfileForAssistantExecutionTarget(
      resolvedTarget,
    );
    final nextProfile = currentProfile.copyWith(
      useSetupCode: true,
      setupCode: setupCode.trim(),
      host: decoded?.host ?? currentProfile.host,
      port: decoded?.port ?? currentProfile.port,
      tls: decoded?.tls ?? currentProfile.tls,
      mode: resolvedTarget == AssistantExecutionTarget.local
          ? RuntimeConnectionMode.local
          : RuntimeConnectionMode.remote,
    );
    await saveSettings(
      settings
          .copyWithGatewayProfileAt(
            _gatewayProfileIndexForExecutionTarget(resolvedTarget),
            nextProfile,
          )
          .copyWith(assistantExecutionTarget: resolvedTarget),
      refreshAfterSave: false,
    );
    _upsertAssistantThreadRecord(
      _sessionsController.currentSessionKey,
      executionTarget: resolvedTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _connectProfile(
      nextProfile,
      profileIndex: resolvedProfileIndex,
      authTokenOverride: resolvedToken,
      authPasswordOverride: resolvedPassword,
    );
    await _chatController.loadSession(_sessionsController.currentSessionKey);
  }

  Future<void> connectManual({
    required String host,
    required int port,
    required bool tls,
    required RuntimeConnectionMode mode,
    String token = '',
    String password = '',
  }) async {
    final nextTarget = _assistantExecutionTargetForMode(mode);
    final nextProfileIndex = _gatewayProfileIndexForExecutionTarget(nextTarget);
    await _settingsController.saveGatewaySecrets(
      profileIndex: nextProfileIndex,
      token: token.trim(),
      password: password.trim(),
    );
    final resolvedHost =
        host.trim().isEmpty && mode == RuntimeConnectionMode.local
        ? '127.0.0.1'
        : host.trim();
    final resolvedPort = mode == RuntimeConnectionMode.local && port <= 0
        ? 18789
        : port;
    final nextProfile = _gatewayProfileForAssistantExecutionTarget(nextTarget)
        .copyWith(
          mode: mode,
          useSetupCode: false,
          setupCode: '',
          host: resolvedHost,
          port: resolvedPort <= 0 ? 443 : resolvedPort,
          tls: mode == RuntimeConnectionMode.local ? false : tls,
        );
    await saveSettings(
      settings
          .copyWithGatewayProfileAt(
            _gatewayProfileIndexForExecutionTarget(nextTarget),
            nextProfile,
          )
          .copyWith(assistantExecutionTarget: nextTarget),
      refreshAfterSave: false,
    );
    _upsertAssistantThreadRecord(
      _sessionsController.currentSessionKey,
      executionTarget: nextTarget,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await _connectProfile(
      nextProfile,
      profileIndex: nextProfileIndex,
      authTokenOverride: token.trim(),
      authPasswordOverride: password.trim(),
    );
    await _chatController.loadSession(_sessionsController.currentSessionKey);
  }

  Future<void> disconnectGateway() async {
    _clearCodexGatewayRegistration();
    await _runtime.disconnect(clearDesiredProfile: false);
    await _settingsController.refreshDerivedState();
    await _agentsController.refresh();
    await _sessionsController.refresh();
    _chatController.clear();
    await _instancesController.refresh();
    await _skillsController.refresh();
    await _connectorsController.refresh();
    await _modelsController.refresh();
    await _cronJobsController.refresh();
    _devicesController.clear();
    _recomputeTasks();
  }

  Future<void> _connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    await _runtime.connectProfile(
      profile,
      profileIndex: profileIndex,
      authTokenOverride: authTokenOverride,
      authPasswordOverride: authPasswordOverride,
    );
    await refreshGatewayHealth();
    await refreshAgents();
    await refreshSessions();
    await _instancesController.refresh();
    await _skillsController.refresh(
      agentId: _agentsController.selectedAgentId.isEmpty
          ? null
          : _agentsController.selectedAgentId,
    );
    await _connectorsController.refresh();
    await _modelsController.refresh();
    await _cronJobsController.refresh();
    await _devicesController.refresh(quiet: true);
    await _settingsController.refreshDerivedState();
    await _ensureCodexGatewayRegistration();
    _recomputeTasks();
  }
}
