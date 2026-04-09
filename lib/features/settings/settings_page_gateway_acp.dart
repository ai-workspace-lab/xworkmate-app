// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../runtime/gateway_acp_client.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import '../../models/app_models.dart';
import '../../widgets/surface_card.dart';
import 'settings_page_core.dart';
import 'settings_page_support.dart';
import 'settings_page_widgets.dart';

String externalAcpEndpointExamplesText() {
  return appText(
    '推荐：托管服务优先填写 https://agent.example.com 这类基地址；应用会自动派生 /acp 与 /acp/rpc。仅在直连原始 ACP WebSocket 监听器时使用 ws://127.0.0.1:9001 或 wss://agent.example.com/acp。AUTH 填 secret ref 名；为空时不发送 Authorization。',
    'Recommended: for hosted services, enter a base URL such as https://agent.example.com. The app derives /acp and /acp/rpc automatically. Use ws://127.0.0.1:9001 or wss://agent.example.com/acp only when connecting to a raw ACP WebSocket listener directly. AUTH stores a secret ref name; leave it empty to omit Authorization.',
  );
}

String describeExternalAcpTestFailure(Object error, {Uri? endpoint}) {
  Map<String, dynamic> detailMap = const <String, dynamic>{};
  if (error is GatewayAcpException) {
    final details = error.details;
    detailMap = details is Map<String, dynamic>
        ? details
        : details is Map
        ? details.cast<String, dynamic>()
        : const <String, dynamic>{};
    if (error.code == 'ACP_HTTP_STREAM_CLOSED') {
      final requestUrl = detailMap['requestUrl']?.toString().trim() ?? '';
      final statusCode = detailMap['statusCode']?.toString().trim() ?? 'n/a';
      final contentType = detailMap['contentType']?.toString().trim();
      final bodyRead = detailMap['bodyRead'] == true ? 'yes' : 'no';
      return appText(
        '连接不稳定：服务端在响应体接收完成前提前关闭了连接。'
            '${requestUrl.isEmpty ? '' : '\nURL: $requestUrl'}'
            '\nHTTP: $statusCode'
            '\ncontent-type: ${contentType == null || contentType.isEmpty ? 'n/a' : contentType}'
            '\nbody received: $bodyRead'
            '\n应用会对这类瞬时错误自动重试一次；如果仍失败，请检查上游服务或反向代理是否提前断流。',
        'Connection was interrupted before the response body finished arriving.'
            '${requestUrl.isEmpty ? '' : '\nURL: $requestUrl'}'
            '\nHTTP: $statusCode'
            '\ncontent-type: ${contentType == null || contentType.isEmpty ? 'n/a' : contentType}'
            '\nbody received: $bodyRead'
            '\nThe app retries this transient error once automatically. If it still fails, inspect the upstream service or reverse proxy for early connection termination.',
      );
    }
  }

  final raw = error.toString().trim();
  final lowered = raw.toLowerCase();
  final scheme = endpoint?.scheme.trim().toLowerCase() ?? '';

  if (raw.contains('ACP_HTTP_ENDPOINT_MISSING')) {
    return appText(
      '连接失败：当前地址是 WebSocket 地址，无法回退到 HTTP ACP RPC。托管服务通常应填写 https://host[:port] 基地址；只有在直连原始 ACP WebSocket 监听器时才使用 ws:// 或 wss://。',
      'Connection failed: the current address is a WebSocket URL, so HTTP ACP RPC fallback is unavailable. Hosted services should usually use a base URL like https://host[:port]. Use ws:// or wss:// only for a direct raw ACP WebSocket listener.',
    );
  }

  if (raw.contains('Missing JSON document')) {
    return appText(
      scheme == 'http' || scheme == 'https'
          ? '连接失败：已访问 /acp/rpc，但服务端返回的不是 ACP JSON 响应。请确认该地址提供了 HTTP ACP bridge，而不是只暴露网页或仅支持 WebSocket。'
          : '连接失败：服务端返回的不是 ACP JSON 响应。请确认该地址是有效的 ACP 入口。',
      scheme == 'http' || scheme == 'https'
          ? 'Connection failed: /acp/rpc responded, but it did not return ACP JSON. Confirm that this address exposes an HTTP ACP bridge instead of only a webpage or a websocket-only endpoint.'
          : 'Connection failed: the endpoint did not return ACP JSON. Confirm that this is a valid ACP endpoint.',
    );
  }

  if (lowered.contains('403')) {
    return appText(
      '连接被拒绝（403）。请检查该服务是否允许当前客户端来源访问，并确认 AUTH 引用或服务端鉴权配置是否正确。',
      'Connection was rejected (403). Check whether the service allows this client origin and whether the AUTH ref or server-side auth configuration is correct.',
    );
  }

  if (lowered.contains('handshakeexception') ||
      lowered.contains('tlsv1_alert_internal_error') ||
      lowered.contains('ssl alert number 80') ||
      lowered.contains('tls handshake failed')) {
    return appText(
      'TLS 握手失败。当前更像是服务端 HTTPS/TLS 配置异常，而不是 ACP JSON-RPC 本身报错。请先用 curl 或 openssl 直接探测该域名；如果基地址带子路径，应用会自动派生到该子路径下的 /acp 与 /acp/rpc。',
      'TLS handshake failed. This looks more like a server-side HTTPS/TLS configuration issue than an ACP JSON-RPC failure. Probe the host directly with curl or openssl first; if the base URL includes a subpath, the app derives /acp and /acp/rpc under that subpath automatically.',
    );
  }

  return _appendExternalAcpFailureDiagnostics(raw, detailMap);
}

