import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import 'mobile_builtin_plugin_scenes.dart';
import '../plugins/builtin_plugin_catalog.dart';
import '../plugins/builtin_plugin_visuals.dart';
import 'mobile_assistant_page_sheets.dart';
import '../assistant/assistant_page_composer_clipboard.dart';

final Map<String, List<String>> selectedBuiltinPluginIdsBySessionInternal =
    <String, List<String>>{};

List<String> selectedBuiltinPluginIdsForSession(String sessionKey) {
  return selectedBuiltinPluginIdsBySessionInternal[sessionKey] ??
      const <String>[];
}

void toggleBuiltinPluginForSession(String sessionKey, String pluginId) {
  final selected = selectedBuiltinPluginIdsBySessionInternal.putIfAbsent(
    sessionKey,
    () => <String>[],
  );
  if (!selected.remove(pluginId)) {
    selected.add(pluginId);
  }
  if (selected.isEmpty) {
    selectedBuiltinPluginIdsBySessionInternal.remove(sessionKey);
  }
}

class MobileAssistantComposer extends StatelessWidget {
  const MobileAssistantComposer({
    super.key,
    required this.controller,
    required this.inputController,
    required this.focusNode,
    required this.thinking,
    required this.bottomPadding,
    required this.attachments,
    required this.onPickAttachments,
    required this.onRemoveAttachment,
    required this.onThinkingChanged,
    required this.onSetExecutionTarget,
    required this.onSetProvider,
    required this.onComposerStateChanged,
    required this.onSend,
  });

  final AppController controller;
  final TextEditingController inputController;
  final FocusNode focusNode;
  final String thinking;
  final double bottomPadding;
  final List<ComposerAttachmentInternal> attachments;
  final VoidCallback onPickAttachments;
  final ValueChanged<ComposerAttachmentInternal> onRemoveAttachment;
  final ValueChanged<String> onThinkingChanged;
  final Future<void> Function(AssistantExecutionTarget target)
  onSetExecutionTarget;
  final Future<void> Function(SingleAgentProvider provider) onSetProvider;
  final VoidCallback onComposerStateChanged;
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
    final selectedSkillKeys = controller
        .assistantSelectedSkillKeysForSession(controller.currentSessionKey)
        .toSet();
    final selectedSkills = controller.skills
        .where((skill) => selectedSkillKeys.contains(skill.skillKey))
        .toList(growable: false);

