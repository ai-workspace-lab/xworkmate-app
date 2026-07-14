import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_controller_desktop_thread_binding.dart';
import '../../app/ui_feature_manifest.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../theme/app_palette.dart';

class MobileAssistantListPage extends StatefulWidget {
  const MobileAssistantListPage({
    super.key,
    required this.controller,
    required this.onSelectTask,
    this.onBackHome,
  });

  final AppController controller;
  final ValueChanged<String> onSelectTask;
  final VoidCallback? onBackHome;

  @override
  State<MobileAssistantListPage> createState() =>
      _MobileAssistantListPageState();
}

class _MobileAssistantListPageState extends State<MobileAssistantListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchVisible = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleCreateTask() async {
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
    widget.onSelectTask(sessionKey);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final palette = context.palette;

        var sessions = widget.controller.assistantSessions;
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          sessions = sessions.where((s) {
            final titleMatch = s.label.toLowerCase().contains(q);
            final previewMatch = (s.lastMessagePreview ?? '')
                .toLowerCase()
                .contains(q);
            return titleMatch || previewMatch;
          }).toList();
        }

        return Scaffold(
          backgroundColor: palette.canvas,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                children: [
                  if (widget.onBackHome != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: widget.onBackHome,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 16,
                              color: palette.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              appText('返回对话主页', 'Back to Chat'),
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                  _MobileListHeader(
                    isSearchVisible: _isSearchVisible,
                    onToggleSearch: () {
                      setState(() {
                        _isSearchVisible = !_isSearchVisible;
                        if (!_isSearchVisible) {
                          _searchController.clear();
                          _searchQuery = '';
                        }
                      });
                    },
                    onOpenAccount: () {
                      widget.controller.openSettings(tab: SettingsTab.gateway);
                      widget.controller.navigateTo(
                        WorkspaceDestination.settings,
                      );
                    },
                  ),
                  if (_isSearchVisible) ...[
                    const SizedBox(height: 18),
                    CupertinoSearchTextField(
                      controller: _searchController,
                      placeholder: appText('搜索任务', 'Search tasks'),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.trim();
                        });
                      },
                      style: TextStyle(color: palette.textPrimary),
                    ),
                  ],
                  const SizedBox(height: 28),
                  _MobileDestinationList(controller: widget.controller),
                  const SizedBox(height: 20),
                  Divider(color: palette.strokeSoft, height: 1),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      appText('最近', 'Recent'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: sessions.isEmpty
                        ? Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                appText('暂无任务', 'No tasks found'),
                                style: TextStyle(color: palette.textSecondary),
                              ),
                            ),
                          )
                        : ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.zero,
                            itemCount: sessions.length,
                            separatorBuilder: (_, _) =>
                                Divider(color: palette.strokeSoft, height: 1),
                            itemBuilder: (context, index) {
                              final session = sessions[index];
                              final sessionKey = session.key.trim();
                              final title = session.label.trim().isEmpty
                                  ? appText('新对话', 'New conversation')
                                  : session.label.trim();

                              return Dismissible(
                                key: ValueKey(sessionKey),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 18),
                                  color: palette.warning,
                                  child: const Icon(
                                    CupertinoIcons.archivebox,
                                    color: Colors.white,
                                  ),
                                ),
                                onDismissed: (_) {
                                  widget.controller.saveAssistantTaskArchived(
                                    sessionKey,
                                    true,
                                  );
                                },
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: palette.textPrimary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                  trailing: index < 3
                                      ? Icon(
                                          CupertinoIcons.pin_fill,
                                          color: palette.accent,
                                          size: 18,
                                        )
                                      : null,
                                  onTap: () => widget.onSelectTask(sessionKey),
                                ),
                              );
                            },
                          ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('mobile-assistant-fab-create'),
                          onPressed: _handleCreateTask,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(58),
                            backgroundColor: palette.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 28),
                          label: Text(
                            appText('新建任务', 'New task'),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      _MobileCircleButton(
                        icon: Icons.settings_outlined,
                        tooltip: appText('设置', 'Settings'),
                        onTap: () {
                          widget.controller.navigateTo(
                            WorkspaceDestination.settings,
                          );
                        },
                      ),
                    ],
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

class _MobileListHeader extends StatelessWidget {
  const _MobileListHeader({
    required this.isSearchVisible,
    required this.onToggleSearch,
    required this.onOpenAccount,
  });

  final bool isSearchVisible;
  final VoidCallback onToggleSearch;
  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  'XWorkmate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.accentMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    'v1.1',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: palette.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _MobileCircleButton(
          icon: CupertinoIcons.search,
          tooltip: appText('搜索', 'Search'),
          selected: isSearchVisible,
          onTap: onToggleSearch,
        ),
        const SizedBox(width: 12),
        _MobileCircleButton(
          icon: CupertinoIcons.person,
          tooltip: appText('账号', 'Account'),
          badge: true,
          onTap: onOpenAccount,
        ),
      ],
    );
  }
}

class _MobileDestinationList extends StatelessWidget {
  const _MobileDestinationList({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MobileDestinationItem(
        icon: Icons.tune_rounded,
        label: appText('集成配置', 'Integration'),
        onTap: () {
          controller.openSettings(tab: SettingsTab.gateway);
          controller.navigateTo(WorkspaceDestination.settings);
        },
      ),
      _MobileDestinationItem(
        icon: Icons.inventory_2_outlined,
        label: appText('归档任务', 'Archived tasks'),
        onTap: () {
          controller.openSettings(tab: SettingsTab.archivedTasks);
          controller.navigateTo(WorkspaceDestination.settings);
        },
      ),
      _MobileDestinationItem(
        icon: Icons.extension_outlined,
        label: appText('插件', 'Plugins'),
        onTap: () {
          controller.openSettings(tab: SettingsTab.plugins);
          controller.navigateTo(WorkspaceDestination.settings);
        },
      ),
      _MobileDestinationItem(
        icon: Icons.article_outlined,
        label: appText('运行日志', 'Run logs'),
        onTap: () {
          controller.openSettings(tab: SettingsTab.logs);
          controller.navigateTo(WorkspaceDestination.settings);
        },
      ),
    ];

    return Column(
      children: [
        for (final item in items)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: item),
      ],
    );
  }
}

class _MobileDestinationItem extends StatelessWidget {
  const _MobileDestinationItem({
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
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: palette.textPrimary, size: 26),
              const SizedBox(width: 22),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileCircleButton extends StatelessWidget {
  const _MobileCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
    this.badge = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? palette.accentMuted : palette.surfacePrimary,
                shape: BoxShape.circle,
                border: Border.all(color: palette.strokeSoft),
                boxShadow: [palette.chromeShadowAmbient],
              ),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Icon(
                  icon,
                  color: selected ? palette.accent : palette.textPrimary,
                  size: 26,
                ),
              ),
            ),
          ),
          if (badge)
            Positioned(
              right: 5,
              top: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.surfacePrimary, width: 2),
                ),
                child: const SizedBox(width: 12, height: 12),
              ),
            ),
        ],
      ),
    );
  }
}
