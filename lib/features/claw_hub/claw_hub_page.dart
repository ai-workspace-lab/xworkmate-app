import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../theme/app_palette.dart';
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
  State<ClawHubPage> createState() => ClawHubPageStateInternal();
}

class ClawHubPageStateInternal extends State<ClawHubPage> {
  final searchControllerInternal = TextEditingController();
  final commandControllerInternal = TextEditingController();
  final scrollControllerInternal = ScrollController();
  final List<ClawHubLogEntry> logsInternal = [];
  bool isExecutingInternal = false;

  @override
  void dispose() {
    searchControllerInternal.dispose();
    commandControllerInternal.dispose();
    scrollControllerInternal.dispose();
    super.dispose();
  }

  void addLogInternal(
    String message, {
    ClawHubLogType type = ClawHubLogType.info,
  }) {
    setState(() {
      logsInternal.add(
        ClawHubLogEntry(
          timestamp: DateTime.now(),
          message: message,
          type: type,
        ),
      );
    });
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollControllerInternal.hasClients) {
        scrollControllerInternal.animateTo(
          scrollControllerInternal.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void executeCommandInternal(String input) {
    if (input.trim().isEmpty) return;

    addLogInternal('\$ clawhub \$input', type: ClawHubLogType.command);
    commandControllerInternal.clear();

    final parts = input.trim().split(RegExp(r'\s+'));
    final command = parts.isNotEmpty ? parts[0] : '';
    final args = parts.length > 1 ? parts.sublist(1) : <String>[];

    switch (command) {
      case 'search':
        handleSearchInternal(args);
        break;
      case 'install':
        handleInstallInternal(args);
        break;
      case 'update':
        handleUpdateInternal(args);
        break;
      case 'help':
      case '--help':
      case '-h':
        showHelpInternal();
        break;
      default:
        addLogInternal(
          'Unknown command: \$command. Type "clawhub help" for available commands.',
          type: ClawHubLogType.error,
        );
    }
  }

  void handleSearchInternal(List<String> args) {
    final query = args.join(' ');
    if (query.isEmpty) {
      addLogInternal(
        'Usage: clawhub search "<query>"',
        type: ClawHubLogType.warning,
      );
      return;
    }

    setState(() => isExecutingInternal = true);
    addLogInternal('Searching for "\$query"...');

    // Simulate search results
    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() => isExecutingInternal = false);
      addLogInternal('');
      addLogInternal('Found 3 packages:', type: ClawHubLogType.success);
      addLogInternal('  ├─ skill-analyzer      v1.2.0    Code analysis skill');
      addLogInternal('  ├─ feishu-connector      v2.1.3    Feishu integration');
      addLogInternal(
        '  └─ azure-deploy         v3.0.1    Azure deployment helper',
      );
      addLogInternal('');
      addLogInternal('Use "clawhub install <slug>" to install a package.');
    });
  }

  void handleInstallInternal(List<String> args) {
    if (args.isEmpty) {
      addLogInternal(
        'Usage: clawhub install <slug>',
        type: ClawHubLogType.warning,
      );
      return;
    }

    setState(() => isExecutingInternal = true);
    addLogInternal('Installing ${args[0]}...');

    Future.delayed(const Duration(milliseconds: 1200), () {
      setState(() => isExecutingInternal = false);
      addLogInternal(
        '✓ Successfully installed ${args[0]}',
        type: ClawHubLogType.success,
      );
      addLogInternal('  Location: ~/.clawhub/skills/${args[0]}');
      addLogInternal('  Run "clawhub update" to check for updates.');
    });
  }

  void handleUpdateInternal(List<String> args) {
    final isAll = args.contains('--all') || args.contains('-a');
    final slug = isAll ? null : (args.isNotEmpty ? args[0] : null);

    setState(() => isExecutingInternal = true);

    if (isAll) {
      addLogInternal('Checking for updates...');
      Future.delayed(const Duration(milliseconds: 1000), () {
        setState(() => isExecutingInternal = false);
        addLogInternal(
          '✓ All packages are up to date',
          type: ClawHubLogType.success,
        );
      });
    } else if (slug != null) {
      addLogInternal('Updating \$slug...');
      Future.delayed(const Duration(milliseconds: 800), () {
        setState(() => isExecutingInternal = false);
        addLogInternal(
          '✓ \$slug updated to latest version',
          type: ClawHubLogType.success,
        );
      });
    } else {
      addLogInternal(
        'Usage: clawhub update <slug>  or  clawhub update --all',
        type: ClawHubLogType.warning,
      );
      setState(() => isExecutingInternal = false);
    }
  }

  void showHelpInternal() {
    addLogInternal('');
    addLogInternal('ClawHub Package Manager', type: ClawHubLogType.success);
    addLogInternal('Usage: clawhub <command> [options]');
    addLogInternal('');
    addLogInternal('Commands:');
    addLogInternal('  search "<query>"     Search for packages');
    addLogInternal('  install <slug>       Install a package');
    addLogInternal('  update <slug>        Update a specific package');
    addLogInternal('  update --all         Update all packages');
    addLogInternal('  help                 Show this help message');
    addLogInternal('');
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
                breadcrumbs: [
                  AppBreadcrumbItem(
                    label: appText('主页', 'Home'),
                    icon: Icons.home_rounded,
                    onTap: widget.controller.navigateHome,
                  ),
                  const AppBreadcrumbItem(label: 'ClawHub'),
                ],
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
                    color: palette.surfaceSecondary.withValues(alpha: 0.5),
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
                            if (isExecutingInternal)
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
                            controller: scrollControllerInternal,
                            itemCount: logsInternal.length,
                            itemBuilder: (context, index) {
                              final log = logsInternal[index];
                              return LogLineInternal(
                                entry: log,
                                palette: palette,
                              );
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
                                controller: commandControllerInternal,
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
                                onSubmitted: executeCommandInternal,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.send_rounded,
                                size: 18,
                                color: palette.accent,
                              ),
                              onPressed: () => executeCommandInternal(
                                commandControllerInternal.text,
                              ),
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
                  QuickActionButtonInternal(
                    icon: Icons.search_rounded,
                    label: appText('搜索技能', 'Search Skills'),
                    onTap: () => executeCommandInternal('search analytics'),
                  ),
                  QuickActionButtonInternal(
                    icon: Icons.download_rounded,
                    label: appText('安装技能', 'Install Skill'),
                    onTap: () =>
                        executeCommandInternal('install example-skill'),
                  ),
                  QuickActionButtonInternal(
                    icon: Icons.update_rounded,
                    label: appText('更新全部', 'Update All'),
                    onTap: () => executeCommandInternal('update --all'),
                  ),
                  QuickActionButtonInternal(
                    icon: Icons.help_outline_rounded,
                    label: appText('查看帮助', 'View Help'),
                    onTap: () => executeCommandInternal('help'),
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

class LogLineInternal extends StatelessWidget {
  const LogLineInternal({
    super.key,
    required this.entry,
    required this.palette,
  });

  final ClawHubLogEntry entry;
  final AppPalette palette;

  Color get colorInternal {
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
          color: colorInternal,
          height: 1.4,
        ),
      ),
    );
  }
}

class QuickActionButtonInternal extends StatelessWidget {
  const QuickActionButtonInternal({
    super.key,
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
