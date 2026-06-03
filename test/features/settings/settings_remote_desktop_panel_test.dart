import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/settings/settings_remote_desktop_panel.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/surface_card.dart';

void main() {
  group('SettingsRemoteDesktopPanel', () {
    testWidgets('renders the panel title and connection dashboard', (tester) async {
      // Set desktop window size
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      
      final store = _MemorySecureConfigStore();
      final controller = _NoopRefreshAppController(store: store);
      addTearDown(() {
        controller.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: SettingsRemoteDesktopPanel(controller: controller),
        ),
      );

      // Verify the panel headers and titles
      expect(find.text('远程桌面'), findsOneWidget);
      expect(find.text('连接桌面'), findsOneWidget);
      expect(find.text('GPU 加速'), findsOneWidget);

      // Verify inputs
      expect(find.widgetWithText(TextField, 'Display'), findsOneWidget);
      expect(find.text('Display'), findsOneWidget);
    });
  });
}

Widget _buildTestApp({required Widget child}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Material(
      child: Center(
        child: SizedBox(
          width: 1100,
          child: SurfaceCard(child: child),
        ),
      ),
    ),
  );
}

class _NoopRefreshAppController extends AppController {
  _NoopRefreshAppController({required SecureConfigStore store})
      : super(environmentOverride: const <String, String>{}, store: store);

  Future<void> refreshAcpCapabilitiesInternal({
    bool forceRefresh = false,
    bool persistMountTargets = false,
  }) async {}

  Future<void> refreshSingleAgentCapabilitiesInternal({
    bool forceRefresh = false,
  }) async {}
}

class _MemorySecureConfigStore extends SecureConfigStore {
  _MemorySecureConfigStore() : super(enableSecureStorage: false);

  SettingsSnapshot _settings = SettingsSnapshot.defaults();
  final Map<String, String> _secrets = <String, String>{};

  @override
  Future<void> initialize() async {}

  @override
  Future<SettingsSnapshot> loadSettingsSnapshot() async => _settings;

  @override
  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) async {
    _settings = snapshot;
  }

  @override
  Future<Map<String, String>> loadSecureRefs() async => _secrets;

  @override
  Future<List<SecretAuditEntry>> loadAuditTrail() async =>
      const <SecretAuditEntry>[];

  @override
  Future<void> appendAudit(SecretAuditEntry entry) async {}

  @override
  Future<String?> loadSecretValueByRef(String refName) async =>
      _secrets[refName];

  @override
  Future<void> saveSecretValueByRef(String refName, String value) async {
    _secrets[refName] = value;
  }

  @override
  Future<String?> loadAccountSessionToken() async => null;

  @override
  Future<AccountSessionSummary?> loadAccountSessionSummary() async => null;

  @override
  Future<AccountSyncState?> loadAccountSyncState() async => null;
}
