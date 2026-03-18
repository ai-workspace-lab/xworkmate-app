import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../features/account/account_page.dart';
import '../../features/ai_gateway/ai_gateway_page.dart';
import '../../features/assistant/assistant_page.dart';
import '../../features/claw_hub/claw_hub_page.dart';
import '../../features/mcp_server/mcp_server_page.dart';
import '../../features/modules/modules_page.dart';
import '../../features/secrets/secrets_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/skills/skills_page.dart';
import '../../features/tasks/tasks_page.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_models.dart';
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

const _background = Color(0xFFF3EFF6);
const _surface = Colors.white;
const _surfaceSoft = Color(0xFFF7F4FB);
const _stroke = Color(0xFFE3DDEE);
const _textPrimary = Color(0xFF101113);
const _textSecondary = Color(0xFF8A8694);
const _accentStart = Color(0xFF7C88F8);
const _accentEnd = Color(0xFF6757EF);
const _accentSoft = Color(0xFFD9D5FA);
const _blueSoft = Color(0xFFDCE4F1);
const _blueLine = Color(0xFF6285A6);
const _greenSoft = Color(0xFFDCEFE2);
const _greenLine = Color(0xFF62C56A);
const _orangeSoft = Color(0xFFF5E7D9);
const _orangeLine = Color(0xFFE1913E);

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
    return switch (destination) {
      WorkspaceDestination.assistant => AssistantPage(
        controller: widget.controller,
        onOpenDetail: _openDetailSheet,
        showStandaloneTaskRail: false,
      ),
      WorkspaceDestination.tasks => TasksPage(
        controller: widget.controller,
        onOpenDetail: _openDetailSheet,
      ),
      WorkspaceDestination.skills => SkillsPage(
        controller: widget.controller,
        onOpenDetail: _openDetailSheet,
      ),
      WorkspaceDestination.nodes => ModulesPage(
        controller: widget.controller,
        onOpenDetail: _openDetailSheet,
        initialTab: ModulesTab.nodes,
      ),
      WorkspaceDestination.agents => ModulesPage(
        controller: widget.controller,
        onOpenDetail: _openDetailSheet,
        initialTab: ModulesTab.agents,
      ),
      WorkspaceDestination.mcpServer => McpServerPage(
        controller: widget.controller,
        onOpenDetail: _openDetailSheet,
      ),
      WorkspaceDestination.clawHub => ClawHubPage(
        controller: widget.controller,
        onOpenDetail: _openDetailSheet,
      ),
      WorkspaceDestination.secrets => SecretsPage(
        controller: widget.controller,
        onOpenDetail: _openDetailSheet,
      ),
      WorkspaceDestination.aiGateway => AiGatewayPage(
        controller: widget.controller,
        onOpenDetail: _openDetailSheet,
      ),
      WorkspaceDestination.settings => SettingsPage(
        controller: widget.controller,
      ),
      WorkspaceDestination.account => AccountPage(
        controller: widget.controller,
      ),
    };
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

        return Scaffold(
          backgroundColor: _background,
          body: Stack(
            children: [
              const Positioned(
                top: 100,
                left: -80,
                child: _GlowOrb(size: 220, color: Color(0x1A8C89FF)),
              ),
              const Positioned(
                right: -90,
                bottom: 220,
                child: _GlowOrb(size: 260, color: Color(0x143AB08F)),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _surface.withValues(alpha: 0.94),
                              border: Border.all(color: _stroke),
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
                      color: Colors.black.withValues(alpha: 0.12),
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
    final entries = <_WorkspaceEntry>[
      _WorkspaceEntry(
        destination: WorkspaceDestination.skills,
        subtitle: appText('技能包与依赖状态', 'Packages and dependency status'),
        iconColor: _blueLine,
        iconBackground: _blueSoft,
      ),
      _WorkspaceEntry(
        destination: WorkspaceDestination.nodes,
        subtitle: appText('边缘节点与实例', 'Edge nodes and instances'),
        iconColor: const Color(0xFF5CC9B7),
        iconBackground: const Color(0xFFDDF3EF),
      ),
      _WorkspaceEntry(
        destination: WorkspaceDestination.agents,
        subtitle: appText('代理运行态与配置', 'Agent state and configuration'),
        iconColor: _orangeLine,
        iconBackground: _orangeSoft,
      ),
      _WorkspaceEntry(
        destination: WorkspaceDestination.mcpServer,
        subtitle: appText('MCP 连接与工具注册', 'MCP endpoints and tools'),
        iconColor: const Color(0xFF5E7CE2),
        iconBackground: const Color(0xFFE1E8FB),
      ),
      _WorkspaceEntry(
        destination: WorkspaceDestination.clawHub,
        subtitle: appText('技能与模板市场', 'Marketplace and templates'),
        iconColor: const Color(0xFF845EC2),
        iconBackground: const Color(0xFFECE2FF),
      ),
      _WorkspaceEntry(
        destination: WorkspaceDestination.aiGateway,
        subtitle: appText('模型与代理网关', 'Models and agent gateway'),
        iconColor: const Color(0xFF6B5CF2),
        iconBackground: _accentSoft,
      ),
      _WorkspaceEntry(
        destination: WorkspaceDestination.account,
        subtitle: appText('身份、工作区与会话', 'Identity, workspace and sessions'),
        iconColor: _greenLine,
        iconBackground: _greenSoft,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 16, color: _textSecondary),
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
    final statusLabel = connection.status == RuntimeConnectionStatus.connected
        ? appText('会话已就绪', 'Session Ready')
        : appText('等待接入', 'Awaiting Connection');
    final statusColor = connection.status == RuntimeConnectionStatus.connected
        ? _greenLine
        : _textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _stroke, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            connection.remoteAddress ?? 'xworkmate.svc.plus',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            activeAgentName,
            style: const TextStyle(fontSize: 16, color: _textSecondary),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surfaceSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: _blueLine),
          const SizedBox(width: 8),
          Text(
            '$label · $value',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _stroke, width: 1.2),
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
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right_rounded, color: _textSecondary),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_accentStart, _accentEnd]),
        borderRadius: BorderRadius.circular(999),
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
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
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xF8FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _stroke),
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
                          ? _surfaceSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tab.icon,
                          size: 24,
                          color: currentTab == tab ? _blueLine : _textPrimary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tab.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: currentTab == tab ? _blueLine : _textPrimary,
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
