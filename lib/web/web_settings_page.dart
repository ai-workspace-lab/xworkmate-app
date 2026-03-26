import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller_web.dart';
import '../app/app_metadata.dart';
import '../app/ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../widgets/desktop_workspace_scaffold.dart';
import '../widgets/section_tabs.dart';
import '../widgets/surface_card.dart';
import '../widgets/top_bar.dart';

class WebSettingsPage extends StatefulWidget {
  const WebSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebSettingsPage> createState() => _WebSettingsPageState();
}

enum _WebGatewaySettingsSubTab { gateway, llm, acp }

class _WebSettingsPageState extends State<WebSettingsPage> {
  late final TextEditingController _directNameController;
  late final TextEditingController _directBaseUrlController;
  late final TextEditingController _directProviderController;
  late final TextEditingController _directApiKeyController;
  late final TextEditingController _localHostController;
  late final TextEditingController _localPortController;
  late final TextEditingController _localTokenController;
  late final TextEditingController _localPasswordController;
  late final TextEditingController _remoteHostController;
  late final TextEditingController _remotePortController;
  late final TextEditingController _remoteTokenController;
  late final TextEditingController _remotePasswordController;
  late final TextEditingController _sessionRemoteBaseUrlController;
  late final TextEditingController _sessionApiTokenController;
  late final Map<String, TextEditingController> _externalAcpLabelControllers;
  late final Map<String, TextEditingController> _externalAcpEndpointControllers;
  late WebSessionPersistenceMode _sessionPersistenceMode;
  bool _remoteTls = true;
  _WebGatewaySettingsSubTab _gatewaySubTab = _WebGatewaySettingsSubTab.gateway;

  String _directMessage = '';
  String _localGatewayMessage = '';
  String _remoteGatewayMessage = '';
  String _sessionPersistenceMessage = '';

