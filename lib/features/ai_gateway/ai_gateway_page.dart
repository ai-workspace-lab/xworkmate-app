import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/platform_environment.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';

class AiGatewayPage extends StatefulWidget {
  const AiGatewayPage({
    super.key,
    required this.controller,
    required this.onOpenDetail,
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  State<AiGatewayPage> createState() => _AiGatewayPageState();
}

class _AiGatewayPageState extends State<AiGatewayPage> {
  AiGatewayTab _tab = AiGatewayTab.models;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    final metrics = [
      MetricSummary(
        label: appText('网关状态', 'Gateway'),
        value: controller.connection.status.label,
        caption:
            controller.connection.remoteAddress ??
            appText('未连接', 'Disconnected'),
        icon: Icons.wifi_tethering_rounded,
        status: _connectionStatus(controller.connection.status),
      ),
      MetricSummary(
        label: appText('活跃模型', 'Active Models'),
        value: '${controller.models.length}',
        caption: controller.models.isNotEmpty
            ? controller.models.first.name
            : appText('无', 'None'),
        icon: Icons.psychology_rounded,
      ),
      MetricSummary(
        label: appText('代理', 'Agents'),
        value: '${controller.agents.length}',
        caption: controller.activeAgentName,
        icon: Icons.hub_rounded,
      ),
    ];

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                breadcrumbs: [
                  AppBreadcrumbItem(
                    label: appText('主页', 'Home'),
                    icon: Icons.home_rounded,
                    onTap: controller.navigateHome,
                  ),
                  const AppBreadcrumbItem(label: 'AI Gateway'),
                  AppBreadcrumbItem(label: _tab.label),
                ],
                title: 'AI Gateway',
                subtitle: appText(
                  'AI 代理与模型网关配置管理中心。',
                  'AI proxy and model gateway configuration center.',
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: metrics.map((m) => MetricCard(metric: m)).toList(),
              ),
              const SizedBox(height: 24),
              SectionTabs(
                items: AiGatewayTab.values.map((t) => t.label).toList(),
                value: _tab.label,
                onChanged: (label) => setState(
                  () => _tab = AiGatewayTab.values.firstWhere(
                    (t) => t.label == label,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildTabContent(context, _tab, controller),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabContent(
    BuildContext context,
    AiGatewayTab tab,
    AppController controller,
  ) {
    final palette = context.palette;

    switch (tab) {
      case AiGatewayTab.models:
        return SurfaceCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.psychology_rounded,
                      color: palette.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      appText('模型列表', 'Model List'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(appText('添加模型', 'Add Model')),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (controller.models.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        appText('暂无配置的模型', 'No models configured'),
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ),
                  )
                else
                  ...controller.models.map(
                    (model) => _ModelCard(model: model, onTap: () {}),
                  ),
              ],
            ),
          ),
        );

      case AiGatewayTab.agents:
        return SurfaceCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Codex Bridge Toggle Card
                Row(
                  children: [
                    Icon(Icons.hub_rounded, color: palette.accent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      appText('代理列表', 'Agent List'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(appText('添加代理', 'Add Agent')),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (controller.agents.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        appText('暂无配置的代理', 'No agents configured'),
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ),
                  )
                else
                  ...controller.agents.map(
                    (agent) => _AgentCard(agent: agent, onTap: () {}),
                  ),
              ],
            ),
          ),
        );

      case AiGatewayTab.endpoints:
        return SurfaceCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.device_hub_rounded,
                      color: palette.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      appText('端点配置', 'Endpoint Configuration'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _EndpointCard(
                  name: 'OpenAI',
                  endpoint: 'https://api.openai.com/v1',
                  status: 'Connected',
                  onTap: () {},
                ),
                const SizedBox(height: 12),
                _EndpointCard(
                  name: 'Azure OpenAI',
                  endpoint: 'https://*.openai.azure.com',
                  status: 'Disconnected',
                  onTap: () {},
                ),
              ],
            ),
          ),
        );
      case AiGatewayTab.tools:
        return SurfaceCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.build_rounded, color: palette.accent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      appText('工具集成', 'Tool Integration'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _CodexIntegrationCard(controller: controller),
              ],
            ),
          ),
        );
    }
  }

  StatusInfo? _connectionStatus(RuntimeConnectionStatus status) {
    return switch (status) {
      RuntimeConnectionStatus.connected => const StatusInfo(
        'Connected',
        StatusTone.success,
      ),
      RuntimeConnectionStatus.connecting => const StatusInfo(
        'Connecting',
        StatusTone.accent,
      ),
      RuntimeConnectionStatus.offline => const StatusInfo(
        'Offline',
        StatusTone.neutral,
      ),
      RuntimeConnectionStatus.error => const StatusInfo(
        'Error',
        StatusTone.danger,
      ),
    };
  }
}

