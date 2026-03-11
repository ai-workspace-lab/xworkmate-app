import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  AccountTab _tab = AccountTab.profile;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final settings = controller.settings;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                title: appText('账号', 'Account'),
                subtitle: appText(
                  '用户身份、工作区切换与登录会话。',
                  'Identity, workspace switching, and sign-in sessions.',
                ),
              ),
              const SizedBox(height: 24),
              SectionTabs(
                items: AccountTab.values.map((item) => item.label).toList(),
                value: _tab.label,
                size: SectionTabsSize.small,
                onChanged: (value) => setState(
                  () => _tab = AccountTab.values.firstWhere(
                    (item) => item.label == value,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_tab == AccountTab.profile)
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.accountUsername.trim().isEmpty
                            ? appText('本地操作员', 'Local Operator')
                            : settings.accountUsername,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        settings.accountLocalMode
                            ? appText(
                                '本地模式 · 占位账号会话',
                                'Local mode · Placeholder account session',
                              )
                            : appText(
                                '统一账号入口等待后端集成',
                                'Unified account entry pending backend integration',
                              ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: ValueKey(settings.accountBaseUrl),
                        initialValue: settings.accountBaseUrl,
                        decoration: InputDecoration(
                          labelText: appText('服务地址', 'Service URL'),
                        ),
                        onFieldSubmitted: (value) => controller.saveSettings(
                          settings.copyWith(accountBaseUrl: value),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: ValueKey(settings.accountUsername),
                        initialValue: settings.accountUsername,
                        decoration: InputDecoration(
                          labelText: appText('邮箱 / 用户名', 'Email / Username'),
                        ),
                        onFieldSubmitted: (value) => controller.saveSettings(
                          settings.copyWith(accountUsername: value),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_tab == AccountTab.workspace)
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.accountWorkspace,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        appText(
                          '$kProductBrandName 的工作区外壳',
                          'Workspace shell for $kProductBrandName',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: ValueKey(settings.accountWorkspace),
                        initialValue: settings.accountWorkspace,
                        decoration: InputDecoration(
                          labelText: appText('工作区名称', 'Workspace Label'),
                        ),
                        onFieldSubmitted: (value) => controller.saveSettings(
                          settings.copyWith(accountWorkspace: value),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_tab == AccountTab.sessions)
                if (controller.sessions.isEmpty)
                  SurfaceCard(
                    child: Text(
                      appText(
                        '还没有 Gateway 会话。请先连接并开始一次对话。',
                        'No gateway sessions yet. Connect and start a chat first.',
                      ),
                    ),
                  )
                else
                  ...controller.sessions.map(
                    (session) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SurfaceCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    session.label,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${session.surface ?? appText('会话', 'Session')} · ${session.kind ?? 'chat'}',
                                  ),
                                ],
                              ),
                            ),
                            Text(session.model ?? appText('网关', 'gateway')),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
