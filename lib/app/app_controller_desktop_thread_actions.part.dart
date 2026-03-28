part of 'app_controller_desktop.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopThreadActions on AppController {
  bool assistantSessionHasPendingRun(String sessionKey) {
    final normalized = _normalizedAssistantSessionKey(sessionKey);
    if (assistantExecutionTargetForSession(normalized) ==
        AssistantExecutionTarget.singleAgent) {
      return _aiGatewayPendingSessionKeys.contains(normalized);
    }
    return (_chatController.hasPendingRun || _multiAgentRunPending) &&
        matchesSessionKey(normalized, _sessionsController.currentSessionKey);
  }

  Future<void> _sendSingleAgentMessage(
    String message, {
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<CollaborationAttachment> localAttachments,
  }) => AppControllerDesktopSingleAgent(this)._sendSingleAgentMessage(
    message,
    thinking: thinking,
    attachments: attachments,
    localAttachments: localAttachments,
  );

  Future<void> _abortAiGatewayRun(String sessionKey) =>
      AppControllerDesktopSingleAgent(this)._abortAiGatewayRun(sessionKey);

  Future<void> connectSavedGateway() async {
    final target = currentAssistantExecutionTarget;
    if (target == AssistantExecutionTarget.singleAgent) {
      return;
    }
    await AppControllerDesktopGateway(this)._connectProfile(
      _gatewayProfileForAssistantExecutionTarget(target),
      profileIndex: _gatewayProfileIndexForExecutionTarget(target),
    );
  }

  Future<void> clearStoredGatewayToken({int? profileIndex}) async {
    await _settingsController.clearGatewaySecrets(
      profileIndex: profileIndex,
      token: true,
    );
  }

  Future<void> refreshGatewayHealth() async {
    if (!_runtime.isConnected) {
      return;
    }
    try {
      await _runtime.health();
    } catch (_) {}
    try {
      await _runtime.status();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refreshDevices({bool quiet = false}) async {
    await _devicesController.refresh(quiet: quiet);
  }

  Future<void> approveDevicePairing(String requestId) async {
    await _devicesController.approve(requestId);
    await _settingsController.refreshDerivedState();
  }

  Future<void> rejectDevicePairing(String requestId) async {
    await _devicesController.reject(requestId);
  }

  Future<void> removePairedDevice(String deviceId) async {
    await _devicesController.remove(deviceId);
    await _settingsController.refreshDerivedState();
  }

  Future<String?> rotateDeviceRoleToken({
    required String deviceId,
    required String role,
    List<String> scopes = const <String>[],
  }) async {
    final token = await _devicesController.rotateToken(
      deviceId: deviceId,
      role: role,
      scopes: scopes,
    );
    await _settingsController.refreshDerivedState();
    return token;
  }

  Future<void> revokeDeviceRoleToken({
    required String deviceId,
    required String role,
  }) async {
    await _devicesController.revokeToken(deviceId: deviceId, role: role);
    await _settingsController.refreshDerivedState();
  }

  Future<void> refreshAgents() async {
    await _agentsController.refresh();
    _sessionsController.configure(
      mainSessionKey: _runtime.snapshot.mainSessionKey ?? 'main',
      selectedAgentId: _agentsController.selectedAgentId,
      defaultAgentId: '',
    );
    _recomputeTasks();
  }

  Future<void> selectAgent(String? agentId) async {
    _agentsController.selectAgent(agentId);
    if (currentAssistantExecutionTarget !=
        AssistantExecutionTarget.singleAgent) {
      final target = currentAssistantExecutionTarget;
      final nextProfile = _gatewayProfileForAssistantExecutionTarget(
        target,
      ).copyWith(selectedAgentId: _agentsController.selectedAgentId);
      await AppControllerDesktopSettings(this).saveSettings(
        settings.copyWithGatewayProfileAt(
          _gatewayProfileIndexForExecutionTarget(target),
          nextProfile,
        ),
        refreshAfterSave: false,
      );
    }
    _sessionsController.configure(
      mainSessionKey: _runtime.snapshot.mainSessionKey ?? 'main',
      selectedAgentId: _agentsController.selectedAgentId,
      defaultAgentId: '',
    );
    await _chatController.loadSession(_sessionsController.currentSessionKey);
    await _skillsController.refresh(
      agentId: _agentsController.selectedAgentId.isEmpty
          ? null
          : _agentsController.selectedAgentId,
    );
    _recomputeTasks();
  }

  Future<void> refreshSessions() async {
    _sessionsController.configure(
      mainSessionKey: _runtime.snapshot.mainSessionKey ?? 'main',
      selectedAgentId: _agentsController.selectedAgentId,
      defaultAgentId: '',
    );
    await _sessionsController.refresh();
    await _chatController.loadSession(_sessionsController.currentSessionKey);
    _recomputeTasks();
  }

  Future<void> switchSession(String sessionKey) async {
    final previousSessionKey = _normalizedAssistantSessionKey(
      _sessionsController.currentSessionKey,
    );
    final nextSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final nextTarget = assistantExecutionTargetForSession(nextSessionKey);
    final nextViewMode = assistantMessageViewModeForSession(nextSessionKey);

    if (!isSingleAgentMode) {
      _preserveGatewayHistoryForSession(previousSessionKey);
    }

    await _setCurrentAssistantSessionKey(nextSessionKey);
    _upsertAssistantThreadRecord(
      nextSessionKey,
      executionTarget: nextTarget,
      messageViewMode: nextViewMode,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    _syncAssistantWorkspaceRefForSession(
      nextSessionKey,
      executionTarget: nextTarget,
    );
    await _applyAssistantExecutionTarget(
      nextTarget,
      sessionKey: nextSessionKey,
      persistDefaultSelection: false,
    );
    if (nextTarget == AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(nextSessionKey);
    }
    _recomputeTasks();
  }

  Future<void> sendChatMessage(
    String message, {
    String thinking = 'off',
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    List<CollaborationAttachment> localAttachments =
        const <CollaborationAttachment>[],
    List<String> selectedSkillLabels = const <String>[],
  }) async {
    final currentSessionKey = _sessionsController.currentSessionKey;
    if (!isSingleAgentMode ||
        assistantWorkspaceRefForSession(currentSessionKey).trim().isEmpty) {
      _syncAssistantWorkspaceRefForSession(currentSessionKey);
    }
    if (isSingleAgentMode) {
      await _sendSingleAgentMessage(
        message,
        thinking: thinking,
        attachments: attachments,
        localAttachments: localAttachments,
      );
      await _flushAssistantThreadPersistence();
      _recomputeTasks();
      return;
    }
    final dispatch = _codeAgentNodeOrchestrator.buildGatewayDispatch(
      _buildCodeAgentNodeState(),
    );
    await _chatController.sendMessage(
      sessionKey: _sessionsController.currentSessionKey,
      message: message,
      thinking: thinking,
      attachments: attachments,
      agentId: dispatch.agentId,
      metadata: dispatch.metadata,
    );
    _recomputeTasks();
  }

  Future<void> abortRun() async {
    if (_multiAgentRunPending) {
      final sessionKey = _normalizedAssistantSessionKey(
        _sessionsController.currentSessionKey,
      );
      try {
        await _gatewayAcpClient.cancelSession(
          sessionId: sessionKey,
          threadId: sessionKey,
        );
      } catch (_) {
        // Best effort cancellation only.
      }
      _multiAgentRunPending = false;
      _recomputeTasks();
      _notifyIfActive();
      return;
    }
    if (isSingleAgentMode) {
      final sessionKey = _normalizedAssistantSessionKey(
        _sessionsController.currentSessionKey,
      );
      if (_singleAgentExternalCliPendingSessionKeys.contains(sessionKey)) {
        await _singleAgentRunner.abort(sessionKey);
        _aiGatewayPendingSessionKeys.remove(sessionKey);
        _singleAgentExternalCliPendingSessionKeys.remove(sessionKey);
        _clearAiGatewayStreamingText(sessionKey);
        _recomputeTasks();
        _notifyIfActive();
        return;
      }
      await _abortAiGatewayRun(_sessionsController.currentSessionKey);
      return;
    }
    await _chatController.abortRun();
  }

  Future<void> prepareForExit() async {
    try {
      await abortRun();
    } catch (_) {
      // Best effort only. Native termination still proceeds.
    }
    await _flushAssistantThreadPersistence();
  }

  Map<String, dynamic> desktopStatusSnapshot() {
    final pausedTasks = _tasksController.scheduled
        .where((item) => item.status == 'Disabled')
        .length;
    final timedOutTasks = _tasksController.failed
        .where(_looksLikeTimedOutTask)
        .length;
    final failedTasks = _tasksController.failed.length;
    final queuedTasks = _tasksController.queue.length;
    final runningTasks = _tasksController.running.length;
    final scheduledTasks = _tasksController.scheduled.length;
    final badgeCount = runningTasks + pausedTasks + timedOutTasks;
    return <String, dynamic>{
      'connectionStatus': _desktopConnectionStatusValue(connection.status),
      'connectionLabel': connection.status.label,
      'runningTasks': runningTasks,
      'pausedTasks': pausedTasks,
      'timedOutTasks': timedOutTasks,
      'queuedTasks': queuedTasks,
      'scheduledTasks': scheduledTasks,
      'failedTasks': failedTasks,
      'totalTasks': _tasksController.totalCount,
      'badgeCount': badgeCount > 0 ? badgeCount : runningTasks + queuedTasks,
    };
  }

  bool _looksLikeTimedOutTask(DerivedTaskItem item) {
    final haystack = '${item.status} ${item.title} ${item.summary}'
        .toLowerCase();
    return haystack.contains('timed out') ||
        haystack.contains('timeout') ||
        haystack.contains('超时');
  }

  String _desktopConnectionStatusValue(RuntimeConnectionStatus status) {
    switch (status) {
      case RuntimeConnectionStatus.connected:
        return 'connected';
      case RuntimeConnectionStatus.connecting:
        return 'connecting';
      case RuntimeConnectionStatus.error:
        return 'error';
      case RuntimeConnectionStatus.offline:
        return 'disconnected';
    }
  }
}
