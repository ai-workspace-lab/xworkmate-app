import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import '../../theme/app_theme.dart';
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
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
        ),
        XTypeGroup(label: 'Logs', extensions: ['log', 'txt', 'json', 'csv']),
        XTypeGroup(
          label: 'Files',
          extensions: ['md', 'pdf', 'yaml', 'yml', 'zip'],
        ),
      ],
    );
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
      final attachmentPayloads = await buildAssistantAttachmentPayloadsInternal(submittedAttachments);
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

  void prefillPluginScenePrompt(String prompt) {
    HapticFeedback.selectionClick();
    inputController.text = prompt;
    inputController.selection = TextSelection.collapsed(offset: prompt.length);
    inputFocusNode.requestFocus();
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
        final hasPendingRun =
            controller.hasAssistantPendingRun || controller.activeRunId != null;
        final title = hasPendingRun
            ? appText('执行中', 'Running')
            : appText('会话', 'Chat');

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
                    title: title,
                    onBack: widget.onBack,
                    onOpenHistory: showSessionSwitcher,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        if (!controller
                                .currentAssistantConnectionState
                                .connected &&
                            messages.isNotEmpty)
                          MobileAssistantStatusBanner(
                            controller: controller,
                            onConnectBridge: widget.mobileActions.connectBridge,
                          ),
                        Expanded(
                          child: MobileAssistantConversation(
                            controller: controller,
                            messages: messages,
                            scrollController: conversationController,
                            onConnectBridge: widget.mobileActions.connectBridge,
                            onSelectPluginScene: prefillPluginScenePrompt,
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
                              _attachments = List.from(_attachments)..remove(attachment);
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

class _MobileAssistantTopBar extends StatelessWidget {
  const _MobileAssistantTopBar({
    required this.title,
    required this.onBack,
    required this.onOpenHistory,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
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

class MobileAssistantStatusBanner extends StatelessWidget {
  const MobileAssistantStatusBanner({
    super.key,
    required this.controller,
    required this.onConnectBridge,
  });

  final AppController controller;
  final VoidCallback onConnectBridge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final connection = controller.currentAssistantConnectionState;
    final target = controller.currentAssistantExecutionTarget;
    final provider = controller.assistantProviderForSession(
      controller.currentSessionKey,
    );
    final hasProvider = !provider.isUnspecified;
    final title = connection.connected
        ? appText('AI Workspace 已连接', 'AI Workspace Connected')
        : appText('先配置集成连接', 'Configure Integration First');
    final detail = connection.connected
        ? [
            target.compactLabel,
            if (hasProvider)
              provider.label
            else
              appText('Provider 未就绪', 'Provider unavailable'),
            appText('已准备好执行', 'Ready to run'),
          ].where((item) => item.trim().isNotEmpty).join(' · ')
        : appText('先去配置集成连接', 'Configure integration first');

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: DecoratedBox(
        key: const Key('mobile-assistant-status-banner'),
        decoration: BoxDecoration(
          color: connection.connected
              ? palette.accentMuted
              : palette.surfacePrimary,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: connection.connected
                ? palette.accent.withValues(alpha: 0.18)
                : palette.strokeSoft,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                connection.connected
                    ? Icons.verified_outlined
                    : Icons.link_off_rounded,
                color: connection.connected ? palette.accent : palette.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!connection.connected) ...[
                const SizedBox(width: 10),
                FilledButton(
                  key: const Key('mobile-assistant-connect-bridge-button'),
                  onPressed: onConnectBridge,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(92, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(appText('去配置集成', 'Configure')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
