// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/app_store_policy.dart';
import '../../app/ui_feature_manifest.dart';
import '../../app/workspace_navigation.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/gateway_runtime.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import 'codex_integration_card.dart';
import 'skill_directory_authorization_card.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';
import 'settings_page_core.dart';
import 'settings_page_sections.dart';
import 'settings_page_gateway.dart';
import 'settings_page_gateway_connection.dart';
import 'settings_page_gateway_llm.dart';
import 'settings_page_presentation.dart';
import 'settings_page_multi_agent.dart';
import 'settings_page_support.dart';
import 'settings_page_widgets.dart';

extension SettingsPageDeviceMixinInternal on SettingsPageStateInternal {
  Widget buildDeviceSecurityCardInternal(
    BuildContext context,
    AppController controller,
  ) {
    final theme = Theme.of(context);
    final connection = controller.connection;
    final devices = controller.devices;
    final pending = devices.pending;
    final paired = devices.paired;
    final authScopes = connection.authScopes.isEmpty
        ? appText('未协商', 'Not negotiated')
        : connection.authScopes.join(', ');
    return SurfaceCard(
      key: const ValueKey('gateway-device-security-card'),
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
                      appText('设备配对与角色令牌', 'Device Pairing & Role Tokens'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      appText(
                        '对齐 OpenClaw 的 Devices 安全机制，处理 pairing requests 和按角色下发的 device token。',
                        'Match OpenClaw device security: pairing requests and per-role device tokens.',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: controller.runtime.isConnected
                    ? () => controller.refreshDevices()
                    : null,
                child: Text(appText('刷新', 'Refresh')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          InfoRowInternal(
            label: appText('本机 Device ID', 'Local Device ID'),
            value: connection.deviceId ?? appText('未初始化', 'Not initialized'),
          ),
          InfoRowInternal(
            label: appText('当前角色', 'Current Role'),
            value: connection.authRole ?? 'operator',
          ),
          InfoRowInternal(
            label: appText('授权范围', 'Granted Scopes'),
            value: authScopes,
          ),
          if (connection.pairingRequired) ...[
            const SizedBox(height: 8),
            buildNoticeInternal(
              context,
              tone: theme.colorScheme.tertiaryContainer,
              title: appText('需要设备审批', 'Pairing Required'),
              message: appText(
                '当前设备已经向 Gateway 发起配对。请在已授权的 operator 设备上审批该请求，然后重新连接。',
                'This device has requested pairing. Approve it from an authorized operator device, then reconnect.',
              ),
            ),
          ] else if (connection.gatewayTokenMissing) ...[
            const SizedBox(height: 8),
            buildNoticeInternal(
              context,
              tone: theme.colorScheme.errorContainer,
              title: appText('缺少共享 Token', 'Shared Token Missing'),
              message: appText(
                '当前连接没有通过共享 token 或已配对 device token 完成鉴权。先输入共享 Token 建立首次配对，后续可切换为 device token。',
                'The current connection is missing shared-token or paired device-token auth. Use a shared token for the first pairing, then continue with the device token.',
              ),
            ),
          ],
          if ((controller.devicesController.error ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            buildNoticeInternal(
              context,
              tone: theme.colorScheme.errorContainer,
              title: appText('设备列表错误', 'Devices Error'),
              message: controller.devicesController.error!,
            ),
          ],
          const SizedBox(height: 16),
          if (!controller.runtime.isConnected) ...[
            Text(
              appText(
                '连接 Gateway 后，这里会显示待审批设备、已配对设备和角色令牌。',
                'Connect the gateway to load pending devices, paired devices, and role tokens.',
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ] else ...[
            Text(
              appText('待审批请求', 'Pending Requests'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (pending.isEmpty)
              Text(
                appText('当前没有待审批设备。', 'No pending pairing requests.'),
                style: theme.textTheme.bodyMedium,
              )
            else
              ...pending.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: buildPendingDeviceCardInternal(
                    context,
                    controller,
                    item,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Text(
              appText('已配对设备', 'Paired Devices'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (paired.isEmpty)
              Text(
                appText('当前没有已配对设备。', 'No paired devices yet.'),
                style: theme.textTheme.bodyMedium,
              )
            else
              ...paired.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: buildPairedDeviceCardInternal(
                    context,
                    controller,
                    item,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget buildPendingDeviceCardInternal(
    BuildContext context,
    AppController controller,
    GatewayPendingDevice item,
  ) {
    final theme = Theme.of(context);
    final metadata = <String>[
      if ((item.role ?? '').isNotEmpty) 'role: ${item.role}',
      if (item.scopes.isNotEmpty) item.scopes.join(', '),
      if ((item.remoteIp ?? '').isNotEmpty) item.remoteIp!,
      relativeTimeInternal(item.requestedAtMs),
      if (item.isRepair) appText('修复请求', 'repair'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  SelectableText(
                    item.deviceId,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(metadata.join(' · '), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () =>
                      controller.approveDevicePairing(item.requestId),
                  child: Text(appText('批准', 'Approve')),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final confirmed = await confirmDeviceActionInternal(
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
                  child: Text(appText('拒绝', 'Reject')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildPairedDeviceCardInternal(
    BuildContext context,
    AppController controller,
    GatewayPairedDevice item,
  ) {
    final theme = Theme.of(context);
    final meta = <String>[
      if (item.roles.isNotEmpty) 'roles: ${item.roles.join(', ')}',
      if (item.scopes.isNotEmpty) 'scopes: ${item.scopes.join(', ')}',
      if ((item.remoteIp ?? '').isNotEmpty) item.remoteIp!,
      if (item.currentDevice) appText('当前设备', 'current device'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                      Text(item.label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      SelectableText(
                        item.deviceId,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(meta.join(' · '), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () async {
                    final confirmed = await confirmDeviceActionInternal(
                      context,
                      title: appText('移除已配对设备', 'Remove Paired Device'),
                      message: appText(
                        '确定移除 ${item.label} 吗？这会使该设备需要重新配对。',
                        'Remove ${item.label}? The device will need pairing again.',
                      ),
                    );
                    if (confirmed == true) {
                      await controller.removePairedDevice(item.deviceId);
                    }
                  },
                  child: Text(appText('移除', 'Remove')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (item.tokens.isEmpty)
              Text(
                appText('当前没有角色令牌。', 'No role tokens.'),
                style: theme.textTheme.bodySmall,
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: buildTokenRowInternal(
                  context,
                  controller,
                  item,
                  latestDeviceTokenInternal(item.tokens),
                ),
              ),
          ],
        ),
      ),
    );
  }

  GatewayDeviceTokenSummary latestDeviceTokenInternal(
    List<GatewayDeviceTokenSummary> tokens,
  ) {
    final sorted = List<GatewayDeviceTokenSummary>.from(tokens)
      ..sort((left, right) {
        final rightTime = deviceTokenStatusTimeInternal(right);
        final leftTime = deviceTokenStatusTimeInternal(left);
        return rightTime.compareTo(leftTime);
      });
    return sorted.first;
  }

  int deviceTokenStatusTimeInternal(GatewayDeviceTokenSummary token) {
    return token.lastUsedAtMs ??
        token.rotatedAtMs ??
        token.revokedAtMs ??
        token.createdAtMs ??
        0;
  }

  Widget buildTokenRowInternal(
    BuildContext context,
    AppController controller,
    GatewayPairedDevice device,
    GatewayDeviceTokenSummary token,
  ) {
    final theme = Theme.of(context);
    final details = <String>[
      token.revoked ? appText('已撤销', 'revoked') : appText('有效', 'active'),
      if (token.scopes.isNotEmpty) token.scopes.join(', '),
      relativeTimeInternal(deviceTokenStatusTimeInternal(token)),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(token.role, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(details.join(' · '), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () async {
                    final nextToken = await controller.rotateDeviceRoleToken(
                      deviceId: device.deviceId,
                      role: token.role,
                      scopes: token.scopes,
                    );
                    if (!context.mounted ||
                        nextToken == null ||
                        nextToken.isEmpty) {
                      return;
                    }
                    await showRotatedTokenDialogInternal(
                      context,
                      device: device,
                      role: token.role,
                      token: nextToken,
                    );
                  },
                  child: Text(appText('轮换', 'Rotate')),
                ),
                if (!token.revoked)
                  OutlinedButton(
                    onPressed: () async {
                      final confirmed = await confirmDeviceActionInternal(
                        context,
                        title: appText('撤销角色令牌', 'Revoke Role Token'),
                        message: appText(
                          '确定撤销 ${device.label} 的 ${token.role} 令牌吗？',
                          'Revoke the ${token.role} token for ${device.label}?',
                        ),
                      );
                      if (confirmed == true) {
                        await controller.revokeDeviceRoleToken(
                          deviceId: device.deviceId,
                          role: token.role,
                        );
                      }
                    },
                    child: Text(appText('撤销', 'Revoke')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildNoticeInternal(
    BuildContext context, {
    required Color tone,
    required String title,
    required String message,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          SelectableText(message, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Future<bool?> confirmDeviceActionInternal(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appText('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(appText('确认', 'Confirm')),
          ),
        ],
      ),
    );
  }

  Future<void> showClearAssistantLocalStateDialogInternal(
    BuildContext context,
    AppController controller,
  ) {
    var confirmed = false;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(appText('清理本地数据', 'Clear Local Data')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appText(
                  '该操作会删除本机保存的 Assistant 任务线程会话、本地设置快照和恢复备份，且无法撤销。',
                  'This deletes locally stored Assistant threads, settings snapshots, and recovery backups. This cannot be undone.',
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const ValueKey('assistant-local-state-clear-confirm'),
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                onChanged: (value) {
                  setDialogState(() {
                    confirmed = value ?? false;
                  });
                },
                title: Text(
                  appText(
                    '我确认删除本机任务线程会话和本地配置',
                    'I confirm deleting local threads and settings',
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(appText('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: !confirmed
                  ? null
                  : () async {
                      await controller.clearAssistantLocalState();
                      if (!dialogContext.mounted) {
                        return;
                      }
                      Navigator.of(dialogContext).pop();
                    },
              child: Text(appText('确认清理', 'Confirm Clear')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showRotatedTokenDialogInternal(
    BuildContext context, {
    required GatewayPairedDevice device,
    required String role,
    required String token,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText('新的角色令牌', 'New Role Token')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText(
                '${device.label} 的 $role 令牌已轮换，请立即安全保存。',
                'Rotated the $role token for ${device.label}. Store it securely now.',
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(token),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appText('关闭', 'Close')),
          ),
        ],
      ),
    );
  }

  String relativeTimeInternal(int? timestampMs) {
    if (timestampMs == null || timestampMs <= 0) {
      return appText('时间未知', 'time unknown');
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
}
