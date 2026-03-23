import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../runtime/platform_environment.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';

class CodexIntegrationCard extends StatefulWidget {
  const CodexIntegrationCard({super.key, required this.controller});

  final AppController controller;

  @override
  State<CodexIntegrationCard> createState() => _CodexIntegrationCardState();
}

class _CodexIntegrationCardState extends State<CodexIntegrationCard> {
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
  void didUpdateWidget(covariant CodexIntegrationCard oldWidget) {
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
          appText('LLM API Endpoint 未配置', 'LLM API Endpoint not configured'),
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
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
