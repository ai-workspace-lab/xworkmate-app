// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/ui_feature_manifest.dart';
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
        : appText('用户登录状态', 'User Login State');
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
                  appText('用户登录状态', 'User Login State'),
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  appText(
                    '先完成账户登录，再同步或校验默认连接配置。',
                    'Sign in first, then sync or verify the default connection configuration.',
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
                '这里仅描述认证状态本身：登录、MFA、同步状态与当前账户身份。默认连接来源和高级覆盖在下面分别配置。',
                'This card describes authentication only: sign-in, MFA, sync state, and current account identity. The default connection source and advanced overrides are configured below.',
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
                    appText('登录状态摘要', 'Login state summary'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${appText('服务地址', 'Service URL')}: ${settings.accountBaseUrl.trim().isEmpty ? appText('未填写', 'Not set') : settings.accountBaseUrl}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${appText('账户标识', 'Account')}: ${settings.accountUsername.trim().isEmpty ? appText('未填写', 'Not set') : settings.accountUsername}',
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
    SettingsSnapshot settings, {
    required UiFeatureAccess uiFeatures,
  }) {
    syncAcpBridgeServerModeDraftControllersInternal(settings);
    final modeConfig = settings.acpBridgeServerModeConfig;
    final supportsSelfHosted = uiFeatures.supportsGatewaySelfHostedBase;
    final effectiveUsesSelfHosted =
        supportsSelfHosted && modeConfig.usesSelfHostedBase;
    final effectiveUsesCloudSync = !effectiveUsesSelfHosted;
    final accountController = controller.settingsController;
    final accountSyncState = accountController.accountSyncState;
    final accountSignedIn = accountController.accountSignedIn;
    final accountBusy = accountController.accountBusy;
    final cloudSync = modeConfig.cloudSynced;
    final remoteSummary = cloudSync.remoteServerSummary;
    final currentSource = effectiveUsesSelfHosted
        ? appText('自建服务', 'Self-hosted')
        : appText('svc.plus 提供', 'svc.plus provided');
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
            appText('基础连接配置', 'Base Connection Configuration'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            supportsSelfHosted
                ? appText(
                    '这里维护默认连接来源与默认凭据。默认来源可以是 svc.plus 提供的托管配置，也可以是自建 ACP Bridge Server。高级自定义模式只在这层默认配置上做覆盖。',
                    'This section maintains the default connection source and default credentials. The default source can come from svc.plus managed configuration or from a self-hosted ACP Bridge Server. Advanced custom mode only overrides this base layer.',
                  )
                : appText(
                    '这里维护默认连接来源与默认凭据。当前默认 UI 仅展示 svc.plus 提供的托管配置入口；实验性的自建与高级覆盖能力保留在代码模块中。',
                    'This section maintains the default connection source and default credentials. The default UI currently exposes only the svc.plus managed entry point, while experimental self-hosted and advanced override capabilities remain in the codebase.',
                  ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                key: const ValueKey('acp-bridge-mode-cloud'),
                label: Text(appText('svc.plus 提供', 'svc.plus provided')),
                selected: effectiveUsesCloudSync,
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
              if (supportsSelfHosted)
                ChoiceChip(
                  key: const ValueKey('acp-bridge-mode-self-hosted'),
                  label: Text(appText('自建服务', 'Self-hosted')),
                  selected: effectiveUsesSelfHosted,
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
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              StatusChipInternal(
                label: '${appText('默认连接来源', 'Default Source')}: $currentSource',
                tone: StatusChipToneInternal.ready,
              ),
              StatusChipInternal(
                label: '${appText('同步状态', 'Sync')}: $syncStatus',
                tone: accountSignedIn
                    ? StatusChipToneInternal.ready
                    : StatusChipToneInternal.idle,
              ),
              if (uiFeatures.supportsGatewayAdvancedCustomMode)
                StatusChipInternal(
                  label:
                      '${appText('高级覆盖', 'Advanced Override')}: ${modeConfig.mode == AcpBridgeServerMode.advancedCustom ? appText('已启用', 'Enabled') : appText('未启用', 'Disabled')}',
                  tone: modeConfig.mode == AcpBridgeServerMode.advancedCustom
                      ? StatusChipToneInternal.ready
                      : StatusChipToneInternal.idle,
                ),
            ],
          ),
          const SizedBox(height: 16),
          ...switch (effectiveUsesCloudSync) {
            true => <Widget>[
              Text(
                accountSignedIn
                    ? appText(
                        '当前默认来源为 svc.plus 提供的托管配置。你可以直接同步远端默认配置。',
                        'The current default source is managed by svc.plus. You can sync the remote defaults directly.',
                      )
                    : appText(
                        '当前默认来源为 svc.plus 提供的托管配置，但你还没有登录。建议先完成登录，再同步默认配置。',
                        'The current default source is managed by svc.plus, but no account is signed in yet. Sign in first, then sync the default configuration.',
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
              if (uiFeatures.supportsGatewayAdvancedCustomMode)
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
            false => <Widget>[
              Text(
                appText(
                  '当前默认来源为自建服务。下面的 ACP Bridge Server URL、用户和密码会作为默认连接配置使用；如果启用了高级自定义模式，其它集成项只会覆盖这份默认配置。',
                  'The current default source is self-hosted. The ACP Bridge Server URL, username, and password below act as the default connection configuration. If advanced custom mode is enabled, the other integrations only override this base layer.',
                ),
              ),
            ],
          },
          if (supportsSelfHosted) ...[
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
            '这里仅管理 Bridge 侧 catalog 的同步定义与认证信息。助手里的 Provider 列表完全以 Bridge 返回的 capabilities 为准，本页配置不会直接决定下拉里显示什么。',
            'This section only manages sync definitions and credentials for the Bridge-side catalog. The provider list in Assistant comes entirely from Bridge capabilities; editing settings here does not directly populate the picker.',
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
            label: Text(
              appText('添加 Bridge 同步配置', 'Add Bridge sync definition'),
            ),
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
