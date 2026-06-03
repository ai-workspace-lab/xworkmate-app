import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_palette.dart';
import '../desktop/desktop_view.dart';

class SettingsRemoteDesktopPanel extends StatefulWidget {
  const SettingsRemoteDesktopPanel({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsRemoteDesktopPanel> createState() =>
      _SettingsRemoteDesktopPanelState();
}

class _SettingsRemoteDesktopPanelState extends State<SettingsRemoteDesktopPanel> {
  final GlobalKey _desktopViewKey = GlobalKey();
  bool _isMaximized = false;

  void _toggleMaximize() {
    if (_isMaximized) {
      Navigator.of(context).pop();
    } else {
      setState(() => _isMaximized = true);
      showDialog(
        context: context,
        useSafeArea: false,
        barrierDismissible: false,
        builder: (context) {
          return Dialog.fullscreen(
            child: DesktopView(
              key: _desktopViewKey,
              controller: widget.controller,
              isMaximized: true,
              onToggleMaximize: () {
                Navigator.of(context).pop();
              },
            ),
          );
        },
      ).then((_) {
        if (mounted) {
          setState(() => _isMaximized = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Column(
      key: const ValueKey('settings-remote-desktop-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.desktop_windows_outlined, color: palette.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                appText('远程桌面', 'Remote Desktop'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!_isMaximized)
          SizedBox(
            height: 640,
            child: DesktopView(
              key: _desktopViewKey,
              controller: widget.controller,
              isMaximized: false,
              onToggleMaximize: _toggleMaximize,
            ),
          ),
      ],
    );
  }
}