enum AiGatewayTab { models, agents, endpoints, tools }

extension AiGatewayTabCopy on AiGatewayTab {
  String get label => switch (this) {
    AiGatewayTab.models => appText('模型', 'Models'),
    AiGatewayTab.agents => appText('代理', 'Agents'),
    AiGatewayTab.endpoints => appText('端点', 'Endpoints'),
    AiGatewayTab.tools => appText('工具', 'Tools'),
  };
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.model, required this.onTap});

  final dynamic model;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: palette.surfaceSecondary,
      elevation: 0,
      child: ListTile(
        onTap: onTap,
        leading: Icon(Icons.psychology_rounded, color: palette.accent),
        title: Text(
          model.name ?? 'Unknown',
          style: TextStyle(color: palette.textPrimary),
        ),
        subtitle: Text(
          model.provider ?? 'Unknown provider',
          style: TextStyle(color: palette.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Active',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent, required this.onTap});

  final dynamic agent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: palette.surfaceSecondary,
      elevation: 0,
      child: ListTile(
        onTap: onTap,
        leading: Icon(Icons.hub_rounded, color: palette.accent),
        title: Text(
          agent.name ?? 'Unknown',
          style: TextStyle(color: palette.textPrimary),
        ),
        subtitle: Text(
          agent.capabilities?.join(', ') ?? 'No capabilities',
          style: TextStyle(color: palette.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(Icons.chevron_right, color: palette.textMuted)],
        ),
      ),
    );
  }
}

class _EndpointCard extends StatelessWidget {
  const _EndpointCard({
    required this.name,
    required this.endpoint,
    required this.status,
    required this.onTap,
  });

  final String name;
  final String endpoint;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isConnected = status == 'Connected';