String _appendExternalAcpFailureDiagnostics(
  String message,
  Map<String, dynamic> details,
) {
  final requestUrl = details['requestUrl']?.toString().trim() ?? '';
  final statusCode = details['statusCode']?.toString().trim() ?? '';
  final contentType = details['contentType']?.toString().trim() ?? '';
  final hasBodyRead = details.containsKey('bodyRead');
  final bodyRead = details['bodyRead'] == true ? 'yes' : 'no';
  final buffer = StringBuffer(message);
  if (requestUrl.isNotEmpty) {
    buffer.write('\nURL: $requestUrl');
  }
  if (statusCode.isNotEmpty) {
    buffer.write('\nHTTP: $statusCode');
  }
  if (contentType.isNotEmpty) {
    buffer.write('\ncontent-type: $contentType');
  }
  if (hasBodyRead) {
    buffer.write('\nbody received: $bodyRead');
  }
  return buffer.toString();
}

String describeExternalAcpTestSuccess(GatewayAcpCapabilities capabilities) {
  final diagnostics = capabilities.diagnostics;
  final transport =
      diagnostics['transport']?.toString().trim().toLowerCase() ?? '';
  final statusCode = diagnostics['statusCode'];
  final providerNames = capabilities.providers
      .map((item) => item.providerId)
      .toList(growable: false);
  final providerLine = providerNames.isEmpty
      ? appText('providers: none declared', 'providers: none declared')
      : 'providers: ${providerNames.join('/')}';
  if (transport.startsWith('http')) {
    final resolvedStatus = statusCode?.toString().trim();
    return appText(
      'HTTP ${resolvedStatus == null || resolvedStatus.isEmpty ? 200 : resolvedStatus}\nACP capabilities ok\n$providerLine',
      'HTTP ${resolvedStatus == null || resolvedStatus.isEmpty ? 200 : resolvedStatus}\nACP capabilities ok\n$providerLine',
    );
  }
  return appText(
    'WebSocket connected\nACP capabilities ok\n$providerLine',
    'WebSocket connected\nACP capabilities ok\n$providerLine',
  );
}

bool shouldRetryExternalAcpTestFailure(Object error) {
  return error is GatewayAcpException && error.code == 'ACP_HTTP_STREAM_CLOSED';
}

