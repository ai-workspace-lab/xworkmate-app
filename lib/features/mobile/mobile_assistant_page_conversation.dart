import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import 'mobile_builtin_plugin_scenes.dart';
import '../plugins/builtin_plugin_visuals.dart';

class MobileAssistantConversation extends StatelessWidget {
  const MobileAssistantConversation({
    super.key,
    required this.controller,
    required this.messages,
    required this.scrollController,
    required this.onConnectBridge,
    required this.onSelectPluginScene,
  });

  final AppController controller;
  final List<GatewayChatMessage> messages;
  final ScrollController scrollController;
  final VoidCallback onConnectBridge;
  final ValueChanged<String> onSelectPluginScene;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return MobileAssistantEmptyState(
        controller: controller,
        onConnectBridge: onConnectBridge,
        onSelectPluginScene: onSelectPluginScene,
      );
    }

    final showSyntheticRunCard =
        (controller.hasAssistantPendingRun || controller.activeRunId != null) &&
        !messages.any((m) => m.pending);
    final itemCount = messages.length + (showSyntheticRunCard ? 1 : 0);

    return ListView.separated(
      key: const Key('mobile-assistant-conversation-list'),
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemBuilder: (context, index) {
        if (index >= messages.length) {
          return const _MobileExecutionProgressCard();
        }

        final message = messages[index];
        final role = message.role.toLowerCase();
        final isUser = role == 'user';

        if (isUser) {
          return _MobileUserMessageBubble(message: message);
        }

        return _MobileAssistantMessageCard(message: message);
      },
    );
  }
}

class _MobileUserMessageBubble extends StatelessWidget {
  const _MobileUserMessageBubble({required this.message});

