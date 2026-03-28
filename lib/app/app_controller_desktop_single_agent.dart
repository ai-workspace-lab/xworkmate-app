part of 'app_controller_desktop.dart';

extension AppControllerDesktopSingleAgent on AppController {
  Future<void> _sendSingleAgentMessage(
    String message, {
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<CollaborationAttachment> localAttachments,
  }) async {
    final sessionKey = _normalizedAssistantSessionKey(
      _sessionsController.currentSessionKey,
    );
    final trimmed = message.trim();
    if (trimmed.isEmpty && attachments.isEmpty) {
      return;
    }
    await _enqueueThreadTurn<void>(sessionKey, () async {
      final userText = trimmed.isEmpty ? 'See attached.' : trimmed;
      _appendAssistantThreadMessage(
        sessionKey,
        GatewayChatMessage(
          id: _nextLocalMessageId(),
          role: 'user',
          text: userText,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      );
      _aiGatewayPendingSessionKeys.add(sessionKey);
      _recomputeTasks();
      _notifyIfActive();

      try {
        final selection = singleAgentProviderForSession(sessionKey);
        final selectedSkills = assistantSelectedSkillsForSession(sessionKey);
        final gatewayToken = await settingsController.loadGatewayToken();
        final resolution = await _singleAgentRunner.resolveProvider(
          selection: selection,
          availableProviders: configuredSingleAgentProviders,
          configuredCodexCliPath: configuredCodexCliPath,
          gatewayToken: gatewayToken,
        );
        final provider = resolution.resolvedProvider;
        if (provider == null) {
          if (singleAgentUsesAiChatFallbackForSession(sessionKey)) {
            _appendSingleAgentFallbackStatusMessage(
              sessionKey,
              resolution.fallbackReason,
            );
            await _sendAiGatewayMessage(
              message,
              thinking: thinking,
              attachments: attachments,
              sessionKeyOverride: sessionKey,
              appendUserMessage: false,
              managePendingState: false,
            );
          } else {
            _appendAssistantThreadMessage(
              sessionKey,
              GatewayChatMessage(
                id: _nextLocalMessageId(),
                role: 'assistant',
                text: _singleAgentUnavailableLabel(
                  sessionKey,
                  resolution.fallbackReason,
                ),
                timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
                toolCallId: null,
                toolName: _singleAgentRuntimeDebugToolName(
                  provider?.label ?? selection.label,
                ),
                stopReason: null,
                pending: false,
                error: false,
              ),
            );
          }
          return;
        }

        _appendSingleAgentRuntimeStatusMessage(sessionKey, provider);
        _singleAgentExternalCliPendingSessionKeys.add(sessionKey);

        final result = await _singleAgentRunner.run(
          SingleAgentRunRequest(
            sessionId: sessionKey,
            provider: provider,
            prompt: message,
            model: assistantModelForSession(sessionKey),
            gatewayToken: gatewayToken,
            workingDirectory:
                _resolveSingleAgentWorkingDirectoryForSession(
                  sessionKey,
                  provider: provider,
                ) ??
                Directory.current.path,
            attachments: localAttachments,
            selectedSkills: selectedSkills,
            aiGatewayBaseUrl: aiGatewayUrl,
            aiGatewayApiKey: await loadAiGatewayApiKey(),
            config: settings.multiAgent,
            onOutput: (text) => _appendAiGatewayStreamingText(sessionKey, text),
            configuredCodexCliPath: configuredCodexCliPath,
          ),
        );
        final resolvedRuntimeModel = result.resolvedModel.trim();
        if (resolvedRuntimeModel.isNotEmpty) {
          _singleAgentRuntimeModelBySession[sessionKey] = resolvedRuntimeModel;
        }
        final resolvedWorkingDirectory = result.resolvedWorkingDirectory.trim();
        if (resolvedWorkingDirectory.isNotEmpty) {
          _upsertAssistantThreadRecord(
            sessionKey,
            workspaceRef: resolvedWorkingDirectory,
            workspaceRefKind:
                result.resolvedWorkspaceRefKind ??
                assistantWorkspaceRefKindForSession(sessionKey),
            updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          );
        }
        _clearAiGatewayStreamingText(sessionKey);
        if (result.aborted) {
          final partial = result.output.trim();
          if (partial.isNotEmpty) {
            _appendAssistantThreadMessage(
              sessionKey,
              GatewayChatMessage(
                id: _nextLocalMessageId(),
                role: 'assistant',
                text: partial,
                timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
                toolCallId: null,
                toolName: null,
                stopReason: 'aborted',
                pending: false,
                error: false,
              ),
            );
          }
          return;
        }
        if (result.shouldFallbackToAiChat) {
          if (singleAgentUsesAiChatFallbackForSession(sessionKey)) {
            _appendSingleAgentFallbackStatusMessage(
              sessionKey,
              result.fallbackReason ?? result.errorMessage,
            );
            await _sendAiGatewayMessage(
              message,
              thinking: thinking,
              attachments: attachments,
              sessionKeyOverride: sessionKey,
              appendUserMessage: false,
              managePendingState: false,
            );
          } else {
            _appendAssistantThreadMessage(
              sessionKey,
              GatewayChatMessage(
                id: _nextLocalMessageId(),
                role: 'assistant',
                text: _singleAgentUnavailableLabel(
                  sessionKey,
                  result.fallbackReason ?? result.errorMessage,
                ),
                timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
                toolCallId: null,
                toolName: _singleAgentRuntimeDebugToolName(provider.label),
                stopReason: null,
                pending: false,
                error: false,
              ),
            );
          }
          return;
        }

        if (!result.success) {
          _appendAssistantThreadMessage(
            sessionKey,
            _assistantErrorMessage(
              appText(
                '单机智能体执行失败：${result.errorMessage}',
                'Single Agent execution failed: ${result.errorMessage}',
              ),
            ),
          );
          return;
        }

        _appendAssistantThreadMessage(
          sessionKey,
          GatewayChatMessage(
            id: _nextLocalMessageId(),
            role: 'assistant',
            text: result.output,
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: false,
          ),
        );
      } catch (error) {
        _clearAiGatewayStreamingText(sessionKey);
        _appendAssistantThreadMessage(
          sessionKey,
          _assistantErrorMessage(error.toString()),
        );
      } finally {
        _singleAgentExternalCliPendingSessionKeys.remove(sessionKey);
        _clearAiGatewayStreamingText(sessionKey);
        _aiGatewayPendingSessionKeys.remove(sessionKey);
        _recomputeTasks();
        _notifyIfActive();
      }
    });
  }

  Future<void> _sendAiGatewayMessage(
    String message, {
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    String? sessionKeyOverride,
    bool appendUserMessage = true,
    bool managePendingState = true,
  }) async {
    final sessionKey = _normalizedAssistantSessionKey(
      sessionKeyOverride ?? _sessionsController.currentSessionKey,
    );
    final trimmed = message.trim();
    if (trimmed.isEmpty && attachments.isEmpty) {
      return;
    }

    final baseUrl = _normalizeAiGatewayBaseUrl(settings.aiGateway.baseUrl);
    if (baseUrl == null) {
      _appendAssistantThreadMessage(
        sessionKey,
        _assistantErrorMessage(
          appText(
            'LLM API Endpoint 未配置，无法发送对话。',
            'LLM API Endpoint is not configured, so the conversation could not be sent.',
          ),
        ),
      );
      return;
    }

    final apiKey = await loadAiGatewayApiKey();
    if (apiKey.isEmpty) {
      _appendAssistantThreadMessage(
        sessionKey,
        _assistantErrorMessage(
          appText(
            'LLM API Token 未配置，无法发送对话。',
            'LLM API Token is not configured, so the conversation could not be sent.',
          ),
        ),
      );
      return;
    }

    final model = resolvedAiGatewayModel;
    if (model.isEmpty) {
      _appendAssistantThreadMessage(
        sessionKey,
        _assistantErrorMessage(
          appText(
            '当前没有可用的 LLM API 对话模型。请先在 设置 -> 集成 中同步并选择可用模型。',
            'No LLM API chat model is available yet. Sync and select a supported model in Settings -> Integrations first.',
          ),
        ),
      );
      return;
    }

    if (appendUserMessage) {
      final userText = trimmed.isEmpty ? 'See attached.' : trimmed;
      _appendAssistantThreadMessage(
        sessionKey,
        GatewayChatMessage(
          id: _nextLocalMessageId(),
          role: 'user',
          text: userText,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      );
    }
    if (managePendingState) {
      _aiGatewayPendingSessionKeys.add(sessionKey);
      _recomputeTasks();
      _notifyIfActive();
    }

    try {
      final assistantText = await _requestAiGatewayCompletion(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        thinking: thinking,
        sessionKey: sessionKey,
      );
      _appendAssistantThreadMessage(
        sessionKey,
        GatewayChatMessage(
          id: _nextLocalMessageId(),
          role: 'assistant',
          text: assistantText,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      );
    } on _AiGatewayAbortException catch (error) {
      final partial = error.partialText.trim();
      if (partial.isNotEmpty) {
        _appendAssistantThreadMessage(
          sessionKey,
          GatewayChatMessage(
            id: _nextLocalMessageId(),
            role: 'assistant',
            text: partial,
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: null,
            stopReason: 'aborted',
            pending: false,
            error: false,
          ),
        );
      }
    } catch (error) {
      _appendAssistantThreadMessage(
        sessionKey,
        _assistantErrorMessage(_aiGatewayErrorLabel(error)),
      );
    } finally {
      _aiGatewayStreamingClients.remove(sessionKey);
      _clearAiGatewayStreamingText(sessionKey);
      if (managePendingState) {
        _aiGatewayPendingSessionKeys.remove(sessionKey);
        _recomputeTasks();
        _notifyIfActive();
      }
    }
  }

  Future<String> _requestAiGatewayCompletion({
    required Uri baseUrl,
    required String apiKey,
    required String model,
    required String thinking,
    required String sessionKey,
  }) async {
    final uri = _aiGatewayChatUri(baseUrl);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _aiGatewayStreamingClients[sessionKey] = client;
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/event-stream, application/json',
      );
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set('x-api-key', apiKey);
      final payload = <String, dynamic>{
        'model': model,
        'stream': true,
        'messages': _buildAiGatewayRequestMessages(sessionKey),
      };
      final normalizedThinking = thinking.trim().toLowerCase();
      if (normalizedThinking.isNotEmpty && normalizedThinking != 'off') {
        payload['reasoning_effort'] = normalizedThinking;
      }
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.transform(utf8.decoder).join();
        throw _AiGatewayChatException(
          _formatAiGatewayHttpError(
            response.statusCode,
            _extractAiGatewayErrorDetail(body),
          ),
        );
      }
      final contentType =
          response.headers.contentType?.mimeType.toLowerCase() ??
          response.headers
              .value(HttpHeaders.contentTypeHeader)
              ?.toLowerCase() ??
          '';
      if (contentType.contains('text/event-stream')) {
        final streamed = await _readAiGatewayStreamingResponse(
          response: response,
          sessionKey: sessionKey,
        );
        if (streamed.trim().isEmpty) {
          throw const FormatException('Missing assistant content');
        }
        return streamed.trim();
      }
      return await _readAiGatewayJsonCompletion(response);
    } catch (error) {
      if (_consumeAiGatewayAbort(sessionKey)) {
        throw _AiGatewayAbortException(
          _aiGatewayStreamingTextBySession[sessionKey] ?? '',
        );
      }
      rethrow;
    } finally {
      _aiGatewayStreamingClients.remove(sessionKey);
      client.close(force: true);
    }
  }

