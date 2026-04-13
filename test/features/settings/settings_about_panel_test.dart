import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/settings_about_panel.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/surface_card.dart';

void main() {
  testWidgets('renders app and bridge build metadata clearly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: 1100,
              child: SurfaceCard(
                child: SettingsAboutPanel(
                  snapshot: const SettingsAboutSnapshot(
                    appVersion: '1.0.0-beta.2',
                    appBuildNumber: '4',
                    appBuildDate: '2026-03-28',
                    appCommit: 'f153d7b',
                    bridgeEndpoint: 'https://xworkmate-bridge.svc.plus',
                    bridgeStatus: 'ok',
                    bridgeVersion: '991ecb0ae2f270cdf6cc7bd456d4391cce664ae2',
                    bridgeBuildDate: '2026-04-13T09:00:00Z',
                    bridgeCommit: '991ecb0ae2f270cdf6cc7bd456d4391cce664ae2',
                    bridgeImage:
                        'ghcr.io/x-evor/xworkmate-bridge:991ecb0ae2f270cdf6cc7bd456d4391cce664ae2',
                  ),
                  busy: false,
                  onRefresh: () async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('关于'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-about-app-version')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Version: 1.0.0-beta.2'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Build Date: 2026-03-28'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Commit: 991ecb0ae2f270cdf6cc7bd456d4391cce664ae2'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-about-refresh-button')),
      findsOneWidget,
    );
  });
}
