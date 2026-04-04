// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';
import 'settings_page_core.dart';
import 'settings_page_support.dart';
import 'settings_page_widgets.dart';

extension SettingsPageGatewayAcpMixinInternal on SettingsPageStateInternal {
  Widget buildExternalAcpEndpointManagerInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    syncExternalAcpDraftControllersInternal(settings);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            key: const ValueKey('external-acp-provider-add-button'),
            onPressed: () => showAddExternalAcpProviderWizardInternal(
              context,
              controller,
              settings,
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(appText('添加更多自定义配置', 'Add more custom configurations')),
          ),
        ),
        const SizedBox(height: 16),
        ...settings.externalAcpEndpoints.map(
          (profile) => Padding(
            key: ValueKey('external-acp-card-${profile.providerKey}'),
            padding: const EdgeInsets.only(bottom: 12),
            child: buildExternalAcpProviderCardInternal(
              context,
              controller,
              settings,
              profile,
            ),
          ),
        ),
      ],
    );
  }

  Widget buildExternalAcpProviderCardInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    ExternalAcpEndpointProfile profile,
  ) {
    final provider = profile.toProvider();
    final labelController =
        externalAcpLabelControllersInternal[profile.providerKey]!;
    final endpointController =
        externalAcpEndpointControllersInternal[profile.providerKey]!;
    final authController =
        externalAcpAuthControllersInternal[profile.providerKey]!;
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
                  onPressed: () => saveSettingsInternal(
                    controller,
                    settings.copyWith(
                      externalAcpEndpoints: settings.externalAcpEndpoints
                          .where(
                            (item) => item.providerKey != profile.providerKey,
                          )
                          .toList(growable: false),
                    ),
                  ),
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
            key: ValueKey('external-acp-label-${profile.providerKey}'),
            controller: labelController,
            decoration: InputDecoration(
              labelText: appText('显示名称', 'Display name'),
            ),
            onChanged: (_) => setStateInternal(() {}),
          ),
          TextField(
            key: ValueKey('external-acp-endpoint-${profile.providerKey}'),
            controller: endpointController,
            decoration: InputDecoration(
              labelText: appText('ACP Server Endpoint', 'ACP Server Endpoint'),
            ),
            onChanged: (_) => setStateInternal(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('external-acp-auth-${profile.providerKey}'),
            controller: authController,
            decoration: InputDecoration(
              labelText: appText('AUTH（可为空）', 'AUTH (optional)'),
            ),
            onChanged: (_) => setStateInternal(() {}),
          ),
          Text(
            appText(
              '示例：ws://127.0.0.1:9001、wss://acp.example.com/rpc、http://127.0.0.1:8080、https://agent.example.com。AUTH 填 secret ref 名；为空时不发送 Authorization。',
              'Examples: ws://127.0.0.1:9001, wss://acp.example.com/rpc, http://127.0.0.1:8080, https://agent.example.com. AUTH stores a secret ref name; leave it empty to omit Authorization.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton(
                key: ValueKey('external-acp-test-${profile.providerKey}'),
                onPressed: testing
                    ? null
                    : () => testExternalAcpEndpointInternal(
                        controller,
                        profile.providerKey,
                      ),
                child: Text(
                  testing
                      ? appText('测试中...', 'Testing...')
                      : appText('测试连接', 'Test Connection'),
                ),
              ),
              FilledButton(
                key: ValueKey('external-acp-apply-${profile.providerKey}'),
                onPressed: () => saveExternalAcpEndpointInternal(
                  controller,
                  settings,
                  provider,
                  profile,
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

  Future<void> saveExternalAcpEndpointInternal(
    AppController controller,
    SettingsSnapshot settings,
    SingleAgentProvider provider,
    ExternalAcpEndpointProfile profile,
  ) async {
    final label =
        externalAcpLabelControllersInternal[profile.providerKey]?.text ??
        profile.label;
    final endpoint =
        externalAcpEndpointControllersInternal[profile.providerKey]?.text ??
        profile.endpoint;
    final authRef =
        externalAcpAuthControllersInternal[profile.providerKey]?.text ??
        profile.authRef;
    final next = settings.copyWithExternalAcpEndpointForProvider(
      provider,
      profile.copyWith(label: label, endpoint: endpoint, authRef: authRef),
    );
    await saveSettingsInternal(controller, next);
    await handleTopLevelApplyInternal(controller);
    if (!mounted) {
      return;
    }
    setStateInternal(() {
      externalAcpMessageByProviderInternal[profile.providerKey] = appText(
        '配置已保存并生效。',
        'Configuration saved and applied.',
      );
    });
  }

  Future<void> testExternalAcpEndpointInternal(
    AppController controller,
    String providerKey,
  ) async {
    final endpointText =
        externalAcpEndpointControllersInternal[providerKey]?.text.trim() ?? '';
    final authRef =
        externalAcpAuthControllersInternal[providerKey]?.text.trim() ?? '';
    final endpoint = Uri.tryParse(endpointText);
    if (endpoint == null || endpoint.host.trim().isEmpty) {
      setStateInternal(() {
        externalAcpMessageByProviderInternal[providerKey] = appText(
          '请输入有效的 ACP Server Endpoint。',
          'Enter a valid ACP server endpoint.',
        );
      });
      return;
    }
    setStateInternal(() {
      externalAcpTestingProvidersInternal.add(providerKey);
      externalAcpMessageByProviderInternal.remove(providerKey);
    });
    try {
      final authorization = authRef.isEmpty
          ? ''
          : await controller.settingsController.resolveSecretValueInternal(
              refName: authRef,
            );
      final capabilities = await controller.gatewayAcpClientInternal
          .loadCapabilities(
            forceRefresh: true,
            endpointOverride: endpoint,
            authorizationOverride: authorization,
          );
      if (!mounted) {
        return;
      }
      setStateInternal(() {
        externalAcpMessageByProviderInternal[providerKey] = appText(
          capabilities.providers.isEmpty
              ? '连接成功。'
              : '连接成功，可用 Provider: ${capabilities.providers.map((item) => item.label).join(' / ')}',
          capabilities.providers.isEmpty
              ? 'Connection succeeded.'
              : 'Connection succeeded. Providers: ${capabilities.providers.map((item) => item.label).join(' / ')}',
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setStateInternal(() {
        externalAcpMessageByProviderInternal[providerKey] = '$error';
      });
    } finally {
      if (mounted) {
        setStateInternal(() {
          externalAcpTestingProvidersInternal.remove(providerKey);
        });
      }
    }
  }

  Future<void> showAddExternalAcpProviderWizardInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) async {
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
                        key: const ValueKey('external-acp-wizard-name-field'),
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
                          'external-acp-wizard-endpoint-field',
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
                    key: const ValueKey('external-acp-wizard-confirm-button'),
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
      await saveSettingsInternal(
        controller,
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
}
