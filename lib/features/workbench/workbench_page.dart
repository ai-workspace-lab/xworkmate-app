import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/sidebar_reveal_toggle.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../theme/app_palette.dart';
import '../../widgets/pane_toggle_icon.dart';
import 'workbench_analytics.dart';
import 'workbench_detail_pages.dart';
import 'workbench_insight_sidebar.dart';
import 'workbench_projection.dart';

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  int _tabIndex = 0;
  int _activityWindow = 0;
  bool _insightsExpanded = true;
  Future<void> _openThread(String sessionKey) async {
    await widget.controller.switchSession(sessionKey);
    widget.controller.navigateTo(WorkspaceDestination.assistant);
  }

  void _openAssistant() {
    widget.controller.navigateTo(WorkspaceDestination.assistant);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final projection = buildWorkbenchProjection(
          sessions: widget.controller.assistantSessions,
          threadForSession: widget.controller.taskThreadForSessionInternal,
        );
        return Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    WorkbenchNavigation(
                      index: _tabIndex,
                      activityWindow: _activityWindow,
                      onChanged: (index) => setState(() => _tabIndex = index),
                      onActivityWindowChanged: (value) {
                        setState(() => _activityWindow = value);
                      },
                      onQuickRecord: _openAssistant,
                      leading: SidebarRevealToggle(
                        controller: widget.controller,
                      ),
                      trailing: Tooltip(
                        message: _insightsExpanded
                            ? appText('收起工作洞察', 'Hide work insights')
                            : appText('展开工作洞察', 'Show work insights'),
                        child: IconButton(
                          key: Key(
                            _insightsExpanded
                                ? 'workbench-insights-collapse-button'
                                : 'workbench-insights-expand-button',
                          ),
                          onPressed: () => setState(
                            () => _insightsExpanded = !_insightsExpanded,
                          ),
                          color: context.palette.textSecondary,
                          icon: const PaneToggleIcon(
                            side: PaneSide.right,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: switch (_tabIndex.clamp(0, 4)) {
                        0 => WorkbenchDataOverview(
                          projection: projection,
                          activityWindow: _activityWindow,
                          onOpenThread: _openThread,
                        ),
                        1 => WorkbenchModelAnalysis(
                          projection: projection,
                          activityWindow: _activityWindow,
                          onOpenThread: _openThread,
                        ),
                        2 => WorkbenchTodoPage(
                          items: projection.todos,
                          onOpenThread: _openThread,
                        ),
                        3 => WorkbenchProjectsPage(
                          projects: projection.projects,
                          onOpenThread: _openThread,
                        ),
                        _ => WorkbenchInboxPage(
                          items: projection.inbox,
                          onOpenThread: _openThread,
                        ),
                      },
                    ),
                  ],
                ),
              ),
            ),
            WorkbenchInsightSidebar(
              projection: projection,
              expanded: _insightsExpanded,
            ),
          ],
        );
      },
    );
  }
}
