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
import 'mobile_shell_sheet.dart';
import 'mobile_shell_nav.dart';

class MobileSafeStripInternal extends StatelessWidget {
  const MobileSafeStripInternal({
    super.key,
    required this.controller,
    required this.onOpenSafeSheet,
    required this.onOpenGatewayConnect,
  });

  final AppController controller;
  final VoidCallback onOpenSafeSheet;
  final VoidCallback onOpenGatewayConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final connection = controller.connection;
    final devices = controller.devices;
    final hasPendingRun =
        controller.hasAssistantPendingRun || controller.activeRunId != null;
    final securePathLabel = mobileSecurePathLabelInternal(
      profile: controller.settings.primaryGatewayProfile,
      connection: connection,
    );

    Future<void> handlePrimaryConnect() async {
      if (controller.canQuickConnectGateway) {
        await controller.connectSavedGateway();
        await controller.refreshDevices(quiet: true);
        return;
      }
      onOpenGatewayConnect();
    }

    return Container(
      key: const ValueKey('mobile-safe-strip'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: palette.surfacePrimary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.dialog),
        border: Border.all(color: palette.strokeSoft),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mobile-safe',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appText(
                        '结构化审批、配对和安全运行入口',
                        'Structured approvals, pairing, and run-safe controls',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              MobileFactChipInternal(
                icon: connection.status == RuntimeConnectionStatus.connected
                    ? Icons.verified_outlined
                    : Icons.shield_outlined,
                label: connection.status.label,
                color: connection.status == RuntimeConnectionStatus.connected
                    ? palette.success
                    : palette.textSecondary,
                background:
                    connection.status == RuntimeConnectionStatus.connected
                    ? palette.success.withValues(alpha: 0.14)
                    : palette.surfaceSecondary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MobileFactChipInternal(
                icon: Icons.lock_outline_rounded,
                label: securePathLabel,
                color: palette.accent,
                background: palette.accentMuted,
              ),
              MobileFactChipInternal(
                icon: Icons.computer_outlined,
                label: mobileTargetLabelInternal(controller),
                color: palette.textPrimary,
                background: palette.surfaceSecondary,
              ),
              if (devices.pending.isNotEmpty)
                MobileFactChipInternal(
                  icon: Icons.approval_outlined,
                  label: appText(
                    '${devices.pending.length} 个待审批',
                    '${devices.pending.length} pending',
                  ),
                  color: palette.warning,
                  background: palette.warning.withValues(alpha: 0.12),
                ),
              if (devices.paired.isNotEmpty)
                MobileFactChipInternal(
                  icon: Icons.devices_outlined,
                  label: appText(
                    '${devices.paired.length} 台已配对',
                    '${devices.paired.length} paired',
                  ),
                  color: palette.success,
                  background: palette.success.withValues(alpha: 0.12),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                key: const ValueKey('mobile-safe-open-button'),
                onPressed: onOpenSafeSheet,
                child: Text(appText('安全审批', 'Mobile-safe')),
              ),
              if (controller.runtime.isConnected)
                OutlinedButton(
                  key: const ValueKey('mobile-safe-refresh-button'),
                  onPressed: () async {
                    await controller.refreshGatewayHealth();
                    await controller.refreshDevices(quiet: true);
                  },
                  child: Text(appText('刷新', 'Refresh')),
                )
              else
                FilledButton(
                  key: const ValueKey('mobile-safe-connect-button'),
                  onPressed: () => unawaited(handlePrimaryConnect()),
                  child: Text(
                    controller.canQuickConnectGateway
                        ? appText('快速连接', 'Quick Connect')
                        : appText('配对网关', 'Pair Gateway'),
                  ),
                ),
              if (hasPendingRun)
                OutlinedButton(
                  key: const ValueKey('mobile-safe-stop-run-button'),
                  onPressed: controller.abortRun,
                  child: Text(appText('停止运行', 'Stop Run')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
