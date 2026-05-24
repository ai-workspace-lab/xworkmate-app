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

    return DecoratedBox(
      key: const Key('mobile-assistant-composer'),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        border: Border(top: BorderSide(color: palette.strokeSoft)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, 8, 10, bottomPadding),
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
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
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
                        filled: true,
                        fillColor: palette.surfaceSecondary,
                        hintText: appText(
                          '输入任务或补充上下文',
                          'Type a task or context',
                        ),
                        contentPadding: const EdgeInsets.fromLTRB(
                          12,
                          10,
                          12,
                          10,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                          borderSide: BorderSide(color: palette.strokeSoft),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                          borderSide: BorderSide(
                            color: palette.accent.withValues(alpha: 0.32),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FilledButton(
                    key: const Key('mobile-assistant-send-button'),
                    onPressed: onSend,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: const Icon(Icons.arrow_upward_rounded),
                  ),
                ),
              ],
            ),
          ],
        ),
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
