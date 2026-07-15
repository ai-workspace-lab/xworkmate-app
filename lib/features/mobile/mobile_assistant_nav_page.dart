import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../app/app_controller.dart';
import '../../app/workspace_page_registry.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import 'mobile_assistant_list_page.dart';
import 'mobile_assistant_page_core.dart';

class MobileAssistantNavPage extends StatefulWidget {
  const MobileAssistantNavPage({
    super.key,
    required this.controller,
    required this.onOpenDetail,
    this.mobileActions = const MobileWorkspaceActions(),
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;
  final MobileWorkspaceActions mobileActions;

  @override
  State<MobileAssistantNavPage> createState() => _MobileAssistantNavPageState();
}

class _MobileAssistantNavPageState extends State<MobileAssistantNavPage> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  void _openTaskList() {
    _navigatorKey.currentState?.pushNamed('/tasks');
  }

  void _returnHome() {
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('mobile-assistant-page'),
      child: Navigator(
        key: _navigatorKey,
        initialRoute: '/',
        onGenerateRoute: (RouteSettings settings) {
          WidgetBuilder builder;
          switch (settings.name) {
            case '/':
              builder = (BuildContext context) => MobileAssistantDetailPage(
                controller: widget.controller,
                onOpenDetail: widget.onOpenDetail,
                mobileActions: widget.mobileActions,
                onBack: _openTaskList,
              );
              break;
            case '/tasks':
              builder = (BuildContext context) => MobileAssistantListPage(
                controller: widget.controller,
                onBackHome: _returnHome,
                onSelectTask: (sessionKey) async {
                  _returnHome();
                  unawaited(widget.controller.switchSession(sessionKey));
                },
              );
              break;
            default:
              builder = (BuildContext context) => Center(
                child: CupertinoButton(
                  onPressed: _returnHome,
                  child: Text(appText('返回对话主页', 'Back to Chat')),
                ),
              );
          }
          return CupertinoPageRoute(builder: builder, settings: settings);
        },
      ),
    );
  }
}