  List<Map<String, String>> _buildAiGatewayRequestMessages(String sessionKey) {
    final history = <GatewayChatMessage>[
      ...(_gatewayHistoryCache[sessionKey] ?? const <GatewayChatMessage>[]),
      ...(_assistantThreadMessages[sessionKey] ?? const <GatewayChatMessage>[]),
    ];
    return history
        .where((message) {
          final role = message.role.trim().toLowerCase();
          return (role == 'user' || role == 'assistant') &&
              (message.toolName ?? '').trim().isEmpty &&
              message.text.trim().isNotEmpty;
        })
        .map(
          (message) => <String, String>{
            'role': message.role.trim().toLowerCase() == 'assistant'
                ? 'assistant'
                : 'user',
            'content': message.text.trim(),
          },
        )
        .toList(growable: false);
  }

  Future<String> _readAiGatewayJsonCompletion(
    HttpClientResponse response,
  ) async {
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(_extractFirstJsonDocument(body));
    final assistantText = _extractAiGatewayAssistantText(decoded);
    if (assistantText.trim().isEmpty) {
      throw const FormatException('Missing assistant content');
    }
    return assistantText.trim();
  }

  Future<String> _readAiGatewayStreamingResponse({
    required HttpClientResponse response,
    required String sessionKey,
  }) async {
    final buffer = StringBuffer();
    final eventLines = <String>[];

    void processEvent(String payload) {
      final trimmed = payload.trim();
      if (trimmed.isEmpty) {
        return;
      }
      if (trimmed == '[DONE]') {
        return;
      }
      final deltaText = _extractAiGatewayStreamText(trimmed);
      if (deltaText.isEmpty) {
        return;
      }
      final current = buffer.toString();
      if (current.isEmpty || deltaText == current) {
        buffer
          ..clear()
          ..write(deltaText);
      } else if (deltaText.startsWith(current)) {
        buffer
          ..clear()
          ..write(deltaText);
      } else {
        buffer.write(deltaText);
      }
      _setAiGatewayStreamingText(sessionKey, buffer.toString());
    }

    await for (final line
        in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (_consumeAiGatewayAbort(sessionKey)) {
        throw _AiGatewayAbortException(buffer.toString());
      }
      if (line.isEmpty) {
        if (eventLines.isNotEmpty) {
          processEvent(eventLines.join('\n'));
          eventLines.clear();
        }
        continue;
      }
      if (line.startsWith('data:')) {
        eventLines.add(line.substring(5).trimLeft());
      }
    }

    if (eventLines.isNotEmpty) {
      processEvent(eventLines.join('\n'));
    }

    return buffer.toString();
  }

