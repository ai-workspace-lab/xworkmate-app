import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';

@immutable
class SettingsAboutSnapshot {
  const SettingsAboutSnapshot({
    required this.appVersion,
    required this.appBuildNumber,
    required this.appBuildDate,
    required this.appCommit,
    required this.bridgeEndpoint,
    required this.bridgeStatus,
    required this.bridgeVersion,
    required this.bridgeBuildDate,
    required this.bridgeCommit,
    required this.bridgeImage,
  });

  final String appVersion;
  final String appBuildNumber;
  final String appBuildDate;
  final String appCommit;
  final String bridgeEndpoint;
  final String bridgeStatus;
  final String bridgeVersion;
  final String bridgeBuildDate;
  final String bridgeCommit;
  final String bridgeImage;

  const SettingsAboutSnapshot.defaults()
    : appVersion = '',
      appBuildNumber = '',
      appBuildDate = '',
      appCommit = '',
      bridgeEndpoint = '',
      bridgeStatus = '',
      bridgeVersion = '',
      bridgeBuildDate = '',
      bridgeCommit = '',
      bridgeImage = '';
}

class SettingsAboutPanel extends StatelessWidget {
  const SettingsAboutPanel({
    super.key,
    required this.snapshot,
    required this.busy,
    required this.onRefresh,
  });

  final SettingsAboutSnapshot snapshot;
  final bool busy;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appText('关于', 'About'),
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appText(
                      '直接查看当前应用构建与 Bridge 运行时版本信息，便于排查发布与联调问题。',
                      'Review the current app build and bridge runtime information in one place.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.tonal(
              key: const ValueKey('settings-about-refresh-button'),
              onPressed: busy ? null : () => onRefresh(),
              child: busy
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            key: const ValueKey(
                              'settings-about-refresh-progress',
                            ),
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(appText('刷新中', 'Refreshing')),
                      ],
                    )
                  : Text(appText('刷新版本信息', 'Refresh Build Info')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appText('应用构建', 'App Build'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${appText('Version', 'Version')}: ${_displayValue(snapshot.appVersion)}',
                key: const ValueKey('settings-about-app-version'),
              ),
              const SizedBox(height: 6),
              Text(
                '${appText('Build Number', 'Build Number')}: ${_displayValue(snapshot.appBuildNumber)}',
                key: const ValueKey('settings-about-app-build-number'),
              ),
              const SizedBox(height: 6),
              Text(
                '${appText('Build Date', 'Build Date')}: ${_displayValue(snapshot.appBuildDate)}',
                key: const ValueKey('settings-about-app-build-date'),
              ),
              const SizedBox(height: 6),
              Text(
                'Commit: ${_displayValue(snapshot.appCommit)}',
                key: const ValueKey('settings-about-app-commit'),
              ),
              const SizedBox(height: 18),
              Text(
                appText('Bridge 运行时', 'Bridge Runtime'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${appText('Endpoint', 'Endpoint')}: ${_displayValue(snapshot.bridgeEndpoint)}',
                key: const ValueKey('settings-about-bridge-endpoint'),
              ),
              const SizedBox(height: 6),
              Text(
                '${appText('Status', 'Status')}: ${_displayValue(snapshot.bridgeStatus)}',
                key: const ValueKey('settings-about-bridge-status'),
              ),
              const SizedBox(height: 6),
              Text(
                '${appText('Version', 'Version')}: ${_displayValue(snapshot.bridgeVersion)}',
                key: const ValueKey('settings-about-bridge-version'),
              ),
              const SizedBox(height: 6),
              Text(
                '${appText('Build Date', 'Build Date')}: ${_displayValue(snapshot.bridgeBuildDate)}',
                key: const ValueKey('settings-about-bridge-build-date'),
              ),
              const SizedBox(height: 6),
              Text(
                'Commit: ${_displayValue(snapshot.bridgeCommit)}',
                key: const ValueKey('settings-about-bridge-commit'),
              ),
              const SizedBox(height: 6),
              Text(
                '${appText('Image', 'Image')}: ${_displayValue(snapshot.bridgeImage)}',
                key: const ValueKey('settings-about-bridge-image'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _displayValue(String value) {
  return value.trim().isEmpty ? appText('不可用', 'Unavailable') : value.trim();
}
