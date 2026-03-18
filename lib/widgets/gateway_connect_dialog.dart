import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../i18n/app_language.dart';
import '../runtime/runtime_bootstrap.dart';
import '../runtime/runtime_models.dart';
import 'section_tabs.dart';
import '../theme/app_theme.dart';

class GatewayConnectDialog extends StatefulWidget {
  const GatewayConnectDialog({
    super.key,
    required this.controller,
    this.compact = false,
    this.onDone,
  });

  final AppController controller;
  final bool compact;
  final VoidCallback? onDone;

  @override
  State<GatewayConnectDialog> createState() => _GatewayConnectDialogState();
}

class _GatewayConnectDialogState extends State<GatewayConnectDialog> {
  late final TextEditingController _setupCodeController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String _mode = 'setup';
  String _bootstrapToken = '';
  bool _tls = true;
  bool _obscureSharedToken = true;
  RuntimeConnectionMode _connectionMode = RuntimeConnectionMode.remote;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.controller.settings.gateway;
    _setupCodeController = TextEditingController(text: profile.setupCode);
    _hostController = TextEditingController(text: profile.host);
    _portController = TextEditingController(text: '${profile.port}');
    _tls = profile.tls;
    _connectionMode = profile.mode;
    _mode = profile.useSetupCode ? 'setup' : 'manual';
    _loadBootstrapPrefill();
  }

  @override
  void dispose() {
    _setupCodeController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storedGatewayTokenMask = widget.controller.storedGatewayTokenMask;
    final hasStoredGatewayToken =
        storedGatewayTokenMask != null && storedGatewayTokenMask.isNotEmpty;
    final typedGatewayToken = _tokenController.text.trim();
    final willUseStoredGatewayToken =
        typedGatewayToken.isEmpty && hasStoredGatewayToken;
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            appText('Gateway 访问', 'Gateway Access'),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.section),
          Text(
            appText(
              '通过配置码或手动 Host / TLS 将 XWorkmate 连接到 OpenClaw Gateway。',
              'Connect XWorkmate to an OpenClaw gateway with setup code or manual host / TLS.',
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.section),
          SectionTabs(
            items: [appText('配置码', 'Setup Code'), appText('手动配置', 'Manual')],
            value: _mode == 'setup'
                ? appText('配置码', 'Setup Code')
                : appText('手动配置', 'Manual'),
            size: SectionTabsSize.small,
            onChanged: (value) => setState(
              () => _mode = value == appText('配置码', 'Setup Code')
                  ? 'setup'
                  : 'manual',
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          _StatusBanner(controller: widget.controller),
          const SizedBox(height: AppSpacing.section),
          if (_mode == 'setup') ...[
            TextField(
              controller: _setupCodeController,
              minLines: 4,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: appText('配置码', 'Setup Code'),
                hintText: appText(
                  '粘贴 Gateway 配置码或 JSON 负载',
                  'Paste gateway setup code or JSON payload',
                ),
              ),
            ),
          ] else ...[
            DropdownButtonFormField<RuntimeConnectionMode>(
              initialValue: _connectionMode,
              decoration: InputDecoration(
                labelText: appText('连接模式', 'Connection Mode'),
              ),
              items: RuntimeConnectionMode.values
                  .map(
                    (mode) => DropdownMenuItem<RuntimeConnectionMode>(
                      value: mode,
                      child: Text(mode.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _connectionMode = value;
                  if (value == RuntimeConnectionMode.local) {
                    _hostController.text = '127.0.0.1';
                    _portController.text = '18789';
                    _tls = false;
                  }
                });
              },
            ),
            const SizedBox(height: AppSpacing.section),
            TextField(
              controller: _hostController,
              decoration: InputDecoration(labelText: appText('主机', 'Host')),
            ),
            const SizedBox(height: AppSpacing.section),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: appText('端口', 'Port'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.section),
                Expanded(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _tls,
                    title: Text(appText('TLS', 'TLS')),
                    onChanged: _connectionMode == RuntimeConnectionMode.local
                        ? null
                        : (value) => setState(() => _tls = value),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.section),
          TextField(
            controller: _tokenController,
            obscureText: _obscureSharedToken,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: appText('共享 Token', 'Shared Token'),
              hintText: appText(
                '可选：覆盖默认 Gateway Token',
                'Optional override for gateway token',
              ),
              suffixIcon: IconButton(
                tooltip: _obscureSharedToken
                    ? appText('显示 Token', 'Show token')
                    : appText('隐藏 Token', 'Hide token'),
                onPressed: () =>
                    setState(() => _obscureSharedToken = !_obscureSharedToken),
                icon: Icon(
                  _obscureSharedToken
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (willUseStoredGatewayToken || typedGatewayToken.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.section),
            _SharedTokenStatusCard(
              hasStoredGatewayToken: hasStoredGatewayToken,
              storedGatewayTokenMask: storedGatewayTokenMask,
              willUseStoredGatewayToken: willUseStoredGatewayToken,
              overridingStoredToken:
                  hasStoredGatewayToken && typedGatewayToken.isNotEmpty,
              onClearStoredToken: hasStoredGatewayToken
                  ? () async {
                      await widget.controller.clearStoredGatewayToken();
                      if (mounted) {
                        setState(() {});
                      }
                    }
                  : null,
            ),
          ],
          const SizedBox(height: AppSpacing.section),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: appText('密码', 'Password'),
              hintText: appText('可选：共享密码', 'Optional shared password'),
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          Wrap(
            spacing: AppSpacing.section,
            runSpacing: AppSpacing.section,
            alignment: WrapAlignment.end,
            children: [
              if (widget.controller.connection.status ==
                  RuntimeConnectionStatus.connected)
                OutlinedButton.icon(
                  onPressed: _submitting
                      ? null
                      : () async {
                          setState(() => _submitting = true);
                          await widget.controller.disconnectGateway();
                          if (mounted) {
                            setState(() => _submitting = false);
                          }
                        },
                  icon: const Icon(Icons.link_off_rounded),
                  label: Text(appText('断开连接', 'Disconnect')),
                ),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: const Icon(Icons.wifi_tethering_rounded),
                label: Text(
                  _submitting
                      ? appText('连接中…', 'Connecting…')
                      : appText('连接', 'Connect'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (widget.compact) {
      return body;
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.page),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: body,
      ),
    );
  }

  Future<void> _loadBootstrapPrefill() async {
    final bootstrap = await RuntimeBootstrapConfig.load(
      workspacePathHint: widget.controller.settings.workspacePath,
      cliPathHint: widget.controller.settings.cliPath,
    );
    final preferred = bootstrap.preferredGatewayFor(_connectionMode);
    if (!mounted || preferred == null) {
      return;
    }
    final profile = widget.controller.settings.gateway;
    final defaults = GatewayConnectionProfile.defaults();
    final shouldPrefillEndpoint =
        profile.setupCode.trim().isEmpty &&
        profile.host.trim() == defaults.host &&
        profile.port == defaults.port;
    setState(() {
      if (shouldPrefillEndpoint) {
        _connectionMode = preferred.mode;
        _hostController.text = preferred.host;
        _portController.text = '${preferred.port}';
        _tls = preferred.tls;
      }
      if (_bootstrapToken.isEmpty && preferred.token.isNotEmpty) {
        _bootstrapToken = preferred.token;
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final typedToken = _tokenController.text.trim();
      final resolvedToken = typedToken.isNotEmpty
          ? typedToken
          : widget.controller.hasStoredGatewayToken
          ? ''
          : _bootstrapToken;
      if (_mode == 'setup') {
        await widget.controller.connectWithSetupCode(
          setupCode: _setupCodeController.text,
          token: resolvedToken,
          password: _passwordController.text,
        );
      } else {
        await widget.controller.connectManual(
          host: _hostController.text,
          port: int.tryParse(_portController.text.trim()) ?? 0,
          tls: _tls,
          mode: _connectionMode,
          token: resolvedToken,
          password: _passwordController.text,
        );
      }
      widget.onDone?.call();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class _SharedTokenStatusCard extends StatelessWidget {
  const _SharedTokenStatusCard({
    required this.hasStoredGatewayToken,
    required this.storedGatewayTokenMask,
    required this.willUseStoredGatewayToken,
    required this.overridingStoredToken,
    this.onClearStoredToken,
  });

  final bool hasStoredGatewayToken;
  final String? storedGatewayTokenMask;
  final bool willUseStoredGatewayToken;
  final bool overridingStoredToken;
  final Future<void> Function()? onClearStoredToken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = overridingStoredToken
        ? appText(
            '本次输入会覆盖已安全保存的 shared token。',
            'This entry will overwrite the stored shared token.',
          )
        : willUseStoredGatewayToken
        ? appText(
            '已安全保存 shared token（$storedGatewayTokenMask）。留空时会直接使用它连接。',
            'A shared token is already stored securely ($storedGatewayTokenMask). Leave the field empty to connect with it.',
          )
        : appText(
            '首次连接需要 shared token；点击连接后会写入安全存储。',
            'The first connection needs a shared token; after connect it will be saved into secure storage.',
          );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.section),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasStoredGatewayToken
                ? Icons.lock_rounded
                : Icons.inventory_2_rounded,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.compact),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
          if (onClearStoredToken != null)
            TextButton(
              onPressed: () => onClearStoredToken!.call(),
              child: Text(appText('清除', 'Clear')),
            ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connection = controller.connection;
    final tone = switch (connection.status) {
      RuntimeConnectionStatus.connected => theme.colorScheme.primaryContainer,
      RuntimeConnectionStatus.error => theme.colorScheme.errorContainer,
      RuntimeConnectionStatus.connecting =>
        theme.colorScheme.secondaryContainer,
      RuntimeConnectionStatus.offline =>
        theme.colorScheme.surfaceContainerHighest,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.section),
      decoration: BoxDecoration(
        color: tone,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(connection.status.label, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.compact),
          Text(
            connection.remoteAddress ?? 'No active gateway target',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.section),
          Text(
            appText('认证诊断', 'Auth Diagnostics'),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.compact),
          Text(connection.connectAuthSummary, style: theme.textTheme.bodySmall),
          if (connection.pairingRequired) ...[
            const SizedBox(height: AppSpacing.section),
            Text(
              appText(
                '当前设备需要先完成配对审批。请在已授权设备上批准该请求后重试。',
                'This device must be approved first. Approve the pairing request from an authorized device and try again.',
              ),
              style: theme.textTheme.bodySmall,
            ),
            if ((connection.deviceId ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.compact),
              Text(
                appText(
                  '当前设备 ID: ${connection.deviceId}',
                  'Current device ID: ${connection.deviceId}',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ] else if (connection.gatewayTokenMissing) ...[
            const SizedBox(height: AppSpacing.section),
            Text(
              appText(
                '首次连接请提供共享 Token；配对完成后可继续使用本机 device token。',
                'Provide a shared token for the first connection; after pairing, this device can continue with its device token.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if ((connection.lastError ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.section),
            Text(connection.lastError!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