extension SettingsPageGatewayAcpMixinInternal on SettingsPageStateInternal {
  void syncAccountDraftControllersInternal(SettingsSnapshot settings) {
    if (accountBaseUrlControllerInternal.text ==
            accountBaseUrlSyncedValueInternal &&
        settings.accountBaseUrl != accountBaseUrlSyncedValueInternal) {
      accountBaseUrlControllerInternal.text = settings.accountBaseUrl;
    }
    if (accountUsernameControllerInternal.text ==
            accountUsernameSyncedValueInternal &&
        settings.accountUsername != accountUsernameSyncedValueInternal) {
      accountUsernameControllerInternal.text = settings.accountUsername;
    }
    accountBaseUrlSyncedValueInternal = settings.accountBaseUrl;
    accountUsernameSyncedValueInternal = settings.accountUsername;
  }

  Future<void> saveAccountProfileInternal(SettingsSnapshot settings) async {
    final nextSettings = settings.copyWith(
      accountBaseUrl: accountBaseUrlControllerInternal.text.trim(),
      accountUsername: accountUsernameControllerInternal.text.trim(),
    );
    await saveSettingsInternal(widget.controller, nextSettings);
    accountBaseUrlSyncedValueInternal = nextSettings.accountBaseUrl;
    accountUsernameSyncedValueInternal = nextSettings.accountUsername;
  }

  Future<void> loginAccountInternal(SettingsSnapshot settings) async {
    await saveAccountProfileInternal(settings);
    try {
      await widget.controller.settingsController.loginAccount(
        baseUrl: accountBaseUrlControllerInternal.text.trim(),
        identifier: accountUsernameControllerInternal.text.trim(),
        password: accountPasswordControllerInternal.text,
      );
    } finally {
      accountPasswordControllerInternal.clear();
    }
  }

  Future<void> verifyAccountMfaInternal() async {
    try {
      await widget.controller.settingsController.verifyAccountMfa(
        baseUrl: accountBaseUrlControllerInternal.text.trim(),
        code: accountMfaCodeControllerInternal.text.trim(),
      );
    } finally {
      accountMfaCodeControllerInternal.clear();
    }
  }

  Future<void> syncAccountSettingsInternal(SettingsSnapshot settings) async {
    await saveAccountProfileInternal(settings);
    await widget.controller.settingsController.syncAccountSettings(
      baseUrl: accountBaseUrlControllerInternal.text.trim(),
    );
  }

  Future<void> logoutAccountInternal() async {
    await widget.controller.settingsController.logoutAccount();
    accountPasswordControllerInternal.clear();
    accountMfaCodeControllerInternal.clear();
  }

  Future<void> cancelAccountMfaInternal() async {
    await widget.controller.settingsController.cancelAccountMfaChallenge();
    accountPasswordControllerInternal.clear();
    accountMfaCodeControllerInternal.clear();
  }

  Widget buildOnlineAccountCardInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    syncAccountDraftControllersInternal(settings);
    final accountController = controller.settingsController;
    final accountSession = accountController.accountSession;
    final accountSyncState = accountController.accountSyncState;
    final accountBusy = accountController.accountBusy;
    final accountSignedIn = accountController.accountSignedIn;
    final accountMfaRequired = accountController.accountMfaRequired;
    final signedInLabel = accountSession?.email.trim().isNotEmpty == true
        ? accountSession!.email.trim()
        : accountSession?.name.trim().isNotEmpty == true
        ? accountSession!.name.trim()
        : appText('在线账户', 'Online Account');
    final sessionStatusText = accountSignedIn
        ? appText('已登录：$signedInLabel', 'Signed in: $signedInLabel')
        : accountMfaRequired
        ? appText('等待双重验证', 'Waiting for MFA verification')
        : appText('未登录', 'Signed out');
    final syncStatusText = accountSyncState == null
        ? appText('idle · 尚未同步远程配置', 'idle · Remote config not synced yet')
        : '${accountSyncState.syncState} · ${accountSyncState.syncMessage}';