  String _extractAiGatewayStreamText(String payload) {
    final decoded = jsonDecode(_extractFirstJsonDocument(payload));
    final map = asMap(decoded);
    final choices = asList(map['choices']);
    if (choices.isNotEmpty) {
      final firstChoice = asMap(choices.first);
      final delta = asMap(firstChoice['delta']);
      final deltaContent = _extractAiGatewayContent(delta['content']);
      if (deltaContent.isNotEmpty) {
        return deltaContent;
      }
    }
    return _extractAiGatewayAssistantText(decoded);
  }

  Future<void> _abortAiGatewayRun(String sessionKey) async {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    _aiGatewayAbortedSessionKeys.add(normalizedSessionKey);
    final client = _aiGatewayStreamingClients.remove(normalizedSessionKey);
    if (client != null) {
      try {
        client.close(force: true);
      } catch (_) {
        // Best effort only.
      }
    }
    _aiGatewayPendingSessionKeys.remove(normalizedSessionKey);
    _clearAiGatewayStreamingText(normalizedSessionKey);
    _recomputeTasks();
    _notifyIfActive();
  }

  bool _consumeAiGatewayAbort(String sessionKey) {
    return _aiGatewayAbortedSessionKeys.remove(
      _normalizedAssistantSessionKey(sessionKey),
    );
  }

