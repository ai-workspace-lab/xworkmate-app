import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../i18n/app_language.dart';
import '../../runtime/gateway_runtime.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';

class MobileGatewayPairingGuidePage extends StatelessWidget {
  const MobileGatewayPairingGuidePage({
    super.key,
    required this.supportsQrScan,
    required this.onManualInput,
    required this.onScannedSetupCode,
  });

  final bool supportsQrScan;
  final VoidCallback onManualInput;
  final Future<void> Function(String setupCode) onScannedSetupCode;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F1EF),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  _HeaderCircleButton(
                    key: const ValueKey('pairing-guide-close-button'),
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '配对网关',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 56),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 118,
                      height: 118,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.hub_outlined,
                        size: 56,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      '配对你的 OpenClaw 主机',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '在 Mac、Windows 或云端部署的 OpenClaw 主机上安装 xworkmate，然后生成配对二维码或配置码。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: palette.textSecondary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _GuideCard(
                      key: const ValueKey('pairing-guide-install-card'),
                      title: '自主安装',
                      subtitle: '按下面两步在主机上安装 XWorkmate CLI，然后生成配对码。',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '1. 安装',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _CommandBlock(
                            key: const ValueKey(
                              'pairing-guide-install-command',
                            ),
                            command: 'npm install -g xworkmate',
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '2. 配对',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _CommandBlock(
                            key: const ValueKey('pairing-guide-pair-command'),
                            command: 'xworkmate pair',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey('pairing-guide-scan-button'),
                        onPressed: () async {
                          if (!supportsQrScan) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  appText(
                                    'Android 扫码即将支持，当前请先使用手动输入代码。',
                                    'Android QR scanning is coming soon. Use manual code entry for now.',
                                  ),
                                ),
                              ),
                            );
                            return;
                          }
                          final result = await Navigator.of(context)
                              .push<String>(
                                MaterialPageRoute<String>(
                                  fullscreenDialog: true,
                                  builder: (_) =>
                                      const MobileGatewayQrScannerPage(),
                                ),
                              );
                          if (result == null || !context.mounted) {
                            return;
                          }
                          Navigator.of(context).pop();
                          await onScannedSetupCode(result);
                        },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          backgroundColor: const Color(0xFF151517),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.button,
                            ),
                          ),
                        ),
                        child: Text(
                          '扫描二维码',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const ValueKey('pairing-guide-manual-button'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          onManualInput();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          backgroundColor: Colors.white,
                          foregroundColor: palette.textPrimary,
                          side: BorderSide(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.button,
                            ),
                          ),
                        ),
                        child: Text(
                          '手动输入代码',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MobileGatewayQrScannerPage extends StatefulWidget {
  const MobileGatewayQrScannerPage({super.key});

  @override
  State<MobileGatewayQrScannerPage> createState() =>
      _MobileGatewayQrScannerPageState();
}

class _MobileGatewayQrScannerPageState
    extends State<MobileGatewayQrScannerPage> {
  bool _hasHandledDetection = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _QrScannerSurface(onCodeDetected: _handleDetectedCode),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeaderCircleButton(
                    key: const ValueKey('pairing-scanner-close-button'),
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.black.withValues(alpha: 0.28),
                  ),
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(AppRadius.dialog),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '扫描配对二维码',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '将二维码放入取景框内。扫描成功后会自动把配置码带入 Gateway 设置页。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.82),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleDetectedCode(String raw) {
    if (_hasHandledDetection) {
      return;
    }
    final setupCode = resolveGatewaySetupCodeFromScan(raw);
    if (setupCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appText('未识别到有效配置码，请重试。', 'No valid setup code found. Try again.'),
          ),
        ),
      );
      return;
    }
    _hasHandledDetection = true;
    Navigator.of(context).pop(setupCode);
  }
}

String? resolveGatewaySetupCodeFromScan(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final candidate = _extractSetupCodeFromJsonPayload(trimmed) ?? trimmed;
  return decodeGatewaySetupCode(candidate) != null ? candidate : null;
}

String? _extractSetupCodeFromJsonPayload(String raw) {
  final normalized = raw.trim();
  if (!normalized.startsWith('{')) {
    return null;
  }
  try {
    final dynamic decoded = jsonDecode(normalized);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final setupCode = decoded['setupCode'];
    if (setupCode is! String || setupCode.trim().isEmpty) {
      return null;
    }
    return setupCode.trim();
  } catch (_) {
    return null;
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _CommandBlock extends StatelessWidget {
  const _CommandBlock({super.key, required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6F4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              command,
              style: theme.textTheme.titleMedium?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: command));
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(appText('已复制命令。', 'Command copied.'))),
              );
            },
            icon: const Icon(Icons.content_copy_rounded),
            tooltip: appText('复制命令', 'Copy command'),
          ),
        ],
      ),
    );
  }
}

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.foregroundColor,
    this.backgroundColor,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? foregroundColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 56,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          color: foregroundColor ?? palette.textPrimary,
        ),
      ),
    );
  }
}

class _QrScannerSurface extends StatelessWidget {
  const _QrScannerSurface({required this.onCodeDetected});

  final ValueChanged<String> onCodeDetected;

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      key: const ValueKey('pairing-guide-ios-scanner'),
      onDetect: (capture) {
        final code = capture.barcodes
            .map((item) => item.rawValue?.trim() ?? '')
            .firstWhere((item) => item.isNotEmpty, orElse: () => '');
        if (code.isEmpty) {
          return;
        }
        onCodeDetected(code);
      },
    );
  }
}
