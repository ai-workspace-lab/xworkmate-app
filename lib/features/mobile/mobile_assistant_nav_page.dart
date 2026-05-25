import 'package:flutter/cupertino.dart';

import '../../app/app_controller.dart';
import '../../app/workspace_page_registry.dart';
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
            builder = (BuildContext context) => MobileAssistantListPage(
                  controller: widget.controller,
                  onSelectTask: (sessionKey) async {
                    await widget.controller.switchSession(sessionKey);
                    if (!mounted) return;
                    _navigatorKey.currentState?.pushNamed('/detail');
                  },
                );
            break;
          case '/detail':
            builder = (BuildContext context) => MobileAssistantDetailPage(
                  controller: widget.controller,
                  onOpenDetail: widget.onOpenDetail,
                  mobileActions: widget.mobileActions,
                  onBack: () => _navigatorKey.currentState?.pop(),
                );
            break;
          default:
            builder = (BuildContext context) => const SizedBox();
        }
        return CupertinoPageRoute(
          builder: builder,
          settings: settings,
        );
      },
    ));
  }
}