    return Card(
      color: palette.surfaceSecondary,
      elevation: 0,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          Icons.device_hub_rounded,
          color: isConnected ? palette.accent : palette.textMuted,
        ),
        title: Text(name, style: TextStyle(color: palette.textPrimary)),
        subtitle: Text(
          endpoint,
          style: TextStyle(
            color: palette.textSecondary,
            fontFamily: 'monospace',
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isConnected
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.grey.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 12,
              color: isConnected ? Colors.green : palette.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================
// Codex Integration Section
// ============================================

class _CodexIntegrationCard extends StatefulWidget {
  const _CodexIntegrationCard({required this.controller});

  final AppController controller;

  @override
  State<_CodexIntegrationCard> createState() => _CodexIntegrationCardState();
}

class _CodexIntegrationCardState extends State<_CodexIntegrationCard> {
  bool _isExporting = false;
  String? _exportPath;
  String? _errorMessage;
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(
      text: widget.controller.configuredCodexCliPath,
    );
  }

  @override
  void didUpdateWidget(covariant _CodexIntegrationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextValue = widget.controller.configuredCodexCliPath;
    if (_pathController.text != nextValue) {
      _pathController.value = TextEditingValue(
        text: nextValue,
        selection: TextSelection.collapsed(offset: nextValue.length),
      );
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final controller = widget.controller;
    final selectedRuntimeMode = controller.configuredCodeAgentRuntimeMode;
    final isExternalMode =
        selectedRuntimeMode == CodeAgentRuntimeMode.externalCli;
    final cooperationLabel = switch (controller.codexCooperationState) {
      CodexCooperationState.notStarted => appText('未启动', 'Not started'),
      CodexCooperationState.bridgeOnly => appText(
        '已启动，但未注册到 Gateway',
        'Started, not registered to the gateway',
      ),
      CodexCooperationState.registered => appText(
        '已启动并已注册到 Gateway',
        'Started and registered to the gateway',
      ),
    };
    final binaryLabel = !isExternalMode
        ? appText('不需要', 'Not required')
        : controller.hasDetectedCodexCli
        ? appText('已就绪', 'Ready')
        : appText('未检测到', 'Not found');
    final bridgeLabel = controller.isCodexBridgeEnabled
        ? appText('运行中', 'Running')
        : appText('未启用', 'Disabled');

    return Card(
      color: palette.surfaceSecondary,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.terminal_rounded, color: palette.accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  appText('Codex CLI 集成', 'Codex CLI Integration'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              appText(
                '显式启用桥接后，XWorkmate 会使用外部 Codex CLI 进程，并在 Gateway 已连接时注册为协同 code-agent bridge。',
                'When enabled, XWorkmate launches an external Codex CLI process and registers as a cooperative code-agent bridge if the gateway is connected.',
              ),
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(
                    appText('External Codex CLI', 'External Codex CLI'),
                  ),
                  selected:
                      selectedRuntimeMode == CodeAgentRuntimeMode.externalCli,
                  onSelected: controller.isCodexBridgeBusy
                      ? null
                      : (selected) => selected
                            ? _setRuntimeMode(CodeAgentRuntimeMode.externalCli)
                            : null,
                ),
                ChoiceChip(
                  label: Text(
                    appText(
                      'Built-in Codex (Experimental)',
                      'Built-in Codex (Experimental)',
                    ),
                  ),
                  selected: selectedRuntimeMode == CodeAgentRuntimeMode.builtIn,
                  onSelected: controller.isCodexBridgeBusy
                      ? null
                      : (selected) => selected
                            ? _setRuntimeMode(CodeAgentRuntimeMode.builtIn)
                            : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _StatusRow(
              label: appText('运行时模式', 'Runtime mode'),
              value: controller.effectiveCodeAgentRuntimeMode.label,
            ),
            _StatusRow(
              label: appText('Binary 状态', 'Binary status'),
              value: binaryLabel,
              detail: !isExternalMode
                  ? appText(
                      'Built-in 运行时不依赖外部 codex 可执行文件。',
                      'Built-in runtime does not require an external codex binary.',
                    )
                  : controller.resolvedCodexCliPath ??
                        appText(
                          '请安装 codex 或填写路径。',
                          'Install codex or set a path.',
                        ),
            ),
            _StatusRow(
              label: appText('Bridge 状态', 'Bridge status'),
              value: bridgeLabel,
            ),
            _StatusRow(
              label: appText('Gateway 协同状态', 'Gateway cooperation'),
              value: cooperationLabel,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pathController,
              decoration: InputDecoration(
                labelText: appText('Codex CLI 路径', 'Codex CLI path'),
                hintText: appText(
                  '/opt/homebrew/bin/codex',
                  '/opt/homebrew/bin/codex',
                ),
                suffixIcon: IconButton(
                  onPressed: controller.isCodexBridgeBusy
                      ? null
                      : _savePathOverride,
                  icon: const Icon(Icons.save_rounded),
                ),
              ),
              onSubmitted: (_) => _savePathOverride(),
            ),
            if (isExternalMode && !controller.hasDetectedCodexCli) ...[
              const SizedBox(height: 8),
              Text(
                appText(
                  '未检测到 Codex CLI。可先运行 `npm i -g @openai/codex`，或填写可执行文件绝对路径。',
                  'Codex CLI was not found. Run `npm i -g @openai/codex` or set the absolute binary path.',
                ),
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
            ],
            if (controller.codexRuntimeWarning != null) ...[
              const SizedBox(height: 12),
              _InfoBanner(
                color: Colors.orange,
                icon: Icons.warning_amber_rounded,
                message: controller.codexRuntimeWarning!,
              ),
            ],
            if (_exportPath != null) ...[
              const SizedBox(height: 12),
              _InfoBanner(
                color: Colors.green,
                icon: Icons.check_circle_rounded,
                message: appText('已导出到: ', 'Exported to: ') + _exportPath!,
              ),
            ],
            if ((_errorMessage ?? controller.codexBridgeError) != null) ...[
              const SizedBox(height: 12),
              _InfoBanner(
                color: Colors.red,
                icon: Icons.error_rounded,
                message: _errorMessage ?? controller.codexBridgeError!,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: controller.isCodexBridgeBusy
                        ? null
                        : controller.isCodexBridgeEnabled
                        ? _disableBridge
                        : _enableBridge,
                    icon: controller.isCodexBridgeBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            controller.isCodexBridgeEnabled
                                ? Icons.stop_circle_outlined
                                : Icons.play_circle_outline_rounded,
                            size: 16,
                          ),
                    label: Text(
                      controller.isCodexBridgeEnabled
                          ? appText('停用 Bridge', 'Disable Bridge')
                          : appText('启用 Bridge', 'Enable Bridge'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isExporting ? null : _exportConfig,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 16),
                    label: Text(appText('导出配置', 'Export Config')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _openCodexTerminal,
                icon: const Icon(Icons.terminal_rounded, size: 16),
                label: Text(appText('打开终端', 'Open Terminal')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setRuntimeMode(CodeAgentRuntimeMode mode) async {
    if (widget.controller.isCodexBridgeEnabled) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appText(
              '请先停用 Bridge 再切换运行时模式。',
              'Disable the bridge before switching runtime mode.',
            ),
          ),
        ),
      );
      return;
    }

    await widget.controller.saveSettings(
      widget.controller.settings.copyWith(codeAgentRuntimeMode: mode),
      refreshAfterSave: false,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(appText('运行时模式已更新。', 'Runtime mode updated.'))),
    );
  }

  Future<void> _savePathOverride() async {
    final trimmed = _pathController.text.trim();
    await widget.controller.saveSettings(
      widget.controller.settings.copyWith(codexCliPath: trimmed),
      refreshAfterSave: false,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(appText('Codex CLI 路径已保存', 'Codex CLI path saved')),
      ),
    );
  }

  Future<void> _enableBridge() async {
    setState(() => _errorMessage = null);
    try {
      await widget.controller.enableCodexBridge();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
    }
  }

  Future<void> _disableBridge() async {
    setState(() => _errorMessage = null);
    try {
      await widget.controller.disableCodexBridge();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
    }
  }

  Future<void> _exportConfig() async {
    setState(() {
      _isExporting = true;
      _errorMessage = null;
    });

    try {
      final codexHome = resolveCodexHomeDirectory();
      final configPath = '$codexHome/config.toml';

      final gatewayUrl = widget.controller.aiGatewayUrl;
      final apiKey = await widget.controller.loadAiGatewayApiKey();

      if (gatewayUrl.isEmpty) {
        throw Exception(
          appText('AI Gateway URL 未配置', 'AI Gateway URL not configured'),
        );
      }

      await widget.controller.runtimeCoordinator.configureCodexForGateway(
        gatewayUrl: gatewayUrl,
        apiKey: apiKey,
      );

      setState(() {
        _exportPath = configPath;
        _isExporting = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isExporting = false;
      });
    }
  }

  void _openCodexTerminal() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(appText('请在终端中运行: codex', 'Run in terminal: codex')),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.color,
    required this.icon,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: color),
              overflow: TextOverflow.ellipsis,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }
}
