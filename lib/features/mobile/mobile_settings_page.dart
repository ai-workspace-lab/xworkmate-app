import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/ui_feature_manifest.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import 'mobile_settings_page_widgets.dart';
import '../settings/settings_logs_panel.dart';
import '../settings/settings_plugins_panel.dart';
import '../settings/settings_help_panel.dart';

/// 保存 + 连通性刷新的等待上限。设置持久化链路上任何一环卡住（历史上出现过
/// store 写入在某些环境下不返回），都不能让按钮无限转圈——超时后按「仍在
/// 后台继续」如实反馈，而不是假装成功或假装失败。
const Duration mobileManualBridgeFeedbackTimeoutInternal = Duration(seconds: 8);

class MobileSettingsPage extends StatefulWidget {
  const MobileSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<MobileSettingsPage> createState() => _MobileSettingsPageState();
}

class _MobileSettingsPageState extends State<MobileSettingsPage> {
  late final TextEditingController accountBaseUrlController;
  late final TextEditingController accountIdentifierController;
  late final TextEditingController accountPasswordController;
  late final TextEditingController accountMfaCodeController;
  late final TextEditingController bridgeUrlController;
  late final TextEditingController bridgeTokenController;
  String lastSavedAccountBaseUrl = '';
  String lastSavedAccountIdentifier = '';
  String lastSavedBridgeUrl = '';
  bool accountSyncing = false;
  bool manualBridgeSaving = false;
  /// 手动 Bridge 已生效时，默认展示「已连接视图」；用户点「编辑配置」才
  /// 回到表单。未生效时表单本来就是常驻的，这个标志不参与判断。
  bool manualBridgeEditing = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    lastSavedAccountBaseUrl = settings.accountBaseUrl;
    lastSavedAccountIdentifier = settings.accountUsername;
    lastSavedBridgeUrl =
        settings.acpBridgeServerModeConfig.selfHosted.serverUrl;
    accountBaseUrlController = TextEditingController(
      text: lastSavedAccountBaseUrl,
    );
    accountIdentifierController = TextEditingController(
      text: lastSavedAccountIdentifier,
    );
    accountPasswordController = TextEditingController();
    accountMfaCodeController = TextEditingController();
    bridgeUrlController = TextEditingController(text: lastSavedBridgeUrl);
    bridgeTokenController = TextEditingController();
    unawaited(loadBridgeToken());
  }

  @override
  void dispose() {
    accountBaseUrlController.dispose();
    accountIdentifierController.dispose();
    accountPasswordController.dispose();
    accountMfaCodeController.dispose();
    bridgeUrlController.dispose();
    bridgeTokenController.dispose();
    super.dispose();
  }

  Future<void> loadBridgeToken() async {
    final token = await widget.controller.settingsController
        .loadSecretValueByRef(
          widget
              .controller
              .settings
              .acpBridgeServerModeConfig
              .selfHosted
              .passwordRef,
        );
    if (!mounted) {
      return;
    }
    bridgeTokenController.text = token;
  }

  void syncControllers(SettingsSnapshot settings) {
    if (accountBaseUrlController.text == lastSavedAccountBaseUrl &&
        settings.accountBaseUrl != lastSavedAccountBaseUrl) {
      accountBaseUrlController.text = settings.accountBaseUrl;
    }
    if (accountIdentifierController.text == lastSavedAccountIdentifier &&
        settings.accountUsername != lastSavedAccountIdentifier) {
      accountIdentifierController.text = settings.accountUsername;
    }
    lastSavedAccountBaseUrl = settings.accountBaseUrl;
    lastSavedAccountIdentifier = settings.accountUsername;

    final bridgeConfig = settings.acpBridgeServerModeConfig;
    if (bridgeUrlController.text == lastSavedBridgeUrl &&
        bridgeConfig.selfHosted.serverUrl != lastSavedBridgeUrl) {
      bridgeUrlController.text = bridgeConfig.selfHosted.serverUrl;
    }
    lastSavedBridgeUrl = bridgeConfig.selfHosted.serverUrl;
  }

  /// 返回本次保存后手动 Bridge 是否已配置完整。调用方据此决定要不要等待
  /// 能力刷新——[deferCapabilityRefresh] 为 true 时不在这里 fire-and-forget，
  /// 由调用方 await，从而能把刷新结果反馈给用户。
  Future<bool> persistAccountProfileSettings({
    required SettingsSnapshot settings,
    required bool isManualBridge,
    bool refreshAfterSave = true,
    bool deferCapabilityRefresh = false,
  }) async {
    final nextSettings = await widget.controller.settingsController
        .buildSavedAccountProfileSettings(
          settings: settings,
          accountBaseUrl: accountBaseUrlController.text,
          accountIdentifier: accountIdentifierController.text,
          bridgeServerUrl: bridgeUrlController.text,
          bridgeToken: bridgeTokenController.text,
          isManualBridge: isManualBridge,
        );
    await widget.controller.saveSettings(
      nextSettings,
      refreshAfterSave: isManualBridge ? false : refreshAfterSave,
    );
    lastSavedAccountBaseUrl = nextSettings.accountBaseUrl;
    lastSavedAccountIdentifier = nextSettings.accountUsername;
    lastSavedBridgeUrl =
        nextSettings.acpBridgeServerModeConfig.selfHosted.serverUrl;
    final manualBridgeConfigured =
        nextSettings.acpBridgeServerModeConfig.selfHosted.isConfigured;
    if (isManualBridge && manualBridgeConfigured && !deferCapabilityRefresh) {
      unawaited(refreshBridgeCapabilities());
    }
    return manualBridgeConfigured;
  }

  /// 保存手动 Bridge 配置并等待连通性刷新，把结果以 SnackBar 反馈出去。
  /// 之前这里是 fire-and-forget：点了保存没有任何回执，用户无法判断
  /// 地址/令牌是否真的能连上。
  Future<void> saveManualBridge(SettingsSnapshot settings) async {
    if (manualBridgeSaving) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      manualBridgeSaving = true;
      // 设置是同步生效的：不锁住表单的话，刚点下保存卡片就会翻成
      // 「已连接」——那是在连通性验证完成之前就宣称连上了。保存期间
      // 留在表单上，验证有结果再切换。
      manualBridgeEditing = true;
    });
    bool configured = false;
    bool timedOut = false;
    String? failure;
    try {
      // 整个「保存 + 刷新」共用一个超时预算：逐段各给一次超时会让最坏
      // 等待时间翻倍，用户点一次要等两倍时长才拿到回执。
      await () async {
        configured = await persistAccountProfileSettings(
          settings: settings,
          isManualBridge: true,
          deferCapabilityRefresh: true,
        );
        if (configured) {
          // 必须 await：按钮要保持忙碌态直到能力刷新落地，
          // 否则反馈会早于真实连接状态出现。
          await refreshBridgeCapabilities();
        }
      }().timeout(mobileManualBridgeFeedbackTimeoutInternal);
    } on TimeoutException {
      timedOut = true;
    } catch (e, stackTrace) {
      debugPrint('Error: $e\n$stackTrace');
      failure = '$e';
    } finally {
      if (mounted) {
        setState(() => manualBridgeSaving = false);
      }
    }
    if (mounted && failure == null) {
      // 解除表单锁定，让视图回归由持久化结果自行判定：settings 里真的
      // 生效了才会显示已连接视图，没生效则表单继续在（用户输入还在）。
      // 不用 configured 兜底——超时时它仍是初始值 false，并不代表没保存。
      setState(() => manualBridgeEditing = false);
    }
    if (!mounted || messenger == null) {
      return;
    }
    final connection = widget.controller.currentAssistantConnectionState;
    final String message;
    if (timedOut) {
      message = appText(
        '保存仍在进行中，请稍后在助手页确认连接状态',
        'Still saving; check the connection status on the Assistant page',
      );
    } else if (failure != null) {
      message = appText('保存失败：$failure', 'Save failed: $failure');
    } else if (!configured) {
      message = appText(
        '已保存，但 Bridge 地址或令牌不完整',
        'Saved, but the Bridge URL or token is incomplete',
      );
    } else if (connection.connected) {
      message = appText(
        '已保存 · 连接成功：${connection.detailLabel}',
        'Saved · Connected: ${connection.detailLabel}',
      );
    } else {
      final reason = (connection.lastError ?? '').trim().isNotEmpty
          ? connection.lastError!.trim()
          : connection.primaryLabel;
      message = appText('已保存，但未能连接：$reason', 'Saved, but not connected: $reason');
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('mobile-settings-manual-bridge-snackbar'),
          behavior: SnackBarBehavior.floating,
          content: Text(message),
        ),
      );
  }

  /// 清空手动 Bridge 配置，回到「可以走 svc.plus 登录」的状态。
  /// 手动 Bridge 一旦配置生效，账号登录卡片就不再显示；没有这个出口的话
  /// 用户会被困在手动模式里，既退不出也换不回托管登录。
  Future<void> resetManualBridge() async {
    if (manualBridgeSaving) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => manualBridgeSaving = true);
    String? failure;
    // 输入框先清空：即使后面的持久化卡住，UI 也已回到可重配的状态。
    bridgeUrlController.clear();
    bridgeTokenController.clear();
    lastSavedBridgeUrl = '';
    manualBridgeEditing = false;
    try {
      // 同样共用一个总预算，避免逐段超时把最坏等待时间叠成三倍。
      await () async {
        final current = widget.controller.settings;
        final passwordRef =
            current.acpBridgeServerModeConfig.selfHosted.passwordRef;
        // 先落配置重置：用户要的「退出手动模式」只取决于这一步，
        // 把它排在密钥清理后面的话，密钥清理一卡住就整个退不出去。
        await widget.controller.saveSettings(
          current.copyWith(
            acpBridgeServerModeConfig: AcpBridgeServerModeConfig.defaults(),
          ),
          refreshAfterSave: false,
        );
        if (passwordRef.trim().isNotEmpty) {
          await widget.controller.settingsController.storeInternal
              .clearSecretValueByRef(passwordRef);
        }
        await widget.controller.settingsController.refreshDerivedState();
      }().timeout(mobileManualBridgeFeedbackTimeoutInternal);
    } on TimeoutException {
      // 清理链路卡住时不阻塞 UI：本地输入已清空，下次进入仍可重配。
    } catch (e, stackTrace) {
      debugPrint('Error: $e\n$stackTrace');
      failure = '$e';
    } finally {
      if (mounted) {
        setState(() => manualBridgeSaving = false);
      }
    }
    if (!mounted || messenger == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('mobile-settings-manual-bridge-snackbar'),
          behavior: SnackBarBehavior.floating,
          content: Text(
            failure == null
                ? appText('已清除手动 Bridge 配置', 'Manual Bridge config cleared')
                : appText('清除失败：$failure', 'Reset failed: $failure'),
          ),
        ),
      );
  }

  Future<void> loginAccount(SettingsSnapshot settings) async {
    try {
      final baseUrl = accountBaseUrlController.text.trim();
      final identifier = accountIdentifierController.text.trim();
      await widget.controller.settingsController.loginAccount(
        baseUrl: baseUrl,
        identifier: identifier,
        password: accountPasswordController.text,
      );
      if (!widget.controller.settingsController.accountSignedIn) {
        return;
      }
      await persistAccountProfileSettings(
        settings: widget.controller.settings,
        isManualBridge: false,
        refreshAfterSave: false,
      );
      unawaited(refreshBridgeCapabilities());
    } finally {
      accountPasswordController.clear();
    }
  }

  Future<void> syncAccount(SettingsSnapshot settings) async {
    if (accountSyncing) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => accountSyncing = true);
    AccountSyncResult result;
    try {
      await persistAccountProfileSettings(
        settings: settings,
        isManualBridge: false,
        refreshAfterSave: false,
      );
      result = await widget.controller.settingsController.syncAccountSettings(
        baseUrl: accountBaseUrlController.text.trim(),
      );
      // Keep the button in its busy state until capabilities reflect the sync,
      // so the card and the feedback land at the same moment.
      await refreshBridgeCapabilities();
    } catch (e, stackTrace) {
      debugPrint('Error: $e\n$stackTrace');
      result = AccountSyncResult(state: 'error', message: '$e');
    } finally {
      if (mounted) {
        setState(() => accountSyncing = false);
      }
    }
    if (!mounted || messenger == null) {
      return;
    }
    final succeeded = result.state.trim() == 'ready';
    final message = result.message.trim();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('mobile-settings-account-sync-snackbar'),
          behavior: SnackBarBehavior.floating,
          content: Text(
            succeeded
                ? appText('同步完成：$message', 'Sync complete: $message')
                : appText('同步失败：$message', 'Sync failed: $message'),
          ),
        ),
      );
  }

  Future<void> verifyMfa(SettingsSnapshot settings) async {
    try {
      await persistAccountProfileSettings(
        settings: settings,
        isManualBridge: false,
        refreshAfterSave: false,
      );
      await widget.controller.settingsController.verifyAccountMfa(
        baseUrl: accountBaseUrlController.text.trim(),
        code: accountMfaCodeController.text.trim(),
      );
      unawaited(refreshBridgeCapabilities());
    } finally {
      accountMfaCodeController.clear();
    }
  }

  Future<void> refreshBridgeCapabilities() async {
    final dynamic controller = widget.controller;
    try {
      await controller.refreshSingleAgentCapabilitiesInternal(
        forceRefresh: true,
      );
    } catch (e, stackTrace) {
      debugPrint('Error: $e\n$stackTrace');
      // Account login should not fail only because runtime refresh is transient.
    }
    try {
      await controller.refreshAcpCapabilitiesInternal(forceRefresh: true);
    } catch (e, stackTrace) {
      debugPrint('Error: $e\n$stackTrace');
      // Runtime capabilities can be refreshed again from Assistant.
    }
  }

  Future<void> logoutAccount() async {
    await widget.controller.settingsController.logoutAccount();
    accountPasswordController.clear();
    accountMfaCodeController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.controller,
        widget.controller.settingsController,
      ]),
      builder: (context, _) {
        final controller = widget.controller;
        final settings = controller.settings;
        syncControllers(settings);
        final features = controller.featuresFor(
          resolveUiFeaturePlatformFromContext(context),
        );
        final availableTabs = features.availableSettingsTabs;
        final currentTab = availableTabs.contains(controller.settingsTab)
            ? controller.settingsTab
            : SettingsTab.gateway;
        final palette = context.palette;
        final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 16;
        return ColoredBox(
          key: const Key('mobile-settings-page'),
          color: palette.canvas,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => controller.navigateTo(
                          WorkspaceDestination.assistant,
                        ),
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
                      const SizedBox(height: 24),
                      Text(
                        appText('设置', 'Settings'),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      if (availableTabs.length > 1) ...[
                        MobileSettingsTabSelectorInternal(
                          currentTab: currentTab,
                          availableTabs: availableTabs,
                          onChanged: (tab) => controller.openSettings(tab: tab),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (currentTab == SettingsTab.archivedTasks)
                        _ArchivedTasksSection(controller: controller)
                      else if (currentTab == SettingsTab.plugins)
                        const SettingsPluginsPanel()
                      else if (currentTab == SettingsTab.logs)
                        SettingsLogsPanel(controller: controller)
                      else if (currentTab == SettingsTab.help)
                        const SettingsHelpPanel()
                      else
                        _AccountSection(
                          settings: settings,
                          accountSession:
                              controller.settingsController.accountSession,
                          accountState:
                              controller.settingsController.accountSyncState,
                          accountBusy:
                              controller.settingsController.accountBusy,
                          accountSyncing: accountSyncing,
                          accountStatus:
                              controller.settingsController.accountStatus,
                          accountSignedIn:
                              controller.settingsController.accountSignedIn,
                          accountMfaRequired:
                              controller.settingsController.accountMfaRequired,
                          accountBaseUrlController: accountBaseUrlController,
                          accountIdentifierController:
                              accountIdentifierController,
                          accountPasswordController: accountPasswordController,
                          accountMfaCodeController: accountMfaCodeController,
                          bridgeUrlController: bridgeUrlController,
                          bridgeTokenController: bridgeTokenController,
                          onLogin: () => loginAccount(settings),
                          onVerifyMfa: () => verifyMfa(settings),
                          onCancelMfa: () async {
                            await controller.settingsController
                                .cancelAccountMfaChallenge();
                            accountPasswordController.clear();
                            accountMfaCodeController.clear();
                          },
                          onSync: () => syncAccount(settings),
                          onLogout: logoutAccount,
                          manualBridgeSaving: manualBridgeSaving,
                          onSaveManualBridge: () => saveManualBridge(settings),
                          onResetManualBridge: resetManualBridge,
                          manualBridgeEditing: manualBridgeEditing,
                          onEditManualBridge: () =>
                              setState(() => manualBridgeEditing = true),
                          onCancelManualBridgeEdit: () =>
                              setState(() => manualBridgeEditing = false),
                        ),
                    ],
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

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.settings,
    required this.accountSession,
    required this.accountState,
    required this.accountBusy,
    required this.accountSyncing,
    required this.accountStatus,
    required this.accountSignedIn,
    required this.accountMfaRequired,
    required this.accountBaseUrlController,
    required this.accountIdentifierController,
    required this.accountPasswordController,
    required this.accountMfaCodeController,
    required this.bridgeUrlController,
    required this.bridgeTokenController,
    required this.onLogin,
    required this.onVerifyMfa,
    required this.onCancelMfa,
    required this.onSync,
    required this.onLogout,
    required this.manualBridgeSaving,
    required this.onSaveManualBridge,
    required this.onResetManualBridge,
    required this.manualBridgeEditing,
    required this.onEditManualBridge,
    required this.onCancelManualBridgeEdit,
  });

  final SettingsSnapshot settings;
  final AccountSessionSummary? accountSession;
  final AccountSyncState? accountState;
  final bool accountBusy;
  final bool accountSyncing;
  final String accountStatus;
  final bool accountSignedIn;
  final bool accountMfaRequired;
  final TextEditingController accountBaseUrlController;
  final TextEditingController accountIdentifierController;
  final TextEditingController accountPasswordController;
  final TextEditingController accountMfaCodeController;
  final TextEditingController bridgeUrlController;
  final TextEditingController bridgeTokenController;
  final Future<void> Function() onLogin;
  final Future<void> Function() onVerifyMfa;
  final Future<void> Function() onCancelMfa;
  final Future<void> Function() onSync;
  final Future<void> Function() onLogout;
  final bool manualBridgeSaving;
  final Future<void> Function() onSaveManualBridge;
  final Future<void> Function() onResetManualBridge;
  final bool manualBridgeEditing;
  final VoidCallback onEditManualBridge;
  final VoidCallback onCancelManualBridgeEdit;

  @override
  Widget build(BuildContext context) {
    if (accountMfaRequired) {
      return MobileSettingsCardInternal(
        key: const Key('mobile-settings-mfa-card'),
        icon: Icons.verified_user_outlined,
        title: appText('双重验证', 'Multi-Factor Authentication'),
        subtitle: appText(
          '输入验证码完成登录并同步托管 Bridge。',
          'Enter the code to finish sign-in and sync the managed Bridge.',
        ),
        children: [
          MobileSettingsTextFieldInternal(
            key: const Key('mobile-settings-account-mfa-code-field'),
            controller: accountMfaCodeController,
            label: appText('验证码', 'Code'),
            icon: Icons.key_outlined,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onVerifyMfa(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('mobile-settings-account-mfa-verify-button'),
                  onPressed: accountBusy ? null : onVerifyMfa,
                  child: Text(appText('验证', 'Verify')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonal(
                  key: const Key('mobile-settings-account-mfa-cancel-button'),
                  onPressed: accountBusy ? null : onCancelMfa,
                  child: Text(appText('返回', 'Back')),
                ),
              ),
            ],
          ),
        ],
      );
    }
    final manualBridgeConfigured =
        settings.acpBridgeServerModeConfig.effective.source == 'bridge';
    if (accountSignedIn) {
      final email = accountSession?.email.trim().isNotEmpty == true
          ? accountSession!.email.trim()
          : settings.accountUsername.trim();
      final status = accountState?.syncMessage.trim().isNotEmpty == true
          ? accountState!.syncMessage.trim()
          : accountStatus.trim();
      return Column(
        children: [
          MobileSettingsCardInternal(
            key: const Key('mobile-settings-account-signed-in-card'),
            icon: accountSyncing
                ? Icons.sync_rounded
                : Icons.cloud_done_outlined,
            title: email.isEmpty ? appText('已登录', 'Signed In') : email,
            subtitle: accountSyncing
                ? appText('正在同步托管 Bridge…', 'Syncing managed Bridge…')
                : status.isEmpty
                ? appText('svc.plus 托管 Bridge 已就绪。', 'Managed Bridge is ready.')
                : status,
            children: [
              MobileSettingsMetaRowInternal(
                icon: Icons.hub_outlined,
                label: appText('托管入口', 'Managed Endpoint'),
                value: kManagedBridgeServerUrl,
              ),
              const SizedBox(height: 8),
              MobileSettingsMetaRowInternal(
                key: const Key('mobile-settings-account-last-sync-row'),
                icon: Icons.schedule_rounded,
                label: appText('最近同步', 'Last Sync'),
                value: accountSyncing
                    ? appText('同步中…', 'Syncing…')
                    : _formatLastSyncTime(accountState?.lastSyncAtMs ?? 0),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('mobile-settings-account-sync-button'),
                      onPressed: accountBusy || accountSyncing ? null : onSync,
                      icon: accountSyncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                      label: Text(
                        accountSyncing
                            ? appText('同步中…', 'Syncing…')
                            : appText('同步', 'Sync'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      key: const Key('mobile-settings-account-logout-button'),
                      onPressed: accountBusy || accountSyncing
                          ? null
                          : onLogout,
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(appText('退出', 'Sign Out')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }
    if (manualBridgeConfigured) {
      // 与账号「已连接视图」对称：默认展示连接状态而不是编辑表单，
      // 需要改地址/令牌时再显式进入编辑。
      if (!manualBridgeEditing) {
        return _ManualBridgeConnectedCard(
          accountBusy: accountBusy,
          manualBridgeSaving: manualBridgeSaving,
          endpoint: settings.acpBridgeServerModeConfig.selfHosted.serverUrl,
          onEdit: onEditManualBridge,
          onReset: onResetManualBridge,
        );
      }
      return _ManualBridgeCard(
        accountBusy: accountBusy,
        bridgeUrlController: bridgeUrlController,
        bridgeTokenController: bridgeTokenController,
        manualBridgeSaving: manualBridgeSaving,
        onSaveManualBridge: onSaveManualBridge,
        onCancelEdit: onCancelManualBridgeEdit,
      );
    }
    return Column(
      children: [
        MobileSettingsCardInternal(
          key: const Key('mobile-settings-account-login-card'),
          icon: Icons.cloud_outlined,
          title: appText('svc.plus 登录', 'svc.plus Sign In'),
          subtitle: appText(
            '登录后同步托管 Bridge，助手会直接使用统一入口。',
            'Sign in to sync the managed Bridge for Assistant.',
          ),
          children: [
            if (accountStatus.trim().isNotEmpty &&
                accountStatus.trim() != 'Signed out') ...[
              MobileSettingsMetaRowInternal(
                icon: accountBusy
                    ? Icons.sync_rounded
                    : Icons.info_outline_rounded,
                label: appText('登录状态', 'Sign-in Status'),
                value: accountStatus.trim(),
              ),
              const SizedBox(height: 12),
            ],
            MobileSettingsTextFieldInternal(
              key: const Key('mobile-settings-account-base-url-field'),
              controller: accountBaseUrlController,
              label: appText('服务地址', 'Service URL'),
              icon: Icons.dns_outlined,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.url],
            ),
            const SizedBox(height: 10),
            MobileSettingsTextFieldInternal(
              key: const Key('mobile-settings-account-identifier-field'),
              controller: accountIdentifierController,
              label: appText('邮箱或账号', 'Email or Username'),
              icon: Icons.person_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
            ),
            const SizedBox(height: 10),
            MobileSettingsTextFieldInternal(
              key: const Key('mobile-settings-account-password-field'),
              controller: accountPasswordController,
              label: appText('密码', 'Password'),
              icon: Icons.lock_outline_rounded,
              obscureText: true,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => onLogin(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('mobile-settings-account-login-button'),
                onPressed: accountBusy ? null : onLogin,
                icon: accountBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login_rounded),
                label: Text(appText('登录', 'Sign In')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ManualBridgeCard(
          accountBusy: accountBusy,
          bridgeUrlController: bridgeUrlController,
          bridgeTokenController: bridgeTokenController,
          manualBridgeSaving: manualBridgeSaving,
          onSaveManualBridge: onSaveManualBridge,
        ),
      ],
    );
  }
}

/// 手动 Bridge 生效后的「已连接视图」，与账号登录成功后的卡片对称：
/// 展示当前入口与状态，并提供「编辑配置」与「退出」两个出口——退出后
/// svc.plus 登录与手动 Bridge 两张卡片会重新一起显示。
class _ManualBridgeConnectedCard extends StatelessWidget {
  const _ManualBridgeConnectedCard({
    required this.accountBusy,
    required this.manualBridgeSaving,
    required this.endpoint,
    required this.onEdit,
    required this.onReset,
  });

  final bool accountBusy;
  final bool manualBridgeSaving;
  final String endpoint;
  final VoidCallback onEdit;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) {
    final busy = accountBusy || manualBridgeSaving;
    return MobileSettingsCardInternal(
      key: const Key('mobile-settings-manual-bridge-connected-card'),
      icon: manualBridgeSaving ? Icons.sync_rounded : Icons.link_rounded,
      title: appText('手动 Bridge 已连接', 'Manual Bridge Connected'),
      subtitle: manualBridgeSaving
          ? appText('正在处理…', 'Working…')
          : appText(
              '当前使用手动配置的 Bridge，未走 svc.plus 托管登录。',
              'Using a manually configured Bridge instead of managed sign-in.',
            ),
      children: [
        MobileSettingsMetaRowInternal(
          key: const Key('mobile-settings-manual-bridge-endpoint-row'),
          icon: Icons.dns_outlined,
          label: appText('Bridge 地址', 'Bridge URL'),
          value: endpoint.trim().isEmpty ? '—' : endpoint.trim(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('mobile-settings-manual-bridge-edit-button'),
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: Text(appText('编辑配置', 'Edit Config')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonalIcon(
                key: const Key('mobile-settings-manual-bridge-reset-button'),
                onPressed: busy ? null : onReset,
                icon: manualBridgeSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded),
                label: Text(appText('退出', 'Exit')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ManualBridgeCard extends StatelessWidget {
  const _ManualBridgeCard({
    required this.accountBusy,
    required this.bridgeUrlController,
    required this.bridgeTokenController,
    required this.manualBridgeSaving,
    required this.onSaveManualBridge,
    this.onCancelEdit,
  });

  final bool accountBusy;
  final TextEditingController bridgeUrlController;
  final TextEditingController bridgeTokenController;
  final bool manualBridgeSaving;
  final Future<void> Function() onSaveManualBridge;

  /// 仅在「已生效后再次进入编辑」时提供；首次配置没有可取消的对象。
  final VoidCallback? onCancelEdit;

  @override
  Widget build(BuildContext context) {
    return MobileSettingsCardInternal(
      key: const Key('mobile-settings-manual-bridge-card'),
      icon: Icons.link_outlined,
      title: appText('手动 Bridge', 'Manual Bridge'),
      subtitle: appText(
        '仅用于私有或本地 Bridge；远端托管登录优先。',
        'Use only for private or local Bridge; managed sign-in is preferred.',
      ),
      children: [
        MobileSettingsTextFieldInternal(
          key: const Key('mobile-settings-manual-bridge-url-field'),
          controller: bridgeUrlController,
          label: appText('Bridge 地址', 'Bridge URL'),
          icon: Icons.dns_outlined,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        MobileSettingsTextFieldInternal(
          key: const Key('mobile-settings-manual-bridge-token-field'),
          controller: bridgeTokenController,
          label: appText('鉴权令牌', 'Auth Token'),
          icon: Icons.key_outlined,
          obscureText: true,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) =>
              accountBusy || manualBridgeSaving ? null : onSaveManualBridge(),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            key: const Key('mobile-settings-manual-bridge-save-button'),
            onPressed: accountBusy || manualBridgeSaving
                ? null
                : onSaveManualBridge,
            icon: manualBridgeSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              manualBridgeSaving
                  ? appText('正在连接…', 'Connecting…')
                  : appText('保存手动配置', 'Save Manual Config'),
            ),
          ),
        ),
        if (onCancelEdit != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              key: const Key('mobile-settings-manual-bridge-cancel-edit-button'),
              onPressed: manualBridgeSaving ? null : onCancelEdit,
              child: Text(appText('取消', 'Cancel')),
            ),
          ),
        ],
      ],
    );
  }
}

class _ArchivedTasksSection extends StatefulWidget {
  const _ArchivedTasksSection({required this.controller});

  final AppController controller;

  @override
  State<_ArchivedTasksSection> createState() => _ArchivedTasksSectionState();
}

class _ArchivedTasksSectionState extends State<_ArchivedTasksSection> {
  final Set<String> _selectedKeys = {};

  @override
  Widget build(BuildContext context) {
    final sessions = widget.controller.archivedAssistantSessions;
    if (sessions.isEmpty) {
      _selectedKeys.clear();
      return MobileSettingsCardInternal(
        key: const Key('mobile-settings-archived-empty-card'),
        icon: Icons.inventory_2_outlined,
        title: appText('归档任务', 'Archived Tasks'),
        subtitle: appText('暂无归档任务。', 'No archived tasks.'),
        children: const [],
      );
    }

    _selectedKeys.retainWhere((key) => sessions.any((s) => s.key == key));
    final allSelected = _selectedKeys.length == sessions.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Checkbox(
                value: allSelected,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedKeys.addAll(sessions.map((s) => s.key));
                    } else {
                      _selectedKeys.clear();
                    }
                  });
                },
              ),
              Text(
                appText(
                  '共 ${sessions.length} 条归档任务',
                  'Total ${sessions.length} archived tasks',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              if (_selectedKeys.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: () {
                    for (final key in _selectedKeys.toList()) {
                      widget.controller.saveAssistantTaskArchived(key, false);
                    }
                    setState(() {
                      _selectedKeys.clear();
                    });
                  },
                  icon: const Icon(Icons.unarchive_outlined, size: 18),
                  label: Text(appText('批量解除归档', 'Batch Restore')),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    for (final key in _selectedKeys.toList()) {
                      widget.controller.deleteArchivedAssistantTask(key);
                    }
                    setState(() {
                      _selectedKeys.clear();
                    });
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: Theme.of(context).colorScheme.error,
                  tooltip: appText('批量彻底删除', 'Batch Delete'),
                ),
              ],
            ],
          ),
        ),
        for (final session in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Checkbox(
                    value: _selectedKeys.contains(session.key),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedKeys.add(session.key);
                        } else {
                          _selectedKeys.remove(session.key);
                        }
                      });
                    },
                  ),
                ),
                Expanded(
                  child: MobileSettingsCardInternal(
                    icon: Icons.inventory_2_outlined,
                    title: session.label.trim().isEmpty
                        ? appText('未命名任务', 'Untitled Task')
                        : session.label.trim(),
                    subtitle: session.lastMessagePreview?.trim() ?? '',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () =>
                                  widget.controller.saveAssistantTaskArchived(
                                    session.key,
                                    false,
                                  ),
                              icon: const Icon(Icons.unarchive_outlined),
                              label: Text(appText('恢复', 'Restore')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () => widget.controller
                                  .deleteArchivedAssistantTask(session.key),
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: Text(appText('删除', 'Delete')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _formatLastSyncTime(int lastSyncAtMs) {
  if (lastSyncAtMs <= 0) {
    return appText('尚未同步', 'Not synced yet');
  }
  final at = DateTime.fromMillisecondsSinceEpoch(lastSyncAtMs).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)} '
      '${two(at.hour)}:${two(at.minute)}';
}
