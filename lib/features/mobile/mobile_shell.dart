import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/workspace_page_registry.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../widgets/detail_drawer.dart';
import '../../widgets/gateway_connect_dialog.dart';

enum MobileShellTab { assistant, tasks, workspace, secrets, settings }

extension on MobileShellTab {
  String get label => switch (this) {
    MobileShellTab.assistant => appText('助手', 'Assistant'),
    MobileShellTab.tasks => appText('任务', 'Tasks'),
    MobileShellTab.workspace => appText('工作区', 'Workspace'),
    MobileShellTab.secrets => appText('密钥', 'Secrets'),
    MobileShellTab.settings => appText('设置', 'Settings'),
  };

  IconData get icon => switch (this) {
    MobileShellTab.assistant => Icons.chat_bubble_outline_rounded,
    MobileShellTab.tasks => Icons.layers_rounded,
    MobileShellTab.workspace => Icons.grid_view_rounded,
    MobileShellTab.secrets => Icons.key_rounded,
    MobileShellTab.settings => Icons.settings_rounded,
  };
}

const _tealSoft = Color(0xFFDDF3EF);
const _tealLine = Color(0xFF49A892);
const _violetSoft = Color(0xFFECE2FF);
const _violetLine = Color(0xFF7A61B6);

class MobileShell extends StatefulWidget {
  const MobileShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  bool _showWorkspaceHub = false;
  late WorkspaceDestination _lastDestination;

