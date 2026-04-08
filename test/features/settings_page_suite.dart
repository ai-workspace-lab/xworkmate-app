@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/assistant/assistant_page_message_widgets.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/desktop_platform_service.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/skill_directory_access.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/section_tabs.dart';

import '../test_support.dart';

class _DesktopServiceStub implements DesktopPlatformService {
  @override
  DesktopIntegrationState get state =>
      DesktopIntegrationState.fromJson(const <String, dynamic>{
        'isSupported': true,
        'environment': 'kde',
        'mode': 'proxy',
        'trayAvailable': true,
        'trayEnabled': true,
        'autostartEnabled': false,
        'networkManagerAvailable': true,
        'systemProxy': {
          'enabled': true,
          'host': '127.0.0.1',
          'port': 7890,
          'backend': 'kioslaverc',
          'lastAppliedMode': 'proxy',
        },
        'tunnel': {
          'available': true,
          'connected': false,
          'connectionName': 'XWorkmate Tunnel',
          'backend': 'nmcli',
          'lastError': '',
        },
        'statusMessage': '',
      });

  @override
  bool get isSupported => state.isSupported;

  @override
  Future<void> initialize(LinuxDesktopConfig config) async {}

  @override
  Future<void> syncConfig(LinuxDesktopConfig config) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> setMode(VpnMode mode) async {}

  @override
  Future<void> connectTunnel() async {}

  @override
  Future<void> disconnectTunnel() async {}

  @override
  Future<void> setLaunchAtLogin(bool enabled) async {}

  @override
  void dispose() {}
}

Future<AppController> _createControllerWithSkillAccessService(
  WidgetTester tester,
  SkillDirectoryAccessService skillDirectoryAccessService,
) async {
  final controller = AppController(
    store: createIsolatedTestStore(enableSecureStorage: false),
    skillDirectoryAccessService: skillDirectoryAccessService,
  );
  addTearDown(controller.dispose);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
  return controller;
}

class _FakeSkillDirectoryAccessService implements SkillDirectoryAccessService {
  _FakeSkillDirectoryAccessService({
    required this.userHomeDirectory,
    this.multiDirectoryResponse = const <AuthorizedSkillDirectory>[],
  });

  final String userHomeDirectory;
  final List<AuthorizedSkillDirectory> multiDirectoryResponse;

  @override
  bool get isSupported => true;

  @override
  Future<String> resolveUserHomeDirectory() async {
    return userHomeDirectory;
  }

  @override
  Future<List<AuthorizedSkillDirectory>> authorizeDirectories({
    List<String> suggestedPaths = const <String>[],
  }) async {
    return multiDirectoryResponse;
  }

  @override
  Future<AuthorizedSkillDirectory?> authorizeDirectory({
    String suggestedPath = '',
  }) async {
    final normalized = normalizeAuthorizedSkillDirectoryPath(suggestedPath);
    if (normalized.isEmpty) {
      return null;
    }
    return AuthorizedSkillDirectory(
      path: normalized,
      bookmark: 'bookmark-${normalized.hashCode}',
    );
  }

  @override
  Future<SkillDirectoryAccessHandle?> openDirectory(
    AuthorizedSkillDirectory directory,
  ) async {
    final normalized = normalizeAuthorizedSkillDirectoryPath(directory.path);
    if (normalized.isEmpty) {
      return null;
    }
    return SkillDirectoryAccessHandle(path: normalized, onClose: () async {});
  }
}

