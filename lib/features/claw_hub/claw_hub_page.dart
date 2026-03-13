 import 'package:flutter/material.dart';
 
 import '../../app/app_controller.dart';
 import '../../i18n/app_language.dart';
 import '../../models/app_models.dart';
 import '../../theme/app_palette.dart';
 import '../../theme/app_theme.dart';
 import '../../widgets/section_header.dart';
 import '../../widgets/surface_card.dart';
 import '../../widgets/top_bar.dart';

class ClawHubPage extends StatefulWidget {
  const ClawHubPage({
    super.key,
    required this.controller,
    required this.onOpenDetail,
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  State<ClawHubPage> createState() => _ClawHubPageState();
}

class _ClawHubPageState extends State<ClawHubPage> {
  final _searchController = TextEditingController();
  final _commandController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ClawHubLogEntry> _logs = [];
  bool _isExecuting = false;

  @override
  void dispose() {
    _searchController.dispose();
    _commandController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addLog(String message, {ClawHubLogType type = ClawHubLogType.info}) {
    setState(() {
      _logs.add(ClawHubLogEntry(
        timestamp: DateTime.now(),
        message: message,
        type: type,
      ));
    });
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _executeCommand(String input) {
    if (input.trim().isEmpty) return;

    _addLog('\$ clawhub \$input', type: ClawHubLogType.command);
    _commandController.clear();

    final parts = input.trim().split(RegExp(r'\s+'));
    final command = parts.isNotEmpty ? parts[0] : '';
    final args = parts.length > 1 ? parts.sublist(1) : <String>[];

    switch (command) {
      case 'search':
        _handleSearch(args);
        break;
      case 'install':
        _handleInstall(args);
        break;
      case 'update':
        _handleUpdate(args);
        break;
      case 'help':
      case '--help':
      case '-h':
        _showHelp();
        break;
      default:
        _addLog(
          'Unknown command: \$command. Type "clawhub help" for available commands.',
          type: ClawHubLogType.error,
        );
    }
  }

  void _handleSearch(List<String> args) {
    final query = args.join(' ');
    if (query.isEmpty) {
      _addLog('Usage: clawhub search "<query>"', type: ClawHubLogType.warning);
      return;
    }

    setState(() => _isExecuting = true);
    _addLog('Searching for "\$query"...');

    // Simulate search results
    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() => _isExecuting = false);
      _addLog('');
      _addLog('Found 3 packages:', type: ClawHubLogType.success);
      _addLog('  ├─ skill-analyzer      v1.2.0    Code analysis skill');
      _addLog('  ├─ feishu-connector      v2.1.3    Feishu integration');
      _addLog('  └─ azure-deploy         v3.0.1    Azure deployment helper');
      _addLog('');
      _addLog('Use "clawhub install <slug>" to install a package.');
    });
  }

  void _handleInstall(List<String> args) {
    if (args.isEmpty) {
      _addLog('Usage: clawhub install <slug>', type: ClawHubLogType.warning);
      return;
    }

    final slug = args[0];
    setState(() => _isExecuting = true);
    _addLog('Installing \$slug...');

    Future.delayed(const Duration(milliseconds: 1200), () {
      setState(() => _isExecuting = false);
      _addLog('✓ Successfully installed \$slug', type: ClawHubLogType.success);
      _addLog('  Location: ~/.clawhub/skills/\$slug');
      _addLog('  Run "clawhub update" to check for updates.');
    });
  }

  void _handleUpdate(List<String> args) {
    final isAll = args.contains('--all') || args.contains('-a');
    final slug = isAll ? null : (args.isNotEmpty ? args[0] : null);

    setState(() => _isExecuting = true);

    if (isAll) {
      _addLog('Checking for updates...');
      Future.delayed(const Duration(milliseconds: 1000), () {
        setState(() => _isExecuting = false);
        _addLog('✓ All packages are up to date', type: ClawHubLogType.success);
      });
    } else if (slug != null) {
      _addLog('Updating \$slug...');
      Future.delayed(const Duration(milliseconds: 800), () {
        setState(() => _isExecuting = false);
        _addLog('✓ \$slug updated to latest version', type: ClawHubLogType.success);
      });
    } else {
      _addLog('Usage: clawhub update <slug>  or  clawhub update --all',
          type: ClawHubLogType.warning);
      setState(() => _isExecuting = false);
    }
  }

  void _showHelp() {
    _addLog('');
    _addLog('ClawHub Package Manager', type: ClawHubLogType.success);
    _addLog('Usage: clawhub <command> [options]');
    _addLog('');
    _addLog('Commands:');
    _addLog('  search "<query>"     Search for packages');
    _addLog('  install <slug>       Install a package');
    _addLog('  update <slug>        Update a specific package');
    _addLog('  update --all         Update all packages');
    _addLog('  help                 Show this help message');
    _addLog('');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                title: 'ClawHub',
                subtitle: appText(
                  'NPM 风格的包管理中心，支持搜索、安装和更新 Skills。',
                  'NPM-style package manager for skills.',
                ),
              ),
              const SizedBox(height: 24),
              SectionHeader(
                title: appText('终端', 'Terminal'),
                subtitle: appText('执行终端命令', 'Execute terminal commands'),
              ),
              const SizedBox(height: 12),
              SurfaceCard(
                child: Container(
                  height: 400,
                  decoration: BoxDecoration(
                    color: palette.surfaceSecondary.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      // Terminal header
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surfaceSecondary,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.terminal_rounded,
                              size: 16,
                              color: palette.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'clawhub',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: palette.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            if (_isExecuting)
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: palette.accent,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Terminal output
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          child: ListView.builder(
                            controller: _scrollController,
                            itemCount: _logs.length,
                            itemBuilder: (context, index) {
                              final log = _logs[index];
                              return _LogLine(entry: log, palette: palette);
                            },
                          ),
                        ),
                      ),
                      // Command input
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: palette.surfaceSecondary,
                          border: Border(
                            top: BorderSide(color: palette.strokeSoft),
                          ),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '\$',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: palette.accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _commandController,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                  color: palette.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintText: appText(
                                    '输入命令 (search, install, update)',
                                    'Type command (search, install, update)',
                                  ),
                                  hintStyle: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    color: palette.textMuted,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onSubmitted: _executeCommand,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.send_rounded,
                                size: 18,
                                color: palette.accent,
                              ),
                              onPressed: () =>
                                  _executeCommand(_commandController.text),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SectionHeader(
                title: appText('快速操作', 'Quick Actions'),
                subtitle: appText('常用操作快捷入口', 'Quick access to common actions'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _QuickActionButton(
                    icon: Icons.search_rounded,
                    label: appText('搜索技能', 'Search Skills'),
                    onTap: () => _executeCommand('search analytics'),
                  ),
                  _QuickActionButton(
                    icon: Icons.download_rounded,
                    label: appText('安装技能', 'Install Skill'),
                    onTap: () => _executeCommand('install example-skill'),
                  ),
                  _QuickActionButton(
                    icon: Icons.update_rounded,
                    label: appText('更新全部', 'Update All'),
                    onTap: () => _executeCommand('update --all'),
                  ),
                  _QuickActionButton(
                    icon: Icons.help_outline_rounded,
                    label: appText('查看帮助', 'View Help'),
                    onTap: () => _executeCommand('help'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

enum ClawHubLogType { info, command, success, warning, error }

class ClawHubLogEntry {
  final DateTime timestamp;
  final String message;
  final ClawHubLogType type;

  ClawHubLogEntry({
    required this.timestamp,
    required this.message,
    required this.type,
  });
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry, required this.palette});

  final ClawHubLogEntry entry;
  final AppPalette palette;

  Color get _color {
    switch (entry.type) {
      case ClawHubLogType.command:
        return palette.accent;
      case ClawHubLogType.success:
        return Colors.green;
      case ClawHubLogType.warning:
        return Colors.orange;
      case ClawHubLogType.error:
        return Colors.red;
      case ClawHubLogType.info:
        return palette.textPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        entry.message,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: _color,
          height: 1.4,
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Material(
      color: palette.surfaceSecondary,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: palette.accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
