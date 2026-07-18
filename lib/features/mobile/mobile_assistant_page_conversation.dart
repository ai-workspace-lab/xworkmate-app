import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';
import '../../runtime/assistant_artifacts.dart';
import '../../theme/app_palette.dart';
import '../../widgets/assistant_task_progress_bar.dart';
import 'mobile_builtin_plugin_scenes.dart';

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
      itemCount: itemCount + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemBuilder: (context, index) {
        if (index == itemCount) {
          return _MobileSessionArtifacts(controller: controller);
        }
        if (index >= messages.length) {
          return const _MobileExecutionProgressCard();
        }

        final message = messages[index];
        final role = message.role.toLowerCase();
        final isUser = role == 'user';

        if (isUser) {
          return _MobileUserMessageBubble(message: message);
        }

        return _MobileAssistantMessageCard(
          message: message,
          controller: controller,
        );
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
  const _MobileAssistantMessageCard({
    required this.message,
    required this.controller,
  });

  final GatewayChatMessage message;
  final AppController controller;

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
              if (message.pending || message.error) ...[
                AssistantTaskProgressBar(
                  state: AssistantTaskProgressState(
                    phase: message.error
                        ? AssistantTaskProgressPhase.interrupted
                        : AssistantTaskProgressPhase.running,
                    label: message.error
                        ? appText('任务中断', 'Task interrupted')
                        : appText('正在运行...', 'Running...'),
                  ),
                  onStop: message.pending ? () => controller.abortRun() : null,
                ),
                const SizedBox(height: 18),
              ],
              _MobileBridgeInlineStatus(connected: !message.error),
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
                appText('正在执行中...', 'Executing...'),
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
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
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
                if (!connection.connected) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const Key('mobile-assistant-connect-bridge-button'),
                    onPressed: onConnectBridge,
                    icon: const Icon(Icons.settings_input_component_rounded),
                    label: Text(appText('去配置集成', 'Configure integration')),
                  ),
                ],
                const SizedBox(height: 26),
                SizedBox(
                  key: const Key('mobile-plugin-scene-carousel'),
                  height: 68,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      children: [
                        for (final scene in mobileBuiltinPluginScenes) ...[
                          _MobilePluginSceneChip(
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
                          if (scene != mobileBuiltinPluginScenes.last)
                            const SizedBox(width: 10),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
        borderRadius: BorderRadius.circular(34),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surfaceSecondary,
            borderRadius: BorderRadius.circular(34),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  scene.plugin.icon,
                  size: 25,
                  color: connected ? palette.textSecondary : palette.textMuted,
                ),
                const SizedBox(width: 10),
                Text(
                  scene.sceneLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
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
  const _MobileGeneratedArtifactCard({
    required this.title,
    required this.onTap,
  });

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfacePrimary,
      borderRadius: BorderRadius.circular(12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: palette.strokeSoft),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
                      title,
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
      ),
    );
  }
}

class _MobileSessionArtifacts extends StatefulWidget {
  const _MobileSessionArtifacts({required this.controller});
  final AppController controller;

  @override
  State<_MobileSessionArtifacts> createState() =>
      _MobileSessionArtifactsState();
}

class _MobileSessionArtifactsState extends State<_MobileSessionArtifacts> {
  AssistantArtifactSnapshot? _snapshot;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.controller.loadAssistantArtifactSnapshot();
      if (mounted) setState(() => _snapshot = s);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.controller.assistantArtifactSyncStatusForSession(
      widget.controller.currentSessionKey,
    );
    if (status == 'no-artifacts') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Text(
          appText('未生成任何产物', 'No artifacts generated'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (status == 'syncing') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              appText('正在准备产物...', 'Preparing artifacts...'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }
    if (status == 'failed') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Text(
          appText('产物准备失败，请重试', 'Failed to prepare artifacts. Please retry.'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_snapshot == null || _snapshot!.fileEntries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in _snapshot!.fileEntries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _MobileGeneratedArtifactCard(
              title: entry.label,
              onTap: () async {
                try {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(appText('正在准备文件...', 'Preparing file...')),
                    ),
                  );
                  final preview = await widget.controller
                      .loadAssistantArtifactPreview(entry);
                  if (!context.mounted) return;
                  final dir = await getTemporaryDirectory();
                  final file = File('${dir.path}/${entry.label}');
                  await file.writeAsString(preview.content);
                  await SharePlus.instance.share(
                    ShareParams(files: [XFile(file.path)], text: entry.label),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('下载失败: $e')));
                }
              },
            ),
          ),
      ],
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