Future<void> _pumpSettingsPage(
  WidgetTester tester,
  AppController controller, {
  SettingsTab tab = SettingsTab.general,
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  controller.setSettingsTab(tab);
  await pumpPage(
    tester,
    child: SettingsPage(controller: controller),
    platform: platform,
  );
}

Future<void> _pumpWithoutSettling(
  WidgetTester tester, {
  required Widget child,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1000);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light(platform: TargetPlatform.macOS),
      darkTheme: AppTheme.dark(platform: TargetPlatform.macOS),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

Future<void> _ensureVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('SettingsPage theme chips update controller theme mode', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await _pumpSettingsPage(tester, controller, tab: SettingsTab.appearance);
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.dark);

    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(controller.themeMode, ThemeMode.light);
  });

  testWidgets('SettingsPage hides account access controls by default', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: SettingsPage(controller: controller),
      platform: TargetPlatform.macOS,
    );

    expect(find.text('账号访问'), findsNothing);
    expect(find.text('Account Access'), findsNothing);
    expect(find.text('账号本地模式'), findsNothing);
    expect(find.text('Account local mode'), findsNothing);
  });

  testWidgets('SettingsPage can expose account access when feature enabled', (
    WidgetTester tester,
  ) async {
    final manifest = UiFeatureManifest.fallback().copyWithFeature(
      platform: UiFeaturePlatform.desktop,
      module: 'settings',
      feature: 'account_access',
      enabled: true,
      releaseTier: UiFeatureReleaseTier.experimental,
    );
    final controller = await createTestController(
      tester,
      uiFeatureManifest: manifest,
    );

    await pumpPage(
      tester,
      child: SettingsPage(controller: controller),
      platform: TargetPlatform.macOS,
    );

    expect(find.text('账号访问'), findsOneWidget);
    expect(find.text('账号本地模式'), findsOneWidget);
  });

  testWidgets(
    'SettingsPage workspace tab no longer exposes remote project root',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await _pumpSettingsPage(tester, controller, tab: SettingsTab.workspace);

      expect(find.text('远程项目根目录'), findsNothing);
      expect(find.text('Remote Project Root'), findsNothing);
    },
  );

  testWidgets(
    'SettingsPage renders only the active section without internal tabs',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await pumpPage(
        tester,
        child: SettingsPage(controller: controller, showSectionTabs: false),
        platform: TargetPlatform.macOS,
      );

      expect(find.byType(SectionTabs), findsNothing);
      expect(find.text('Application'), findsOneWidget);
      expect(find.text('OpenClaw Gateway'), findsNothing);
      expect(find.text('LLM 接入点'), findsNothing);
      expect(find.text('工作区路径'), findsNothing);
      expect(
        find.byKey(const ValueKey('external-acp-provider-add-button')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'SettingsPage workspace edits enable the top save-and-apply flow',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await _pumpSettingsPage(tester, controller, tab: SettingsTab.workspace);

      await tester.enterText(
        find.byType(TextFormField).first,
        '/tmp/xworkmate-workspace',
      );
      await tester.pump();

      expect(
        controller.settingsDraft.workspacePath,
        '/tmp/xworkmate-workspace',
      );
      expect(controller.hasSettingsDraftChanges, isTrue);

      final applyButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('settings-global-apply-button')),
      );
      expect(applyButton.onPressed, isNotNull);
    },
  );

  testWidgets('SettingsPage integration tab exposes unified gateway controls', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await _pumpSettingsPage(tester, controller, tab: SettingsTab.gateway);

    expect(find.text('OpenClaw Gateway'), findsWidgets);
    expect(find.text('LLM 接入点'), findsOneWidget);
    expect(find.text('Vault Server'), findsAtLeastNWidgets(1));
    expect(find.byKey(const ValueKey('gateway-test-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('gateway-save-button')), findsNothing);
    expect(find.byKey(const ValueKey('gateway-apply-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gateway-profile-chip-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gateway-profile-chip-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gateway-profile-chip-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gateway-profile-chip-3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gateway-profile-chip-4')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('gateway-profile-chip-2')),
        matching: find.text('连接源 1（空）'),
      ),
      findsOneWidget,
    );
    expect(find.text('自定义连接源 1（空）'), findsNothing);
    expect(
      find.byKey(const ValueKey('gateway-device-security-card')),
      findsOneWidget,
    );

    expect(
      find.byKey(const ValueKey('vault-server-url-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('vault-root-access-token-field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ai-gateway-url-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('gateway-mode-field')), findsNothing);
    expect(find.text('认证诊断'), findsNothing);
    expect(
      find.byKey(const ValueKey('external-acp-provider-add-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-global-apply-button')),
      findsNothing,
    );
  });

  testWidgets('SettingsPage vault card exposes concrete K/V fields', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await _pumpSettingsPage(tester, controller, tab: SettingsTab.gateway);

    expect(find.text('Vault Server'), findsAtLeastNWidgets(1));
    expect(find.text('VAULT_SERVER_URL'), findsOneWidget);
    expect(
      find.textContaining('VAULT_SERVER_ROOT_ACCESS_TOKEN'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('vault-save-button')), findsNothing);
    expect(find.byKey(const ValueKey('vault-apply-button')), findsOneWidget);
  });

  testWidgets('SettingsPage integration tab exposes ACP provider endpoints', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await _pumpSettingsPage(tester, controller, tab: SettingsTab.gateway);

    expect(find.text('外部 ACP Server Endpoint'), findsOneWidget);
    expect(find.textContaining('Codex'), findsWidgets);
    expect(find.textContaining('OpenCode'), findsWidgets);
    expect(find.text('Claude'), findsNothing);
    expect(find.text('Gemini'), findsNothing);
    expect(
      find.byKey(const ValueKey('external-acp-provider-add-button')),
      findsOneWidget,
    );
    expect(find.text('添加更多自定义配置'), findsOneWidget);
    expect(find.textContaining('ws://127.0.0.1:9001'), findsWidgets);
    expect(find.text('标志'), findsNothing);
    expect(find.text('Badge'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-global-save-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings-global-apply-button')),
      findsNothing,
    );
  });

  testWidgets('SettingsPage ACP wizard adds a custom provider card', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await _pumpSettingsPage(tester, controller, tab: SettingsTab.gateway);

    await _ensureVisible(
      tester,
      find.byKey(const ValueKey('external-acp-provider-add-button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('external-acp-provider-add-button')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('external-acp-wizard-name-field')),
      'Lab Agent',
    );
    await tester.enterText(
      find.byKey(const ValueKey('external-acp-wizard-endpoint-field')),
      'wss://lab.example.com/acp',
    );
    await tester.tap(
      find.byKey(const ValueKey('external-acp-wizard-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lab Agent'), findsWidgets);
    expect(find.text('wss://lab.example.com/acp'), findsWidgets);
  });

  testWidgets('SettingsPage skills authorization tab keeps only preset roots', (
    WidgetTester tester,
  ) async {
    final controller = await _createControllerWithSkillAccessService(
      tester,
      _FakeSkillDirectoryAccessService(userHomeDirectory: '/Users/tester'),
    );

    await _pumpSettingsPage(tester, controller, tab: SettingsTab.gateway);

    expect(find.text('~/.agents/skills'), findsOneWidget);
    expect(find.text('/Users/tester/.agents/skills'), findsOneWidget);
    expect(find.text('~/.codex/skills'), findsOneWidget);
    expect(find.text('/Users/tester/.codex/skills'), findsOneWidget);
    expect(find.text('~/.workbuddy/skills'), findsOneWidget);
    expect(find.text('/Users/tester/.workbuddy/skills'), findsOneWidget);
  });

  testWidgets('SettingsPage can batch add custom skills directories', (
    WidgetTester tester,
  ) async {
    final controller = await _createControllerWithSkillAccessService(
      tester,
      _FakeSkillDirectoryAccessService(
        userHomeDirectory: '/Users/tester',
        multiDirectoryResponse: const <AuthorizedSkillDirectory>[
          AuthorizedSkillDirectory(
            path: '/Users/tester/custom-a',
            bookmark: 'bookmark-a',
          ),
          AuthorizedSkillDirectory(
            path: '/Users/tester/custom-b',
            bookmark: 'bookmark-b',
          ),
        ],
      ),
    );

    await _pumpSettingsPage(tester, controller, tab: SettingsTab.gateway);
    await _ensureVisible(
      tester,
      find.byKey(const ValueKey('skill-directory-batch-add-button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('skill-directory-batch-add-button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('skill-directory-path-input')),
      '''
paths:
  - /Users/tester/custom-a
  - "/Users/tester/custom-b"
''',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('skill-directory-direct-add-button')),
    );
    await tester.pump();
    for (
      var attempt = 0;
      attempt < 10 && controller.authorizedSkillDirectories.length < 2;
      attempt += 1
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      controller.authorizedSkillDirectories.map((item) => item.path),
      containsAll(const <String>[
        '/Users/tester/custom-a',
        '/Users/tester/custom-b',
      ]),
    );
    expect(find.text('custom-a'), findsOneWidget);
    expect(find.text('custom-b'), findsOneWidget);
  });

  testWidgets('SettingsPage skills authorization dialog can use picker flow', (
    WidgetTester tester,
  ) async {
    final controller = await _createControllerWithSkillAccessService(
      tester,
      _FakeSkillDirectoryAccessService(
        userHomeDirectory: '/Users/tester',
        multiDirectoryResponse: const <AuthorizedSkillDirectory>[
          AuthorizedSkillDirectory(
            path: '/Users/tester/custom-picker',
            bookmark: 'bookmark-picker',
          ),
        ],
      ),
    );

    await _pumpSettingsPage(tester, controller, tab: SettingsTab.gateway);
    await _ensureVisible(
      tester,
      find.byKey(const ValueKey('skill-directory-batch-add-button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('skill-directory-batch-add-button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('skill-directory-path-input')),
      '/Users/tester/custom-picker',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('skill-directory-picker-button')),
    );
    await tester.pump();
    for (
      var attempt = 0;
      attempt < 10 && controller.authorizedSkillDirectories.isEmpty;
      attempt += 1
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      controller.authorizedSkillDirectories.map((item) => item.path),
      contains('/Users/tester/custom-picker'),
    );
  });

  testWidgets(
    'SettingsPage batch add normalizes pasted SKILL.md paths to skill package directories',
    (WidgetTester tester) async {
      final controller = await _createControllerWithSkillAccessService(
        tester,
        _FakeSkillDirectoryAccessService(userHomeDirectory: '/Users/tester'),
      );

      await _pumpSettingsPage(tester, controller, tab: SettingsTab.gateway);
      await _ensureVisible(
        tester,
        find.byKey(const ValueKey('skill-directory-batch-add-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('skill-directory-batch-add-button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('skill-directory-path-input')),
        '/Users/tester/workspaces/ai-workflow-craft/skills/docx/SKILL.md',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('skill-directory-direct-add-button')),
      );
      await tester.pump();
      for (
        var attempt = 0;
        attempt < 10 && controller.authorizedSkillDirectories.isEmpty;
        attempt += 1
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        controller.authorizedSkillDirectories.map((item) => item.path),
        const <String>[
          '/Users/tester/workspaces/ai-workflow-craft/skills/docx',
        ],
      );
      expect(find.text('docx'), findsOneWidget);
    },
  );

  testWidgets('SettingsPage gateway sections can collapse individually', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await _pumpSettingsPage(tester, controller, tab: SettingsTab.gateway);

    await tester.tap(find.byTooltip('折叠').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('gateway-host-field')), findsNothing);
    expect(find.byKey(const ValueKey('gateway-test-button')), findsNothing);
    expect(
      find.byKey(const ValueKey('gateway-device-security-card')),
      findsNothing,
    );

    await tester.tap(find.byTooltip('展开').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('gateway-host-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('gateway-test-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gateway-device-security-card')),
      findsOneWidget,
    );
  });

  testWidgets('SettingsPage external ACP section can collapse independently', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await _pumpSettingsPage(tester, controller, tab: SettingsTab.gateway);

    await _ensureVisible(tester, find.text('外部 ACP Server Endpoint'));
    await tester.tap(find.text('外部 ACP Server Endpoint').first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('external-acp-provider-add-button')),
      findsNothing,
    );
    expect(find.textContaining('OpenCode'), findsNothing);

    await tester.tap(find.text('外部 ACP Server Endpoint').first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('external-acp-provider-add-button')),
      findsOneWidget,
    );
    expect(find.textContaining('OpenCode'), findsWidgets);
  });

  testWidgets('SettingsPage external ACP card supports continuous input', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    final customProfile = buildCustomExternalAcpEndpointProfile(
      controller.settingsDraft.externalAcpEndpoints,
      label: 'Initial Name',
      endpoint: 'wss://initial.example.com/acp',
    );
    await controller.saveSettingsDraft(
      controller.settingsDraft.copyWith(
        externalAcpEndpoints: <ExternalAcpEndpointProfile>[
          ...controller.settingsDraft.externalAcpEndpoints,
          customProfile,
        ],
      ),
    );

    await _pumpSettingsPage(tester, controller, tab: SettingsTab.gateway);

    final labelField = find.byKey(
      ValueKey('external-acp-label-${customProfile.providerKey}'),
    );
    final testButton = find.byKey(
      ValueKey('external-acp-test-${customProfile.providerKey}'),
    );
    final saveButton = find.byKey(
      ValueKey('external-acp-save-${customProfile.providerKey}'),
    );

    expect(labelField, findsOneWidget);
    expect(testButton, findsOneWidget);
    expect(saveButton, findsOneWidget);

    await tester.enterText(labelField, 'A');
    await tester.pump();
    await tester.enterText(labelField, 'AB');
    await tester.pump();
    await tester.enterText(labelField, 'ABC');
    await tester.pump();

    expect(find.text('ABC'), findsOneWidget);
  });

  testWidgets('SettingsPage shows Linux desktop integration controls', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(
      tester,
      desktopPlatformService: _DesktopServiceStub(),
    );

    await _pumpSettingsPage(tester, controller);

    expect(
      find.byKey(const ValueKey('linux-desktop-integration-card')),
      findsOneWidget,
    );
    expect(find.text('Linux 桌面集成'), findsOneWidget);
    expect(find.text('切换到代理'), findsOneWidget);
    expect(find.text('连接隧道'), findsOneWidget);
  });

  testWidgets('SettingsPage multi-agent tab keeps header readable', (
    WidgetTester tester,
  ) async {
    final manifest = UiFeatureManifest.fallback().copyWithFeature(
      platform: UiFeaturePlatform.desktop,
      module: 'settings',
      feature: 'agents',
      enabled: true,
      releaseTier: UiFeatureReleaseTier.stable,
    );
    final controller = await createTestController(
      tester,
      uiFeatureManifest: manifest,
    );

    await pumpPage(
      tester,
      child: const SizedBox(width: 1100, height: 900, child: Placeholder()),
      platform: TargetPlatform.macOS,
    );
    controller.setSettingsTab(SettingsTab.agents);
    await pumpPage(
      tester,
      child: SizedBox(
        width: 1100,
        height: 900,
        child: SettingsPage(controller: controller),
      ),
      platform: TargetPlatform.macOS,
    );

    final titleFinder = find.text('多 Agent 协作');
    expect(titleFinder, findsOneWidget);
    expect(tester.getSize(titleFinder).width, greaterThan(80));
    expect(find.text('启用协作模式'), findsOneWidget);
    expect(find.text('协作框架'), findsOneWidget);
    expect(find.textContaining('Lead Engineer'), findsWidgets);
    expect(find.textContaining('ollama launch codex'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SettingsPage hides gateway setup code editor by default', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await _pumpSettingsPage(tester, controller, tab: SettingsTab.gateway);
    await tester.tap(find.byKey(const ValueKey('gateway-profile-chip-1')));
    await tester.pumpAndSettle();

    expect(find.text('配置码'), findsNothing);
    expect(
      find.byKey(const ValueKey('gateway-setup-code-field')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('gateway-host-field')), findsOneWidget);
  });

  testWidgets(
    'SettingsPage gateway save and apply marks the selected gateway target as saved even for default-valued profiles',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await _pumpSettingsPage(tester, controller, tab: SettingsTab.gateway);
      await tester.tap(find.byKey(const ValueKey('gateway-profile-chip-0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gateway-apply-button')));
      await tester.pumpAndSettle();

      expect(controller.settings.savedGatewayTargets, contains('local'));
    },
  );

  testWidgets('SettingsPage diagnostics tab filters and clears runtime logs', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.runtime.addRuntimeLogForTest(
      level: 'info',
      category: 'connect',
      message: 'connected remote gateway',
    );
    controller.runtime.addRuntimeLogForTest(
      level: 'warn',
      category: 'pairing',
      message: 'pairing required',
    );

    await _pumpSettingsPage(
      tester,
      controller,
      tab: SettingsTab.diagnostics,
      platform: TargetPlatform.android,
    );

    expect(find.byKey(const ValueKey('runtime-log-card')), findsOneWidget);
    expect(find.textContaining('connected remote gateway'), findsOneWidget);
    expect(find.textContaining('pairing required'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('runtime-log-filter')),
      'pairing',
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('connected remote gateway'), findsNothing);
    expect(find.textContaining('pairing required'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.runtimeLogs, isEmpty);
  });

  testWidgets(
    'Assistant homepage chip and settings pairing card stay globally consistent for a connected gateway snapshot',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.remote,
      );
      final remoteProfile = controller.settings.primaryRemoteGatewayProfile;
      setGatewaySnapshotForTest(
        controller,
        GatewayConnectionSnapshot.initial(mode: RuntimeConnectionMode.remote)
            .copyWith(
              status: RuntimeConnectionStatus.connected,
              statusText: 'Connected',
              remoteAddress: '${remoteProfile.host}:${remoteProfile.port}',
              lastError: 'NOT_PAIRED: pairing required',
              lastErrorCode: 'NOT_PAIRED',
              lastErrorDetailCode: 'PAIRING_REQUIRED',
            ),
      );

      await _pumpWithoutSettling(
        tester,
        child: ConnectionChipInternal(controller: controller),
      );

      expect(find.byKey(const Key('assistant-connection-chip')), findsOneWidget);
      expect(
        find.textContaining(
          '已连接 · ${remoteProfile.host}:${remoteProfile.port}',
        ),
        findsOneWidget,
      );

      controller.setSettingsTab(SettingsTab.gateway);
      await _pumpWithoutSettling(
        tester,
        child: SettingsPage(controller: controller),
      );

      expect(find.text('需要设备审批'), findsNothing);
      expect(find.text('Pairing Required'), findsNothing);
    },
  );

  testWidgets('SettingsPage hides tabs disabled by feature manifest', (
    WidgetTester tester,
  ) async {
    final manifest = UiFeatureManifest.fallback()
        .copyWithFeature(
          platform: UiFeaturePlatform.desktop,
          module: 'settings',
          feature: 'diagnostics',
          enabled: false,
        )
        .copyWithFeature(
          platform: UiFeaturePlatform.desktop,
          module: 'settings',
          feature: 'experimental',
          enabled: false,
        );
    final controller = await createTestController(
      tester,
      uiFeatureManifest: manifest,
    );

    await _pumpSettingsPage(tester, controller);

    expect(find.text('诊断'), findsNothing);
    expect(find.text('实验特性'), findsNothing);
  });

  testWidgets(
    'SettingsPage clears local assistant state with double confirmation',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await _pumpSettingsPage(tester, controller, tab: SettingsTab.diagnostics);

      expect(
        find.byKey(const ValueKey('assistant-local-state-card')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('assistant-local-state-clear-button')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final confirmButtonFinder = find.widgetWithText(FilledButton, '确认清理');
      final confirmButtonBefore = tester.widget<FilledButton>(
        confirmButtonFinder,
      );
      expect(confirmButtonBefore.onPressed, isNull);

      await tester.tap(
        find.byKey(const ValueKey('assistant-local-state-clear-confirm')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final confirmButtonAfter = tester.widget<FilledButton>(
        confirmButtonFinder,
      );
      expect(confirmButtonAfter.onPressed, isNotNull);
    },
  );

  testWidgets('SettingsPage detail mode returns to overview', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.openSettings(
      detail: SettingsDetailPage.gatewayConnection,
      navigationContext: SettingsNavigationContext(
        rootLabel: '设置',
        destination: WorkspaceDestination.settings,
        sectionLabel: SettingsTab.gateway.label,
        settingsTab: SettingsTab.gateway,
      ),
    );

    await pumpPage(
      tester,
      child: SettingsPage(
        controller: controller,
        initialTab: controller.settingsTab,
        initialDetail: controller.settingsDetail,
        navigationContext: controller.settingsNavigationContext,
      ),
    );

    expect(find.text('Gateway 连接参数'), findsWidgets);
    expect(find.text('返回概览'), findsOneWidget);

    await tester.tap(find.text('返回概览'));
    await tester.pumpAndSettle();

    expect(controller.settingsDetail, isNull);
    expect(find.text('搜索设置'), findsOneWidget);
  });

  testWidgets('Sidebar settings entry resets to general overview', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.openSettings(tab: SettingsTab.workspace);

    controller.navigateTo(WorkspaceDestination.assistant);
    controller.openSettings(tab: SettingsTab.general);

    expect(controller.destination, WorkspaceDestination.settings);
    expect(controller.settingsTab, SettingsTab.general);

    await pumpPage(
      tester,
      child: SettingsPage(
        controller: controller,
        initialTab: controller.settingsTab,
        initialDetail: controller.settingsDetail,
        navigationContext: controller.settingsNavigationContext,
      ),
      platform: TargetPlatform.macOS,
    );

    expect(find.byType(SectionTabs), findsNothing);
    expect(find.text('Application'), findsOneWidget);
  });

  testWidgets('SettingsPage expands optional LLM endpoints with add button', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.openSettings(
      detail: SettingsDetailPage.aiGatewayIntegration,
      navigationContext: SettingsNavigationContext(
        rootLabel: '设置',
        destination: WorkspaceDestination.settings,
        sectionLabel: SettingsTab.gateway.label,
        settingsTab: SettingsTab.gateway,
      ),
    );

    await pumpPage(
      tester,
      child: SettingsPage(
        controller: controller,
        initialTab: controller.settingsTab,
        initialDetail: controller.settingsDetail,
        navigationContext: controller.settingsNavigationContext,
      ),
    );

    expect(find.byKey(const ValueKey('llm-endpoint-chip-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('llm-endpoint-chip-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('llm-endpoint-add-button')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('llm-endpoint-chip-0')),
        matching: find.textContaining('主 LLM API'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('llm-endpoint-chip-1')),
        matching: find.textContaining('Ollama 本地'),
      ),
      findsOneWidget,
    );
    expect(find.text('连接源详情'), findsOneWidget);
    expect(find.textContaining('自定义连接源'), findsNothing);
    expect(find.byKey(const ValueKey('llm-endpoint-chip-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('llm-endpoint-panel-ollamaLocal')),
      findsOneWidget,
    );
  });
}