  final GatewayChatMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 286),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.accentMuted,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  message.text,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.textPrimary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatMessageTime(message.timestampMs),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileAssistantMessageCard extends StatelessWidget {
  const _MobileAssistantMessageCard({required this.message});

  final GatewayChatMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final label = message.toolName?.trim().isNotEmpty == true
        ? message.toolName!.trim()
        : 'XWorkmate';
    final statusLabel = message.error
        ? appText('需要处理', 'Needs attention')
        : message.pending
        ? appText('执行中', 'Running')
        : appText('已完成', 'Done');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.accent,
            shape: BoxShape.circle,
          ),
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Text(
                'X',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MobileStatusPill(
                    label: statusLabel,
                    color: message.error ? palette.danger : palette.accent,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                message.text,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: palette.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _MobileExecutionTimeline(
                running: message.pending,
                failed: message.error,
              ),
              const SizedBox(height: 18),
              _MobileBridgeInlineStatus(connected: !message.error),
              const SizedBox(height: 18),
              _MobileGeneratedArtifactCard(),
              const SizedBox(height: 12),
              _MobileLogButton(),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileExecutionProgressCard extends StatelessWidget {
  const _MobileExecutionProgressCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfacePrimary.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: palette.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                appText(
                  '正在生成中...你可以随时查看日志或取消任务。',
                  'Generating... you can view logs or cancel anytime.',
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MobileAssistantEmptyState extends StatelessWidget {
  const MobileAssistantEmptyState({
    super.key,
    required this.controller,
    required this.onConnectBridge,
    required this.onSelectPluginScene,
  });

  final AppController controller;
  final VoidCallback onConnectBridge;
  final ValueChanged<String> onSelectPluginScene;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final connection = controller.currentAssistantConnectionState;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _MobileBridgeHeroStatus(
                  connected: connection.connected,
                  detail: connection.connected
                      ? appText('在线 · 随时为你执行任务', 'Online · ready to run')
                      : appText('先去配置集成连接', 'Configure integration first'),
                ),
                const SizedBox(height: 30),
                Text(
                  appText('你想先用哪个插件场景？', 'Which plugin scene do you want?'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  connection.connected
                      ? appText(
                          '点一下场景卡，我会把对应任务填进输入框。',
                          'Tap a scene card and I will prefill the task prompt.',
                        )
                      : connection.detailLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 26),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 10.0;
                    final columns = constraints.maxWidth >= 220 ? 2 : 1;
                    final cardWidth =
                        (constraints.maxWidth - (spacing * (columns - 1))) /
                        columns;
                    return Wrap(
                      alignment: WrapAlignment.center,
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (final scene in mobileBuiltinPluginScenes)
                          SizedBox(
                            width: cardWidth,
                            child: _MobilePluginSceneChip(
                              key: ValueKey(
                                'mobile-plugin-scene-${scene.plugin.id}',
                              ),
                              scene: scene,
                              connected: connection.connected,
                              onTap: () {
                                if (!connection.connected) {
                                  onConnectBridge();
                                  return;
                                }
                                onSelectPluginScene(scene.prefillPrompt);
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
                if (!connection.connected) ...[
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    key: const Key('mobile-assistant-connect-bridge-button'),
                    onPressed: onConnectBridge,
                    icon: const Icon(Icons.settings_input_component_rounded),
                    label: Text(appText('去配置集成', 'Configure integration')),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MobileBridgeHeroStatus extends StatelessWidget {
  const _MobileBridgeHeroStatus({
    required this.connected,
    required this.detail,
  });

  final bool connected;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surfacePrimary,
                shape: BoxShape.circle,
                border: Border.all(color: palette.accent, width: 1.4),
              ),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Icon(
                  connected ? Icons.hub_outlined : Icons.link_off_rounded,
                  color: connected ? palette.accent : palette.warning,
                  size: 30,
                ),
              ),
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: connected ? palette.success : palette.warning,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.canvas, width: 3),
                ),
                child: const SizedBox(width: 17, height: 17),
              ),
            ),
          ],
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                connected
                    ? appText('AI Workspace 已连接', 'AI Workspace Connected')
                    : appText('先配置集成连接', 'Configure Integration First'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobilePluginSceneChip extends StatelessWidget {
  const _MobilePluginSceneChip({
    super.key,
    required this.scene,
    required this.connected,
    required this.onTap,
  });

  final MobileBuiltinPluginSceneSpec scene;
  final bool connected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surfacePrimary.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: connected
                  ? palette.accent.withValues(alpha: 0.34)
                  : palette.strokeSoft,
            ),
            boxShadow: [palette.chromeShadowAmbient],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BuiltinPluginIconTile(plugin: scene.plugin, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scene.sceneLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        scene.plugin.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                          height: 1.32,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final format in scene.plugin.outputFormats.take(
                            2,
                          ))
                            _MobilePluginFormatTag(label: format.toUpperCase()),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobilePluginFormatTag extends StatelessWidget {
  const _MobilePluginFormatTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: palette.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MobileStatusPill extends StatelessWidget {
  const _MobileStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MobileExecutionTimeline extends StatelessWidget {
  const _MobileExecutionTimeline({required this.running, required this.failed});

  final bool running;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final steps = [
      _TimelineStep(appText('归档任务', 'Archive task'), true),
      _TimelineStep(appText('AI 工作空间', 'AI workspace'), running),
      _TimelineStep(appText('运行日志', 'Run logs'), !running && !failed),
      _TimelineStep(appText('完成', 'Complete'), !running && !failed),
    ];
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appText('执行进度', 'Progress'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < steps.length; i++)
          _MobileTimelineRow(
            step: steps[i],
            isLast: i == steps.length - 1,
            running: running && i == 1,
          ),
      ],
    );
  }
}

class _TimelineStep {
  const _TimelineStep(this.label, this.done);

  final String label;
  final bool done;
}

class _MobileTimelineRow extends StatelessWidget {
  const _MobileTimelineRow({
    required this.step,
    required this.isLast,
    required this.running,
  });

  final _TimelineStep step;
  final bool isLast;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final active = step.done || running;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: step.done ? palette.accent : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? palette.accent : palette.textMuted,
                  width: 1.6,
                ),
              ),
              child: SizedBox(
                width: 22,
                height: 22,
                child: step.done
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 15,
                      )
                    : running
                    ? Padding(
                        padding: const EdgeInsets.all(4),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.accent,
                        ),
                      )
                    : null,
              ),
            ),
            if (!isLast)
              Container(
                width: 1.4,
                height: 34,
                color: active ? palette.accent : palette.stroke,
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              step.label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: active ? palette.textPrimary : palette.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileBridgeInlineStatus extends StatelessWidget {
  const _MobileBridgeInlineStatus({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              connected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              color: connected ? palette.accent : palette.warning,
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              connected
                  ? appText(
                      '在线 · AI Workspace 连接正常',
                      'Online · AI Workspace healthy',
                    )
                  : appText(
                      'AI Workspace 需要检查',
                      'AI Workspace needs attention',
                    ),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileGeneratedArtifactCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  Icons.insert_chart_outlined_rounded,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appText('任务结果.md', 'Task result.md'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    appText('已生成 · 等待确认', 'Generated · awaiting review'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _MobileLogButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.list_rounded, color: palette.textSecondary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                appText('查看运行日志', 'View run logs'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }
}

String _formatMessageTime(double? timestampMs) {
  if (timestampMs == null) {
    return '';
  }
  final date = DateTime.fromMillisecondsSinceEpoch(timestampMs.round());
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
