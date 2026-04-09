// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../app/ui_feature_manifest.dart';
import '../../app/workspace_page_registry.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_drawer.dart';
import 'mobile_gateway_pairing_guide_page.dart';
import 'mobile_shell_core.dart';
import 'mobile_shell_strip.dart';
import 'mobile_shell_sheet.dart';
import 'mobile_shell_nav.dart';

class MobileWorkspaceLauncherInternal extends StatelessWidget {
  const MobileWorkspaceLauncherInternal({
    super.key,
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
    final features = controller.featuresFor(UiFeaturePlatform.mobile);
    final entries =
        <WorkspaceEntryInternal>[
              WorkspaceEntryInternal(
                destination: WorkspaceDestination.skills,
                subtitle: appText('技能包与依赖状态', 'Packages and dependency status'),
                iconColor: palette.accent,
                iconBackground: palette.accentMuted,
              ),
              WorkspaceEntryInternal(
                destination: WorkspaceDestination.nodes,
                subtitle: appText('边缘节点与实例', 'Edge nodes and instances'),
                iconColor: tealLineInternal,
                iconBackground: tealSoftInternal,
              ),
              WorkspaceEntryInternal(
                destination: WorkspaceDestination.agents,
                subtitle: appText('代理运行态与配置', 'Agent state and configuration'),
                iconColor: palette.warning,
                iconBackground: palette.warning.withValues(alpha: 0.12),
              ),
              WorkspaceEntryInternal(
                destination: WorkspaceDestination.mcpServer,
                subtitle: appText('MCP 连接与工具注册', 'MCP endpoints and tools'),
                iconColor: palette.accent,
                iconBackground: palette.accentMuted,
              ),
              WorkspaceEntryInternal(
                destination: WorkspaceDestination.clawHub,
                subtitle: appText('技能与模板市场', 'Marketplace and templates'),
                iconColor: violetLineInternal,
                iconBackground: violetSoftInternal,
              ),
              WorkspaceEntryInternal(
                destination: WorkspaceDestination.aiGateway,
                subtitle: appText('模型与代理网关', 'Models and agent gateway'),
                iconColor: palette.accent,
                iconBackground: palette.accentMuted,
              ),
            ]
            .where(
              (entry) =>
                  features.allowedDestinations.contains(entry.destination),
            )
            .toList(growable: false);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LauncherHeaderInternal(
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
          WorkspaceHeroInternal(
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
                        child: WorkspaceShortcutCardInternal(
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

class WorkspaceEntryInternal {
  const WorkspaceEntryInternal({
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

class LauncherHeaderInternal extends StatelessWidget {
  const LauncherHeaderInternal({
    super.key,
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
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
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
            GradientActionButtonInternal(
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

class WorkspaceHeroInternal extends StatelessWidget {
  const WorkspaceHeroInternal({
    super.key,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.strokeSoft),
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
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
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
              HeroMetricInternal(
                label: appText('会话', 'Sessions'),
                value: '$sessionCount',
                icon: Icons.chat_bubble_outline_rounded,
              ),
              HeroMetricInternal(
                label: appText('运行任务', 'Running'),
                value: '$runningTaskCount',
                icon: Icons.play_circle_outline_rounded,
              ),
              HeroMetricInternal(
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

class HeroMetricInternal extends StatelessWidget {
  const HeroMetricInternal({
    super.key,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppRadius.card),
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

class WorkspaceShortcutCardInternal extends StatelessWidget {
  const WorkspaceShortcutCardInternal({
    super.key,
    required this.entry,
    required this.onTap,
  });

  final WorkspaceEntryInternal entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.surfacePrimary,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: entry.iconBackground,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Icon(
                  entry.destination.icon,
                  color: entry.iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.destination.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
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

class GradientActionButtonInternal extends StatelessWidget {
  const GradientActionButtonInternal({
    super.key,
    required this.label,
    required this.onPressed,
  });

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
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          minimumSize: const Size(0, AppSizes.buttonHeightMobile),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        ),
        child: Text(label),
      ),
    );
  }
}
