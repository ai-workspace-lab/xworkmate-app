import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_controller_desktop_thread_binding.dart';
import '../../app/ui_feature_manifest.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_palette.dart';

class MobileAssistantListPage extends StatefulWidget {
  const MobileAssistantListPage({
    super.key,
    required this.controller,
    required this.onSelectTask,
  });

  final AppController controller;
  final ValueChanged<String> onSelectTask;

  @override
  State<MobileAssistantListPage> createState() => _MobileAssistantListPageState();
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
        .visibleAssistantExecutionTargets(
          uiFeatures.availableExecutionTargets,
        );
    
    final sessionKey = widget.controller.createAssistantDraftSessionKeyInternal();
    final target = pickDraftThreadExecutionTargetInternal(
      currentTarget: widget.controller.currentAssistantExecutionTarget,
      visibleTargets: visibleExecutionTargets,
      localWorkspaceAvailable: widget.controller.settings.workspacePath.trim().isNotEmpty,
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
            final previewMatch = (s.lastMessagePreview ?? '').toLowerCase().contains(q);
            return titleMatch || previewMatch;
          }).toList();
        }

        return Scaffold(
          backgroundColor: palette.canvas,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              CupertinoSliverNavigationBar(
                backgroundColor: palette.canvas.withValues(alpha: 0.8),
                largeTitle: const Text('XWorkmate'),
                border: null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        setState(() {
                          _isSearchVisible = !_isSearchVisible;
                          if (!_isSearchVisible) {
                            _searchController.clear();
                            _searchQuery = '';
                          }
                        });
                      },
                      child: Icon(
                        CupertinoIcons.search,
                        color: palette.textPrimary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        // TODO: Open settings or profile
                      },
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: palette.accent,
                        child: const Text('X', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isSearchVisible)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: CupertinoSearchTextField(
                      controller: _searchController,
                      placeholder: appText('搜索任务', 'Search tasks'),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.trim();
                        });
                      },
                      style: TextStyle(color: palette.textPrimary),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                  child: Text(
                    appText('最近', 'Recent'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: palette.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (sessions.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      appText('暂无任务', 'No tasks found'),
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final session = sessions[index];
                      final sessionKey = session.key.trim();
                      final pending = widget.controller.assistantSessionHasPendingRun(sessionKey);
                      
                      final title = session.label.trim().isEmpty
                          ? appText('新对话', 'New conversation')
                          : session.label.trim();
                      final preview = session.lastMessagePreview?.trim() ?? '';
                      
                      return Dismissible(
                        key: ValueKey(sessionKey),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20.0),
                          color: palette.warning,
                          child: const Icon(CupertinoIcons.archivebox, color: Colors.white),
                        ),
                        onDismissed: (direction) {
                          widget.controller.saveAssistantTaskArchived(sessionKey, true);
                        },
                        child: InkWell(
                          onTap: () => widget.onSelectTask(sessionKey),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: pending ? palette.accentMuted : palette.surfacePrimary,
                                  child: Icon(
                                    pending ? CupertinoIcons.bolt_fill : CupertinoIcons.chat_bubble_2,
                                    color: pending ? palette.accent : palette.textSecondary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: palette.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        preview.isEmpty ? appText('未开始', 'Not started') : preview,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: palette.textSecondary,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
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
                    childCount: sessions.length,
                  ),
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('mobile-assistant-fab-create'),
            onPressed: _handleCreateTask,
            backgroundColor: palette.accent,
            foregroundColor: Colors.white,
            elevation: 4,
            icon: const Icon(CupertinoIcons.add),
            label: Text(
              appText('聊天', 'Chat'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }
}
