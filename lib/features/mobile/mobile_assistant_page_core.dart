import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../assistant/assistant_attachment_payloads.dart';
import '../assistant/assistant_page_composer_clipboard.dart';
import '../../app/app_controller.dart';
import '../../app/app_controller_desktop_thread_binding.dart';
import '../../app/ui_feature_manifest.dart';
import '../../app/workspace_page_registry.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import 'mobile_assistant_page_composer.dart';
import 'mobile_assistant_page_conversation.dart';

class MobileAssistantDetailPage extends StatefulWidget {
  const MobileAssistantDetailPage({
    super.key,
    required this.controller,
    required this.onOpenDetail,
    required this.onBack,
    this.mobileActions = const MobileWorkspaceActions(),
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;
  final VoidCallback onBack;
  final MobileWorkspaceActions mobileActions;

  @override
  State<MobileAssistantDetailPage> createState() =>
      _MobileAssistantDetailPageState();
}

class _MobileAssistantDetailPageState extends State<MobileAssistantDetailPage> {
  late final TextEditingController inputController;
  late final ScrollController conversationController;
  late final FocusNode inputFocusNode;
  String thinking = 'medium';
  String lastScrollSignature = '';

  List<ComposerAttachmentInternal> _attachments = [];

  @override
  void initState() {
    super.initState();
    inputController = TextEditingController();
    conversationController = ScrollController();
    inputFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(prepareMobileAssistantSession());
    });
  }

  Future<void> prepareMobileAssistantSession() async {
    await widget.controller.ensureActiveAssistantThreadInternal();
    await widget.controller.refreshAcpCapabilitiesInternal(forceRefresh: true);
  }

