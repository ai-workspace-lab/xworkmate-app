part of 'app_controller_web.dart';

extension AppControllerWebGatewayChat on AppController {
  Future<void> sendMessage(
    String rawMessage, {
    String thinking = 'medium',
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    List<String> selectedSkillLabels = const <String>[],
    bool useMultiAgent = false,
  }) async {
    final trimmed = rawMessage.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _syncThreadWorkspaceRef(_currentSessionKey);
    const maxAttachmentBytes = 10 * 1024 * 1024;
    final totalAttachmentBytes = attachments.fold<int>(
      0,
      (total, item) => total + _base64Size(item.content),
    );
    if (totalAttachmentBytes > maxAttachmentBytes) {
      _lastAssistantError = appText(
        '附件总大小超过 10MB，请减少附件后重试。',
        'Attachments exceed the 10MB limit. Remove some files and try again.',
      );
      _notifyChanged();
      return;
    }
    final sessionKey = _normalizedSessionKey(_currentSessionKey);
    await _enqueueThreadTurn<void>(sessionKey, () async {
      _lastAssistantError = null;
      final target = assistantExecutionTargetForSession(sessionKey);
      final current = _threadRecords[sessionKey] ?? _newRecord(target: target);
      final nextMessages = <GatewayChatMessage>[
        ...current.messages,
        GatewayChatMessage(
          id: _messageId(),
          role: 'user',
          text: trimmed,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      ];
      _upsertThreadRecord(
        sessionKey,
        messages: nextMessages,
        executionTarget: target,
        title: _deriveThreadTitle(current.title, nextMessages),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
      _pendingSessionKeys.add(sessionKey);
      await _persistThreads();
      _notifyChanged();

      try {
        if (useMultiAgent && _settings.multiAgent.enabled) {
          await runMultiAgentCollaboration(
            rawPrompt: trimmed,
            composedPrompt: trimmed,
            attachments: attachments,
            selectedSkillLabels: selectedSkillLabels,
          );
          return;
        }
        if (target == AssistantExecutionTarget.singleAgent) {
          final provider = singleAgentProviderForSession(sessionKey);
          if (provider == SingleAgentProvider.auto) {
            if (!canUseAiGatewayConversation) {
              throw Exception(
                appText(
                  '请先在 Settings 配置单机智能体所需的 LLM API Endpoint、LLM API Token 和默认模型。',
                  'Configure the Single Agent LLM API Endpoint, LLM API Token, and default model first.',
                ),
              );
            }
            final directPrompt = attachments.isEmpty
                ? trimmed
                : _augmentPromptWithAttachments(trimmed, attachments);
            final directHistory = List<GatewayChatMessage>.from(nextMessages);
            if (directHistory.isNotEmpty) {
              final last = directHistory.removeLast();
              directHistory.add(
                last.copyWith(text: directPrompt, role: 'user', error: false),
              );
            }
            final reply = await _aiGatewayClient.completeChat(
              baseUrl: _settings.aiGateway.baseUrl,
              apiKey: _aiGatewayApiKeyCache,
              model: assistantModelForSession(sessionKey),
              history: directHistory,
            );
            _appendAssistantMessage(
              sessionKey: sessionKey,
              text: reply,
              error: false,
            );
          } else {
            await _sendSingleAgentViaAcp(
              sessionKey: sessionKey,
              prompt: trimmed,
              provider: provider,
              model: assistantModelForSession(sessionKey),
              thinking: thinking,
              attachments: attachments,
              selectedSkillLabels: selectedSkillLabels,
            );
          }
        } else {
          final expectedMode = target == AssistantExecutionTarget.local
              ? RuntimeConnectionMode.local
              : RuntimeConnectionMode.remote;
          if (connection.status != RuntimeConnectionStatus.connected ||
              connection.mode != expectedMode) {
            throw Exception(
              appText(
                '当前线程目标网关未连接。',
                'The gateway for this thread target is not connected.',
              ),
            );
          }
          await _relayClient.sendChat(
            sessionKey: sessionKey,
            message: attachments.isEmpty
                ? trimmed
                : _augmentPromptWithAttachments(trimmed, attachments),
            thinking: thinking,
            attachments: attachments,
            metadata: <String, dynamic>{
              if (selectedSkillLabels.isNotEmpty)
                'selectedSkills': selectedSkillLabels,
            },
          );
        }
      } catch (error) {
        _appendAssistantMessage(
          sessionKey: sessionKey,
          text: error.toString(),
          error: true,
        );
        _lastAssistantError = error.toString();
        _pendingSessionKeys.remove(sessionKey);
        _streamingTextBySession.remove(sessionKey);
        await _persistThreads();
        _notifyChanged();
      }
    });
  }

  Future<void> runMultiAgentCollaboration({
    required String rawPrompt,
    required String composedPrompt,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<String> selectedSkillLabels,
  }) async {
    final sessionKey = _normalizedSessionKey(_currentSessionKey);
    await _enqueueThreadTurn<void>(sessionKey, () async {
      _multiAgentRunPending = true;
      _acpBusy = true;
      _pendingSessionKeys.add(sessionKey);
      _notifyChanged();
      try {
        final target = assistantExecutionTargetForSession(sessionKey);
        final endpoint = _acpEndpointForTarget(
          target == AssistantExecutionTarget.singleAgent
              ? AssistantExecutionTarget.remote
              : target,
        );
        if (endpoint == null) {
          throw Exception(
            appText(
              '当前线程的 ACP 端点不可用，请先配置并连接 Gateway。',
              'ACP endpoint is unavailable for this thread. Configure and connect Gateway first.',
            ),
          );
        }
        await _refreshAcpCapabilities(endpoint);
        final inlineAttachments = attachments
            .map(
              (item) => <String, dynamic>{
                'name': item.fileName,
                'mimeType': item.mimeType,
                'content': item.content,
                'sizeBytes': _base64Size(item.content),
              },
            )
            .toList(growable: false);
        final params = <String, dynamic>{
          'sessionId': sessionKey,
          'threadId': sessionKey,
          'mode': 'multi-agent',
          'taskPrompt': composedPrompt,
          'workingDirectory': '',
          'selectedSkills': selectedSkillLabels,
          'attachments': attachments
              .map(
                (item) => <String, dynamic>{
                  'name': item.fileName,
                  'description': item.mimeType,
                  'path': '',
                },
              )
              .toList(growable: false),
          if (inlineAttachments.isNotEmpty)
            'inlineAttachments': inlineAttachments,
          'aiGatewayBaseUrl': _settings.aiGateway.baseUrl.trim(),
          'aiGatewayApiKey': _aiGatewayApiKeyCache.trim(),
        };
        String? summary;
        final response = await _requestAcpSessionMessage(
          endpoint: endpoint,
          params: params,
          hasInlineAttachments: inlineAttachments.isNotEmpty,
          onNotification: (notification) {
            final update = _acpSessionUpdateFromNotification(
              notification,
              sessionKey: sessionKey,
            );
            if (update == null) {
              return;
            }
            if (update.type == 'delta' && update.text.isNotEmpty) {
              _appendStreamingText(sessionKey, update.text);
              _notifyChanged();
              return;
            }
            if (update.error && update.message.isNotEmpty) {
              summary = update.message;
            }
            if (update.type == 'done' &&
                summary == null &&
                update.message.isNotEmpty) {
              summary = update.message;
            }
          },
        );
        final result = _castMap(response['result']);
        final summaryText = summary?.trim().isNotEmpty == true
            ? summary!.trim()
            : result['summary']?.toString().trim() ??
                  result['message']?.toString().trim() ??
                  appText('多智能体协作已完成。', 'Multi-agent collaboration completed.');
        _appendAssistantMessage(
          sessionKey: sessionKey,
          text: summaryText,
          error: false,
        );
      } catch (error) {
        _appendAssistantMessage(
          sessionKey: sessionKey,
          text: error.toString(),
          error: true,
        );
        _lastAssistantError = error.toString();
      } finally {
        _multiAgentRunPending = false;
        _acpBusy = false;
        _pendingSessionKeys.remove(sessionKey);
        _clearStreamingText(sessionKey);
        await _persistThreads();
        _notifyChanged();
      }
    });
  }

  Future<void> selectDirectModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await selectAssistantModel(trimmed);
    _settings = _settings.copyWith(defaultModel: trimmed);
    await _persistSettings();
    _notifyChanged();
  }

  Future<void> _sendSingleAgentViaAcp({
    required String sessionKey,
    required String prompt,
    required SingleAgentProvider provider,
    required String model,
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<String> selectedSkillLabels,
  }) async {
    final endpoint = _acpEndpointForTarget(AssistantExecutionTarget.remote);
    if (endpoint == null) {
      throw Exception(
        appText(
          'Remote ACP 端点不可用，请先配置 Remote Gateway。',
          'Remote ACP endpoint is unavailable. Configure Remote Gateway first.',
        ),
      );
    }
    await _refreshAcpCapabilities(endpoint);
    if (_acpCapabilities.providers.isNotEmpty &&
        !_acpCapabilities.providers.any(
          (item) => item.providerId == provider.providerId,
        )) {
      throw Exception(
        appText(
          '当前 ACP 不支持所选 Provider：${provider.label}',
          'Current ACP does not support provider: ${provider.label}',
        ),
      );
    }
    final selectedSkills = selectedSkillLabels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final inlineAttachments = attachments
        .map(
          (item) => <String, dynamic>{
            'name': item.fileName,
            'mimeType': item.mimeType,
            'content': item.content,
            'sizeBytes': _base64Size(item.content),
          },
        )
        .toList(growable: false);
    final params = <String, dynamic>{
      'sessionId': sessionKey,
      'threadId': sessionKey,
      'mode': 'single-agent',
      'provider': provider.providerId,
      'model': model.trim(),
      'thinking': thinking,
      'taskPrompt': prompt,
      'selectedSkills': selectedSkills,
      'attachments': attachments
          .map(
            (item) => <String, dynamic>{
              'name': item.fileName,
              'description': item.mimeType,
              'path': '',
            },
          )
          .toList(growable: false),
      if (inlineAttachments.isNotEmpty) 'inlineAttachments': inlineAttachments,
      'aiGatewayBaseUrl': _settings.aiGateway.baseUrl.trim(),
      'aiGatewayApiKey': _aiGatewayApiKeyCache.trim(),
    };

    String streamingText = '';
    String? completionText;
    String? errorText;
    final response = await _requestAcpSessionMessage(
      endpoint: endpoint,
      params: params,
      hasInlineAttachments: inlineAttachments.isNotEmpty,
      onNotification: (notification) {
        final update = _acpSessionUpdateFromNotification(
          notification,
          sessionKey: sessionKey,
        );
        if (update == null) {
          return;
        }
        if (update.type == 'delta' && update.text.isNotEmpty) {
          streamingText += update.text;
          _appendStreamingText(sessionKey, update.text);
          _notifyChanged();
          return;
        }
        if (update.error && update.message.isNotEmpty) {
          errorText = update.message;
          return;
        }
        if (update.type == 'done' && update.message.isNotEmpty) {
          completionText = update.message;
        }
      },
    );

    final result = _castMap(response['result']);
    final message =
        (completionText?.trim().isNotEmpty == true
                ? completionText!.trim()
                : (streamingText.trim().isNotEmpty
                      ? streamingText.trim()
                      : (result['message']?.toString().trim() ?? '')))
            .trim();

    if (errorText?.trim().isNotEmpty == true) {
      throw Exception(errorText!.trim());
    }
    if (message.isEmpty) {
      throw Exception(
        appText(
          'Single Agent 没有返回可显示的输出。',
          'Single Agent returned no displayable output.',
        ),
      );
    }
    _appendAssistantMessage(
      sessionKey: sessionKey,
      text: message,
      error: false,
    );
    _clearStreamingText(sessionKey);
  }
}
