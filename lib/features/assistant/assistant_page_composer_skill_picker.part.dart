part of 'assistant_page.dart';

class _ComposerSelectedSkillChip extends StatelessWidget {
  const _ComposerSelectedSkillChip({
    super.key,
    required this.option,
    required this.onDeleted,
  });

  final _ComposerSkillOption option;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _skillOptionTooltip(option),
      child: InputChip(
        avatar: Icon(option.icon, size: 16, color: context.palette.accent),
        label: Text(option.label),
        onDeleted: onDeleted,
        side: BorderSide.none,
        backgroundColor: context.palette.surfaceSecondary,
        deleteIconColor: context.palette.textMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
      ),
    );
  }
}

class _SkillPickerPopover extends StatelessWidget {
  const _SkillPickerPopover({
    required this.maxHeight,
    required this.searchController,
    required this.searchFocusNode,
    required this.selectedSkillKeys,
    required this.filteredSkills,
    required this.isLoading,
    required this.hasQuery,
    required this.onQueryChanged,
    required this.onToggleSkill,
  });

  final double maxHeight;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final List<String> selectedSkillKeys;
  final List<_ComposerSkillOption> filteredSkills;
  final bool isLoading;
  final bool hasQuery;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onToggleSkill;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Material(
      key: const Key('assistant-skill-picker-popover'),
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 360,
          maxWidth: 480,
          maxHeight: maxHeight,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surfacePrimary,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.strokeSoft),
            boxShadow: [palette.chromeShadowAmbient],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: TextField(
                  key: const Key('assistant-skill-picker-search'),
                  controller: searchController,
                  focusNode: searchFocusNode,
                  autofocus: true,
                  onChanged: onQueryChanged,
                  decoration: InputDecoration(
                    hintText: appText('搜索技能', 'Search skills'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: searchController.text.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: appText('清除', 'Clear'),
                            onPressed: () {
                              searchController.clear();
                              onQueryChanged('');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              Container(height: 1, color: palette.strokeSoft),
              Expanded(
                child: filteredSkills.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isLoading) ...[
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: palette.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              Text(
                                isLoading
                                    ? appText('正在加载技能…', 'Loading skills…')
                                    : hasQuery
                                    ? appText('没有匹配的技能。', 'No matching skills.')
                                    : appText(
                                        '当前没有已加载技能。',
                                        'No skills are loaded yet.',
                                      ),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        itemCount: filteredSkills.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final skill = filteredSkills[index];
                          return _SkillPickerTile(
                            key: ValueKey<String>(
                              'assistant-skill-option-${skill.key}',
                            ),
                            option: skill,
                            selected: selectedSkillKeys.contains(skill.key),
                            onTap: () => onToggleSkill(skill.key),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillPickerTile extends StatelessWidget {
  const _SkillPickerTile({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _ComposerSkillOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Tooltip(
      message: _skillOptionTooltip(option),
      waitDuration: const Duration(milliseconds: 250),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: selected
                  ? palette.surfaceSecondary
                  : palette.surfacePrimary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.strokeSoft),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