  @override
  void dispose() {
    inputController.dispose();
    conversationController.dispose();
    inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    final uiFeatures = widget.controller.featuresFor(
      resolveUiFeaturePlatformFromContext(context),
    );
    if (!uiFeatures.supportsFileAttachments) {
      return;
    }

    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: Text(appText('选择附件类型', 'Select Attachment Type')),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context, 'photo');
            },
            child: Text(appText('照片和视频', 'Photos and Videos')),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context, 'file');
            },
            child: Text(appText('浏览文件', 'Browse Files')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text(appText('取消', 'Cancel')),
        ),
      ),
    );

    if (action == null) {
      return;
    }

    List<XFile> files = [];
    if (action == 'photo') {
      final picker = ImagePicker();
      files = await picker.pickMultiImage();
    } else if (action == 'file') {
      files = await openFiles();
    }

    if (!mounted || files.isEmpty) {
      return;
    }

    setState(() {
      _attachments = [
        ..._attachments,
        ...files.map(ComposerAttachmentInternal.fromXFile),
      ];
    });
  }

  Future<void> sendCurrentPrompt() async {
    final text = inputController.text.trim();
    if (text.isEmpty && _attachments.isEmpty) {
      inputFocusNode.requestFocus();
      return;
    }

    final submittedAttachments = List<ComposerAttachmentInternal>.from(
      _attachments,
      growable: false,
    );
    inputController.clear();
    setState(() {
      _attachments = [];
    });
    HapticFeedback.lightImpact();

    try {
      final attachmentPayloads = await buildAssistantAttachmentPayloadsInternal(
        submittedAttachments,
      );
      await widget.controller.sendChatMessage(
        text,
        thinking: thinking,
        attachments: attachmentPayloads,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> setExecutionTarget(AssistantExecutionTarget target) async {
    HapticFeedback.selectionClick();
    try {
      await widget.controller.ensureActiveAssistantThreadInternal();
      await widget.controller.setAssistantExecutionTarget(target);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> setProvider(SingleAgentProvider provider) async {
    HapticFeedback.selectionClick();
    try {
      await widget.controller.ensureActiveAssistantThreadInternal();
      await widget.controller.setAssistantProvider(provider);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> createMobileTask() async {
    final uiFeatures = widget.controller.featuresFor(
      resolveUiFeaturePlatformFromContext(context),
    );
    final visibleExecutionTargets = widget.controller
        .visibleAssistantExecutionTargets(uiFeatures.availableExecutionTargets);
    final sessionKey = widget.controller
        .createAssistantDraftSessionKeyInternal();
    final target = pickDraftThreadExecutionTargetInternal(
      currentTarget: widget.controller.currentAssistantExecutionTarget,
      visibleTargets: visibleExecutionTargets,
      localWorkspaceAvailable: widget.controller.settings.workspacePath
          .trim()
          .isNotEmpty,
    );
    widget.controller.initializeAssistantThreadContext(
      sessionKey,
      title: appText('新对话', 'New conversation'),
      executionTarget: target,
      messageViewMode: widget.controller.currentAssistantMessageViewMode,
    );
    await switchMobileSession(sessionKey);
  }

  Future<void> switchMobileSession(String sessionKey) async {
    HapticFeedback.selectionClick();
    await widget.controller.switchSession(sessionKey);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void toggleBuiltinPluginShortcut(String pluginId) {
    HapticFeedback.selectionClick();
    toggleBuiltinPluginForSession(
      widget.controller.currentSessionKey,
      pluginId,
    );
    setState(() {});
  }

  Future<void> showSessionSwitcher() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _MobileSessionSwitcherSheet(
          controller: widget.controller,
          onCreateTask: () async {
            Navigator.of(sheetContext).pop();
            await createMobileTask();
          },
          onSelectSession: (sessionKey) async {
            Navigator.of(sheetContext).pop();
            await switchMobileSession(sessionKey);
          },
          onOpenFullList: () {
            Navigator.of(sheetContext).pop();
            widget.onBack();
          },
        );
      },
    );
  }

  Future<void> copyTaskWorkspaceReference(String workspaceReference) async {
    final normalized = workspaceReference.trim();
    if (normalized.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: normalized));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(appText('任务路径已复制', 'Task path copied'))),
    );
  }

  void maybeScrollToBottom(List<GatewayChatMessage> messages) {
    final signature = messages.isEmpty
        ? widget.controller.currentSessionKey
        : '${widget.controller.currentSessionKey}:${messages.length}:${messages.last.id}:${messages.last.pending}:${messages.last.error}';
    if (signature == lastScrollSignature) {
      return;
    }
    lastScrollSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !conversationController.hasClients) {
        return;
      }
      conversationController.animateTo(
        conversationController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final messages = List<GatewayChatMessage>.from(controller.chatMessages);
        maybeScrollToBottom(messages);
        final mediaQuery = MediaQuery.of(context);
        final bottomInset = mediaQuery.viewInsets.bottom;
        final bottomPadding = math.max(mediaQuery.viewPadding.bottom, 10.0);
        final palette = context.palette;
        final sessionKey = controller.currentSessionKey.trim();
        final connection = controller.currentAssistantConnectionState;
        final taskWorkspaceReference = sessionKey.isEmpty
            ? ''
            : controller.localThreadWorkspaceDisplayPathInternal(sessionKey);

        return Scaffold(
          backgroundColor: palette.canvas,
          body: SafeArea(
            bottom: false,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Column(
                children: [
                  _MobileAssistantTopBar(
                    connected: connection.connected,
                    detail: connection.connected
                        ? null
                        : appText('先去配置集成连接', 'Configure integration first'),
                    onBack: widget.onBack,
                    onOpenHistory: showSessionSwitcher,
                    extraWidget: taskWorkspaceReference.isNotEmpty
                        ? _MobileTaskWorkspaceReference(
                            workspaceReference: taskWorkspaceReference,
                            onCopy: () => unawaited(
                              copyTaskWorkspaceReference(taskWorkspaceReference),
                            ),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: MobileAssistantConversation(
                            controller: controller,
                            messages: messages,
                            scrollController: conversationController,
                            onConnectBridge: widget.mobileActions.connectBridge,
                            selectedBuiltinPluginIds:
                                selectedBuiltinPluginIdsForSession(
                                  controller.currentSessionKey,
                                ).toSet(),
                            onToggleBuiltinPlugin: toggleBuiltinPluginShortcut,
                          ),
                        ),
                        MobileAssistantComposer(
                          controller: controller,
                          inputController: inputController,
                          focusNode: inputFocusNode,
                          thinking: thinking,
                          bottomPadding: bottomPadding,
                          attachments: _attachments,
                          onPickAttachments: _pickAttachments,
                          onRemoveAttachment: (attachment) {
                            setState(() {
                              _attachments = List.from(_attachments)
                                ..remove(attachment);
                            });
                          },
                          onThinkingChanged: (value) {
                            setState(() {
                              thinking = value;
                            });
                          },
                          onSetExecutionTarget: setExecutionTarget,
                          onSetProvider: setProvider,
                          onComposerStateChanged: () {
                            if (mounted) {
                              setState(() {});
                            }
                          },
                          onSend: () => unawaited(sendCurrentPrompt()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileTaskWorkspaceReference extends StatefulWidget {
  const _MobileTaskWorkspaceReference({
    required this.workspaceReference,
    required this.onCopy,
  });

  final String workspaceReference;
  final VoidCallback onCopy;

  @override
  State<_MobileTaskWorkspaceReference> createState() =>
      _MobileTaskWorkspaceReferenceState();
}

class _MobileTaskWorkspaceReferenceState
    extends State<_MobileTaskWorkspaceReference> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    if (!_expanded) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: () => setState(() => _expanded = true),
            borderRadius: BorderRadius.circular(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.chromeSurface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.chromeStroke),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: palette.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      appText('查看任务ID', 'View Task ID'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
          setState(() => _expanded = false);
        }
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.chromeSurface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.chromeStroke),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
            child: Row(
              children: [
                Icon(Icons.tag_rounded, size: 15, color: palette.textSecondary),
                const SizedBox(width: 7),
                Expanded(
                  child: Tooltip(
                    message: widget.workspaceReference,
                    child: Text(
                      widget.workspaceReference,
                      key: const Key('mobile-assistant-task-workspace-ref'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: palette.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('mobile-assistant-copy-task-workspace-ref'),
                  tooltip: appText('复制任务ID', 'Copy task ID'),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: widget.onCopy,
                  icon: const Icon(Icons.content_copy_rounded, size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileAssistantTopBar extends StatelessWidget {
  const _MobileAssistantTopBar({
    required this.connected,
    this.detail,
    required this.onBack,
    required this.onOpenHistory,
    this.extraWidget,
  });

  final bool connected;
  final String? detail;
  final VoidCallback onBack;
  final VoidCallback onOpenHistory;
  final Widget? extraWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Row(
        children: [
          _MobileTopCircleButton(
            key: const Key('mobile-assistant-open-menu-button'),
            icon: Icons.menu_rounded,
            tooltip: appText('返回任务列表', 'Back to tasks'),
            onTap: onBack,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: MobileBridgeHeroStatus(
                connected: connected,
                detail: detail,
                extraWidget: extraWidget,
              ),
            ),
          ),
          _MobileTopCircleButton(
            key: const Key('mobile-assistant-open-history-button'),
            icon: Icons.history_rounded,
            tooltip: appText('最近任务', 'Recent tasks'),
            onTap: onOpenHistory,
          ),
        ],
      ),
    );
  }
}

class _MobileTopCircleButton extends StatelessWidget {
  const _MobileTopCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(29),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surfacePrimary,
            shape: BoxShape.circle,
            border: Border.all(color: palette.strokeSoft),
            boxShadow: [palette.chromeShadowAmbient],
          ),
          child: SizedBox(
            width: 58,
            height: 58,
            child: Icon(icon, color: palette.textPrimary, size: 28),
          ),
        ),
      ),
    );
  }
}

class _MobileSessionSwitcherSheet extends StatelessWidget {
  const _MobileSessionSwitcherSheet({
    required this.controller,
    required this.onCreateTask,
    required this.onSelectSession,
    required this.onOpenFullList,
  });

  final AppController controller;
  final Future<void> Function() onCreateTask;
  final Future<void> Function(String sessionKey) onSelectSession;
  final VoidCallback onOpenFullList;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sessions = controller.assistantSessions.take(8).toList();
    final currentKey = controller.currentSessionKey.trim();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surfacePrimary,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.strokeSoft),
            boxShadow: [palette.chromeShadowLift],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.stroke,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const SizedBox(width: 38, height: 4),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        appText('切换任务会话', 'Switch Tasks'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('mobile-session-switcher-full-list'),
                      onPressed: onOpenFullList,
                      child: Text(appText('全部', 'All')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      appText('暂无历史会话', 'No previous tasks'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: sessions.length,
                      separatorBuilder: (_, _) =>
                          Divider(color: palette.strokeSoft, height: 1),
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        final sessionKey = session.key.trim();
                        final selected = sessionKey == currentKey;
                        final title = session.label.trim().isEmpty
                            ? appText('新对话', 'New conversation')
                            : session.label.trim();
                        final preview =
                            session.lastMessagePreview?.trim() ?? '';
                        return Material(
                          color: Colors.transparent,
                          child: ListTile(
                            key: ValueKey(
                              'mobile-session-switcher-$sessionKey',
                            ),
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.chat_bubble_outline_rounded,
                              color: selected
                                  ? palette.accent
                                  : palette.textSecondary,
                            ),
                            title: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: palette.textPrimary,
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                            ),
                            subtitle: preview.isEmpty
                                ? null
                                : Text(
                                    preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              color: palette.textMuted,
                            ),
                            onTap: () => onSelectSession(sessionKey),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('mobile-session-switcher-new-task'),
                    onPressed: onCreateTask,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(appText('新建任务', 'New task')),
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

class MobileBridgeHeroStatus extends StatelessWidget {
  const MobileBridgeHeroStatus({
    super.key,
    required this.connected,
    this.detail,
    this.extraWidget,
  });

  final bool connected;
  final String? detail;
  final Widget? extraWidget;

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
              if (detail != null && detail!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  detail!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
                ),
              ],
              if (extraWidget != null) ...[
                const SizedBox(height: 6),
                extraWidget!,
              ]
            ],
          ),
        ),
      ],
    );
  }
}
