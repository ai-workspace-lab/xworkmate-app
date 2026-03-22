import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../runtime/runtime_bootstrap.dart';
import '../runtime/runtime_models.dart';
import 'section_tabs.dart';
import '../theme/app_palette.dart';
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

  bool get _isAiGatewayOnlyMode =>
      _mode == 'manual' &&
      _connectionMode == RuntimeConnectionMode.unconfigured;

  bool get _manualGatewayFieldsEnabled => !_isAiGatewayOnlyMode;

  bool get _credentialFieldsEnabled =>
      _mode == 'setup' || _manualGatewayFieldsEnabled;

  String _connectionModeLabel(RuntimeConnectionMode mode) {
    return switch (mode) {
      RuntimeConnectionMode.unconfigured => appText(
        '仅 AI Gateway',
        'AI Gateway Only',
      ),
      RuntimeConnectionMode.local => appText(
        '本地 OpenClaw Gateway',
        'Local OpenClaw Gateway',
      ),
      RuntimeConnectionMode.remote => appText(
        '远程 OpenClaw Gateway',
        'Remote OpenClaw Gateway',
      ),
    };
  }

  @override
  void initState() {
    super.initState();
    final profile = widget.controller.settings.gateway;
    final executionTarget = widget.controller.currentAssistantExecutionTarget;
    _setupCodeController = TextEditingController(text: profile.setupCode);
    _hostController = TextEditingController(text: profile.host);
    _portController = TextEditingController(text: '${profile.port}');
    _tls = profile.tls;
    _connectionMode = switch (executionTarget) {
      AssistantExecutionTarget.aiGatewayOnly =>
        RuntimeConnectionMode.unconfigured,
      AssistantExecutionTarget.local => RuntimeConnectionMode.local,
      AssistantExecutionTarget.remote => RuntimeConnectionMode.remote,
    };
    _mode = executionTarget == AssistantExecutionTarget.aiGatewayOnly
        ? 'manual'
        : (profile.useSetupCode ? 'setup' : 'manual');
    _loadBootstrapPrefill();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uiFeatures = widget.controller.featuresFor(
      resolveUiFeaturePlatformFromContext(context),
    );
    _connectionMode = _sanitizeConnectionMode(_connectionMode, uiFeatures);
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
    final uiFeatures = widget.controller.featuresFor(
      resolveUiFeaturePlatformFromContext(context),
    );
    final availableConnectionModes = _availableConnectionModes(uiFeatures);
    final theme = Theme.of(context);
    final palette = context.palette;
    final horizontalPadding = widget.compact ? 20.0 : 24.0;
    final verticalPadding = widget.compact ? 18.0 : 22.0;
    final dialogTitleStyle = theme.textTheme.headlineSmall?.copyWith(
      fontSize: AppTypography.titleSize,
      height: AppTypography.titleHeight,
      letterSpacing: -0.18,
      fontWeight: AppTypography.titleWeight,
    );
    final supportingCopyStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 12,
      height: 16 / 12,
      color: palette.textSecondary,
    );
    final fieldLabelStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      height: 16 / 12,
      color: palette.textMuted,
    );
    final floatingFieldLabelStyle = fieldLabelStyle?.copyWith(
      color: palette.textSecondary,
      fontWeight: FontWeight.w500,
    );
    final storedGatewayTokenMask = widget.controller.storedGatewayTokenMask;
    final hasStoredGatewayToken =
        storedGatewayTokenMask != null && storedGatewayTokenMask.isNotEmpty;
    final typedGatewayToken = _tokenController.text.trim();
    final willUseStoredGatewayToken =
        typedGatewayToken.isEmpty && hasStoredGatewayToken;
    final showSharedTokenStatusCard =
        _credentialFieldsEnabled &&
        (willUseStoredGatewayToken || typedGatewayToken.isNotEmpty);
    final body = Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          labelStyle: fieldLabelStyle,
          floatingLabelStyle: floatingFieldLabelStyle,
          hintStyle: fieldLabelStyle,
        ),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          verticalPadding,
          horizontalPadding,
          verticalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              appText('Gateway 访问', 'Gateway Access'),
              style: dialogTitleStyle,
            ),
            const SizedBox(height: AppSpacing.section),
            Text(
              appText(
                '通过配置码或手动 Host / TLS 将 XWorkmate 连接到 OpenClaw Gateway。远程模式保持显式 TLS 直连；也可切换到仅 AI Gateway 模式，仅使用模型路由而不建立 Gateway 会话。',
                'Connect XWorkmate to an OpenClaw gateway with setup code or manual host / TLS. Remote mode keeps TLS explicit for direct access. You can also switch to AI Gateway Only mode to use model routing without opening a gateway session.',
              ),
              style: supportingCopyStyle,
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
            const SizedBox(height: 14),
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
              _FormSectionLabel(label: appText('连接目标', 'Connection Target')),
              const SizedBox(height: 8),
              DropdownButtonFormField<RuntimeConnectionMode>(
                initialValue: _connectionMode,
                decoration: InputDecoration(
                  labelText: appText('工作模式', 'Work Mode'),
                ),
                items: availableConnectionModes
                    .map(
                      (mode) => DropdownMenuItem<RuntimeConnectionMode>(
                        value: mode,
                        child: Text(_connectionModeLabel(mode)),
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
              if (_isAiGatewayOnlyMode) ...[
                const SizedBox(height: 10),
                Text(
                  appText(
                    '当前模式仅通过 AI Gateway 处理任务，不会建立 OpenClaw Gateway 会话。',
                    'This mode routes tasks through AI Gateway only and does not establish an OpenClaw Gateway session.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    height: 16 / 12,
                    color: palette.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _hostController,
                enabled: _manualGatewayFieldsEnabled,
                decoration: InputDecoration(labelText: appText('主机', 'Host')),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _portController,
                      enabled: _manualGatewayFieldsEnabled,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: appText('端口', 'Port'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _TlsToggleCard(
                      value: _tls,
                      label: appText('TLS', 'TLS'),
                      enabled:
                          _manualGatewayFieldsEnabled &&
                          _connectionMode != RuntimeConnectionMode.local,
                      onChanged:
                          !_manualGatewayFieldsEnabled ||
                              _connectionMode == RuntimeConnectionMode.local
                          ? null
                          : (value) => setState(() => _tls = value),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            _FormSectionLabel(label: appText('凭证', 'Credentials')),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenController,
              enabled: _credentialFieldsEnabled,
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
                  onPressed: !_credentialFieldsEnabled
                      ? null
                      : () => setState(
                          () => _obscureSharedToken = !_obscureSharedToken,
                        ),
                  icon: Icon(
                    _obscureSharedToken
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (showSharedTokenStatusCard) ...[
              const SizedBox(height: 10),
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
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              enabled: _credentialFieldsEnabled,
              obscureText: true,
              decoration: InputDecoration(
                labelText: appText('密码', 'Password'),
                hintText: appText('可选：共享密码', 'Optional shared password'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.controller.connection.status ==
                    RuntimeConnectionStatus.connected) ...[
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
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: const Icon(Icons.wifi_tethering_rounded),
                    label: Text(
                      _submitting
                          ? (_isAiGatewayOnlyMode
                                ? appText('应用中…', 'Applying…')
                                : appText('连接中…', 'Connecting…'))
                          : (_isAiGatewayOnlyMode
                                ? appText('应用模式', 'Apply Mode')
                                : appText('连接', 'Connect')),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
        if (_connectionMode != RuntimeConnectionMode.unconfigured) {
          _connectionMode = preferred.mode;
        }
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
      } else if (_connectionMode == RuntimeConnectionMode.unconfigured) {
        await widget.controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.aiGatewayOnly,
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

  List<RuntimeConnectionMode> _availableConnectionModes(
    UiFeatureAccess uiFeatures,
  ) {
    return <RuntimeConnectionMode>[
      if (uiFeatures.supportsDirectAi) RuntimeConnectionMode.unconfigured,
      if (uiFeatures.supportsLocalGateway) RuntimeConnectionMode.local,
      if (uiFeatures.supportsRelayGateway) RuntimeConnectionMode.remote,
    ];
  }

  RuntimeConnectionMode _sanitizeConnectionMode(
    RuntimeConnectionMode mode,
    UiFeatureAccess uiFeatures,
  ) {
    final available = _availableConnectionModes(uiFeatures);
    if (available.contains(mode)) {
      return mode;
    }
    if (available.isNotEmpty) {
      return available.first;
    }
    return RuntimeConnectionMode.unconfigured;
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
    final palette = context.palette;
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary.withValues(alpha: 0.92),
        border: Border.all(color: palette.strokeSoft),
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
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                height: 16 / 12,
                color: palette.textSecondary,
              ),
            ),
          ),
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
    final palette = context.palette;
    final connection = controller.connection;
    final tone = switch (connection.status) {
      RuntimeConnectionStatus.connected => palette.accentMuted,
      RuntimeConnectionStatus.error => theme.colorScheme.errorContainer,
      RuntimeConnectionStatus.connecting => palette.surfaceSecondary,
      RuntimeConnectionStatus.offline => palette.surfaceSecondary,
    };
    final statusColor = switch (connection.status) {
      RuntimeConnectionStatus.connected => palette.success,
      RuntimeConnectionStatus.error => palette.danger,
      RuntimeConnectionStatus.connecting => palette.accent,
      RuntimeConnectionStatus.offline => palette.textSecondary,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: tone,
        border: Border.all(color: palette.strokeSoft),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                connection.status.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 14,
                  height: 16 / 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            connection.remoteAddress ?? 'No active gateway target',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              height: 18 / 13,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          _FormSectionLabel(label: appText('认证诊断', 'Auth Diagnostics')),
          const SizedBox(height: 6),
          Text(
            connection.connectAuthSummary,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              height: 16 / 12,
              color: palette.textSecondary,
            ),
          ),
          if (connection.pairingRequired) ...[
            const SizedBox(height: AppSpacing.section),
            Text(
              appText(
                '当前设备需要先完成配对审批。请在已授权设备上批准该请求后重试。',
                'This device must be approved first. Approve the pairing request from an authorized device and try again.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                height: 16 / 12,
                color: palette.textSecondary,
              ),
            ),
            if ((connection.deviceId ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.compact),
              Text(
                appText(
                  '当前设备 ID: ${connection.deviceId}',
                  'Current device ID: ${connection.deviceId}',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  height: 16 / 12,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ] else if (connection.gatewayTokenMissing) ...[
            const SizedBox(height: AppSpacing.section),
            Text(
              appText(
                '首次连接请提供共享 Token；配对完成后可继续使用本机 device token。',
                'Provide a shared token for the first connection; after pairing, this device can continue with its device token.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                height: 16 / 12,
                color: palette.textSecondary,
              ),
            ),
          ],
          if ((connection.lastError ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.section),
            Text(
              connection.lastError!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                height: 16 / 12,
                color: palette.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FormSectionLabel extends StatelessWidget {
  const _FormSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: palette.textMuted,
        letterSpacing: 0.32,
      ),
    );
  }
}

class _TlsToggleCard extends StatelessWidget {
  const _TlsToggleCard({
    required this.value,
    required this.label,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.inputHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.surfacePrimary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: enabled ? palette.textSecondary : palette.textMuted,
              ),
            ),
          ),
          Switch.adaptive(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}