  GatewayChatMessage _assistantErrorMessage(String text) {
    return GatewayChatMessage(
      id: _nextLocalMessageId(),
      role: 'assistant',
      text: text,
      timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      toolCallId: null,
      toolName: null,
      stopReason: null,
      pending: false,
      error: true,
    );
  }

  String? _singleAgentRuntimeDebugToolName(String label) {
    if (!_showsSingleAgentRuntimeDebugMessages) {
      return null;
    }
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  void _appendSingleAgentRuntimeStatusMessage(
    String sessionKey,
    SingleAgentProvider provider,
  ) {
    if (!_showsSingleAgentRuntimeDebugMessages) {
      return;
    }
    _appendAssistantThreadMessage(
      sessionKey,
      GatewayChatMessage(
        id: _nextLocalMessageId(),
        role: 'assistant',
        text: appText(
          '单机智能体已切换到 ${provider.label} 执行当前任务。',
          'Single Agent is using ${provider.label} for this task.',
        ),
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        toolCallId: null,
        toolName: provider.label,
        stopReason: null,
        pending: false,
        error: false,
      ),
    );
  }

  void _appendSingleAgentFallbackStatusMessage(
    String sessionKey,
    String? reason,
  ) {
    if (!_showsSingleAgentRuntimeDebugMessages) {
      return;
    }
    _appendAssistantThreadMessage(
      sessionKey,
      GatewayChatMessage(
        id: _nextLocalMessageId(),
        role: 'assistant',
        text: _singleAgentFallbackLabel(reason),
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        toolCallId: null,
        toolName: 'AI Chat fallback',
        stopReason: null,
        pending: false,
        error: false,
      ),
    );
  }

  String _singleAgentFallbackLabel(String? reason) {
    final detail = reason?.trim() ?? '';
    return detail.isEmpty
        ? appText(
            '未发现可用的外部 Agent ACP 端点，已回退到 AI Chat。',
            'No external Agent ACP endpoint is available. Falling back to AI Chat.',
          )
        : appText(
            '外部 Agent ACP 连接不可用，已回退到 AI Chat：$detail',
            'External Agent ACP connection is unavailable. Falling back to AI Chat: $detail',
          );
  }

  String _singleAgentUnavailableLabel(String sessionKey, String? reason) {
    final normalizedSessionKey = _normalizedAssistantSessionKey(sessionKey);
    final detail = reason?.trim() ?? '';
    final selection = singleAgentProviderForSession(normalizedSessionKey);
    if (singleAgentShouldSuggestAutoSwitchForSession(normalizedSessionKey)) {
      return detail.isEmpty
          ? appText(
              '当前线程固定为 ${selection.label}，但它在这台设备上不可用。检测到其他外部 Agent ACP 端点时不会自动改线，可切到 Auto。',
              'This thread is pinned to ${selection.label}, but it is unavailable on this device. XWorkmate will not reroute to another external Agent ACP endpoint automatically. Switch to Auto instead.',
            )
          : appText(
              '当前线程固定为 ${selection.label}：$detail 检测到其他外部 Agent ACP 端点时不会自动改线，可切到 Auto。',
              'This thread is pinned to ${selection.label}: $detail XWorkmate will not reroute to another external Agent ACP endpoint automatically. Switch to Auto instead.',
            );
    }
    if (singleAgentNeedsAiGatewayConfigurationForSession(
      normalizedSessionKey,
    )) {
      return detail.isEmpty
          ? appText(
              '当前没有可用的外部 Agent ACP 端点，也没有可用的 AI Chat fallback。请先配置外部 Agent 连接，或配置 LLM API。',
              'No external Agent ACP endpoint is available, and AI Chat fallback is not configured. Configure an external Agent connection or configure LLM API first.',
            )
          : appText(
              '$detail 当前没有可用的外部 Agent ACP 端点，也没有可用的 AI Chat fallback。请先配置外部 Agent 连接，或配置 LLM API。',
              '$detail No external Agent ACP endpoint is available, and AI Chat fallback is not configured. Configure an external Agent connection or configure LLM API first.',
            );
    }
    return detail.isEmpty
        ? appText(
            '当前线程的外部 Agent ACP 连接尚未就绪。',
            'The external Agent ACP connection for this thread is not ready yet.',
          )
        : appText(
            '当前线程的外部 Agent ACP 连接尚未就绪：$detail',
            'The external Agent ACP connection for this thread is not ready yet: $detail',
          );
  }
}