  @override
  void initState() {
    super.initState();
    _directNameController = TextEditingController();
    _directBaseUrlController = TextEditingController();
    _directProviderController = TextEditingController();
    _directApiKeyController = TextEditingController();
    _localHostController = TextEditingController();
    _localPortController = TextEditingController();
    _localTokenController = TextEditingController();
    _localPasswordController = TextEditingController();
    _remoteHostController = TextEditingController();
    _remotePortController = TextEditingController();
    _remoteTokenController = TextEditingController();
    _remotePasswordController = TextEditingController();
    _sessionRemoteBaseUrlController = TextEditingController();
    _sessionApiTokenController = TextEditingController();
    _externalAcpLabelControllers = <String, TextEditingController>{};
    _externalAcpEndpointControllers = <String, TextEditingController>{};
    _sessionPersistenceMode = widget.controller.webSessionPersistence.mode;
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant WebSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  @override
  void dispose() {
    _directNameController.dispose();
    _directBaseUrlController.dispose();
    _directProviderController.dispose();
    _directApiKeyController.dispose();
    _localHostController.dispose();
    _localPortController.dispose();
    _localTokenController.dispose();
    _localPasswordController.dispose();
    _remoteHostController.dispose();
    _remotePortController.dispose();
    _remoteTokenController.dispose();
    _remotePasswordController.dispose();
    _sessionRemoteBaseUrlController.dispose();
    _sessionApiTokenController.dispose();
    for (final controller in _externalAcpLabelControllers.values) {
      controller.dispose();
    }
    for (final controller in _externalAcpEndpointControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    final settings = widget.controller.settingsDraft;
    final localProfile = settings.primaryLocalGatewayProfile;
    final remoteProfile = settings.primaryRemoteGatewayProfile;
    _setIfDifferent(_directNameController, settings.aiGateway.name);
    _setIfDifferent(_directBaseUrlController, settings.aiGateway.baseUrl);
    _setIfDifferent(_directProviderController, settings.defaultProvider);
    _setIfDifferent(
      _directApiKeyController,
      widget.controller.storedAiGatewayApiKeyMask == null
          ? ''
          : _directApiKeyController.text,
    );
    _setIfDifferent(_localHostController, localProfile.host);
    _setIfDifferent(_localPortController, '${localProfile.port}');
    _setIfDifferent(_remoteHostController, remoteProfile.host);
    _setIfDifferent(_remotePortController, '${remoteProfile.port}');
    _remoteTls = remoteProfile.tls;
    _setIfDifferent(
      _localTokenController,
      widget.controller.storedRelayTokenMaskForProfile(
                kGatewayLocalProfileIndex,
              ) ==
              null
          ? ''
          : _localTokenController.text,
    );
    _setIfDifferent(
      _localPasswordController,
      widget.controller.storedRelayPasswordMaskForProfile(
                kGatewayLocalProfileIndex,
              ) ==
              null
          ? ''
          : _localPasswordController.text,
    );
    _setIfDifferent(
      _remoteTokenController,
      widget.controller.storedRelayTokenMaskForProfile(
                kGatewayRemoteProfileIndex,
              ) ==
              null
          ? ''
          : _remoteTokenController.text,
    );
    _setIfDifferent(
      _remotePasswordController,
      widget.controller.storedRelayPasswordMaskForProfile(
                kGatewayRemoteProfileIndex,
              ) ==
              null
          ? ''
          : _remotePasswordController.text,
    );
    _sessionPersistenceMode = settings.webSessionPersistence.mode;
    _setIfDifferent(
      _sessionRemoteBaseUrlController,
      settings.webSessionPersistence.remoteBaseUrl,
    );
    _setIfDifferent(
      _sessionApiTokenController,
      widget.controller.storedWebSessionApiTokenMask == null
          ? ''
          : _sessionApiTokenController.text,
    );
    _syncExternalAcpControllers(settings);
  }

  void _syncExternalAcpControllers(SettingsSnapshot settings) {
    final activeKeys = settings.externalAcpEndpoints
        .map((item) => item.providerKey)
        .toSet();
    for (final profile in settings.externalAcpEndpoints) {
      final key = profile.providerKey;
      final labelController = _externalAcpLabelControllers.putIfAbsent(
        key,
        () => TextEditingController(),
      );
      final endpointController = _externalAcpEndpointControllers.putIfAbsent(
        key,
        () => TextEditingController(),
      );
      _setIfDifferent(labelController, profile.label);
      _setIfDifferent(endpointController, profile.endpoint);
    }
    _disposeRemovedControllers(_externalAcpLabelControllers, activeKeys);
    _disposeRemovedControllers(_externalAcpEndpointControllers, activeKeys);
  }

  void _disposeRemovedControllers(
    Map<String, TextEditingController> controllers,
    Set<String> activeKeys,
  ) {
    final removedKeys = controllers.keys
        .where((key) => !activeKeys.contains(key))
        .toList(growable: false);
    for (final key in removedKeys) {
      controllers.remove(key)?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final uiFeatures = controller.featuresFor(UiFeaturePlatform.web);
        final availableTabs = uiFeatures.availableSettingsTabs;
        final currentTab = uiFeatures.sanitizeSettingsTab(
          controller.settingsTab,
        );
        final showGlobalApplyBar =
            currentTab != SettingsTab.gateway ||
            _gatewaySubTab == _WebGatewaySettingsSubTab.acp;
        return DesktopWorkspaceScaffold(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TopBar(
                  breadcrumbs: <AppBreadcrumbItem>[
                    AppBreadcrumbItem(
                      label: appText('主页', 'Home'),
                      icon: Icons.home_rounded,
                      onTap: controller.navigateHome,
                    ),
                    AppBreadcrumbItem(
                      label: appText('设置', 'Settings'),
                      onTap: () => controller.openSettings(tab: currentTab),
                    ),
                    AppBreadcrumbItem(label: currentTab.label),
                  ],
                  title: appText('设置', 'Settings'),
                  subtitle: appText(
                    '配置 XWorkmate Web 工作区、网关默认项、界面与诊断选项',
                    'Configure workspace, gateway defaults, appearance, and diagnostics for XWorkmate Web.',
                  ),
                  trailing: SizedBox(
                    width: 260,
                    child: TextField(
                      key: const ValueKey('web-settings-search-field'),
                      decoration: InputDecoration(
                        hintText: appText('搜索设置', 'Search settings'),
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (showGlobalApplyBar) ...[
                  _buildGlobalApplyBar(context, controller),
                  const SizedBox(height: 16),
                ],
                SectionTabs(
                  items: availableTabs.map((item) => item.label).toList(),
                  value: currentTab.label,
                  onChanged: (label) {
                    final tab = availableTabs.firstWhere(
                      (item) => item.label == label,
                    );
                    controller.setSettingsTab(tab);
                  },
                ),
                const SizedBox(height: 24),
                ...switch (currentTab) {
                  SettingsTab.general => _buildGeneral(
                    context,
                    controller,
                    controller.settingsDraft,
                  ),
                  SettingsTab.gateway => _buildGateway(
                    context,
                    controller,
                    controller.settingsDraft,
                  ),
                  SettingsTab.appearance => _buildAppearance(
                    context,
                    controller,
                  ),
                  _ => _buildAbout(context),
                },
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlobalApplyBar(BuildContext context, AppController controller) {
    final theme = Theme.of(context);
    final hasDraft = controller.hasSettingsDraftChanges;
    final hasPendingApply = controller.hasPendingSettingsApply;
    final message = controller.settingsDraftStatusMessage;
    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appText('设置提交流程', 'Settings Submission'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  message.isNotEmpty
                      ? message
                      : hasDraft
                      ? appText(
                          '当前存在未保存草稿。保存：仅保存配置，不立即生效。',
                          'There are unsaved drafts. Save persists configuration only and does not apply it immediately.',
                        )
                      : hasPendingApply
                      ? appText(
                          '当前存在已保存但未应用的更改。应用：立即按当前配置生效。',
                          'There are saved changes waiting to be applied. Apply makes the current configuration take effect immediately.',
                        )
                      : appText(
                          '当前没有待提交更改。',
                          'There are no pending settings changes.',
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton(
                key: const ValueKey('settings-global-save-button'),
                onPressed:
                    hasDraft || _gatewaySubTab == _WebGatewaySettingsSubTab.acp
                    ? () => _handleTopLevelSave(controller)
                    : null,
                child: Text(appText('保存', 'Save')),
              ),
              FilledButton.tonal(
                key: const ValueKey('settings-global-apply-button'),
                onPressed:
                    (hasDraft ||
                        hasPendingApply ||
                        _gatewaySubTab == _WebGatewaySettingsSubTab.acp)
                    ? () => _handleTopLevelApply(controller)
                    : null,
                child: Text(appText('应用', 'Apply')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGeneral(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final targets = controller
        .featuresFor(UiFeaturePlatform.web)
        .availableExecutionTargets
        .toList(growable: false);
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('通用', 'General'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              appText(
                '这里维护 Web 默认执行目标与会话持久化摘要，结构与 App 设置页保持一致。',
                'Maintain the default web execution target and session persistence summary here, aligned with the app settings layout.',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              appText('默认工作模式', 'Default work mode'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<AssistantExecutionTarget>(
              initialValue: settings.assistantExecutionTarget,
              items: targets
                  .map((target) {
                    return DropdownMenuItem<AssistantExecutionTarget>(
                      value: target,
                      child: Text(_targetLabel(target)),
                    );
                  })
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  unawaited(
                    controller.saveSettingsDraft(
                      settings.copyWith(assistantExecutionTarget: value),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            Text(controller.conversationPersistenceSummary),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildGateway(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    return [
      SectionTabs(
        items: <String>[
          'OpenClaw Gateway',
          appText('LLM 接入点', 'LLM Endpoints'),
          appText('ACP 外部接入', 'External ACP'),
        ],
        value: switch (_gatewaySubTab) {
          _WebGatewaySettingsSubTab.gateway => 'OpenClaw Gateway',
          _WebGatewaySettingsSubTab.llm => appText('LLM 接入点', 'LLM Endpoints'),
          _WebGatewaySettingsSubTab.acp => appText('ACP 外部接入', 'External ACP'),
        },
        onChanged: (value) => setState(() {
          _gatewaySubTab = switch (value) {
            'OpenClaw Gateway' => _WebGatewaySettingsSubTab.gateway,
            _ when value == appText('LLM 接入点', 'LLM Endpoints') =>
              _WebGatewaySettingsSubTab.llm,
            _ => _WebGatewaySettingsSubTab.acp,
          };
        }),
      ),
      const SizedBox(height: 16),
      ...switch (_gatewaySubTab) {
        _WebGatewaySettingsSubTab.gateway => _buildGatewayOverview(
          context,
          controller,
        ),
        _WebGatewaySettingsSubTab.llm => _buildLlmEndpointManager(
          context,
          controller,
          settings,
        ),
        _WebGatewaySettingsSubTab.acp => <Widget>[
          _buildExternalAcpEndpointManager(context, controller),
        ],
      },
    ];
  }

  List<Widget> _buildGatewayOverview(
    BuildContext context,
    AppController controller,
  ) {
    final palette = context.palette;
    return [
      SurfaceCard(
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: palette.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                appText(
                  'Web 版凭证会保存在当前浏览器本地存储中，安全性低于桌面端安全存储。请仅在可信设备上使用。',
                  'Web credentials are persisted in this browser and are less secure than desktop secure storage. Use only on trusted devices.',
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OpenClaw Gateway',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              appText(
                '这里维护 Local / Remote Gateway 与浏览器会话持久化配置。保存：仅保存配置，不立即生效。应用：立即按当前配置生效。',
                'Maintain Local / Remote Gateway and browser session persistence here. Save persists configuration only, while Apply makes it take effect immediately.',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _buildGatewayCard(
        context,
        controller: controller,
        title: appText('Local Gateway', 'Local Gateway'),
        executionTarget: AssistantExecutionTarget.local,
        profileIndex: kGatewayLocalProfileIndex,
        hostController: _localHostController,
        portController: _localPortController,
        tokenController: _localTokenController,
        passwordController: _localPasswordController,
        tokenMask: controller.storedRelayTokenMaskForProfile(
          kGatewayLocalProfileIndex,
        ),
        passwordMask: controller.storedRelayPasswordMaskForProfile(
          kGatewayLocalProfileIndex,
        ),
        tls: false,
        onTlsChanged: null,
        message: _localGatewayMessage,
        onMessageChanged: (value) {
          setState(() => _localGatewayMessage = value);
        },
      ),
      const SizedBox(height: 12),
      _buildGatewayCard(
        context,
        controller: controller,
        title: appText('Remote Gateway', 'Remote Gateway'),
        executionTarget: AssistantExecutionTarget.remote,
        profileIndex: kGatewayRemoteProfileIndex,
        hostController: _remoteHostController,
        portController: _remotePortController,
        tokenController: _remoteTokenController,
        passwordController: _remotePasswordController,
        tokenMask: controller.storedRelayTokenMaskForProfile(
          kGatewayRemoteProfileIndex,
        ),
        passwordMask: controller.storedRelayPasswordMaskForProfile(
          kGatewayRemoteProfileIndex,
        ),
        tls: _remoteTls,
        onTlsChanged: (value) {
          setState(() => _remoteTls = value);
        },
        message: _remoteGatewayMessage,
        onMessageChanged: (value) {
          setState(() => _remoteGatewayMessage = value);
        },
      ),
      const SizedBox(height: 12),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('会话持久化', 'Session persistence'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              appText(
                '默认使用浏览器本地缓存保存 Assistant 会话。若要做 durable store，请配置一个 HTTPS Session API；该 API 可以由 PostgreSQL 等后端数据库承接，但浏览器不会直接连接数据库。',
                'Assistant sessions default to browser-local cache. For durable storage, configure an HTTPS session API. That API can be backed by PostgreSQL, but the browser never connects to the database directly.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<WebSessionPersistenceMode>(
              initialValue: _sessionPersistenceMode,
              items: WebSessionPersistenceMode.values
                  .map(
                    (mode) => DropdownMenuItem<WebSessionPersistenceMode>(
                      value: mode,
                      child: Text(mode.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _sessionPersistenceMode = value;
                });
              },
              decoration: InputDecoration(
                labelText: appText('保存位置', 'Persistence target'),
              ),
            ),
            if (_sessionPersistenceMode ==
                WebSessionPersistenceMode.remote) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _sessionRemoteBaseUrlController,
                decoration: InputDecoration(
                  labelText: appText(
                    'Session API Base URL',
                    'Session API Base URL',
                  ),
                  hintText: 'https://xworkmate.svc.plus/api/web-sessions',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sessionApiTokenController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: appText('Session API Token', 'Session API token'),
                  helperText: controller.storedWebSessionApiTokenMask == null
                      ? appText(
                          '只保留在当前浏览器会话内存中；刷新页面后需要重新输入。',
                          'Kept only in the current browser session memory; re-enter it after reload.',
                        )
                      : '${appText('当前会话', 'This session')}: ${controller.storedWebSessionApiTokenMask} · ${appText('刷新后需重新输入', 'Re-enter after reload')}',
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () async {
                    await controller.saveWebSessionPersistenceConfiguration(
                      mode: _sessionPersistenceMode,
                      remoteBaseUrl: _sessionRemoteBaseUrlController.text,
                      apiToken: _sessionApiTokenController.text,
                    );
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _sessionPersistenceMessage =
                          controller.sessionPersistenceStatusMessage;
                    });
                  },
                  child: Text(appText('Save', 'Save')),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    await controller.saveWebSessionPersistenceConfiguration(
                      mode: _sessionPersistenceMode,
                      remoteBaseUrl: _sessionRemoteBaseUrlController.text,
                      apiToken: _sessionApiTokenController.text,
                    );
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _sessionPersistenceMessage = appText(
                        '会话存储配置已应用到当前浏览器会话。',
                        'Session persistence settings are now applied to this browser session.',
                      );
                    });
                  },
                  child: Text(appText('Apply', 'Apply')),
                ),
              ],
            ),
            if (_sessionPersistenceMessage.trim().isNotEmpty ||
                controller.sessionPersistenceStatusMessage
                    .trim()
                    .isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                (_sessionPersistenceMessage.trim().isNotEmpty
                        ? _sessionPersistenceMessage
                        : controller.sessionPersistenceStatusMessage)
                    .trim(),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildLlmEndpointManager(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final palette = context.palette;
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('LLM 接入点', 'LLM Endpoints'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              appText(
                'Web 版保持与 App 一致的接入点结构，但当前仅开放主 LLM API 连接源。',
                'Web keeps the same endpoint structure as the app, but currently exposes only the primary LLM API source.',
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ChoiceChip(
                  key: const ValueKey('web-settings-llm-primary-chip'),
                  selected: true,
                  avatar: const Icon(Icons.link_rounded, size: 18),
                  label: Text(appText('主 LLM API', 'Primary LLM API')),
                  onSelected: (_) {},
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appText('连接源详情', 'Source details'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _directNameController,
                    decoration: InputDecoration(
                      labelText: appText('配置名称', 'Profile name'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _directBaseUrlController,
                    decoration: InputDecoration(
                      labelText: appText(
                        'LLM API Endpoint',
                        'LLM API Endpoint',
                      ),
                      hintText: 'https://api.example.com/v1',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _directProviderController,
                    decoration: InputDecoration(
                      labelText: appText(
                        'LLM API Token 引用',
                        'LLM API token reference',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _directApiKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: appText('LLM API Token', 'LLM API Token'),
                      helperText: controller.storedAiGatewayApiKeyMask == null
                          ? null
                          : '${appText('已安全保存', 'Stored securely')}: ${controller.storedAiGatewayApiKeyMask}',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: controller.resolvedAiGatewayModel.isEmpty
                        ? null
                        : controller.resolvedAiGatewayModel,
                    items: settings.aiGateway.availableModels
                        .map(
                          (item) => DropdownMenuItem<String>(
                            value: item,
                            child: Text(item),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        controller.selectDirectModel(value);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: appText('默认模型', 'Default model'),
                      hintText: appText('先同步模型目录', 'Sync model catalog first'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton(
                        onPressed: controller.aiGatewayBusy
                            ? null
                            : () async {
                                final result = await controller
                                    .testAiGatewayConnection(
                                      baseUrl: _directBaseUrlController.text,
                                      apiKey: _directApiKeyController.text,
                                    );
                                if (!mounted) {
                                  return;
                                }
                                setState(() => _directMessage = result.message);
                              },
                        child: Text(appText('测试连接', 'Test')),
                      ),
                      FilledButton(
                        onPressed: controller.aiGatewayBusy
                            ? null
                            : () async {
                                await controller.saveAiGatewayConfiguration(
                                  name: _directNameController.text,
                                  baseUrl: _directBaseUrlController.text,
                                  provider: _directProviderController.text,
                                  apiKey: _directApiKeyController.text,
                                  defaultModel:
                                      controller.resolvedAiGatewayModel,
                                );
                                if (!mounted) {
                                  return;
                                }
                                setState(() {
                                  _directMessage = appText(
                                    '配置已保存，尚未同步模型目录。',
                                    'Configuration saved; model catalog not synced yet.',
                                  );
                                });
                              },
                        child: Text(appText('保存', 'Save')),
                      ),
                      FilledButton.icon(
                        onPressed: controller.aiGatewayBusy
                            ? null
                            : () async {
                                await controller.saveAiGatewayConfiguration(
                                  name: _directNameController.text,
                                  baseUrl: _directBaseUrlController.text,
                                  provider: _directProviderController.text,
                                  apiKey: _directApiKeyController.text,
                                  defaultModel:
                                      controller.resolvedAiGatewayModel,
                                );
                                try {
                                  await controller.syncAiGatewayModels(
                                    name: _directNameController.text,
                                    baseUrl: _directBaseUrlController.text,
                                    provider: _directProviderController.text,
                                    apiKey: _directApiKeyController.text,
                                  );
                                  if (!mounted) {
                                    return;
                                  }
                                  setState(() {
                                    _directMessage = controller
                                        .settings
                                        .aiGateway
                                        .syncMessage;
                                  });
                                } catch (error) {
                                  if (!mounted) {
                                    return;
                                  }
                                  setState(() => _directMessage = '$error');
                                }
                              },
                        icon: controller.aiGatewayBusy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_circle_outline_rounded),
                        label: Text(appText('应用', 'Apply')),
                      ),
                    ],
                  ),
                  if (_directMessage.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _directMessage,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildExternalAcpEndpointManager(
    BuildContext context,
    AppController controller,
  ) {
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appText('外部 ACP Server Endpoint', 'External ACP Server Endpoints'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            appText(
              '预设保留 Codex、OpenCode；其余 provider 通过“自定义添加更多”扩展。每条记录可自定义显示名称和 ACP Server Endpoint，协议支持 ws / wss / http / https。',
              'Codex and OpenCode stay as presets. Add more custom providers as needed. Each entry can define its own display name and ACP server endpoint with ws / wss / http / https.',
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const ValueKey('web-external-acp-provider-add-button'),
              onPressed: () {
                unawaited(
                  controller.saveSettingsDraft(
                    _appendExternalAcpProvider(controller.settingsDraft),
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: Text(appText('自定义添加更多', 'Add more custom providers')),
            ),
          ),
          const SizedBox(height: 16),
          ...controller.settingsDraft.externalAcpEndpoints.map(
            (profile) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildExternalAcpProviderCard(
                context,
                controller,
                profile,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExternalAcpProviderCard(
    BuildContext context,
    AppController controller,
    ExternalAcpEndpointProfile profile,
  ) {
    final provider = profile.toProvider();
    final labelController = _externalAcpLabelControllers[profile.providerKey]!;
    final endpointController =
        _externalAcpEndpointControllers[profile.providerKey]!;
    final configured = endpointController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  provider.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (!profile.isPreset) ...[
                IconButton(
                  tooltip: appText('删除 Provider', 'Remove provider'),
                  onPressed: () {
                    final next = controller.settingsDraft.copyWith(
                      externalAcpEndpoints: controller
                          .settingsDraft
                          .externalAcpEndpoints
                          .where(
                            (item) => item.providerKey != profile.providerKey,
                          )
                          .toList(growable: false),
                    );
                    unawaited(controller.saveSettingsDraft(next));
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                const SizedBox(width: 4),
              ],
              _StatusChip(
                label: configured
                    ? appText('已配置', 'Configured')
                    : appText('未配置', 'Empty'),
                tone: configured ? _StatusChipTone.ready : _StatusChipTone.idle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: labelController,
            decoration: InputDecoration(
              labelText: appText('显示名称', 'Display name'),
            ),
            onChanged: (_) => _stageExternalAcpDraft(controller),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: endpointController,
            decoration: InputDecoration(
              labelText: appText('ACP Endpoint', 'ACP Endpoint'),
            ),
            onChanged: (_) => _stageExternalAcpDraft(controller),
          ),
          const SizedBox(height: 8),
          Text(
            appText(
              '示例：ws://127.0.0.1:9001、wss://acp.example.com/rpc、http://127.0.0.1:8080、https://agent.example.com',
              'Examples: ws://127.0.0.1:9001, wss://acp.example.com/rpc, http://127.0.0.1:8080, https://agent.example.com',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _handleTopLevelSave(AppController controller) async {
    _stageExternalAcpDraft(controller);
    await controller.persistSettingsDraft();
  }

  Future<void> _handleTopLevelApply(AppController controller) async {
    _stageExternalAcpDraft(controller);
    await controller.applySettingsDraft();
  }

  void _stageExternalAcpDraft(AppController controller) {
    final nextProfiles = controller.settingsDraft.externalAcpEndpoints
        .map(
          (profile) => profile.copyWith(
            label:
                _externalAcpLabelControllers[profile.providerKey]?.text ??
                profile.label,
            endpoint:
                _externalAcpEndpointControllers[profile.providerKey]?.text ??
                profile.endpoint,
          ),
        )
        .toList(growable: false);
    final next = controller.settingsDraft.copyWith(
      externalAcpEndpoints: nextProfiles,
    );
    if (next.toJsonString() == controller.settingsDraft.toJsonString()) {
      return;
    }
    unawaited(controller.saveSettingsDraft(next));
  }

  SettingsSnapshot _appendExternalAcpProvider(SettingsSnapshot settings) {
    var suffix = settings.externalAcpEndpoints.length + 1;
    String providerKey() => 'custom-agent-$suffix';
    final existingKeys = settings.externalAcpEndpoints
        .map((item) => item.providerKey)
        .toSet();
    while (existingKeys.contains(providerKey())) {
      suffix += 1;
    }
    return settings.copyWith(
      externalAcpEndpoints: <ExternalAcpEndpointProfile>[
        ...settings.externalAcpEndpoints,
        ExternalAcpEndpointProfile(
          providerKey: providerKey(),
          label: appText('自定义 Provider $suffix', 'Custom Provider $suffix'),
          badge: '$suffix',
          endpoint: '',
          enabled: true,
        ),
      ],
    );
  }

  Widget _buildGatewayCard(
    BuildContext context, {
    required AppController controller,
    required String title,
    required AssistantExecutionTarget executionTarget,
    required int profileIndex,
    required TextEditingController hostController,
    required TextEditingController portController,
    required TextEditingController tokenController,
    required TextEditingController passwordController,
    required String? tokenMask,
    required String? passwordMask,
    required bool tls,
    required ValueChanged<bool>? onTlsChanged,
    required String message,
    required ValueChanged<String> onMessageChanged,
  }) {
    final expectedMode = executionTarget == AssistantExecutionTarget.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    final matchesTarget = controller.connection.mode == expectedMode;
    final status = matchesTarget
        ? controller.connection.status.label
        : RuntimeConnectionStatus.offline.label;
    final endpoint =
        '${hostController.text.trim()}:${_parsePort(portController.text, fallback: 443)}';
    final statusEndpoint = matchesTarget
        ? (controller.connection.remoteAddress?.trim().isNotEmpty == true
              ? controller.connection.remoteAddress!.trim()
              : endpoint)
        : endpoint;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: hostController,
            decoration: InputDecoration(
              labelText: appText('主机或 URL', 'Host or URL'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: portController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: appText('端口', 'Port')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: tokenController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: appText('Gateway Token', 'Gateway token'),
              helperText: tokenMask == null
                  ? null
                  : '${appText('已保存', 'Stored')}: $tokenMask',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: appText('Gateway Password', 'Gateway password'),
              helperText: passwordMask == null
                  ? null
                  : '${appText('已保存', 'Stored')}: $passwordMask',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${appText('状态', 'Status')}: $status · $statusEndpoint',
                ),
              ),
              if (onTlsChanged != null) ...[
                Switch(value: tls, onChanged: onTlsChanged),
                Text(appText('TLS', 'TLS')),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton(
                onPressed: controller.relayBusy
                    ? null
                    : () async {
                        final profile = _gatewayProfileDraft(
                          executionTarget: executionTarget,
                          host: hostController.text,
                          portText: portController.text,
                          tls: tls,
                        );
                        final result = await controller
                            .testGatewayConnectionDraft(
                              profile: profile,
                              executionTarget: executionTarget,
                              tokenOverride: tokenController.text,
                              passwordOverride: passwordController.text,
                            );
                        if (!mounted) {
                          return;
                        }
                        onMessageChanged(
                          '${result.state.toUpperCase()} · ${result.message}',
                        );
                      },
                child: Text(appText('Test', 'Test')),
              ),
              FilledButton(
                onPressed: controller.relayBusy
                    ? null
                    : () async {
                        await controller.saveRelayConfiguration(
                          profileIndex: profileIndex,
                          host: hostController.text,
                          port: _parsePort(portController.text, fallback: 443),
                          tls: tls,
                          token: tokenController.text,
                          password: passwordController.text,
                        );
                        if (!mounted) {
                          return;
                        }
                        onMessageChanged(
                          appText(
                            '配置已保存，尚未应用到当前线程连接。',
                            'Configuration saved but not applied to active thread connections yet.',
                          ),
                        );
                      },
                child: Text(appText('Save', 'Save')),
              ),
              FilledButton.icon(
                onPressed: controller.relayBusy
                    ? null
                    : () async {
                        try {
                          await controller.applyRelayConfiguration(
                            profileIndex: profileIndex,
                            host: hostController.text,
                            port: _parsePort(
                              portController.text,
                              fallback: 443,
                            ),
                            tls: tls,
                            token: tokenController.text,
                            password: passwordController.text,
                          );
                          if (!mounted) {
                            return;
                          }
                          onMessageChanged(
                            appText(
                              '配置已应用；当前线程目标匹配时将使用新连接。',
                              'Configuration applied. Threads targeting this gateway now use the updated connection.',
                            ),
                          );
                        } catch (error) {
                          if (!mounted) {
                            return;
                          }
                          onMessageChanged('$error');
                        }
                      },
                icon: controller.relayBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_circle_outline_rounded),
                label: Text(appText('Apply', 'Apply')),
              ),
            ],
          ),
          if (message.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  GatewayConnectionProfile _gatewayProfileDraft({
    required AssistantExecutionTarget executionTarget,
    required String host,
    required String portText,
    required bool tls,
  }) {
    final mode = executionTarget == AssistantExecutionTarget.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    final defaults = executionTarget == AssistantExecutionTarget.local
        ? GatewayConnectionProfile.defaultsLocal()
        : GatewayConnectionProfile.defaultsRemote();
    return defaults.copyWith(
      mode: mode,
      host: host.trim(),
      port: _parsePort(portText, fallback: defaults.port),
      tls: mode == RuntimeConnectionMode.local ? false : tls,
      useSetupCode: false,
      setupCode: '',
    );
  }

  int _parsePort(String value, {required int fallback}) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) {
      return fallback;
    }
    return parsed;
  }

  List<Widget> _buildAppearance(
    BuildContext context,
    AppController controller,
  ) {
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('界面偏好', 'Appearance'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ThemeMode>(
              initialValue: controller.themeMode,
              items: ThemeMode.values
                  .map(
                    (mode) => DropdownMenuItem<ThemeMode>(
                      value: mode,
                      child: Text(_themeLabel(mode)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  controller.setThemeMode(value);
                }
              },
              decoration: InputDecoration(labelText: appText('主题', 'Theme')),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: controller.toggleAppLanguage,
              icon: const Icon(Icons.translate_rounded),
              label: Text(
                controller.appLanguage == AppLanguage.zh ? '中文' : 'English',
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildAbout(BuildContext context) {
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'XWorkmate Web',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(kAppVersionLabel),
            const SizedBox(height: 8),
            Text(
              appText(
                'Root SPA 目标部署到 https://xworkmate.svc.plus/ 。单机智能体依赖的 LLM API endpoint 需要浏览器可达且支持 CORS；否则请使用 Relay 模式。',
                'The root SPA targets https://xworkmate.svc.plus/ . Single Agent LLM API endpoints must be browser-reachable and CORS-compatible; otherwise use relay mode.',
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

void _setIfDifferent(TextEditingController controller, String value) {
  if (controller.text == value) {
    return;
  }
  controller.value = controller.value.copyWith(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
    composing: TextRange.empty,
  );
}

String _themeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => appText('浅色', 'Light'),
    ThemeMode.dark => appText('深色', 'Dark'),
    ThemeMode.system => appText('跟随系统', 'System'),
  };
}

String _targetLabel(AssistantExecutionTarget target) {
  return switch (target) {
    AssistantExecutionTarget.singleAgent => appText(
      'Single Agent',
      'Single Agent',
    ),
    AssistantExecutionTarget.local => appText('Local Gateway', 'Local Gateway'),
    AssistantExecutionTarget.remote => appText(
      'Remote Gateway',
      'Remote Gateway',
    ),
  };
}

enum _StatusChipTone { idle, ready }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final _StatusChipTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final background = switch (tone) {
      _StatusChipTone.idle => palette.surfaceSecondary,
      _StatusChipTone.ready => palette.accent.withValues(alpha: 0.14),
    };
    final foreground = switch (tone) {
      _StatusChipTone.idle => palette.textSecondary,
      _StatusChipTone.ready => palette.accent,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
