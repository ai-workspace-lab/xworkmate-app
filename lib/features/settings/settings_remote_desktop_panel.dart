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
  OverlayEntry? _overlayEntry;

  void _toggleMaximize() {
    if (_isMaximized) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      setState(() => _isMaximized = false);
    } else {
      setState(() => _isMaximized = true);
      _overlayEntry = OverlayEntry(
        builder: (context) {
          return Material(
            child: SafeArea(
              child: DesktopView(
                key: _desktopViewKey,
                controller: widget.controller,
                isMaximized: true,
                onToggleMaximize: _toggleMaximize,
              ),
            ),
          );
        },
      );
      Overlay.of(context).insert(_overlayEntry!);
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
                appText('AI工作空间', 'AI Workspace'),
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
