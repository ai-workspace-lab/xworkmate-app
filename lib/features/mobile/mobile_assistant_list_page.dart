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
              SliverAppBar(
                backgroundColor: palette.canvas,
                surfaceTintColor: Colors.transparent,
                pinned: true,
                title: Text(
                  'XWorkmate',
                  style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.bold, fontSize: 20),
                ),
                centerTitle: false,
                actions: [
                  IconButton(
                    icon: Icon(
                      CupertinoIcons.search,
                      color: palette.textPrimary,
                      size: 24,
                    ),
                    onPressed: () {
                      setState(() {
                        _isSearchVisible = !_isSearchVisible;
                        if (!_isSearchVisible) {
                          _searchController.clear();
                          _searchQuery = '';
                        }
                      });
                    },
                  ),
                  Builder(
                    builder: (context) {
                      return IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          Scaffold.of(context).openDrawer();
                        },
                        icon: CircleAvatar(
                          radius: 14,
                          backgroundColor: palette.accent,
                          child: const Text('X', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      );
                    }
                  ),
                  const SizedBox(width: 8),
                ],
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
                      
                      final title = session.label.trim().isEmpty
                          ? appText('新对话', 'New conversation')
                          : session.label.trim();
                      
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
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16,
                                      color: palette.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
          drawer: Drawer(
            backgroundColor: palette.surfacePrimary,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: palette.accent,
                          child: const Text('X', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'XWorkmate',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: palette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(CupertinoIcons.person, color: palette.textPrimary),
                    title: Text(appText('账号登录', 'Account Login'), style: TextStyle(color: palette.textPrimary)),
                    onTap: () {
                      Navigator.pop(context);
                      widget.controller.openSettings(tab: SettingsTab.gateway);
                      widget.controller.navigateTo(WorkspaceDestination.settings);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.inventory_2_outlined, color: palette.textPrimary),
                    title: Text(appText('归档管理', 'Archived Tasks'), style: TextStyle(color: palette.textPrimary)),
                    onTap: () {
                      Navigator.pop(context);
                      widget.controller.openSettings(tab: SettingsTab.archivedTasks);
                      widget.controller.navigateTo(WorkspaceDestination.settings);
                    },
                  ),
                  const Spacer(),
                  const Divider(),
                  ListTile(
                    leading: Icon(CupertinoIcons.info_circle, color: palette.textPrimary),
                    title: Text(appText('关于', 'About'), style: TextStyle(color: palette.textPrimary)),
                    onTap: () {
                      Navigator.pop(context);
                      showAboutDialog(
                        context: context,
                        applicationName: 'XWorkmate',
                        applicationVersion: '1.0.0',
                        applicationLegalese: '© 2026 Cloud Neutral Toolkit',
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('mobile-assistant-fab-create'),
            onPressed: _handleCreateTask,
            backgroundColor: palette.textPrimary,
            foregroundColor: palette.canvas,
            elevation: 4,
            icon: const Icon(Icons.edit_square, size: 20),
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
