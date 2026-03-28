part of 'settings_page.dart';

extension _SettingsPageGatewayLlmMixin on _SettingsPageState {
  Widget _buildAiGatewayCardBody(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    _syncDraftControllerValue(
      _aiGatewayNameController,
      settings.aiGateway.name,
      syncedValue: _aiGatewayNameSyncedValue,
      onSyncedValueChanged: (value) => _aiGatewayNameSyncedValue = value,
    );
    _syncDraftControllerValue(
      _aiGatewayUrlController,
      settings.aiGateway.baseUrl,
      syncedValue: _aiGatewayUrlSyncedValue,
      onSyncedValueChanged: (value) => _aiGatewayUrlSyncedValue = value,
    );
    _syncDraftControllerValue(
      _aiGatewayApiKeyRefController,
      settings.aiGateway.apiKeyRef,
      syncedValue: _aiGatewayApiKeyRefSyncedValue,
      onSyncedValueChanged: (value) => _aiGatewayApiKeyRefSyncedValue = value,
    );
    final selectedModels = settings.aiGateway.selectedModels.isNotEmpty
        ? settings.aiGateway.selectedModels
        : settings.aiGateway.availableModels.take(5).toList(growable: false);
    final filteredModels = _filterAiGatewayModels(
      settings.aiGateway.availableModels,
    );
    final hasStoredAiGatewayApiKey =
        controller.settingsController.secureRefs['ai_gateway_api_key'] != null;
    final statusTheme = _aiGatewayFeedbackTheme(
      context,
      _aiGatewayTestMessage.isEmpty
          ? settings.aiGateway.syncState
          : _aiGatewayTestState,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('ai-gateway-name-field'),
          controller: _aiGatewayNameController,
          decoration: InputDecoration(
            labelText: appText('配置名称', 'Profile Name'),
          ),
          onChanged: (_) => unawaited(
            _saveAiGatewayDraft(controller, settings).catchError((_) {}),
          ),
          onSubmitted: (_) => _saveAiGatewayDraft(controller, settings),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('ai-gateway-url-field'),
          controller: _aiGatewayUrlController,
          decoration: InputDecoration(
            labelText: appText('LLM API Endpoint', 'LLM API Endpoint'),
          ),
          onChanged: (_) => unawaited(
            _saveAiGatewayDraft(controller, settings).catchError((_) {}),
          ),
          onSubmitted: (_) => _saveAiGatewayDraft(controller, settings),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('ai-gateway-api-key-ref-field'),
          controller: _aiGatewayApiKeyRefController,
          decoration: InputDecoration(
            labelText: appText('LLM API Token 引用', 'LLM API Token Ref'),
          ),
          onChanged: (_) => unawaited(
            _saveAiGatewayDraft(controller, settings).catchError((_) {}),
          ),
          onSubmitted: (_) => _saveAiGatewayDraft(controller, settings),
        ),
        _buildSecureField(
          fieldKey: const ValueKey('ai-gateway-api-key-field'),
          controller: _aiGatewayApiKeyController,
          label:
              '${appText('LLM API Token', 'LLM API Token')} (${_aiGatewayApiKeyRefController.text.trim().isEmpty ? settings.aiGateway.apiKeyRef : _aiGatewayApiKeyRefController.text.trim()})',
          hasStoredValue: hasStoredAiGatewayApiKey,
          fieldState: _aiGatewayApiKeyState,
          onStateChanged: (value) =>
              _setState(() => _aiGatewayApiKeyState = value),
          loadValue: controller.settingsController.loadAiGatewayApiKey,
          onSubmitted: (value) async =>
              controller.saveAiGatewayApiKeyDraft(value),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示；可直接测试，也可通过本区保存/应用提交。',
            'Stored securely. Test directly or submit it with the local Save / Apply actions.',
          ),
          emptyHelperText: appText(
            '输入后可直接测试，也可通过本区保存/应用提交。',
            'Test it now, or submit it with the local Save / Apply actions.',
          ),
        ),
        const SizedBox(height: 12),
        _buildSettingsSectionActions(
          controller: controller,
          testKey: const ValueKey('ai-gateway-test-button'),
          saveKey: const ValueKey('ai-gateway-save-button'),
          applyKey: const ValueKey('ai-gateway-apply-button'),
          testing: _aiGatewayTesting,
          onTest: () => _testAiGatewayConnection(controller, settings),
          onSave: () => _saveAiGatewayAndPersist(controller, settings),
          onApply: () => _saveAiGatewayAndApply(controller, settings),
        ),
        const SizedBox(height: 12),
        Text(
          settings.aiGateway.syncMessage,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_aiGatewayTestMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('ai-gateway-test-feedback'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusTheme.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _aiGatewayTestMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: statusTheme.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_aiGatewayTestEndpoint.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _aiGatewayTestEndpoint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: statusTheme.foreground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (settings.aiGateway.availableModels.isNotEmpty) ...[
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('ai-gateway-model-search'),
            controller: _aiGatewayModelSearchController,
            decoration: InputDecoration(
              labelText: appText('搜索模型', 'Search models'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _aiGatewayModelSearchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: appText('清空搜索', 'Clear search'),
                      onPressed: () {
                        _aiGatewayModelSearchController.clear();
                        _setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
            onChanged: (_) => _setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                appText(
                  '已选 ${selectedModels.length} / ${settings.aiGateway.availableModels.length}',
                  'Selected ${selectedModels.length} / ${settings.aiGateway.availableModels.length}',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              OutlinedButton(
                key: const ValueKey('ai-gateway-select-filtered'),
                onPressed: filteredModels.isEmpty
                    ? null
                    : () async {
                        await controller.updateAiGatewaySelection(
                          <String>{
                            ...selectedModels,
                            ...filteredModels,
                          }.toList(growable: false),
                        );
                      },
                child: Text(appText('选择筛选结果', 'Select filtered')),
              ),
              OutlinedButton(
                key: const ValueKey('ai-gateway-reset-default'),
                onPressed: () async {
                  await controller.updateAiGatewaySelection(
                    settings.aiGateway.availableModels
                        .take(5)
                        .toList(growable: false),
                  );
                },
                child: Text(appText('恢复默认 5 个', 'Reset default 5')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (filteredModels.isEmpty)
            Text(
              appText('没有匹配的模型。', 'No matching models.'),
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filteredModels
                  .map((modelId) {
                    final selected = selectedModels.contains(modelId);
                    return FilterChip(
                      label: Text(modelId),
                      selected: selected,
                      onSelected: (_) async {
                        final nextSelection = selected
                            ? selectedModels
                                  .where((item) => item != modelId)
                                  .toList(growable: true)
                            : <String>[...selectedModels, modelId];
                        await controller.updateAiGatewaySelection(
                          nextSelection,
                        );
                      },
                    );
                  })
                  .toList(growable: false),
            ),
        ],
      ],
    );
  }

  Widget _buildOllamaLocalEndpointBody(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditableField(
          label: appText('服务地址', 'Endpoint'),
          value: settings.ollamaLocal.endpoint,
          onSubmitted: (value) => _saveSettings(
            controller,
            settings.copyWith(
              ollamaLocal: settings.ollamaLocal.copyWith(endpoint: value),
            ),
          ),
        ),
        _EditableField(
          label: appText('默认模型', 'Default Model'),
          value: settings.ollamaLocal.defaultModel,
          onSubmitted: (value) => _saveSettings(
            controller,
            settings.copyWith(
              ollamaLocal: settings.ollamaLocal.copyWith(defaultModel: value),
            ),
          ),
        ),
        _SwitchRow(
          label: appText('自动发现', 'Auto Discover'),
          value: settings.ollamaLocal.autoDiscover,
          onChanged: (value) => _saveSettings(
            controller,
            settings.copyWith(
              ollamaLocal: settings.ollamaLocal.copyWith(autoDiscover: value),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => controller.testOllamaConnection(cloud: false),
            child: Text(
              '${appText('测试连接', 'Test Connection')} · ${controller.settingsController.ollamaStatus}',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOllamaCloudEndpointBody(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final hasStoredOllamaApiKey =
        controller.settingsController.secureRefs['ollama_cloud_api_key'] !=
        null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditableField(
          label: appText('基础地址', 'Base URL'),
          value: settings.ollamaCloud.baseUrl,
          onSubmitted: (value) => _saveSettings(
            controller,
            settings.copyWith(
              ollamaCloud: settings.ollamaCloud.copyWith(baseUrl: value),
            ),
          ),
        ),
        _EditableField(
          label: appText('工作区 / 组织', 'Workspace / Org'),
          value:
              '${settings.ollamaCloud.organization} / ${settings.ollamaCloud.workspace}',
          onSubmitted: (value) {
            final parts = value.split('/');
            _saveSettings(
              controller,
              settings.copyWith(
                ollamaCloud: settings.ollamaCloud.copyWith(
                  organization: parts.isNotEmpty ? parts.first.trim() : '',
                  workspace: parts.length > 1 ? parts[1].trim() : '',
                ),
              ),
            );
          },
        ),
        _EditableField(
          label: appText('默认模型', 'Default Model'),
          value: settings.ollamaCloud.defaultModel,
          onSubmitted: (value) => _saveSettings(
            controller,
            settings.copyWith(
              ollamaCloud: settings.ollamaCloud.copyWith(defaultModel: value),
            ),
          ),
        ),
        _buildSecureField(
          controller: _ollamaApiKeyController,
          label:
              '${appText('API Key', 'API Key')} (${settings.ollamaCloud.apiKeyRef})',
          hasStoredValue: hasStoredOllamaApiKey,
          fieldState: _ollamaApiKeyState,
          onStateChanged: (value) =>
              _setState(() => _ollamaApiKeyState = value),
          loadValue: controller.settingsController.loadOllamaCloudApiKey,
          onSubmitted: (value) async =>
              controller.saveOllamaCloudApiKeyDraft(value),
          storedHelperText: appText(
            '已安全保存，默认以 **** 显示；可直接测试，也可通过本区保存/应用提交。',
            'Stored securely. Test directly or submit it with the local Save / Apply actions.',
          ),
          emptyHelperText: appText(
            '输入后可直接测试，也可通过本区保存/应用提交。',
            'Test it now, or submit it with the local Save / Apply actions.',
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => controller.testOllamaConnection(cloud: true),
            child: Text(
              '${appText('测试云端', 'Test Cloud')} · ${controller.settingsController.ollamaStatus}',
            ),
          ),
        ),
      ],
    );
  }

  int _resolvedVisibleLlmEndpointCount(
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final requiredCount = _requiredLlmEndpointSlotCount(controller, settings);
    return requiredCount > _llmEndpointSlotLimit
        ? requiredCount
        : _llmEndpointSlotLimit;
  }

  int _requiredLlmEndpointSlotCount(
    AppController controller,
    SettingsSnapshot settings,
  ) {
    var requiredCount = 1;
    if (_isOllamaLocalEndpointConfigured(settings)) {
      requiredCount = 2;
    }
    if (_isOllamaCloudEndpointConfigured(controller, settings)) {
      requiredCount = 3;
    }
    return requiredCount;
  }

  bool _isLlmEndpointSlotConfigured(
    AppController controller,
    SettingsSnapshot settings,
    _LlmEndpointSlot slot,
  ) {
    return switch (slot) {
      _LlmEndpointSlot.aiGateway => _isAiGatewayEndpointConfigured(
        controller,
        settings,
      ),
      _LlmEndpointSlot.ollamaLocal => _isOllamaLocalEndpointConfigured(
        settings,
      ),
      _LlmEndpointSlot.ollamaCloud => _isOllamaCloudEndpointConfigured(
        controller,
        settings,
      ),
    };
  }

  bool _isAiGatewayEndpointConfigured(
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final defaults = AiGatewayProfile.defaults();
    final config = settings.aiGateway;
    return config.name.trim() != defaults.name ||
        config.baseUrl.trim().isNotEmpty ||
        config.apiKeyRef.trim() != defaults.apiKeyRef ||
        config.availableModels.isNotEmpty ||
        config.selectedModels.isNotEmpty ||
        controller.settingsController.secureRefs['ai_gateway_api_key'] != null;
  }

  bool _isOllamaLocalEndpointConfigured(SettingsSnapshot settings) {
    final defaults = OllamaLocalConfig.defaults();
    final config = settings.ollamaLocal;
    return config.endpoint.trim() != defaults.endpoint ||
        config.defaultModel.trim() != defaults.defaultModel ||
        config.autoDiscover != defaults.autoDiscover;
  }

  bool _isOllamaCloudEndpointConfigured(
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final defaults = OllamaCloudConfig.defaults();
    final config = settings.ollamaCloud;
    return config.baseUrl.trim() != defaults.baseUrl ||
        config.organization.trim().isNotEmpty ||
        config.workspace.trim().isNotEmpty ||
        config.defaultModel.trim() != defaults.defaultModel ||
        config.apiKeyRef.trim() != defaults.apiKeyRef ||
        controller.settingsController.secureRefs['ollama_cloud_api_key'] !=
            null;
  }
}
