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
import 'web_settings_page_gateway.dart';
import 'web_settings_page_support.dart';

extension WebSettingsPageSectionsMixinInternal on WebSettingsPageStateInternal {
  Widget buildGlobalApplyBarInternal(
    BuildContext context,
    AppController controller,
  ) {
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
                          '当前存在未保存草稿。保存并生效：按当前配置立即更新。',
                          'There are unsaved drafts. Save & apply updates the current configuration immediately.',
                        )
                      : hasPendingApply
                      ? appText(
                          '当前存在待生效更改。保存并生效：立即按当前配置更新。',
                          'There are saved changes waiting to be applied. Save & apply updates the current configuration immediately.',
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
              FilledButton.tonal(
                key: const ValueKey('settings-global-apply-button'),
                onPressed:
                    (hasDraft ||
                        hasPendingApply ||
                        gatewaySubTabInternal ==
                            WebGatewaySettingsSubTabInternal.acp)
                    ? () => handleTopLevelApplyInternal(controller)
                    : null,
                child: Text(appText('保存并生效', 'Save & apply')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> buildGeneralInternal(
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
                      child: Text(targetLabelInternal(target)),
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

  List<Widget> buildGatewayInternal(
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
        value: switch (gatewaySubTabInternal) {
          WebGatewaySettingsSubTabInternal.gateway => 'OpenClaw Gateway',
          WebGatewaySettingsSubTabInternal.llm => appText(
            'LLM 接入点',
            'LLM Endpoints',
          ),
          WebGatewaySettingsSubTabInternal.acp => appText(
            'ACP 外部接入',
            'External ACP',
          ),
        },
        onChanged: (value) => setStateInternal(() {
          gatewaySubTabInternal = switch (value) {
            'OpenClaw Gateway' => WebGatewaySettingsSubTabInternal.gateway,
            _ when value == appText('LLM 接入点', 'LLM Endpoints') =>
              WebGatewaySettingsSubTabInternal.llm,
            _ => WebGatewaySettingsSubTabInternal.acp,
          };
        }),
      ),
      const SizedBox(height: 16),
      ...switch (gatewaySubTabInternal) {
        WebGatewaySettingsSubTabInternal.gateway =>
          buildGatewayOverviewInternal(context, controller),
        WebGatewaySettingsSubTabInternal.llm => buildLlmEndpointManagerInternal(
          context,
          controller,
          settings,
        ),
        WebGatewaySettingsSubTabInternal.acp => <Widget>[
          buildExternalAcpEndpointManagerInternal(context, controller),
        ],
      },
    ];
  }

  List<Widget> buildGatewayOverviewInternal(
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
                '这里维护 Local / Remote Gateway 与浏览器会话持久化配置。保存并生效：立即按当前配置更新。',
                'Maintain Local / Remote Gateway and browser session persistence here. Save & apply updates the active configuration immediately.',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      buildGatewayCardInternal(
        context,
        controller: controller,
        title: appText('Local Gateway', 'Local Gateway'),
        executionTarget: AssistantExecutionTarget.local,
        profileIndex: kGatewayLocalProfileIndex,
        hostController: localHostControllerInternal,
        portController: localPortControllerInternal,
        tokenController: localTokenControllerInternal,
        passwordController: localPasswordControllerInternal,
        tokenMask: controller.storedRelayTokenMaskForProfile(
          kGatewayLocalProfileIndex,
        ),
        passwordMask: controller.storedRelayPasswordMaskForProfile(
          kGatewayLocalProfileIndex,
        ),
        tls: false,
        onTlsChanged: null,
        message: localGatewayMessageInternal,
        onMessageChanged: (value) {
          setStateInternal(() => localGatewayMessageInternal = value);
        },
      ),
      const SizedBox(height: 12),
      buildGatewayCardInternal(
        context,
        controller: controller,
        title: appText('Remote Gateway', 'Remote Gateway'),
        executionTarget: AssistantExecutionTarget.remote,
        profileIndex: kGatewayRemoteProfileIndex,
        hostController: remoteHostControllerInternal,
        portController: remotePortControllerInternal,
        tokenController: remoteTokenControllerInternal,
        passwordController: remotePasswordControllerInternal,
        tokenMask: controller.storedRelayTokenMaskForProfile(
          kGatewayRemoteProfileIndex,
        ),
        passwordMask: controller.storedRelayPasswordMaskForProfile(
          kGatewayRemoteProfileIndex,
        ),
        tls: remoteTlsInternal,
        onTlsChanged: (value) {
          setStateInternal(() => remoteTlsInternal = value);
        },
        message: remoteGatewayMessageInternal,
        onMessageChanged: (value) {
          setStateInternal(() => remoteGatewayMessageInternal = value);
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
              initialValue: sessionPersistenceModeInternal,
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
                setStateInternal(() {
                  sessionPersistenceModeInternal = value;
                });
              },
              decoration: InputDecoration(
                labelText: appText('保存位置', 'Persistence target'),
              ),
            ),
            if (sessionPersistenceModeInternal ==
                WebSessionPersistenceMode.remote) ...[
              const SizedBox(height: 10),
              TextField(
                controller: sessionRemoteBaseUrlControllerInternal,
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
                controller: sessionApiTokenControllerInternal,
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
                FilledButton.tonal(
                  onPressed: () async {
                    await controller.saveWebSessionPersistenceConfiguration(
                      mode: sessionPersistenceModeInternal,
                      remoteBaseUrl:
                          sessionRemoteBaseUrlControllerInternal.text,
                      apiToken: sessionApiTokenControllerInternal.text,
                    );
                    if (!mounted) {
                      return;
                    }
                    setStateInternal(() {
                      sessionPersistenceMessageInternal = appText(
                        '会话存储配置已保存并生效。',
                        'Session persistence settings are saved and applied.',
                      );
                    });
                  },
                  child: Text(appText('保存并生效', 'Save & apply')),
                ),
              ],
            ),
            if (sessionPersistenceMessageInternal.trim().isNotEmpty ||
                controller.sessionPersistenceStatusMessage
                    .trim()
                    .isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                (sessionPersistenceMessageInternal.trim().isNotEmpty
                        ? sessionPersistenceMessageInternal
                        : controller.sessionPersistenceStatusMessage)
                    .trim(),
              ),
            ],
          ],
        ),
      ),
    ];
  }
}
