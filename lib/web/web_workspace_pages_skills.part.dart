part of 'web_workspace_pages.dart';

class WebSkillsPage extends StatefulWidget {
  const WebSkillsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebSkillsPage> createState() => _WebSkillsPageState();
}

class _WebSkillsPageState extends State<WebSkillsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedSkillKey;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final skills = controller.skills
            .where(_matchesQuery)
            .toList(growable: false);
        final selected = _resolveSelectedSkill(skills);
        return DesktopWorkspaceScaffold(
          breadcrumbs: _buildWebBreadcrumbs(
            controller,
            rootLabel: WorkspaceDestination.skills.label,
          ),
          eyebrow: appText('技能与能力包', 'Skills and capabilities'),
          title: appText('技能工作台', 'Skills workspace'),
          subtitle: appText(
            '左侧浏览技能包，右侧查看描述、依赖和使用建议。',
            'Browse skills on the left, inspect descriptions, dependencies, and usage guidance on the right.',
          ),
          toolbar: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() => _query = value.trim().toLowerCase());
                  },
                  decoration: InputDecoration(
                    hintText: appText('搜索技能', 'Search skills'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: appText('清除', 'Clear'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              IconButton(
                tooltip: appText('刷新技能', 'Refresh skills'),
                onPressed: () => controller.skillsController.refresh(
                  agentId: controller.selectedAgentId.isEmpty
                      ? null
                      : controller.selectedAgentId,
                ),
                icon: const Icon(Icons.refresh_rounded),
              ),
              FilledButton.tonalIcon(
                onPressed: () =>
                    controller.navigateTo(WorkspaceDestination.assistant),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(appText('回到对话使用', 'Use in assistant')),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SurfaceCard(
              padding: EdgeInsets.zero,
              borderRadius: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Row(
                  children: [
                    SizedBox(
                      width: 360,
                      child: _SkillsListPanel(
                        skills: skills,
                        selectedSkillKey: selected?.skillKey,
                        onSelectSkill: (skill) {
                          setState(() => _selectedSkillKey = skill.skillKey);
                        },
                      ),
                    ),
                    Container(width: 1, color: context.palette.strokeSoft),
                    Expanded(
                      child: _SkillDetailPanel(
                        controller: controller,
                        selected: selected,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _matchesQuery(GatewaySkillSummary skill) {
    if (_query.isEmpty) {
      return true;
    }
    final haystack = [
      skill.name,
      skill.description,
      skill.source,
      skill.skillKey,
      skill.primaryEnv ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(_query);
  }

  GatewaySkillSummary? _resolveSelectedSkill(List<GatewaySkillSummary> skills) {
    if (skills.isEmpty) {
      return null;
    }
    for (final skill in skills) {
      if (skill.skillKey == _selectedSkillKey) {
        return skill;
      }
    }
    return skills.first;
  }
}

class _SkillsListPanel extends StatelessWidget {
  const _SkillsListPanel({
    required this.skills,
    required this.selectedSkillKey,
    required this.onSelectSkill,
  });

  final List<GatewaySkillSummary> skills;
  final String? selectedSkillKey;
  final ValueChanged<GatewaySkillSummary> onSelectSkill;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(
            children: [
              Text(
                appText('技能列表', 'Skill list'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Text(
                '${skills.length}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
        Container(height: 1, color: palette.strokeSoft),
        Expanded(
          child: skills.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      appText(
                        '当前没有可展示的技能。',
                        'No skills are available right now.',
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: skills.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final skill = skills[index];
                    return _SkillListTile(
                      skill: skill,
                      selected: skill.skillKey == selectedSkillKey,
                      onTap: () => onSelectSkill(skill),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SkillListTile extends StatelessWidget {
  const _SkillListTile({
    required this.skill,
    required this.selected,
    required this.onTap,
  });

  final GatewaySkillSummary skill;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: selected ? palette.surfacePrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected ? palette.surfaceSecondary : Colors.transparent,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: palette.shadow.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: Text(
            skill.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: selected ? palette.textPrimary : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillDetailPanel extends StatelessWidget {
  const _SkillDetailPanel({required this.controller, required this.selected});

  final AppController controller;
  final GatewaySkillSummary? selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (selected == null) {
      return Center(
        child: Text(
          appText('选择左侧技能查看详情。', 'Select a skill on the left.'),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: palette.textSecondary),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                selected!.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              StatusBadge(
                status: selected!.disabled
                    ? _skillStatus(
                        appText('已禁用', 'Disabled'),
                        StatusTone.warning,
                      )
                    : _skillStatus(
                        appText('已启用', 'Enabled'),
                        StatusTone.success,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            selected!.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _DependencyCard(
                title: appText('缺失二进制', 'Missing bins'),
                values: selected!.missingBins,
              ),
              _DependencyCard(
                title: appText('缺失环境变量', 'Missing env'),
                values: selected!.missingEnv,
              ),
              _DependencyCard(
                title: appText('缺失配置', 'Missing config'),
                values: selected!.missingConfig,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.surfaceSecondary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appText('在对话中使用', 'Use in the assistant'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  appText(
                    '回到 Assistant 后，可通过下方建议按钮或直接描述需求来调用该技能上下文。',
                    'After returning to Assistant, use the suggested chips or describe the task directly to route into this skill context.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () =>
                    controller.navigateTo(WorkspaceDestination.assistant),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(appText('去对话中使用', 'Use in assistant')),
              ),
              OutlinedButton.icon(
                onPressed: () => controller.skillsController.refresh(
                  agentId: controller.selectedAgentId.isEmpty
                      ? null
                      : controller.selectedAgentId,
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(appText('刷新', 'Refresh')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DependencyCard extends StatelessWidget {
  const _DependencyCard({required this.title, required this.values});

  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            values.isEmpty ? appText('无', 'None') : values.join(', '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

StatusInfo _skillStatus(String label, StatusTone tone) =>
    StatusInfo(label, tone);
