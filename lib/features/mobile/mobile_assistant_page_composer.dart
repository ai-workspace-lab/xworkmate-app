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

    void showConfigurationMenu() {
      showModalBottomSheet(
        context: context,
        backgroundColor: palette.surfacePrimary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appText('会话配置', 'Configuration'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 12,
                    children: [
                      MobileAssistantActionChip(
                        key: const Key('mobile-assistant-target-button'),
                        icon: target.isGateway
                            ? Icons.cloud_queue_rounded
                            : Icons.smart_toy_outlined,
                        label: target.compactLabel,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          showMobileAssistantTargetSheet(
                            context,
                            controller: controller,
                            onSelected: onSetExecutionTarget,
                          );
                        },
                      ),
                      MobileAssistantActionChip(
                        key: const Key('mobile-assistant-provider-button'),
                        icon: Icons.hub_outlined,
                        label: providerLabel,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          showMobileAssistantProviderSheet(
                            context,
                            controller: controller,
                            target: target,
                            selectedProvider: provider,
                            onSelected: onSetProvider,
                          );
                        },
                      ),
                      MobileAssistantActionChip(
                        key: const Key('mobile-assistant-permission-button'),
                        icon: mobilePermissionIcon(
                          controller.assistantPermissionLevel,
                        ),
                        label: controller.assistantPermissionLevel.label,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          showMobileAssistantPermissionSheet(
                            context,
                            controller: controller,
                          );
                        },
                      ),
                      MobileAssistantActionChip(
                        key: const Key('mobile-assistant-thinking-button'),
                        icon: Icons.psychology_alt_outlined,
                        label: mobileThinkingLabel(thinking),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          showMobileAssistantThinkingSheet(
                            context,
                            value: thinking,
                            onSelected: onThinkingChanged,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Padding(
      key: const Key('mobile-assistant-composer'),
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding == 0 ? 12 : bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPendingRun)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: IconButton.filledTonal(
                  key: const Key('mobile-assistant-stop-button'),
                  onPressed: () => unawaited(controller.abortRun()),
                  icon: const Icon(Icons.stop_rounded),
                  tooltip: appText('停止运行', 'Stop Run'),
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 7),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.light ? const Color(0xFFF4F6F8) : palette.surfaceSecondary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    key: const Key('mobile-assistant-composer-add-button'),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.add, color: palette.textPrimary, size: 20),
                    onPressed: showConfigurationMenu,
                  ),
                ),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.light ? const Color(0xFFF4F6F8) : palette.surfaceSecondary,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Row(
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
                               hintText: appText(
                                 '询问 XWorkmate...',
                                 'Ask XWorkmate...',
                               ),
                               hintStyle: TextStyle(color: palette.textMuted),
                               border: InputBorder.none,
                               enabledBorder: InputBorder.none,
                               focusedBorder: InputBorder.none,
                               contentPadding: const EdgeInsets.only(left: 16, right: 8, top: 14, bottom: 14),
                             ),
                           ),
                         ),
                       ),
                       Padding(
                         padding: const EdgeInsets.only(right: 12, bottom: 12),
                         child: Icon(Icons.mic_none, color: Theme.of(context).brightness == Brightness.light ? const Color(0xFF9CA3AF) : palette.textMuted, size: 22),
                       ),
                     ],
                   ),
                 ),
               ),
               Padding(
                 padding: const EdgeInsets.only(left: 8, bottom: 7),
                 child: Container(
                   width: 32,
                   height: 32,
                   decoration: BoxDecoration(
                     color: Theme.of(context).brightness == Brightness.light ? const Color(0xFF6EA8FF) : palette.accent,
                     shape: BoxShape.circle,
                     boxShadow: Theme.of(context).brightness == Brightness.light ? [
                       BoxShadow(
                         color: const Color(0xFF6EA8FF).withValues(alpha: 0.15),
                         blurRadius: 4,
                         offset: const Offset(0, 2),
                       )
                     ] : null,
                   ),
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
