import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';

class MobileAssistantConversation extends StatelessWidget {
  const MobileAssistantConversation({
    super.key,
    required this.controller,
    required this.messages,
    required this.scrollController,
    required this.onConnectBridge,
    required this.onFocusComposer,
  });

  final AppController controller;
  final List<GatewayChatMessage> messages;
  final ScrollController scrollController;
  final VoidCallback onConnectBridge;
  final VoidCallback onFocusComposer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (messages.isEmpty) {
      return MobileAssistantEmptyState(
        controller: controller,
        onConnectBridge: onConnectBridge,
        onFocusComposer: onFocusComposer,
      );
    }

    return ListView.separated(
      key: const Key('mobile-assistant-conversation-list'),
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      itemCount: messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final message = messages[index];
        final role = message.role.toLowerCase();
        final isUser = role == 'user';
        final label = message.toolName?.trim().isNotEmpty == true
            ? message.toolName!.trim()
            : isUser
            ? appText('你', 'You')
            : 'XWorkmate';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isUser ? palette.accent : palette.surfacePrimary,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: isUser
                      ? palette.accent.withValues(alpha: 0.08)
                      : palette.strokeSoft,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isUser
                            ? Colors.white.withValues(alpha: 0.82)
                            : palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message.text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isUser ? Colors.white : palette.textPrimary,
                      ),
                    ),
                    if (message.pending || message.error) ...[
                      const SizedBox(height: 6),
                      Text(
                        message.pending
                            ? appText('运行中', 'Running')
                            : appText('失败', 'Failed'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: message.error
                              ? palette.danger
                              : palette.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class MobileAssistantEmptyState extends StatelessWidget {
  const MobileAssistantEmptyState({
    super.key,
    required this.controller,
    required this.onConnectBridge,
    required this.onFocusComposer,
  });

  final AppController controller;
  final VoidCallback onConnectBridge;
  final VoidCallback onFocusComposer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final connection = controller.currentAssistantConnectionState;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              connection.connected
                  ? Icons.chat_bubble_outline_rounded
                  : Icons.cloud_off_rounded,
              size: 34,
              color: connection.connected ? palette.accent : palette.warning,
            ),
            const SizedBox(height: 12),
            Text(
              connection.connected
                  ? appText('开始一个移动任务', 'Start a Mobile Task')
                  : appText('先连接 Bridge', 'Connect Bridge First'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              connection.connected
                  ? appText(
                      '输入需求后直接提交，Provider、权限和推理强度从底部操作区调整。',
                      'Type a request and submit. Provider, permissions, and reasoning live in the bottom controls.',
                    )
                  : connection.detailLabel,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: connection.connected
                  ? onFocusComposer
                  : onConnectBridge,
              icon: Icon(
                connection.connected ? Icons.edit_rounded : Icons.link_rounded,
              ),
              label: Text(
                connection.connected
                    ? appText('输入任务', 'Write Task')
                    : appText('连接 Bridge', 'Connect Bridge'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
