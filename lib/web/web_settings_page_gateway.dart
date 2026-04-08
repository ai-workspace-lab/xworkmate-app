// ignore_for_file: unused_import, unnecessary_import

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
import 'web_settings_page_core.dart';
import 'web_settings_page_sections.dart';
import 'web_settings_page_support.dart';

extension WebSettingsPageGatewayMixinInternal on WebSettingsPageStateInternal {
  List<Widget> buildLlmEndpointManagerInternal(
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
                    controller: directNameControllerInternal,
                    decoration: InputDecoration(
                      labelText: appText('配置名称', 'Profile name'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: directBaseUrlControllerInternal,
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
                    controller: directProviderControllerInternal,
                    decoration: InputDecoration(
                      labelText: appText(
                        'LLM API Token 引用',
                        'LLM API token reference',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: directApiKeyControllerInternal,
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
                                      baseUrl:
                                          directBaseUrlControllerInternal.text,
                                      apiKey:
                                          directApiKeyControllerInternal.text,
                                    );
                                if (!mounted) {
                                  return;
                                }
                                setStateInternal(
                                  () => directMessageInternal = result.message,
                                );
                              },
                        child: Text(appText('测试连接', 'Test Connection')),
                      ),
                      FilledButton(
                        onPressed: controller.aiGatewayBusy
                            ? null
                            : () async {
                                await controller.saveAiGatewayConfiguration(
                                  name: directNameControllerInternal.text,
                                  baseUrl: directBaseUrlControllerInternal.text,
                                  provider:
                                      directProviderControllerInternal.text,
                                  apiKey: directApiKeyControllerInternal.text,
                                  defaultModel:
                                      controller.resolvedAiGatewayModel,
                                );
                                try {
                                  await controller.syncAiGatewayModels(
                                    name: directNameControllerInternal.text,
                                    baseUrl:
                                        directBaseUrlControllerInternal.text,
                                    provider:
                                        directProviderControllerInternal.text,
                                    apiKey: directApiKeyControllerInternal.text,
                                  );
                                  if (!mounted) {
                                    return;
                                  }
                                  setStateInternal(() {
                                    directMessageInternal = controller
                                        .settings
                                        .aiGateway
                                        .syncMessage;
                                  });
                                } catch (error) {
                                  if (!mounted) {
                                    return;
                                  }
                                  setStateInternal(
                                    () => directMessageInternal = '$error',
                                  );
                                }
                              },
                        child: controller.aiGatewayBusy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(appText('保存并生效', 'Save & apply')),
                      ),
                    ],
                  ),
                  if (directMessageInternal.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      directMessageInternal,
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

  Widget buildExternalAcpEndpointManagerInternal(
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
              '这里保留 Codex、OpenCode 作为内建接入。更多 Provider 请通过向导新增自定义 ACP Server Endpoint；历史上真正配置过的 Claude / Gemini 会迁移为自定义条目，空白旧预设会自动清理。',
              'Codex and OpenCode stay here as built-in integrations. Add more providers through the custom ACP endpoint wizard; configured legacy Claude and Gemini entries are migrated into custom entries, while empty legacy presets are cleaned up automatically.',
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const ValueKey('web-external-acp-provider-add-button'),
              onPressed: () =>
                  showAddExternalAcpProviderWizardInternal(context, controller),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                appText('添加更多自定义配置', 'Add more custom configurations'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...controller.settingsDraft.externalAcpEndpoints.map(
            (profile) => Padding(
              key: ValueKey('web-external-acp-card-${profile.providerKey}'),
              padding: const EdgeInsets.only(bottom: 12),
              child: buildExternalAcpProviderCardInternal(
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

  Widget buildExternalAcpProviderCardInternal(
    BuildContext context,
    AppController controller,
    ExternalAcpEndpointProfile profile,
  ) {
    final provider = profile.toProvider();
    final labelController =
        externalAcpLabelControllersInternal[profile.providerKey]!;
    final endpointController =
        externalAcpEndpointControllersInternal[profile.providerKey]!;
    final message =
        externalAcpMessageByProviderInternal[profile.providerKey] ?? '';
    final testing = externalAcpTestingProvidersInternal.contains(
      profile.providerKey,
    );
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
              StatusChipInternal(
                label: configured
                    ? appText('已配置', 'Configured')
                    : appText('未配置', 'Empty'),
                tone: configured
                    ? StatusChipToneInternal.ready
                    : StatusChipToneInternal.idle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('web-external-acp-label-${profile.providerKey}'),
            controller: labelController,
            decoration: InputDecoration(
              labelText: appText('显示名称', 'Display name'),
            ),
            onChanged: (_) => setStateInternal(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('web-external-acp-endpoint-${profile.providerKey}'),
            controller: endpointController,
            decoration: InputDecoration(
              labelText: appText('ACP Server Endpoint', 'ACP Server Endpoint'),
            ),
            onChanged: (_) => setStateInternal(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            appText(
              '示例：ws://127.0.0.1:9001、wss://acp.example.com/rpc、http://127.0.0.1:8080、https://agent.example.com',
              'Examples: ws://127.0.0.1:9001, wss://acp.example.com/rpc, http://127.0.0.1:8080, https://agent.example.com',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton(
                key: ValueKey('web-external-acp-test-${profile.providerKey}'),
                onPressed: testing
                    ? null
                    : () =>
                          testExternalAcpEndpointInternal(controller, profile),
                child: Text(
                  testing
                      ? appText('测试中...', 'Testing...')
                      : appText('测试连接', 'Test Connection'),
                ),
              ),
              FilledButton(
                key: ValueKey('web-external-acp-save-${profile.providerKey}'),
                onPressed: () => saveExternalAcpEndpointInternal(
                  controller,
                  profile.providerKey,
                ),
                child: Text(appText('保存并生效', 'Save & apply')),
              ),
            ],
          ),
          if (message.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> handleTopLevelApplyInternal(AppController controller) async {
    stageExternalAcpDraftInternal(controller);
    await controller.applySettingsDraft();
  }

  void stageExternalAcpDraftInternal(AppController controller) {
    final nextProfiles = controller.settingsDraft.externalAcpEndpoints
        .map(
          (profile) => profile.copyWith(
            label:
                externalAcpLabelControllersInternal[profile.providerKey]
                    ?.text ??
                profile.label,
            endpoint:
                externalAcpEndpointControllersInternal[profile.providerKey]
                    ?.text ??
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

  Future<void> saveExternalAcpEndpointInternal(
    AppController controller,
    String providerKey,
  ) async {
    stageExternalAcpDraftInternal(controller);
    await controller.applySettingsDraft();
    if (!mounted) {
      return;
    }
    setStateInternal(() {
      externalAcpMessageByProviderInternal[providerKey] = appText(
        '配置已保存并生效。',
        'Configuration saved and applied.',
      );
    });
  }

  Future<void> testExternalAcpEndpointInternal(
    AppController controller,
    ExternalAcpEndpointProfile profile,
  ) async {
    final endpointText =
        externalAcpEndpointControllersInternal[profile.providerKey]?.text
            .trim() ??
        '';
    final endpoint = Uri.tryParse(endpointText);
    if (endpoint == null || endpoint.host.trim().isEmpty) {
      setStateInternal(() {
        externalAcpMessageByProviderInternal[profile.providerKey] = appText(
          '请输入有效的 ACP Server Endpoint。',
          'Enter a valid ACP server endpoint.',
        );
      });
      return;
    }
    setStateInternal(() {
      externalAcpTestingProvidersInternal.add(profile.providerKey);
      externalAcpMessageByProviderInternal.remove(profile.providerKey);
    });
    try {
      final capabilities = await controller.acpClientInternal.loadCapabilities(
        endpoint: endpoint,
      );
      if (!mounted) {
        return;
      }
      setStateInternal(() {
        externalAcpMessageByProviderInternal[profile.providerKey] = appText(
          capabilities.providers.isEmpty
              ? '连接成功。'
              : '连接成功，可用 Provider: ${capabilities.providers.map((item) => item.label).join(' / ')}',
          capabilities.providers.isEmpty
              ? 'Connection successful.'
              : 'Connection successful. Providers: ${capabilities.providers.map((item) => item.label).join(' / ')}',
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setStateInternal(() {
        externalAcpMessageByProviderInternal[profile.providerKey] = '$error';
      });
    } finally {
      if (mounted) {
        setStateInternal(() {
          externalAcpTestingProvidersInternal.remove(profile.providerKey);
        });
      }
    }
  }

  Future<void> showAddExternalAcpProviderWizardInternal(
    BuildContext context,
    AppController controller,
  ) async {
    final settings = controller.settingsDraft;
    final nameController = TextEditingController();
    final endpointController = TextEditingController();
    var attemptedSubmit = false;
    try {
      final profile = await showDialog<ExternalAcpEndpointProfile>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final name = nameController.text.trim();
              final endpoint = endpointController.text.trim();
              final endpointValid =
                  endpoint.isEmpty || isSupportedExternalAcpEndpoint(endpoint);
              final canSubmit =
                  name.isNotEmpty && endpoint.isNotEmpty && endpointValid;
              return AlertDialog(
                title: Text(
                  appText('添加自定义 ACP Endpoint', 'Add custom ACP endpoint'),
                ),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appText(
                          '通过向导新增更多外部 Agent Provider。先填写显示名称，再输入可访问的 ACP Server Endpoint。',
                          'Use this wizard to add more external agent providers. Start with a display name, then enter a reachable ACP server endpoint.',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        appText('步骤 1 · 显示名称', 'Step 1 · Display name'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey(
                          'web-external-acp-wizard-name-field',
                        ),
                        controller: nameController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: appText(
                            '例如：Claude Sonnet / Lab Agent',
                            'For example: Claude Sonnet / Lab Agent',
                          ),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        appText(
                          '步骤 2 · ACP Server Endpoint',
                          'Step 2 · ACP Server Endpoint',
                        ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey(
                          'web-external-acp-wizard-endpoint-field',
                        ),
                        controller: endpointController,
                        decoration: InputDecoration(
                          hintText: 'ws://127.0.0.1:9001',
                          errorText: attemptedSubmit && endpoint.isEmpty
                              ? appText(
                                  '请输入 ACP Server Endpoint。',
                                  'Enter an ACP server endpoint.',
                                )
                              : attemptedSubmit && !endpointValid
                              ? appText(
                                  '仅支持 ws / wss / http / https。',
                                  'Only ws / wss / http / https are supported.',
                                )
                              : null,
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        appText(
                          '支持协议：ws、wss、http、https。新增后会出现在下方列表，并和助手页的 provider 菜单保持一致。',
                          'Supported schemes: ws, wss, http, https. The new entry appears in the list below and stays aligned with the assistant provider menu.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(appText('取消', 'Cancel')),
                  ),
                  FilledButton(
                    key: const ValueKey(
                      'web-external-acp-wizard-confirm-button',
                    ),
                    onPressed: canSubmit
                        ? () {
                            Navigator.of(dialogContext).pop(
                              buildCustomExternalAcpEndpointProfile(
                                settings.externalAcpEndpoints,
                                label: name,
                                endpoint: endpoint,
                              ),
                            );
                          }
                        : () {
                            setDialogState(() {
                              attemptedSubmit = true;
                            });
                          },
                    child: Text(appText('添加', 'Add')),
                  ),
                ],
              );
            },
          );
        },
      );
      if (profile == null) {
        return;
      }
      await controller.saveSettingsDraft(
        settings.copyWith(
          externalAcpEndpoints: <ExternalAcpEndpointProfile>[
            ...settings.externalAcpEndpoints,
            profile,
          ],
        ),
      );
    } finally {
      nameController.dispose();
      endpointController.dispose();
    }
  }

  Widget buildGatewayCardInternal(
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
        '${hostController.text.trim()}:${parsePortInternal(portController.text, fallback: 443)}';
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
                        final profile = gatewayProfileDraftInternal(
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
                child: Text(appText('测试连接', 'Test Connection')),
              ),
              FilledButton(
                onPressed: controller.relayBusy
                    ? null
                    : () async {
                        try {
                          await controller.applyRelayConfiguration(
                            profileIndex: profileIndex,
                            host: hostController.text,
                            port: parsePortInternal(
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
                child: controller.relayBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(appText('保存并生效', 'Save & apply')),
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

  GatewayConnectionProfile gatewayProfileDraftInternal({
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
      port: parsePortInternal(portText, fallback: defaults.port),
      tls: mode == RuntimeConnectionMode.local ? false : tls,
      useSetupCode: false,
      setupCode: '',
    );
  }

  int parsePortInternal(String value, {required int fallback}) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) {
      return fallback;
    }
    return parsed;
  }

  List<Widget> buildAppearanceInternal(
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
                      child: Text(themeLabelInternal(mode)),
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

  List<Widget> buildAboutInternal(BuildContext context) {
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