    void showConfigurationMenu() {
      final selectedPluginIds = List<String>.from(
        selectedBuiltinPluginIdsForSession(controller.currentSessionKey),
      );
      final selectedSkillKeySet = Set<String>.from(selectedSkillKeys);
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: palette.surfacePrimary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) {
          int activeTabIndex = 0;
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              void togglePlugin(String pluginId) {
                toggleBuiltinPluginForSession(
                  controller.currentSessionKey,
                  pluginId,
                );
                onComposerStateChanged();
                setSheetState(() {
                  if (!selectedPluginIds.remove(pluginId)) {
                    selectedPluginIds.add(pluginId);
                  }
                });
              }

              void toggleSkill(String skillKey) {
                unawaited(
                  controller.toggleAssistantSkillForSession(
                    controller.currentSessionKey,
                    skillKey,
                  ),
                );
                onComposerStateChanged();
                setSheetState(() {
                  if (!selectedSkillKeySet.remove(skillKey)) {
                    selectedSkillKeySet.add(skillKey);
                  }
                });
              }

              void refreshSkillsIfEmpty() {
                final skillsController = controller.skillsController;
                if (controller.skills.isNotEmpty || skillsController.loading) {
                  return;
                }
                final selectedAgentId = controller.selectedAgentId.trim();
                unawaited(
                  skillsController.refresh(
                    agentId: selectedAgentId.isEmpty ? null : selectedAgentId,
                  ),
                );
              }

              Widget buildHeaderChip({
                required String label,
                required bool selected,
                required IconData icon,
                required Key key,
                required VoidCallback onTap,
              }) {
                return InkWell(
                  key: key,
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? palette.accentMuted
                          : palette.surfaceSecondary,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? palette.accent
                            : palette.strokeSoft,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 14,
                          color: selected
                              ? palette.accent
                              : palette.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: TextStyle(
                            color: selected
                                ? palette.accent
                                : palette.textSecondary,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(sheetContext).size.height * 0.84,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    buildHeaderChip(
                                      key: const Key('mobile-assistant-tab-attach'),
                                      label: appText('添加附件', 'Attach'),
                                      icon: CupertinoIcons.paperclip,
                                      selected: false,
                                      onTap: () {
                                        Navigator.pop(sheetContext);
                                        onPickAttachments();
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    buildHeaderChip(
                                      key: const Key('mobile-assistant-tab-0'),
                                      label: appText('会话配置', 'Config'),
                                      icon: Icons.tune_rounded,
                                      selected: activeTabIndex == 0,
                                      onTap: () => setSheetState(() => activeTabIndex = 0),
                                    ),
                                    const SizedBox(width: 8),
                                    buildHeaderChip(
                                      key: const Key('mobile-assistant-tab-1'),
                                      label: appText('内置插件', 'Plugins'),
                                      icon: Icons.extension_rounded,
                                      selected: activeTabIndex == 1,
                                      onTap: () => setSheetState(() => activeTabIndex = 1),
                                    ),
                                    const SizedBox(width: 8),
                                    buildHeaderChip(
                                      key: const Key('mobile-assistant-tab-2'),
                                      label: appText('技能选择', 'Skills'),
                                      icon: Icons.psychology_rounded,
                                      selected: activeTabIndex == 2,
                                      onTap: () {
                                        refreshSkillsIfEmpty();
                                        setSheetState(() => activeTabIndex = 2);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              key: const Key('mobile-assistant-sheet-close'),
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close_rounded),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        if (activeTabIndex == 0) ...[
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 8,
                            runSpacing: 10,
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
                                key: const Key(
                                  'mobile-assistant-provider-button',
                                ),
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
                                key: const Key(
                                  'mobile-assistant-permission-button',
                                ),
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
                                key: const Key(
                                  'mobile-assistant-thinking-button',
                                ),
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
                        if (activeTabIndex == 1) ...[
                          const SizedBox(height: 14),
                          Text(
                            appText(
                              '点选即可叠加到当前会话。',
                              'Tap to keep a plugin active for this session.',
                            ),
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final scene in mobileBuiltinPluginScenes)
                                FilterChip(
                                  key: ValueKey(
                                    'mobile-assistant-plugin-chip-${scene.plugin.id}',
                                  ),
                                  avatar: BuiltinPluginIconTile(
                                    plugin: scene.plugin,
                                    size: 20,
                                  ),
                                  label: Text(scene.sceneLabel),
                                  selected: selectedPluginIds.contains(
                                    scene.plugin.id,
                                  ),
                                  onSelected: (_) =>
                                      togglePlugin(scene.plugin.id),
                                ),
                            ],
                          ),
                        ],
                        if (activeTabIndex == 2) ...[
                          const SizedBox(height: 14),
                          Text(
                            appText(
                              '和桌面端保持同一套会话技能选择。',
                              'Keeps the same session skill selections as desktop.',
                            ),
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          AnimatedBuilder(
                            animation: controller,
                            builder: (context, _) {
                              if (controller.skills.isEmpty) {
                                return Text(
                                  appText(
                                    '当前没有已加载技能。',
                                    'No skills are loaded yet.',
                                  ),
                                  style: Theme.of(sheetContext)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: palette.textSecondary,
                                      ),
                                );
                              }
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final skill in controller.skills)
                                    FilterChip(
                                      key: ValueKey(
                                        'mobile-assistant-skill-chip-${skill.skillKey}',
                                      ),
                                      avatar: const Icon(
                                        Icons.key_rounded,
                                        size: 16,
                                      ),
                                      label: Text(skill.name),
                                      selected: selectedSkillKeySet
                                          .contains(skill.skillKey),
                                      onSelected: (_) =>
                                          toggleSkill(skill.skillKey),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    return Padding(
      key: const Key('mobile-assistant-composer'),
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        bottomPadding == 0 ? 14 : bottomPadding + 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: palette.surfacePrimary,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: palette.strokeSoft),
              boxShadow: [palette.chromeShadowAmbient],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 48,
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
                      contentPadding: const EdgeInsets.only(
                        left: 18,
                        right: 18,
                        top: 14,
                        bottom: 8,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    top: 2,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      IconButton(
                        key: const Key('mobile-assistant-composer-add-button'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        icon: Icon(
                          Icons.add_rounded,
                          color: palette.textPrimary,
                          size: 28,
                        ),
                        onPressed: showConfigurationMenu,
                      ),
                      _MobileAssistantPrimaryActionButton(
                        isBusy: hasPendingRun,
                        onSend: onSend,
                        onStop: () => unawaited(controller.abortRun()),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (selectedBuiltinPluginIdsForSession(
                controller.currentSessionKey,
              ).isNotEmpty ||
              selectedSkills.isNotEmpty ||
              attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final attachment in attachments)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _MobileAssistantSelectionChip(
                        key: ValueKey<String>(
                          'mobile-assistant-selected-attachment-${attachment.name}',
                        ),
                        icon: CupertinoIcons.doc,
                        label: attachment.name,
                        onDeleted: () => onRemoveAttachment(attachment),
                      ),
                    ),
                  for (final pluginId in selectedBuiltinPluginIdsForSession(
                    controller.currentSessionKey,
                  ))
                    if (BuiltinPluginCatalog.byId(pluginId) case final plugin?)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _MobileAssistantSelectionChip(
                          key: ValueKey<String>(
                            'mobile-assistant-selected-plugin-$pluginId',
                          ),
                          iconWidget: BuiltinPluginIconTile(
                            plugin: plugin,
                            size: 18,
                          ),
                          label: plugin.name,
                          onDeleted: () {
                            toggleBuiltinPluginForSession(
                              controller.currentSessionKey,
                              pluginId,
                            );
                            onComposerStateChanged();
                          },
                        ),
                      ),
                  for (final skill in selectedSkills)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _MobileAssistantSelectionChip(
                        key: ValueKey<String>(
                          'mobile-assistant-selected-skill-${skill.skillKey}',
                        ),
                        icon: Icons.key_rounded,
                        label: skill.name,
                        onDeleted: () {
                          unawaited(
                            controller.toggleAssistantSkillForSession(
                              controller.currentSessionKey,
                              skill.skillKey,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MobileAssistantPrimaryActionButton extends StatelessWidget {
  const _MobileAssistantPrimaryActionButton({
    required this.isBusy,
    required this.onSend,
    required this.onStop,
  });

  final bool isBusy;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final backgroundColor = isBusy
        ? palette.surfaceSecondary
        : palette.accentMuted;
    final foregroundColor = isBusy ? palette.textPrimary : palette.accent;
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        key: ValueKey<String>(
          isBusy
              ? 'mobile-assistant-stop-button'
              : 'mobile-assistant-send-button',
        ),
        tooltip: isBusy
            ? appText('停止运行', 'Stop run')
            : appText('提交任务', 'Submit task'),
        onPressed: isBusy ? onStop : onSend,
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          side: BorderSide(
            color: isBusy
                ? palette.strokeSoft
                : Colors.transparent,
            width: 1.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isBusy ? 12 : 999),
          ),
          minimumSize: const Size(40, 40),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(
          isBusy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
          size: isBusy ? 20 : 22,
        ),
      ),
    );
  }
}

class _MobileAssistantSelectionChip extends StatelessWidget {
  const _MobileAssistantSelectionChip({
    super.key,
    this.icon,
    this.iconWidget,
    required this.label,
    required this.onDeleted,
  }) : assert(icon != null || iconWidget != null);

  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InputChip(
      avatar: iconWidget ?? Icon(icon, size: 18, color: palette.textSecondary),
      label: Text(label),
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      deleteIconColor: palette.textMuted,
      backgroundColor: palette.surfacePrimary,
      side: BorderSide(color: palette.strokeSoft),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 2),
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
