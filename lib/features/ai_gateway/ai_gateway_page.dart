 import 'package:flutter/material.dart';
 
 import '../../app/app_controller.dart';
 import '../../i18n/app_language.dart';
 import '../../models/app_models.dart';
 import '../../runtime/runtime_models.dart';
 import '../../theme/app_palette.dart';
 import '../../theme/app_theme.dart';
 import '../../widgets/metric_card.dart';
 import '../../widgets/section_header.dart';
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
    final palette = context.palette;

    final metrics = [
      MetricSummary(
        label: appText('网关状态', 'Gateway'),
        value: controller.connection.status.label,
        caption: controller.connection.remoteAddress ?? appText('未连接', 'Disconnected'),
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
                  () => _tab = AiGatewayTab.values.firstWhere((t) => t.label == label),
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

  Widget _buildTabContent(BuildContext context, AiGatewayTab tab, AppController controller) {
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
                    Icon(Icons.psychology_rounded, color: palette.accent, size: 20),
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
                  ...controller.models.map((model) => _ModelCard(
                    model: model,
                    onTap: () {},
                  )),
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
                  ...controller.agents.map((agent) => _AgentCard(
                    agent: agent,
                    onTap: () {},
                  )),
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
                    Icon(Icons.device_hub_rounded, color: palette.accent, size: 20),
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

  }

  StatusInfo? _connectionStatus(RuntimeConnectionStatus status) {
    return switch (status) {
      RuntimeConnectionStatus.connected => const StatusInfo('Connected', StatusTone.success),
      RuntimeConnectionStatus.connecting => const StatusInfo('Connecting', StatusTone.accent),
      RuntimeConnectionStatus.offline => const StatusInfo('Offline', StatusTone.neutral),
      RuntimeConnectionStatus.error => const StatusInfo('Error', StatusTone.danger),
    };
  }
}

enum AiGatewayTab { models, agents, endpoints, tools }

extension AiGatewayTabCopy on AiGatewayTab {
  String get label => switch (this) {
    AiGatewayTab.models => appText('模型', 'Models'),
    AiGatewayTab.agents => appText('代理', 'Agents'),
    AiGatewayTab.endpoints => appText('端点', 'Endpoints'),
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
        title: Text(model.name ?? 'Unknown', style: TextStyle(color: palette.textPrimary)),
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
                color: Colors.green.withOpacity(0.2),
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
        title: Text(agent.name ?? 'Unknown', style: TextStyle(color: palette.textPrimary)),
        subtitle: Text(
          agent.capabilities?.join(', ') ?? 'No capabilities',
          style: TextStyle(color: palette.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chevron_right, color: palette.textMuted),
          ],
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
          style: TextStyle(color: palette.textSecondary, fontFamily: 'monospace'),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isConnected
                ? Colors.green.withOpacity(0.2)
                : Colors.grey.withOpacity(0.2),
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

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
                '导出配置文件以在命令行中使用 Codex CLI。',
                'Export configuration to use Codex CLI in terminal.',
              ),
              style: TextStyle(
                fontSize: 13,
                color: palette.textSecondary,
              ),
            ),
            if (_exportPath != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        appText('已导出到: ', 'Exported to: ') + _exportPath!,
                        style: TextStyle(fontSize: 12, color: Colors.green),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_rounded, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isExporting ? null : _exportConfig,
                    icon: _isExporting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.download_rounded, size: 16),
                    label: Text(appText('导出配置', 'Export Config')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openCodexTerminal,
                    icon: Icon(Icons.terminal_rounded, size: 16),
                    label: Text(appText('打开终端', 'Open Terminal')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportConfig() async {
    setState(() {
      _isExporting = true;
      _errorMessage = null;
    });

    try {
      final home = Platform.environment['HOME'] ?? '';
      final codexHome = Platform.environment['CODEX_HOME'] ?? '$home/.codex';
      final configPath = '$codexHome/config.toml';

      // Get gateway URL and API key from controller
      final gatewayUrl = widget.controller.aiGatewayUrl;
      final apiKey = widget.controller.aiGatewayApiKey;

      if (gatewayUrl.isEmpty) {
        throw Exception(appText('AI Gateway URL 未配置', 'AI Gateway URL not configured'));
      }

      // Create config directory if needed
      final configDir = Directory(codexHome);
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }

      // Generate config content
      final configContent = '''
# Generated by XWorkmate - AI Gateway Configuration
# Last updated: ${DateTime.now().toIso8601String()}

[model_providers.xworkmate]
name = "XWorkmate AI Gateway"
base_url = "$gatewayUrl"
${apiKey.isNotEmpty ? 'experimental_bearer_token = "$apiKey"' : ''}
wire_api = "responses"

[model]
model = "gpt-4.1"

[approval_policy]
policy = "suggest"

[sandbox]
mode = "workspace-write"

[features]
child_agents_md = true
''';

      await File(configPath).writeAsString(configContent);

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
    // This would open a terminal with Codex environment
    // Implementation depends on platform
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(appText('请在终端中运行: codex', 'Run in terminal: codex')),
      ),
    );
  }
}