  @override
  void initState() {
    super.initState();
    _lastDestination = widget.controller.destination;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant MobileShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_handleControllerChanged);
    _lastDestination = widget.controller.destination;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final destination = widget.controller.destination;
    if (destination == _lastDestination) {
      return;
    }
    _lastDestination = destination;
    if (_showWorkspaceHub && mounted) {
      setState(() {
        _showWorkspaceHub = false;
      });
    }
  }

  MobileShellTab _tabForDestination(WorkspaceDestination destination) {
    return switch (destination) {
      WorkspaceDestination.assistant => MobileShellTab.assistant,
      WorkspaceDestination.tasks => MobileShellTab.tasks,
      WorkspaceDestination.skills ||
      WorkspaceDestination.nodes ||
      WorkspaceDestination.agents ||
      WorkspaceDestination.mcpServer ||
      WorkspaceDestination.clawHub ||
      WorkspaceDestination.aiGateway ||
      WorkspaceDestination.account => MobileShellTab.workspace,
      WorkspaceDestination.secrets => MobileShellTab.secrets,
      WorkspaceDestination.settings => MobileShellTab.settings,
    };
  }

  void _selectTab(MobileShellTab tab) {
    switch (tab) {
      case MobileShellTab.assistant:
        setState(() => _showWorkspaceHub = false);
        widget.controller.navigateTo(WorkspaceDestination.assistant);
        return;
      case MobileShellTab.tasks:
        setState(() => _showWorkspaceHub = false);
        widget.controller.navigateTo(WorkspaceDestination.tasks);
        return;
      case MobileShellTab.workspace:
        setState(() => _showWorkspaceHub = true);
        return;
      case MobileShellTab.secrets:
        setState(() => _showWorkspaceHub = false);
        widget.controller.navigateTo(WorkspaceDestination.secrets);
        return;
      case MobileShellTab.settings:
        setState(() => _showWorkspaceHub = false);
        widget.controller.navigateTo(WorkspaceDestination.settings);
        return;
    }
  }

  void _openWorkspaceDestination(WorkspaceDestination destination) {
    setState(() => _showWorkspaceHub = false);
    widget.controller.navigateTo(destination);
  }

  void _openDetailSheet(DetailPanelData detail) {
    widget.controller.openDetail(detail);
  }

  void _showConnectSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: GatewayConnectDialog(
            controller: widget.controller,
            onDone: () => Navigator.of(sheetContext).pop(),
          ),
        );
      },
    );
  }

  Widget _buildCurrentPage() {
    if (_showWorkspaceHub) {
      return _MobileWorkspaceLauncher(
        controller: widget.controller,
        onOpenGatewayConnect: _showConnectSheet,
        onSelectDestination: _openWorkspaceDestination,
      );
    }

    final destination = widget.controller.destination;
    return buildWorkspacePage(
      destination: destination,
      controller: widget.controller,
      onOpenDetail: _openDetailSheet,
      surface: WorkspacePageSurface.mobile,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final currentTab = _showWorkspaceHub
            ? MobileShellTab.workspace
            : _tabForDestination(widget.controller.destination);
        final destinationKey = _showWorkspaceHub
            ? const ValueKey<String>('mobile-shell-workspace')
            : ValueKey<String>(
                'mobile-shell-${widget.controller.destination.name}',
              );
        final detailPanel = widget.controller.detailPanel;
        final palette = context.palette;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Scaffold(
          backgroundColor: palette.canvas,
          body: Stack(
            children: [
              Positioned(
                top: 100,
                left: -80,
                child: _GlowOrb(
                  size: 220,
                  color: palette.accentMuted.withValues(
                    alpha: isDark ? 0.36 : 0.6,
                  ),
                ),
              ),
              Positioned(
                right: -90,
                bottom: 220,
                child: _GlowOrb(
                  size: 260,
                  color: palette.chromeHighlight.withValues(
                    alpha: isDark ? 0.16 : 0.4,
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  palette.chromeHighlight.withValues(
                                    alpha: isDark ? 0.16 : 0.9,
                                  ),
                                  palette.chromeSurface.withValues(alpha: 0.94),
                                ],
                              ),
                              border: Border.all(color: palette.chromeStroke),
                              boxShadow: [palette.chromeShadowAmbient],
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeOutCubic,
                              child: KeyedSubtree(
                                key: destinationKey,
                                child: _buildCurrentPage(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 12, 6, 18),
                        child: _BottomPillNav(
                          currentTab: currentTab,
                          onChanged: _selectTab,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (detailPanel != null)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: widget.controller.closeDetail,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.14),
                    ),
                  ),
                ),
              if (detailPanel != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: 0.92,
                    child: DetailSheet(
                      data: detailPanel,
                      onClose: widget.controller.closeDetail,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MobileWorkspaceLauncher extends StatelessWidget {
  const _MobileWorkspaceLauncher({
    required this.controller,
    required this.onOpenGatewayConnect,
    required this.onSelectDestination,
  });

  final AppController controller;
  final VoidCallback onOpenGatewayConnect;
  final ValueChanged<WorkspaceDestination> onSelectDestination;

  @override
  Widget build(BuildContext context) {
    final connection = controller.connection;
    final palette = context.palette;
    final entries = <_WorkspaceEntry>[
      _WorkspaceEntry(
        destination: WorkspaceDestination.skills,
        subtitle: appText('技能包与依赖状态', 'Packages and dependency status'),
        iconColor: palette.accent,
        iconBackground: palette.accentMuted,
      ),
      _WorkspaceEntry(
        destination: WorkspaceDestination.nodes,
        subtitle: appText('边缘节点与实例', 'Edge nodes and instances'),
        iconColor: _tealLine,
        iconBackground: _tealSoft,
      ),
      _WorkspaceEntry(
        destination: WorkspaceDestination.agents,
        subtitle: appText('代理运行态与配置', 'Agent state and configuration'),
        iconColor: palette.warning,
        iconBackground: palette.warning.withValues(alpha: 0.12),
      ),
      _WorkspaceEntry(
        destination: WorkspaceDestination.mcpServer,
        subtitle: appText('MCP 连接与工具注册', 'MCP endpoints and tools'),
        iconColor: palette.accent,
        iconBackground: palette.accentMuted,
      ),
      _WorkspaceEntry(
        destination: WorkspaceDestination.clawHub,
        subtitle: appText('技能与模板市场', 'Marketplace and templates'),
        iconColor: _violetLine,
        iconBackground: _violetSoft,
      ),
      _WorkspaceEntry(
        destination: WorkspaceDestination.aiGateway,
        subtitle: appText('模型与代理网关', 'Models and agent gateway'),
        iconColor: palette.accent,
        iconBackground: palette.accentMuted,
      ),
      _WorkspaceEntry(
        destination: WorkspaceDestination.account,
        subtitle: appText('身份、工作区与会话', 'Identity, workspace and sessions'),
        iconColor: palette.success,
        iconBackground: palette.success.withValues(alpha: 0.12),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LauncherHeader(
            title: appText('工作区', 'Workspace'),
            subtitle: appText(
              'Android 与 iOS 统一移动入口，集中访问全部核心模块。',
              'Shared mobile entry for Android and iOS with access to all core modules.',
            ),
            primaryLabel: connection.status == RuntimeConnectionStatus.connected
                ? appText('查看连接', 'Connection')
                : appText('连接 Gateway', 'Connect Gateway'),
            secondaryLabel: appText('返回助手', 'Open Assistant'),
            onPrimaryPressed: onOpenGatewayConnect,
            onSecondaryPressed: () =>
                onSelectDestination(WorkspaceDestination.assistant),
          ),
          const SizedBox(height: 18),
          _WorkspaceHero(
            connection: connection,
            activeAgentName: controller.activeAgentName,
            sessionCount: controller.sessions.length,
            runningTaskCount: controller.tasksController.running.length,
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 2 : 1;
              final width = columns == 2
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: entries
                    .map(
                      (entry) => SizedBox(
                        width: width,
                        child: _WorkspaceShortcutCard(
                          entry: entry,
                          onTap: () => onSelectDestination(entry.destination),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WorkspaceEntry {
  const _WorkspaceEntry({
    required this.destination,
    required this.subtitle,
    required this.iconColor,
    required this.iconBackground,
  });

  final WorkspaceDestination destination;
  final String subtitle;
  final Color iconColor;
  final Color iconBackground;
}

class _LauncherHeader extends StatelessWidget {
  const _LauncherHeader({
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimaryPressed,
    required this.onSecondaryPressed,
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _GradientActionButton(
              label: primaryLabel,
              onPressed: onPrimaryPressed,
            ),
            OutlinedButton.icon(
              onPressed: onSecondaryPressed,
              icon: const Icon(Icons.arrow_outward_rounded),
              label: Text(secondaryLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class _WorkspaceHero extends StatelessWidget {
  const _WorkspaceHero({
    required this.connection,
    required this.activeAgentName,
    required this.sessionCount,
    required this.runningTaskCount,
  });

  final GatewayConnectionSnapshot connection;
  final String activeAgentName;
  final int sessionCount;
  final int runningTaskCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final statusLabel = connection.status == RuntimeConnectionStatus.connected
        ? appText('会话已就绪', 'Session Ready')
        : appText('等待接入', 'Awaiting Connection');
    final statusColor = connection.status == RuntimeConnectionStatus.connected
        ? palette.success
        : palette.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.chromeHighlight.withValues(alpha: 0.86),
            palette.surfacePrimary.withValues(alpha: 0.94),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.strokeSoft),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusLabel,
            style: theme.textTheme.labelLarge?.copyWith(color: statusColor),
          ),
          const SizedBox(height: 10),
          Text(
            connection.remoteAddress ?? 'xworkmate.svc.plus',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            activeAgentName,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _HeroMetric(
                label: appText('会话', 'Sessions'),
                value: '$sessionCount',
                icon: Icons.chat_bubble_outline_rounded,
              ),
              _HeroMetric(
                label: appText('运行任务', 'Running'),
                value: '$runningTaskCount',
                icon: Icons.play_circle_outline_rounded,
              ),
              _HeroMetric(
                label: appText('状态', 'Status'),
                value: connection.status.label,
                icon: Icons.monitor_heart_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: palette.accent),
          const SizedBox(width: 8),
          Text(
            '$label · $value',
            style: theme.textTheme.labelLarge?.copyWith(
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceShortcutCard extends StatelessWidget {
  const _WorkspaceShortcutCard({required this.entry, required this.onTap});

  final _WorkspaceEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.chromeHighlight.withValues(alpha: 0.84),
                palette.surfacePrimary.withValues(alpha: 0.94),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: entry.iconBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  entry.destination.icon,
                  color: entry.iconColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.destination.label,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.chevron_right_rounded, color: palette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientActionButton extends StatelessWidget {
  const _GradientActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.accent, palette.accentHover],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        child: Text(label),
      ),
    );
  }
}

class _BottomPillNav extends StatelessWidget {
  const _BottomPillNav({required this.currentTab, required this.onChanged});

  final MobileShellTab currentTab;
  final ValueChanged<MobileShellTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: palette.surfacePrimary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.strokeSoft),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: Row(
        children: MobileShellTab.values
            .map(
              (tab) => Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(tab),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: currentTab == tab
                          ? palette.surfaceSecondary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tab.icon,
                          size: 24,
                          color: currentTab == tab
                              ? palette.accent
                              : palette.textPrimary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tab.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: currentTab == tab
                                ? palette.accent
                                : palette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