    Widget buildSignedOutLoginCard() {
      final theme = Theme.of(context);
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_outlined,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  appText('在线账户', 'Online Account'),
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  appText(
                    '请先登录 ACP Bridge Server',
                    'Please sign in to ACP Bridge Server',
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withValues(
                      alpha: 0.8,
                    ),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                TextFormField(
                  key: const ValueKey('account-base-url-field'),
                  controller: accountBaseUrlControllerInternal,
                  decoration: InputDecoration(
                    labelText: appText('服务地址', 'Service URL'),
                    prefixIcon: const Icon(Icons.dns_outlined),
                  ),
                  onFieldSubmitted: (_) => saveAccountProfileInternal(settings),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('account-username-field'),
                  controller: accountUsernameControllerInternal,
                  decoration: InputDecoration(
                    labelText: appText('邮箱或账号', 'Email or Username'),
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                  onFieldSubmitted: (_) => saveAccountProfileInternal(settings),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('account-password-field'),
                  controller: accountPasswordControllerInternal,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: appText('密码', 'Password'),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                  ),
                  onFieldSubmitted: (_) => loginAccountInternal(settings),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('account-login-button'),
                    onPressed: accountBusy
                        ? null
                        : () => loginAccountInternal(settings),
                    child: Text(appText('登录', 'Sign In')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildSignedInProfileCard() {
      return SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              accountSignedIn
                  ? signedInLabel
                  : settings.accountUsername.trim().isEmpty
                  ? appText('本地操作员', 'Local Operator')
                  : settings.accountUsername,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              appText(
                '这里继续只负责在线账户身份、MFA、工作区与同步摘要。ACP Bridge Server 的本地连接与高级配置在下面统一收口。',
                'This card focuses on online account identity, MFA, workspace, and sync summary. Local ACP Bridge Server connection and advanced config are unified below.',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              sessionStatusText,
              key: const ValueKey('account-session-status'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              syncStatusText,
              key: const ValueKey('account-sync-status'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appText('在线账户同步摘要', 'Online account sync summary'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${appText('服务地址', 'Service URL')}: ${settings.accountBaseUrl.trim().isEmpty ? appText('未填写', 'Not set') : settings.accountBaseUrl}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${appText('在线账户', 'Online Account')}: ${settings.accountUsername.trim().isEmpty ? appText('未填写', 'Not set') : settings.accountUsername}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${appText('最近同步', 'Last Sync')}: ${accountSyncState == null || settings.acpBridgeServerModeConfig.cloudSynced.lastSyncAt <= 0 ? appText('尚未同步', 'Not synced yet') : DateTime.fromMillisecondsSinceEpoch(settings.acpBridgeServerModeConfig.cloudSynced.lastSyncAt).toLocal().toIso8601String()}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (accountMfaRequired) ...[
              TextFormField(
                key: const ValueKey('account-mfa-code-field'),
                controller: accountMfaCodeControllerInternal,
                decoration: InputDecoration(
                  labelText: appText('双重验证代码', 'MFA Code'),
                ),
                onFieldSubmitted: (_) => verifyAccountMfaInternal(),
              ),
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (accountMfaRequired)
                  FilledButton.tonal(
                    key: const ValueKey('account-verify-mfa-button'),
                    onPressed: accountBusy ? null : verifyAccountMfaInternal,
                    child: Text(appText('验证并同步', 'Verify & Sync')),
                  ),
                if (accountMfaRequired)
                  FilledButton.tonal(
                    key: const ValueKey('account-edit-button'),
                    onPressed: accountBusy ? null : cancelAccountMfaInternal,
                    child: Text(appText('返回编辑', 'Back to Edit')),
                  ),
                if (accountSignedIn)
                  FilledButton.tonal(
                    key: const ValueKey('account-sync-button'),
                    onPressed: accountBusy
                        ? null
                        : () => syncAccountSettingsInternal(settings),
                    child: Text(appText('重新同步', 'Sync Again')),
                  ),
                if (accountSignedIn)
                  FilledButton.tonal(
                    key: const ValueKey('account-logout-button'),
                    onPressed: accountBusy ? null : logoutAccountInternal,
                    child: Text(appText('退出登录', 'Log Out')),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return accountSignedIn || accountMfaRequired
        ? buildSignedInProfileCard()
        : buildSignedOutLoginCard();
  }

  Widget buildAcpBridgeServerModeCardInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    syncAcpBridgeServerModeDraftControllersInternal(settings);
    final modeConfig = settings.acpBridgeServerModeConfig;
    final accountController = controller.settingsController;
    final accountSyncState = accountController.accountSyncState;
    final accountSignedIn = accountController.accountSignedIn;
    final accountBusy = accountController.accountBusy;
    final cloudSync = modeConfig.cloudSynced;
    final remoteSummary = cloudSync.remoteServerSummary;
    final currentSource = switch (modeConfig.sourceTag) {
      'cloudSynced' => appText('在线账户', 'Online Account'),
      'selfHosted' => appText('本地账户', 'Local Account'),
      _ => appText('高级模式', 'Advanced Mode'),
    };
    final syncStatus = accountSyncState?.syncState.trim().isNotEmpty == true
        ? accountSyncState!.syncState
        : appText('未同步', 'Not synced');
    final lastSyncLabel = cloudSync.lastSyncAt <= 0
        ? appText('尚未同步', 'Not synced yet')
        : DateTime.fromMillisecondsSinceEpoch(
            cloudSync.lastSyncAt,
          ).toLocal().toIso8601String();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appText(
              'ACP Bridge Server 连接模式',
              'ACP Bridge Server Connection Mode',
            ),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            appText(
              '在线账户负责云端同步，本地账户负责连接 ACP Bridge Server，高级模式是在本地账户基础上再叠加 advanced config 覆盖层。App 只负责配置、会话、安全存储与连接编排，不承载服务端逻辑。',
              'Online account handles cloud sync, local account connects to ACP Bridge Server, and advanced mode layers advanced config on top of the local account. The app stays a pure client for configuration, session handling, secure storage, and connection orchestration.',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                key: const ValueKey('acp-bridge-mode-cloud'),
                label: Text(appText('在线账户', 'Online Account')),
                selected: modeConfig.mode == AcpBridgeServerMode.cloudSynced,
                onSelected: (_) => saveSettingsInternal(
                  controller,
                  settings.copyWith(
                    accountLocalMode: false,
                    acpBridgeServerModeConfig: modeConfig.copyWith(
                      mode: AcpBridgeServerMode.cloudSynced,
                    ),
                  ),
                ),
              ),
              ChoiceChip(
                key: const ValueKey('acp-bridge-mode-self-hosted'),
                label: Text(appText('本地账户', 'Local Account')),
                selected: modeConfig.mode == AcpBridgeServerMode.selfHosted,
                onSelected: (_) => saveSettingsInternal(
                  controller,
                  settings.copyWith(
                    accountLocalMode: true,
                    acpBridgeServerModeConfig: modeConfig.copyWith(
                      mode: AcpBridgeServerMode.selfHosted,
                    ),
                  ),
                ),
              ),
              ChoiceChip(
                key: const ValueKey('acp-bridge-mode-advanced'),
                label: Text(appText('高级模式', 'Advanced Mode')),
                selected: modeConfig.mode == AcpBridgeServerMode.advancedCustom,
                onSelected: (_) => saveSettingsInternal(
                  controller,
                  settings.captureAcpBridgeServerAdvancedOverrides().copyWith(
                    acpBridgeServerModeConfig: settings
                        .captureAcpBridgeServerAdvancedOverrides()
                        .acpBridgeServerModeConfig
                        .copyWith(mode: AcpBridgeServerMode.advancedCustom),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              StatusChipInternal(
                label: '${appText('当前模式', 'Mode')}: $currentSource',
                tone: StatusChipToneInternal.ready,
              ),
              StatusChipInternal(
                label: '${appText('同步状态', 'Sync')}: $syncStatus',
                tone: accountSignedIn
                    ? StatusChipToneInternal.ready
                    : StatusChipToneInternal.idle,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...switch (modeConfig.mode) {
            AcpBridgeServerMode.cloudSynced => <Widget>[
              Text(
                accountSignedIn
                    ? appText(
                        '已登录在线账户，可直接同步云端 ACP Bridge Server 默认配置。',
                        'Signed in to the online account. You can sync the cloud ACP Bridge Server defaults directly.',
                      )
                    : appText(
                        '当前未登录在线账户。建议先登录，再从云端同步默认配置。',
                        'No online account is signed in. Sign in first, then sync the default configuration from the cloud.',
                      ),
              ),
              Text(
                '${appText('远端摘要', 'Remote Summary')}: ${remoteSummary.endpoint.trim().isEmpty ? appText('待同步', 'Pending sync') : remoteSummary.endpoint}',
              ),
              const SizedBox(height: 6),
              Text(
                '${appText('最近同步', 'Last Sync')}: $lastSyncLabel',
                key: const ValueKey('acp-bridge-cloud-last-sync'),
              ),
              const SizedBox(height: 6),
              Text(
                '${appText('高级覆盖', 'Advanced Override')}: ${remoteSummary.hasAdvancedOverrides ? appText('存在', 'Present') : appText('无', 'None')}',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.tonal(
                    key: const ValueKey('acp-bridge-cloud-sync'),
                    onPressed: accountBusy || !accountSignedIn
                        ? null
                        : () => syncAccountSettingsInternal(settings),
                    child: Text(appText('重新同步', 'Sync Again')),
                  ),
                  FilledButton.tonal(
                    key: const ValueKey('acp-bridge-cloud-disconnect'),
                    onPressed: accountBusy || !accountSignedIn
                        ? null
                        : logoutAccountInternal,
                    child: Text(appText('断开', 'Disconnect')),
                  ),
                ],
              ),
            ],
            AcpBridgeServerMode.selfHosted => <Widget>[],
            AcpBridgeServerMode.advancedCustom => <Widget>[
              Text(
                appText(
                  '高级模式 = 本地账户 + advanced config。下面先保留本地 ACP Bridge Server 连接，再把 OpenClaw Gateway / Vault Server / LLM Endpoint / 外部 ACP Server endpoint / SKILLS 目录 当作覆盖层。未覆盖的值继续继承当前基础模式。',
                  'Advanced mode = local account + advanced config. Keep the local ACP Bridge Server connection below, then treat the OpenClaw Gateway / Vault Server / LLM Endpoint / external ACP server endpoint / SKILLS directory as overrides. Fields you do not override keep inheriting from the current base mode.',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                key: const ValueKey('acp-bridge-advanced-reset'),
                onPressed: () => resetAcpBridgeServerAdvancedOverridesInternal(
                  controller,
                  settings,
                ),
                child: Text(appText('清空高级覆盖', 'Clear Advanced Overrides')),
              ),
            ],
          },
          const SizedBox(height: 16),
          buildAcpBridgeServerSelfHostedPanelInternal(
            context,
            controller,
            settings,
            targetMode: modeConfig.mode == AcpBridgeServerMode.advancedCustom
                ? AcpBridgeServerMode.advancedCustom
                : AcpBridgeServerMode.selfHosted,
          ),
        ],
      ),
    );
  }

  Widget buildAcpBridgeServerSelfHostedPanelInternal(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings, {
    AcpBridgeServerMode targetMode = AcpBridgeServerMode.selfHosted,
  }) {
    final selfHosted = settings.acpBridgeServerModeConfig.selfHosted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appText('连接 ACP Bridge Server', 'Connect to ACP Bridge Server'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          appText(
            '填写本地或私有部署的 ACP Bridge Server 地址、用户名和密码，然后测试连接并保存到安全存储。',
            'Enter the URL, username, and password for your local or private ACP Bridge Server, then test the connection and save it into secure storage.',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('acp-bridge-self-hosted-url'),
          controller: acpBridgeServerUrlControllerInternal,
          decoration: InputDecoration(
            labelText: appText(
              'ACP Bridge Server URL',
              'ACP Bridge Server URL',
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('acp-bridge-self-hosted-username'),
          controller: acpBridgeServerUsernameControllerInternal,
          decoration: InputDecoration(labelText: appText('用户', 'Username')),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('acp-bridge-self-hosted-password'),
          controller: acpBridgeServerPasswordControllerInternal,
          obscureText: true,
          decoration: InputDecoration(
            labelText: appText('密码', 'Password'),
            helperText: appText(
              '密码只进入平台 secure storage，不写入普通 settings。',
              'The password is stored only in platform secure storage and never in plain settings.',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('${appText('密码引用', 'Password Ref')}: ${selfHosted.passwordRef}'),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton(
              key: const ValueKey('acp-bridge-self-hosted-test'),
              onPressed: acpBridgeServerSelfHostedTestingInternal
                  ? null
                  : () => testAcpBridgeServerSelfHostedInternal(controller),
              child: Text(
                acpBridgeServerSelfHostedTestingInternal
                    ? appText('测试中...', 'Testing...')
                    : appText('测试连接', 'Test Connection'),
              ),
            ),
            FilledButton.tonal(
              key: const ValueKey('acp-bridge-self-hosted-save'),
              onPressed: () => saveAcpBridgeServerSelfHostedInternal(
                controller,
                settings,
                targetMode: targetMode,
              ),
              child: Text(appText('保存', 'Save')),
            ),
            FilledButton(
              key: const ValueKey('acp-bridge-self-hosted-connect'),
              onPressed: () => connectAcpBridgeServerSelfHostedInternal(
                controller,
                settings,
                targetMode: targetMode,
              ),
              child: Text(appText('连接', 'Connect')),
            ),
          ],
        ),
        if (acpBridgeServerSelfHostedMessageInternal.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(acpBridgeServerSelfHostedMessageInternal),
        ],
      ],
    );
  }

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

  Future<void> saveAcpBridgeServerSelfHostedInternal(
    AppController controller,
    SettingsSnapshot settings, {
    AcpBridgeServerMode targetMode = AcpBridgeServerMode.selfHosted,
  }) async {
    final modeConfig = settings.acpBridgeServerModeConfig;
    final nextSelfHosted = modeConfig.selfHosted.copyWith(
      serverUrl: acpBridgeServerUrlControllerInternal.text,
      username: acpBridgeServerUsernameControllerInternal.text,
    );
    final password = acpBridgeServerPasswordControllerInternal.text.trim();
    if (password.isNotEmpty) {
      await controller.settingsController.saveSecretValueByRef(
        nextSelfHosted.passwordRef,
        password,
        provider: 'ACP Bridge Server',
        module: 'Settings',
      );
    }
    final nextSettings = settings
        .captureAcpBridgeServerAdvancedOverrides()
        .copyWith(
          accountLocalMode: true,
          acpBridgeServerModeConfig: settings
              .captureAcpBridgeServerAdvancedOverrides()
              .acpBridgeServerModeConfig
              .copyWith(mode: targetMode, selfHosted: nextSelfHosted),
        );
    await saveSettingsInternal(controller, nextSettings);
    if (!mounted) {
      return;
    }
    acpBridgeServerPasswordControllerInternal.clear();
    setStateInternal(() {
      acpBridgeServerSelfHostedMessageInternal = appText(
        'ACP Bridge Server 配置已保存，密码已进入 secure storage。',
        'The ACP Bridge Server configuration was saved and the password is now in secure storage.',
      );
    });
  }

  Future<void> connectAcpBridgeServerSelfHostedInternal(
    AppController controller,
    SettingsSnapshot settings, {
    AcpBridgeServerMode targetMode = AcpBridgeServerMode.selfHosted,
  }) async {
    await saveAcpBridgeServerSelfHostedInternal(
      controller,
      settings,
      targetMode: targetMode,
    );
    if (!mounted) {
      return;
    }
    await testAcpBridgeServerSelfHostedInternal(controller);
  }

  Future<void> testAcpBridgeServerSelfHostedInternal(
    AppController controller,
  ) async {
    final endpointText = acpBridgeServerUrlControllerInternal.text.trim();
    final username = acpBridgeServerUsernameControllerInternal.text.trim();
    if (endpointText.isEmpty || username.isEmpty) {
      setStateInternal(() {
        acpBridgeServerSelfHostedMessageInternal = appText(
          '请先填写 URL 和用户。',
          'Enter the URL and username first.',
        );
      });
      return;
    }
    final endpoint = Uri.tryParse(endpointText);
    if (endpoint == null || endpoint.host.trim().isEmpty) {
      setStateInternal(() {
        acpBridgeServerSelfHostedMessageInternal = appText(
          '请输入有效的 ACP Bridge Server URL。',
          'Enter a valid ACP Bridge Server URL.',
        );
      });
      return;
    }
    final password =
        acpBridgeServerPasswordControllerInternal.text.trim().isNotEmpty
        ? acpBridgeServerPasswordControllerInternal.text.trim()
        : await controller.settingsController.loadSecretValueByRef(
            controller
                .settings
                .acpBridgeServerModeConfig
                .selfHosted
                .passwordRef,
          );
    final authorization = password.isEmpty
        ? ''
        : 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    setStateInternal(() {
      acpBridgeServerSelfHostedTestingInternal = true;
      acpBridgeServerSelfHostedMessageInternal = '';
    });
    try {
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
        acpBridgeServerSelfHostedMessageInternal =
            describeExternalAcpTestSuccess(capabilities);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setStateInternal(() {
        acpBridgeServerSelfHostedMessageInternal =
            describeExternalAcpTestFailure(error, endpoint: endpoint);
      });
    } finally {
      if (mounted) {
        setStateInternal(() {
          acpBridgeServerSelfHostedTestingInternal = false;
        });
      }
    }
  }

  Future<void> resetAcpBridgeServerAdvancedOverridesInternal(
    AppController controller,
    SettingsSnapshot settings,
  ) async {
    var next = settings.copyWith(
      gatewayProfiles: SettingsSnapshot.defaults().gatewayProfiles,
      vault: VaultConfig.defaults(),
      aiGateway: AiGatewayProfile.defaults(),
      externalAcpEndpoints: SettingsSnapshot.defaults().externalAcpEndpoints,
      authorizedSkillDirectories:
          SettingsSnapshot.defaults().authorizedSkillDirectories,
      acpBridgeServerModeConfig: settings.acpBridgeServerModeConfig.copyWith(
        mode: settings.acpBridgeServerModeConfig.usesSelfHostedBase
            ? AcpBridgeServerMode.selfHosted
            : AcpBridgeServerMode.cloudSynced,
      ),
    );
    await saveSettingsInternal(controller, next);
    if (controller.settingsController.accountSignedIn &&
        next.acpBridgeServerModeConfig.usesCloudSyncBase) {
      await controller.settingsController.syncAccountSettings(
        baseUrl: next.accountBaseUrl,
      );
    }
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
              hintText: appText(
                'https://agent.example.com',
                'https://agent.example.com',
              ),
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
            externalAcpEndpointExamplesText(),
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
                key: ValueKey('external-acp-save-${profile.providerKey}'),
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
      GatewayAcpCapabilities capabilities;
      try {
        capabilities = await controller.gatewayAcpClientInternal
            .loadCapabilities(
              forceRefresh: true,
              endpointOverride: endpoint,
              authorizationOverride: authorization,
            );
      } catch (error) {
        if (!shouldRetryExternalAcpTestFailure(error)) {
          rethrow;
        }
        capabilities = await controller.gatewayAcpClientInternal
            .loadCapabilities(
              forceRefresh: true,
              endpointOverride: endpoint,
              authorizationOverride: authorization,
            );
      }
      if (!mounted) {
        return;
      }
      setStateInternal(() {
        externalAcpMessageByProviderInternal[providerKey] =
            describeExternalAcpTestSuccess(capabilities);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setStateInternal(() {
        externalAcpMessageByProviderInternal[providerKey] =
            describeExternalAcpTestFailure(error, endpoint: endpoint);
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
                          hintText: 'https://agent.example.com',
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
                          '支持协议：ws、wss、http、https。托管服务推荐填写 https://host[:port] 基地址；只有在直连原始 ACP WebSocket 监听器时才使用 ws / wss。',
                          'Supported schemes: ws, wss, http, https. For hosted services, prefer a base URL like https://host[:port]. Use ws / wss only when connecting to a raw ACP WebSocket listener directly.',
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
