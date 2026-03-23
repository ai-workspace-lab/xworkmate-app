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

class _WebSettingsPageState extends State<WebSettingsPage> {
  late final TextEditingController _directNameController;
  late final TextEditingController _directBaseUrlController;
  late final TextEditingController _directProviderController;
  late final TextEditingController _directApiKeyController;
  late final TextEditingController _relayHostController;
  late final TextEditingController _relayPortController;
  late final TextEditingController _relayTokenController;
  late final TextEditingController _relayPasswordController;
  late final TextEditingController _sessionRemoteBaseUrlController;
  late final TextEditingController _sessionApiTokenController;
  late WebSessionPersistenceMode _sessionPersistenceMode;

  String _directMessage = '';
  String _relayMessage = '';
  String _sessionPersistenceMessage = '';

  @override
  void initState() {
    super.initState();
    _directNameController = TextEditingController();
    _directBaseUrlController = TextEditingController();
    _directProviderController = TextEditingController();
    _directApiKeyController = TextEditingController();
    _relayHostController = TextEditingController();
    _relayPortController = TextEditingController();
    _relayTokenController = TextEditingController();
    _relayPasswordController = TextEditingController();
    _sessionRemoteBaseUrlController = TextEditingController();
    _sessionApiTokenController = TextEditingController();
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
    _relayHostController.dispose();
    _relayPortController.dispose();
    _relayTokenController.dispose();
    _relayPasswordController.dispose();
    _sessionRemoteBaseUrlController.dispose();
    _sessionApiTokenController.dispose();
    super.dispose();
  }

