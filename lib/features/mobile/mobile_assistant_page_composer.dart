import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import 'mobile_assistant_page_sheets.dart';

class MobileAssistantComposer extends StatelessWidget {
  const MobileAssistantComposer({
    super.key,
    required this.controller,
    required this.inputController,
    required this.focusNode,
    required this.thinking,
    required this.bottomPadding,
    required this.onThinkingChanged,
    required this.onSetExecutionTarget,
    required this.onSetProvider,
    required this.onSend,
  });

  final AppController controller;
  final TextEditingController inputController;
  final FocusNode focusNode;
  final String thinking;
  final double bottomPadding;
  final ValueChanged<String> onThinkingChanged;
  final Future<void> Function(AssistantExecutionTarget target)
  onSetExecutionTarget;
  final Future<void> Function(SingleAgentProvider provider) onSetProvider;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final target = controller.currentAssistantExecutionTarget;
    final provider = controller.assistantProviderForSession(
      controller.currentSessionKey,
    );
    final providerLabel = provider.isUnspecified
        ? appText('Provider 未就绪', 'Provider unavailable')
        : provider.label;
    final hasPendingRun =
        controller.hasAssistantPendingRun || controller.activeRunId != null;

    return Padding(
      key: const Key('mobile-assistant-composer'),
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding == 0 ? 12 : bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      MobileAssistantActionChip(
                        key: const Key('mobile-assistant-target-button'),
                        icon: target.isGateway
                            ? Icons.cloud_queue_rounded
                            : Icons.smart_toy_outlined,
                        label: target.compactLabel,
                        onTap: () => showMobileAssistantTargetSheet(
                          context,
                          controller: controller,
                          onSelected: onSetExecutionTarget,
                        ),
                      ),
                      const SizedBox(width: 6),
                      MobileAssistantActionChip(
                        key: const Key('mobile-assistant-provider-button'),
                        icon: Icons.hub_outlined,
                        label: providerLabel,
                        onTap: () => showMobileAssistantProviderSheet(
                          context,
                          controller: controller,
                          target: target,
                          selectedProvider: provider,
                          onSelected: onSetProvider,
                        ),
                      ),
                      const SizedBox(width: 6),
                      MobileAssistantActionChip(
                        key: const Key('mobile-assistant-permission-button'),
                        icon: mobilePermissionIcon(
                          controller.assistantPermissionLevel,
                        ),
                        label: controller.assistantPermissionLevel.label,
                        onTap: () => showMobileAssistantPermissionSheet(
                          context,
                          controller: controller,
                        ),
                      ),
                      const SizedBox(width: 6),
                      MobileAssistantActionChip(
                        key: const Key('mobile-assistant-thinking-button'),
                        icon: Icons.psychology_alt_outlined,
                        label: mobileThinkingLabel(thinking),
                        onTap: () => showMobileAssistantThinkingSheet(
                          context,
                          value: thinking,
                          onSelected: onThinkingChanged,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (hasPendingRun) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const Key('mobile-assistant-stop-button'),
                  onPressed: () => unawaited(controller.abortRun()),
                  icon: const Icon(Icons.stop_rounded),
                  tooltip: appText('停止运行', 'Stop Run'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surfaceSecondary,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 4),
                  child: IconButton(
                    icon: Icon(Icons.add, color: palette.textSecondary),
                    onPressed: () {
                      // 预留功能位
                    },
                  ),
                ),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 46,
                      maxHeight: 118,
                    ),
                    child: TextField(
                      key: const Key('mobile-assistant-input'),
                      controller: inputController,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: appText(
                          '询问 XWorkmate...',
                          'Ask XWorkmate...',
                        ),
                        hintStyle: TextStyle(color: palette.textMuted),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 6),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: palette.accent,
                    child: IconButton(
                      key: const Key('mobile-assistant-send-button'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                      onPressed: onSend,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MobileAssistantActionChip extends StatelessWidget {
  const MobileAssistantActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: palette.strokeSoft),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: palette.textSecondary),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 136),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 16,
                color: palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
