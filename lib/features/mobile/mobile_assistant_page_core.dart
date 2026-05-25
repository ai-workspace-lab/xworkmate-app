import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/workspace_page_registry.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import 'mobile_assistant_page_composer.dart';
import 'mobile_assistant_page_conversation.dart';
import 'mobile_workspace_files_page.dart';

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
  State<MobileAssistantDetailPage> createState() => _MobileAssistantDetailPageState();
}

class _MobileAssistantDetailPageState extends State<MobileAssistantDetailPage> {
  late final TextEditingController inputController;
  late final ScrollController conversationController;
  late final FocusNode inputFocusNode;
  String thinking = 'medium';
  String lastScrollSignature = '';
  int _segmentedIndex = 0;

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

  Future<void> sendCurrentPrompt() async {
    final text = inputController.text.trim();
    if (text.isEmpty) {
      inputFocusNode.requestFocus();
      return;
    }
    inputController.clear();
    HapticFeedback.lightImpact();
    try {
      await widget.controller.sendChatMessage(text, thinking: thinking);
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

        return Scaffold(
          backgroundColor: palette.canvas,
          appBar: CupertinoNavigationBar(
            backgroundColor: palette.canvas.withValues(alpha: 0.9),
            border: Border(bottom: BorderSide(color: palette.strokeSoft)),
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: widget.onBack,
              child: const Icon(CupertinoIcons.back),
            ),
            middle: CupertinoSlidingSegmentedControl<int>(
              groupValue: _segmentedIndex,
              children: {
                0: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(appText('会话', 'Chat')),
                ),
                1: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(appText('工作区', 'Workspace')),
                ),
              },
              onValueChanged: (int? value) {
                if (value != null) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _segmentedIndex = value;
                  });
                }
              },
            ),
          ),
          body: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: bottomInset),
            child: IndexedStack(
              index: _segmentedIndex,
              children: [
                Column(
                  children: [
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
                        onFocusComposer: () => inputFocusNode.requestFocus(),
                      ),
                    ),
                    MobileAssistantComposer(
                      controller: controller,
                      inputController: inputController,
                      focusNode: inputFocusNode,
                      thinking: thinking,
                      bottomPadding: bottomPadding,
                      onThinkingChanged: (value) {
                        setState(() {
                          thinking = value;
                        });
                      },
                      onSetExecutionTarget: setExecutionTarget,
                      onSetProvider: setProvider,
                      onSend: () => unawaited(sendCurrentPrompt()),
                    ),
                  ],
                ),
                MobileWorkspaceFilesPage(
                  controller: controller,
                ),
              ],
            ),
          ),
        );
      },
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
        ? appText('Bridge 已连接', 'Bridge Connected')
        : appText('先连接 Bridge', 'Connect Bridge First');
    final detail = connection.connected
        ? [
            target.compactLabel,
            if (hasProvider)
              provider.label
            else
              appText('Provider 未就绪', 'Provider unavailable'),
            connection.detailLabel,
          ].where((item) => item.trim().isNotEmpty).join(' · ')
        : connection.detailLabel;

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
                  child: Text(appText('连接 Bridge', 'Connect')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
