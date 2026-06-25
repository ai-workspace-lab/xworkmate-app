import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/app_language.dart';
import '../../theme/app_palette.dart';

class SettingsHelpPanel extends StatelessWidget {
  const SettingsHelpPanel({super.key});

  static const _sections = <_HelpSection>[
    _HelpSection(
      title: '1. 快速安装（一键部署）',
      codeLabel: 'bash',
      code: '''
curl -sfL https://install.svc.plus/ai-workspace | bash -
''',
    ),
    _HelpSection(
      title: '2. 带 API Key 安装',
      codeLabel: 'bash',
      code: '''
export DEEPSEEK_API_KEY="<your-deepseek-api-key>"
export NVIDIA_API_KEY="<your-nvidia-api-key>"
export OLLAMA_API_KEY="<your-ollama-api-key>"
curl -sfL https://install.svc.plus/ai-workspace | bash -
''',
    ),
    _HelpSection(
      title: '3. 卸载（保留数据）',
      codeLabel: 'bash',
      code: '''
curl -sfL https://install.svc.plus/ai-workspace | bash -s -- uninstall
''',
    ),
    _HelpSection(
      title: '4. 彻底卸载（清除所有数据）',
      codeLabel: 'bash',
      code: '''
curl -sfL https://install.svc.plus/ai-workspace | bash -s -- uninstall --purge
''',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appText('帮助', 'Help'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            appText(
              '测试提示词模板，本文档提供了用于测试 setup-ai-workspace-all-in-one.sh 的标准化提示词模板，可直接复制粘贴到终端执行。',
              'Test prompt templates for setup-ai-workspace-all-in-one.sh. Copy and paste directly into your terminal.',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          for (final section in _sections) ...[
            _HelpCodeSectionCard(section: section),
            const SizedBox(height: 18),
          ],
          _InfoBlock(
            title: appText('环境变量参考', 'Environment variables'),
            child: Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(1.1),
                1: FlexColumnWidth(1.4),
                2: FlexColumnWidth(0.7),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                _tableRow('DEEPSEEK_API_KEY', 'DeepSeek 模型 API 密钥', '可选'),
                _tableRow('NVIDIA_API_KEY', 'NVIDIA NIM API 密钥', '可选'),
                _tableRow('OLLAMA_API_KEY', 'Ollama 服务 API 密钥', '可选'),
                _tableRow('PLAYBOOK_DIR', '本地 Playbook 目录路径（开发调试用）', '可选'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _InfoBlock(
            title: appText('支持平台', 'Supported platforms'),
            child: Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(1.1),
                1: FlexColumnWidth(0.7),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                _tableRow('macOS (Apple Silicon / Intel)', '已测试'),
                _tableRow('Debian 11/12', '已测试'),
                _tableRow('Ubuntu 22.04/24.04', '已测试'),
                _tableRow('其他 Linux 发行版', '未测试'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TableRow _tableRow(String a, String b, [String? c]) {
    return TableRow(
      children: [_tableCell(a), _tableCell(b), if (c != null) _tableCell(c)],
    );
  }

  Widget _tableCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Text(text),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _HelpSection {
  const _HelpSection({
    required this.title,
    required this.codeLabel,
    required this.code,
  });

  final String title;
  final String codeLabel;
  final String code;
}

class _HelpCodeSectionCard extends StatelessWidget {
  const _HelpCodeSectionCard({required this.section});

  final _HelpSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: palette.surfacePrimary,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 18, 8),
                child: Row(
                  children: [
                    Text(
                      section.codeLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: appText('复制', 'Copy'),
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: section.code.trim()),
                      ),
                      icon: const Icon(Icons.content_copy_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(18),
                child: SelectableText(
                  section.code.trimRight(),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.7,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
