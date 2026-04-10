import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/workspace_navigation.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/settings_page_shell.dart';
import '../../widgets/surface_card.dart';

enum _SettingsIntegrationTab { accountStatus, baseConnection }

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.initialTab = SettingsTab.gateway,
    this.initialDetail,
    this.navigationContext,
    this.showSectionTabs = true,
  });

  final AppController controller;
  final SettingsTab initialTab;
  final SettingsDetailPage? initialDetail;
  final SettingsNavigationContext? navigationContext;
  final bool showSectionTabs;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _searchController = TextEditingController();
  _SettingsIntegrationTab _integrationTab =
      _SettingsIntegrationTab.accountStatus;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _syncAccount(SettingsSnapshot settings) async {
    await widget.controller.settingsController.syncAccountSettings(
      baseUrl: settings.accountBaseUrl,
    );
  }

  Future<void> _logoutAccount() async {
    await widget.controller.settingsController.logoutAccount();
  }

  Future<void> _disconnectManagedBase(SettingsSnapshot settings) async {
    final nextSettings = settings.copyWith(
      accountLocalMode: true,
      acpBridgeServerModeConfig: settings.acpBridgeServerModeConfig.copyWith(
        mode: AcpBridgeServerMode.cloudSynced,
        cloudSynced: settings.acpBridgeServerModeConfig.cloudSynced.copyWith(
          accountIdentifier: '',
        ),
      ),
    );
    await widget.controller.saveSettings(nextSettings);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        controller,
        controller.settingsController,
      ]),
      builder: (context, _) {
        final settings = controller.settingsDraft;
        final accountState = controller.settingsController.accountSyncState;
        final accountBusy = controller.settingsController.accountBusy;
        final accountSignedIn = controller.settingsController.accountSignedIn;
        final accountSession = controller.settingsController.accountSession;
        final cloudSync = settings.acpBridgeServerModeConfig.cloudSynced;
        final remoteSummary = cloudSync.remoteServerSummary.endpoint.trim();
        final serviceUrl = cloudSync.accountBaseUrl.trim().isNotEmpty
            ? cloudSync.accountBaseUrl.trim()
            : settings.accountBaseUrl.trim();
        final accountIdentifier = cloudSync.accountIdentifier.trim().isNotEmpty
            ? cloudSync.accountIdentifier.trim()
            : settings.accountUsername.trim().isNotEmpty
            ? settings.accountUsername.trim()
            : (accountSession?.email.trim() ?? '');
        final sessionLabel = accountSignedIn
            ? appText(
                '已登录：${accountSession?.email.trim().isNotEmpty == true ? accountSession!.email.trim() : appText('当前账号', 'Current account')}',
                'Signed in: ${accountSession?.email.trim().isNotEmpty == true ? accountSession!.email.trim() : appText('Current account', 'Current account')}',
              )
            : appText('未登录', 'Signed out');
        final syncLabel = accountState == null
            ? appText('idle · 尚未同步远程配置', 'idle · Remote config not synced yet')
            : '${accountState.syncState} · ${accountState.syncMessage}';

        return SettingsPageBodyShell(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          breadcrumbs: buildSettingsBreadcrumbs(
            controller,
            tab: SettingsTab.gateway,
            detail: null,
            navigationContext: null,
          ),
          title: appText('设置', 'Settings'),
          subtitle: appText(
            '配置 XWorkmate 工作区、网关默认项、界面与诊断选项',
            'Configure XWorkmate workspace, gateway defaults, and diagnostics.',
          ),
          trailing: SizedBox(
            width: 220,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: appText('搜索设置', 'Search settings'),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          bodyChildren: <Widget>[
            SectionTabs(
              items: <String>[
                appText('用户登录状态', 'User Login State'),
                appText('基础连接配置', 'Base Connection Configuration'),
              ],
              value: _integrationTab == _SettingsIntegrationTab.accountStatus
                  ? appText('用户登录状态', 'User Login State')
                  : appText('基础连接配置', 'Base Connection Configuration'),
              onChanged: (value) {
                setState(() {
                  _integrationTab =
                      value == appText('用户登录状态', 'User Login State')
                      ? _SettingsIntegrationTab.accountStatus
                      : _SettingsIntegrationTab.baseConnection;
                });
              },
            ),
            const SizedBox(height: 16),
            if (_integrationTab == _SettingsIntegrationTab.accountStatus)
              SurfaceCard(
                key: const ValueKey('settings-account-status-card'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accountSession?.email.trim().isNotEmpty == true
                          ? accountSession!.email.trim()
                          : appText('本地操作员', 'Local Operator'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      appText(
                        '这里仅描述认证状态本身：登录、MFA、同步状态与当前账户身份。默认连接来源和高级覆盖在下面分别配置。',
                        'Only authentication state is shown here: sign-in, MFA, sync state, and current account identity.',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      sessionLabel,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      syncLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appText('登录状态摘要', 'Login Status Summary'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${appText('服务地址', 'Service URL')}: ${serviceUrl.isEmpty ? appText('待配置', 'Pending') : serviceUrl}',
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${appText('账户标识', 'Account Identifier')}: ${accountIdentifier.isEmpty ? appText('待登录', 'Not signed in') : accountIdentifier}',
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${appText('最近同步', 'Last Sync')}: ${_formatSyncTime(cloudSync.lastSyncAt)}',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.tonal(
                          key: const ValueKey('settings-account-sync-button'),
                          onPressed: accountBusy
                              ? null
                              : () => _syncAccount(settings),
                          child: Text(appText('重新同步', 'Sync Again')),
                        ),
                        FilledButton.tonal(
                          key: const ValueKey('settings-account-logout-button'),
                          onPressed: accountBusy || !accountSignedIn
                              ? null
                              : _logoutAccount,
                          child: Text(appText('退出登录', 'Log Out')),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              SurfaceCard(
                key: const ValueKey('settings-base-connection-card'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appText('基础连接配置', 'Base Connection Configuration'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      appText(
                        '这里维护默认连接来源与默认凭据。当前默认 UI 仅展示 svc.plus 提供的托管配置入口。',
                        'Default connection source and credentials are managed here. The current UI only exposes svc.plus managed configuration.',
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: null,
                      child: Text(
                        appText('svc.plus 提供', 'Provided by svc.plus'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        Chip(
                          label: Text(
                            appText(
                              '默认连接来源: svc.plus 提供',
                              'Default source: svc.plus',
                            ),
                          ),
                        ),
                        Chip(
                          label: Text(
                            '${appText('同步状态', 'Sync')}: ${accountState?.syncState ?? 'idle'}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      appText(
                        '当前默认来源为 svc.plus 提供的托管配置。你可以直接同步远端默认配置。',
                        'The current default source is the managed svc.plus profile. You can sync remote defaults directly.',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${appText('远端摘要', 'Remote Summary')}: ${remoteSummary.isEmpty ? appText('待同步', 'Pending sync') : remoteSummary}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${appText('最近同步', 'Last Sync')}: ${_formatSyncTime(cloudSync.lastSyncAt)}',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.tonal(
                          key: const ValueKey('settings-base-sync-button'),
                          onPressed: accountBusy
                              ? null
                              : () => _syncAccount(settings),
                          child: Text(appText('重新同步', 'Sync Again')),
                        ),
                        FilledButton.tonal(
                          key: const ValueKey(
                            'settings-base-disconnect-button',
                          ),
                          onPressed: accountBusy
                              ? null
                              : () => _disconnectManagedBase(settings),
                          child: Text(appText('断开', 'Disconnect')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatSyncTime(int lastSyncAtMs) {
    if (lastSyncAtMs <= 0) {
      return appText('尚未同步', 'Not synced yet');
    }
    return DateTime.fromMillisecondsSinceEpoch(
      lastSyncAtMs,
    ).toLocal().toIso8601String();
  }
}
