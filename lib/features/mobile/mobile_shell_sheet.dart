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
import 'mobile_shell_workspace.dart';
import 'mobile_shell_nav.dart';

class MobileSafeSheetInternal extends StatelessWidget {
  const MobileSafeSheetInternal({
    super.key,
    required this.controller,
    required this.onClose,
    required this.onOpenGatewayConnect,
  });

  final AppController controller;
  final VoidCallback onClose;
  final VoidCallback onOpenGatewayConnect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('mobile-safe-sheet'),
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: palette.surfacePrimary.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(AppRadius.dialog + 2),
          border: Border.all(color: palette.strokeSoft),
          boxShadow: [palette.chromeShadowAmbient],
        ),
        child: SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final theme = Theme.of(context);
              final connection = controller.connection;
              final devices = controller.devices;
              final hasPendingRun =
                  controller.hasAssistantPendingRun ||
                  controller.activeRunId != null;
              final securePathLabel = mobileSecurePathLabelInternal(
                profile: controller.settings.primaryGatewayProfile,
                connection: connection,
              );
              final localDeviceLabel =
                  connection.deviceId ?? appText('未初始化', 'Not initialized');
              final devicesError = controller.devicesController.error;

              Future<void> handleConnect() async {
                if (controller.canQuickConnectGateway) {
                  await controller.connectSavedGateway();
                  await controller.refreshDevices(quiet: true);
                  return;
                }
                onOpenGatewayConnect();
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
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
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: palette.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                appText(
                                  '移动端只提供结构化审批、配对管理和运行保护动作，不暴露全局 shell 放权。',
                                  'Mobile only exposes structured approvals, pairing controls, and run-safe actions. No global shell approvals.',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    MobileSafeSectionInternal(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appText('安全直连', 'Secure Direct'),
                            style: theme.textTheme.titleLarge,
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
                                icon: Icons.monitor_heart_outlined,
                                label: connection.status.label,
                                color:
                                    connection.status ==
                                        RuntimeConnectionStatus.connected
                                    ? palette.success
                                    : palette.textSecondary,
                                background:
                                    connection.status ==
                                        RuntimeConnectionStatus.connected
                                    ? palette.success.withValues(alpha: 0.14)
                                    : palette.surfaceSecondary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            mobileTargetLabelInternal(controller),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            appText(
                              '本机设备 ID：$localDeviceLabel',
                              'Local device ID: $localDeviceLabel',
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (controller.runtime.isConnected) ...[
                                OutlinedButton(
                                  onPressed: () async {
                                    await controller.refreshGatewayHealth();
                                    await controller.refreshDevices(
                                      quiet: true,
                                    );
                                  },
                                  child: Text(appText('刷新', 'Refresh')),
                                ),
                                OutlinedButton(
                                  onPressed: controller.disconnectGateway,
                                  child: Text(appText('断开', 'Disconnect')),
                                ),
                              ] else
                                FilledButton(
                                  key: const ValueKey(
                                    'mobile-safe-sheet-connect-button',
                                  ),
                                  onPressed: () => unawaited(handleConnect()),
                                  child: Text(
                                    controller.canQuickConnectGateway
                                        ? appText('快速连接', 'Quick Connect')
                                        : appText('配对网关', 'Pair Gateway'),
                                  ),
                                ),
                              if (hasPendingRun)
                                FilledButton.tonal(
                                  onPressed: controller.abortRun,
                                  child: Text(appText('停止运行', 'Stop Run')),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (connection.pairingRequired) ...[
                      const SizedBox(height: 12),
                      MobileSafetyNoticeInternal(
                        tone: palette.warning.withValues(alpha: 0.12),
                        borderColor: palette.warning.withValues(alpha: 0.32),
                        icon: Icons.approval_outlined,
                        title: appText('需要设备审批', 'Pairing Required'),
                        message: appText(
                          '当前设备已经向 Gateway 发起配对。请在已授权的 operator 设备上审批，然后重新连接。',
                          'This device already requested pairing. Approve it from an authorized operator device, then reconnect.',
                        ),
                      ),
                    ] else if (connection.gatewayTokenMissing) ...[
                      const SizedBox(height: 12),
                      MobileSafetyNoticeInternal(
                        tone: palette.danger.withValues(alpha: 0.1),
                        borderColor: palette.danger.withValues(alpha: 0.2),
                        icon: Icons.key_off_outlined,
                        title: appText('缺少共享 Token', 'Shared Token Missing'),
                        message: appText(
                          '首次连接需要共享 Token；配对完成后可继续使用 device token。',
                          'The first connection needs a shared token; after pairing, the device token can continue.',
                        ),
                      ),
                    ],
                    if ((devicesError ?? '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      MobileSafetyNoticeInternal(
                        tone: palette.danger.withValues(alpha: 0.1),
                        borderColor: palette.danger.withValues(alpha: 0.2),
                        icon: Icons.error_outline_rounded,
                        title: appText('设备列表错误', 'Devices Error'),
                        message: devicesError!,
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      appText('待审批请求', 'Pending Requests'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (!controller.runtime.isConnected)
                      Text(
                        appText(
                          '恢复 xworkmate-bridge 连接后加载待审批设备与已配对设备。',
                          'Pending and paired devices load again after xworkmate-bridge reconnects.',
                        ),
                        style: theme.textTheme.bodyMedium,
                      )
                    else if (devices.pending.isEmpty)
                      Text(
                        appText('当前没有待审批设备。', 'No pending pairing requests.'),
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      Column(
                        key: const ValueKey('mobile-safe-pending-section'),
                        children: devices.pending
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: MobilePendingApprovalCardInternal(
                                  controller: controller,
                                  item: item,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      appText('已配对设备', 'Paired Devices'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (!controller.runtime.isConnected)
                      Text(
                        appText(
                          '恢复 xworkmate-bridge 连接后可查看 paired device，并在移动端直接吊销。',
                          'Paired devices are visible again after xworkmate-bridge reconnects, and can be revoked from mobile.',
                        ),
                        style: theme.textTheme.bodyMedium,
                      )
                    else if (devices.paired.isEmpty)
                      Text(
                        appText('当前没有已配对设备。', 'No paired devices yet.'),
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      Column(
                        key: const ValueKey('mobile-safe-paired-section'),
                        children: devices.paired
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: MobilePairedDeviceCardInternal(
                                  controller: controller,
                                  item: item,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class MobileSafeSectionInternal extends StatelessWidget {
  const MobileSafeSectionInternal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: child,
    );
  }
}

class MobileFactChipInternal extends StatelessWidget {
  const MobileFactChipInternal({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class MobileSafetyNoticeInternal extends StatelessWidget {
  const MobileSafetyNoticeInternal({
    super.key,
    required this.tone,
    required this.borderColor,
    required this.icon,
    required this.title,
    required this.message,
  });

  final Color tone;
  final Color borderColor;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.textPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MobilePendingApprovalCardInternal extends StatelessWidget {
  const MobilePendingApprovalCardInternal({
    super.key,
    required this.controller,
    required this.item,
  });

  final AppController controller;
  final GatewayPendingDevice item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final metadata = <String>[
      if ((item.role ?? '').isNotEmpty) 'role: ${item.role}',
      if (item.scopes.isNotEmpty) item.scopes.join(', '),
      if ((item.remoteIp ?? '').isNotEmpty) item.remoteIp!,
      mobileRelativeTimeInternal(item.requestedAtMs),
      if (item.isRepair) appText('修复请求', 'repair'),
    ];

    return MobileSafeSectionInternal(
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
                    Text(item.label, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      item.deviceId,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (item.isRepair)
                MobileFactChipInternal(
                  icon: Icons.build_circle_outlined,
                  label: appText('修复', 'Repair'),
                  color: palette.warning,
                  background: palette.warning.withValues(alpha: 0.12),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            metadata.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () =>
                    controller.approveDevicePairing(item.requestId),
                child: Text(appText('批准配对', 'Approve Pairing')),
              ),
              OutlinedButton(
                onPressed: () async {
                  final confirmed = await confirmMobileActionInternal(
                    context,
                    title: appText('拒绝配对请求', 'Reject Pairing Request'),
                    message: appText(
                      '确定拒绝 ${item.label} 的配对请求吗？',
                      'Reject the pairing request from ${item.label}?',
                    ),
                  );
                  if (confirmed == true) {
                    await controller.rejectDevicePairing(item.requestId);
                  }
                },
                child: Text(appText('拒绝配对', 'Reject Pairing')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MobilePairedDeviceCardInternal extends StatelessWidget {
  const MobilePairedDeviceCardInternal({
    super.key,
    required this.controller,
    required this.item,
  });

  final AppController controller;
  final GatewayPairedDevice item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final metadata = <String>[
      if (item.roles.isNotEmpty) 'roles: ${item.roles.join(', ')}',
      if (item.scopes.isNotEmpty) 'scopes: ${item.scopes.join(', ')}',
      if ((item.remoteIp ?? '').isNotEmpty) item.remoteIp!,
      if (item.currentDevice) appText('当前设备', 'current device'),
    ];

    return MobileSafeSectionInternal(
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
                    Text(item.label, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      item.deviceId,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (item.currentDevice)
                MobileFactChipInternal(
                  icon: Icons.smartphone_outlined,
                  label: appText('当前设备', 'Current'),
                  color: palette.success,
                  background: palette.success.withValues(alpha: 0.12),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            metadata.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          if (item.tokens.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              appText(
                '角色令牌：${item.tokens.first.role}',
                'Role token: ${item.tokens.first.role}',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () async {
              final confirmed = await confirmMobileActionInternal(
                context,
                title: appText('吊销已配对设备', 'Revoke Paired Device'),
                message: appText(
                  '确定吊销 ${item.label} 吗？该设备之后需要重新配对。',
                  'Revoke ${item.label}? The device will need pairing again.',
                ),
              );
              if (confirmed == true) {
                await controller.removePairedDevice(item.deviceId);
              }
            },
            child: Text(appText('吊销设备', 'Revoke Device')),
          ),
        ],
      ),
    );
  }
}

Future<bool?> confirmMobileActionInternal(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(appText('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(appText('确认', 'Confirm')),
          ),
        ],
      );
    },
  );
}

String mobileSecurePathLabelInternal({
  required GatewayConnectionProfile profile,
  required GatewayConnectionSnapshot connection,
}) {
  final mode = connection.mode == RuntimeConnectionMode.unconfigured
      ? profile.mode
      : connection.mode;
  return switch (mode) {
    RuntimeConnectionMode.remote =>
      profile.tls
          ? appText('Secure Direct TLS', 'Secure Direct TLS')
          : appText('Remote Non-TLS', 'Remote Non-TLS'),
    RuntimeConnectionMode.unconfigured => appText(
      'Gateway 未配置',
      'Gateway Not Configured',
    ),
  };
}

String mobileTargetLabelInternal(AppController controller) {
  final connection = controller.connection;
  if ((connection.remoteAddress ?? '').isNotEmpty) {
    return connection.remoteAddress!;
  }
  final profile = controller.settings.primaryGatewayProfile;
  final host = profile.host.trim();
  if (host.isNotEmpty && profile.port > 0) {
    return '$host:${profile.port}';
  }
  return appText('未连接目标', 'No target');
}

String mobileRelativeTimeInternal(int? timestampMs) {
  if (timestampMs == null || timestampMs <= 0) {
    return appText('刚刚', 'just now');
  }
  final delta = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(timestampMs),
  );
  if (delta.inMinutes < 1) {
    return appText('刚刚', 'just now');
  }
  if (delta.inHours < 1) {
    return appText('${delta.inMinutes} 分钟前', '${delta.inMinutes}m ago');
  }
  if (delta.inDays < 1) {
    return appText('${delta.inHours} 小时前', '${delta.inHours}h ago');
  }
  return appText('${delta.inDays} 天前', '${delta.inDays}d ago');
}
