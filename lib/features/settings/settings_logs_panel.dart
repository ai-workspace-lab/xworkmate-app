import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../app/app_logger.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_palette.dart';

class SettingsLogsPanel extends StatefulWidget {
  const SettingsLogsPanel({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsLogsPanel> createState() => _SettingsLogsPanelState();
}

class _SettingsLogsPanelState extends State<SettingsLogsPanel> {
  Timer? _timer;
  String _bridgeStatus = 'unknown';
  String _gatewayStatus = 'unknown';
  List<String> _bridgeLogs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchStatus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    try {
      final res = await widget.controller.gatewayAcpClientInternal.fetchSystemStatus();
      if (mounted) {
        setState(() {
          _bridgeStatus = res['bridgeStatus']?.toString() ?? 'error';
          _gatewayStatus = res['gatewayStatus']?.toString() ?? 'error';
          
          final logs = res['bridgeLogs'];
          if (logs is List) {
            _bridgeLogs = logs.map((e) => e.toString()).toList();
          }
        });
        // Auto scroll to bottom
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bridgeStatus = 'error';
          _gatewayStatus = 'error';
        });
      }
    }
  }

  Widget _buildStatusCard(String title, String status, AppPalette palette) {
    final isOk = status.toLowerCase() == 'ok' || status.toLowerCase() == 'connected' || status.toLowerCase() == 'running';
    final color = isOk ? Colors.green : (status == 'unknown' ? Colors.grey : Colors.redAccent);
    
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: palette.surfaceSecondary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    
    // Combine local app logs with bridge logs
    final appLogs = AppLogger().getLogs();

    return Column(
      key: const ValueKey('settings-logs-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.terminal_outlined, color: palette.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                appText('运行日志', 'Runtime Logs'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildStatusCard('App Status', 'Running', palette),
            const SizedBox(width: 8),
            _buildStatusCard('Bridge', _bridgeStatus, palette),
            const SizedBox(width: 8),
            _buildStatusCard('Gateway', _gatewayStatus, palette),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 400,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E), // Dark terminal background
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.stroke),
          ),
          padding: const EdgeInsets.all(12),
          child: ListView.builder(
            controller: _scrollController,
            itemCount: appLogs.length + _bridgeLogs.length,
            itemBuilder: (context, index) {
              final isAppLog = index < appLogs.length;
              final logText = isAppLog ? appLogs[index] : _bridgeLogs[index - appLogs.length];
              return Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text(
                  logText,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFFCCCCCC),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
