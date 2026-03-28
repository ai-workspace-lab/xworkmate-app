part of 'assistant_focus_panel.dart';

class AssistantFocusPanel extends StatefulWidget {
  const AssistantFocusPanel({super.key, required this.controller});

  final AppController controller;

  @override
  State<AssistantFocusPanel> createState() => _AssistantFocusPanelState();
}

class AssistantFocusDestinationCard extends StatelessWidget {
  const AssistantFocusDestinationCard({
    super.key,
    required this.controller,
    required this.destination,
    required this.onOpenPage,
    required this.onRemoveFavorite,
  });

  final AppController controller;
  final AssistantFocusEntry destination;
  final VoidCallback onOpenPage;
  final Future<void> Function() onRemoveFavorite;

  @override
  Widget build(BuildContext context) {
    return _AssistantFocusWorkbench(
      controller: controller,
      destination: destination,
      onOpenPage: onOpenPage,
      onRemoveFavorite: onRemoveFavorite,
    );
  }
}

class _AssistantFocusPanelState extends State<AssistantFocusPanel> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final favorites = widget.controller.assistantNavigationDestinations;
    final available = kAssistantNavigationDestinationCandidates
        .where(widget.controller.supportsAssistantFocusEntry)
        .where((item) => !favorites.contains(item))
        .toList(growable: false);

    return SurfaceCard(
      borderRadius: 16,
      padding: EdgeInsets.zero,
      tone: SurfaceCardTone.chrome,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appText('关注入口', 'Focused navigation'),
                        key: const Key('assistant-focus-panel-title'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        appText(
                          '添加后的入口会直接出现在最左侧侧板。这里负责管理关注项和查看摘要，需要完整页面时再单独打开。',
                          'Added entries appear directly in the far-left rail. Manage focused destinations and review summaries here, then open the full page only when needed.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (available.isNotEmpty)
                  PopupMenuButton<AssistantFocusEntry>(
                    key: const Key('assistant-focus-add-menu'),
                    tooltip: appText('添加关注入口', 'Add focused destination'),
                    onSelected: _addFavorite,
                    itemBuilder: (context) => available
                        .map(
                          (destination) => PopupMenuItem<AssistantFocusEntry>(
                            value: destination,
                            child: Row(
                              children: [
                                Icon(destination.icon, size: 18),
                                const SizedBox(width: 10),
                                Expanded(child: Text(destination.label)),
                              ],
                            ),
                          ),
                        )
                        .toList(growable: false),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            palette.chromeHighlight.withValues(alpha: 0.94),
                            palette.chromeSurfacePressed,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.chromeStroke),
                        boxShadow: [palette.chromeShadowLift],
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.strokeSoft),
          Expanded(
            child: favorites.isEmpty
                ? _AssistantFocusEmptyState(
                    message: appText(
                      '还没有关注入口。给功能菜单点星标，或从右上角添加一个入口，加入最左侧侧板。',
                      'No focused entries yet. Star a destination or add one from the top-right menu to place it in the far-left rail.',
                    ),
                    available: available,
                    onAdd: _addFavorite,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: favorites.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final destination = favorites[index];
                      return AssistantFocusDestinationCard(
                        controller: widget.controller,
                        destination: destination,
                        onOpenPage: () => widget.controller.navigateTo(
                          destination.destination ??
                              WorkspaceDestination.settings,
                        ),
                        onRemoveFavorite: () => _removeFavorite(destination),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addFavorite(AssistantFocusEntry destination) async {
    await widget.controller.toggleAssistantNavigationDestination(destination);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _removeFavorite(AssistantFocusEntry destination) async {
    await widget.controller.toggleAssistantNavigationDestination(destination);
    if (mounted) {
      setState(() {});
    }
  }
}

class _AssistantFocusWorkbench extends StatelessWidget {
  const _AssistantFocusWorkbench({
    required this.controller,
    required this.destination,
    required this.onOpenPage,
    required this.onRemoveFavorite,
  });

  final AppController controller;
  final AssistantFocusEntry destination;
  final VoidCallback onOpenPage;
  final Future<void> Function() onRemoveFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: palette.surfaceSecondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    destination.icon,
                    size: 18,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.label,
                        key: ValueKey<String>(
                          'assistant-focus-active-title-${destination.name}',
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        destination.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey<String>(
                    'assistant-focus-open-page-${destination.name}',
                  ),
                  tooltip: appText('打开全页', 'Open full page'),
                  onPressed: onOpenPage,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                ),
                IconButton(
                  key: ValueKey<String>(
                    'assistant-focus-remove-${destination.name}',
                  ),
                  tooltip: appText('取消关注', 'Remove from focused panel'),
                  onPressed: () async {
                    await onRemoveFavorite();
                  },
                  icon: Icon(Icons.star_rounded, color: palette.accent),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.strokeSoft),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: _AssistantFocusPreview(
              controller: controller,
              destination: destination,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantFocusPreview extends StatelessWidget {
  const _AssistantFocusPreview({
    required this.controller,
    required this.destination,
  });

  final AppController controller;
  final AssistantFocusEntry destination;

  @override
  Widget build(BuildContext context) {
    return switch (destination) {
      AssistantFocusEntry.tasks => _TasksFocusPreview(controller: controller),
      AssistantFocusEntry.skills => _SkillsFocusPreview(controller: controller),
      AssistantFocusEntry.nodes => _NodesFocusPreview(controller: controller),
      AssistantFocusEntry.agents => _AgentsFocusPreview(controller: controller),
      AssistantFocusEntry.mcpServer => _McpFocusPreview(controller: controller),
      AssistantFocusEntry.clawHub => _ClawHubFocusPreview(
        controller: controller,
      ),
      AssistantFocusEntry.secrets => _SecretsFocusPreview(
        controller: controller,
      ),
      AssistantFocusEntry.aiGateway => _AiGatewayFocusPreview(
        controller: controller,
      ),
      AssistantFocusEntry.settings => _SettingsFocusPreview(
        controller: controller,
      ),
      AssistantFocusEntry.language => _LanguageFocusPreview(
        controller: controller,
      ),
      AssistantFocusEntry.theme => _ThemeFocusPreview(controller: controller),
    };
  }
}