  void _syncControllers() {
    final settings = widget.controller.settings;
    final relayProfile = settings.primaryRemoteGatewayProfile;
    _setIfDifferent(_directNameController, settings.aiGateway.name);
    _setIfDifferent(_directBaseUrlController, settings.aiGateway.baseUrl);
    _setIfDifferent(_directProviderController, settings.defaultProvider);
    _setIfDifferent(
      _directApiKeyController,
      widget.controller.storedAiGatewayApiKeyMask == null
          ? ''
          : _directApiKeyController.text,
    );
    _setIfDifferent(_relayHostController, relayProfile.host);
    _setIfDifferent(_relayPortController, '${relayProfile.port}');
    _setIfDifferent(
      _relayTokenController,
      widget.controller.storedRelayTokenMask == null
          ? ''
          : _relayTokenController.text,
    );
    _setIfDifferent(
      _relayPasswordController,
      widget.controller.storedRelayPasswordMask == null
          ? ''
          : _relayPasswordController.text,
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
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final settings = controller.settings;
        final uiFeatures = controller.featuresFor(UiFeaturePlatform.web);
        final availableTabs = uiFeatures.availableSettingsTabs;
        final currentTab = uiFeatures.sanitizeSettingsTab(
          controller.settingsTab,
        );
        return DesktopWorkspaceScaffold(
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
          eyebrow: appText('Web Preferences', 'Web Preferences'),
          title: appText('设置', 'Settings'),
          subtitle: appText(
            'Web 版只保留单机智能体 / Relay Gateway、界面偏好和基础信息。',
            'The web app keeps only Single Agent, Relay Gateway, appearance preferences, and basic product info.',
          ),
          toolbar: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => controller.navigateHome(),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: Text(appText('回到助手', 'Back to assistant')),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<ThemeMode>(
                  value: controller.themeMode,
                  onChanged: (value) {
                    if (value != null) {
                      controller.setThemeMode(value);
                    }
                  },
                  items: ThemeMode.values
                      .map(
                        (mode) => DropdownMenuItem<ThemeMode>(
                          value: mode,
                          child: Text(_themeLabel(mode)),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              OutlinedButton.icon(
                onPressed: controller.toggleAppLanguage,
                icon: const Icon(Icons.translate_rounded),
                label: Text(
                  controller.appLanguage == AppLanguage.zh ? '中文' : 'English',
                ),
              ),
            ],
          ),
          child: Column(
            children: [
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
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: switch (currentTab) {
                      SettingsTab.general => _buildGeneral(context, controller),
                      SettingsTab.gateway => _buildGateway(
                        context,
                        controller,
                        settings,
                      ),
                      SettingsTab.appearance => _buildAppearance(
                        context,
                        controller,
                      ),
                      _ => _buildAbout(context),
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildGeneral(BuildContext context, AppController controller) {
    final targets = controller
        .featuresFor(UiFeaturePlatform.web)
        .availableExecutionTargets
        .where(
          (target) =>
              target == AssistantExecutionTarget.singleAgent ||
              target == AssistantExecutionTarget.remote,
        )
        .toList(growable: false);
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('默认工作模式', 'Default work mode'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<AssistantExecutionTarget>(
              initialValue: controller.assistantExecutionTarget,
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
                  controller.setAssistantExecutionTarget(value);
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
    final palette = context.palette;
    final relayProfile = settings.primaryRemoteGatewayProfile;
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
      const SizedBox(height: 12),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('会话持久化', 'Session persistence'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
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
                  child: Text(appText('保存会话存储', 'Save session store')),
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
      const SizedBox(height: 12),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('单机智能体', 'Single Agent'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _directNameController,
              decoration: InputDecoration(labelText: appText('名称', 'Name')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _directProviderController,
              decoration: InputDecoration(
                labelText: appText('Provider 标识', 'Provider label'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _directBaseUrlController,
              decoration: InputDecoration(
                labelText: appText('Base URL', 'Base URL'),
                hintText: 'https://api.example.com/v1',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _directApiKeyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: appText('API Key', 'API Key'),
                helperText: controller.storedAiGatewayApiKeyMask == null
                    ? null
                    : '${appText('已保存', 'Stored')}: ${controller.storedAiGatewayApiKeyMask}',
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
                  child: Text(appText('测试连接', 'Test connection')),
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
                            defaultModel: controller.resolvedAiGatewayModel,
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
                              _directMessage =
                                  controller.settings.aiGateway.syncMessage;
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(appText('保存/应用', 'Save / Apply')),
                ),
              ],
            ),
            if (_directMessage.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _directMessage,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('Relay OpenClaw Gateway', 'Relay OpenClaw Gateway'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _relayHostController,
              decoration: InputDecoration(
                labelText: appText('主机或 URL', 'Host or URL'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _relayPortController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: appText('端口', 'Port')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _relayTokenController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: appText('Relay Token', 'Relay token'),
                helperText: controller.storedRelayTokenMask == null
                    ? null
                    : '${appText('已保存', 'Stored')}: ${controller.storedRelayTokenMask}',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _relayPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: appText('Relay Password', 'Relay password'),
                helperText: controller.storedRelayPasswordMask == null
                    ? null
                    : '${appText('已保存', 'Stored')}: ${controller.storedRelayPasswordMask}',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${appText('状态', 'Status')}: ${controller.connection.status.label} · ${controller.connection.remoteAddress ?? appText('未连接', 'Offline')}',
                  ),
                ),
                Switch(
                  value: relayProfile.tls,
                  onChanged: (value) => controller.saveRelayConfiguration(
                    host: _relayHostController.text,
                    port: int.tryParse(_relayPortController.text.trim()) ?? 443,
                    tls: value,
                    token: _relayTokenController.text,
                    password: _relayPasswordController.text,
                  ),
                ),
                Text(appText('TLS', 'TLS')),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () => controller.saveRelayConfiguration(
                    host: _relayHostController.text,
                    port: int.tryParse(_relayPortController.text.trim()) ?? 443,
                    tls: relayProfile.tls,
                    token: _relayTokenController.text,
                    password: _relayPasswordController.text,
                  ),
                  child: Text(appText('保存', 'Save')),
                ),
                OutlinedButton.icon(
                  onPressed: controller.relayBusy
                      ? null
                      : () async {
                          try {
                            await controller.saveRelayConfiguration(
                              host: _relayHostController.text,
                              port:
                                  int.tryParse(
                                    _relayPortController.text.trim(),
                                  ) ??
                                  443,
                              tls: relayProfile.tls,
                              token: _relayTokenController.text,
                              password: _relayPasswordController.text,
                            );
                            await controller.connectRelay();
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _relayMessage = appText(
                                'Relay 已连接',
                                'Relay connected',
                              );
                            });
                          } catch (error) {
                            if (!mounted) {
                              return;
                            }
                            setState(() => _relayMessage = '$error');
                          }
                        },
                  icon: controller.relayBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_rounded),
                  label: Text(appText('连接 Relay', 'Connect relay')),
                ),
                OutlinedButton(
                  onPressed: controller.relayBusy
                      ? null
                      : () async {
                          await controller.disconnectRelay();
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _relayMessage = appText(
                              'Relay 已断开',
                              'Relay disconnected',
                            );
                          });
                        },
                  child: Text(appText('断开', 'Disconnect')),
                ),
              ],
            ),
            if (_relayMessage.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _relayMessage,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
            ],
          ],
        ),
      ),
    ];
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
                'Root SPA 目标部署到 https://xworkmate.svc.plus/ 。单机智能体依赖的 AI Gateway endpoint 需要浏览器可达且支持 CORS；否则请使用 Relay 模式。',
                'The root SPA targets https://xworkmate.svc.plus/ . Single Agent AI Gateway endpoints must be browser-reachable and CORS-compatible; otherwise use relay mode.',
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
    AssistantExecutionTarget.remote => appText(
      'Relay OpenClaw Gateway',
      'Relay OpenClaw Gateway',
    ),
    _ => '',
  };
}
