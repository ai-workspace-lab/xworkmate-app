import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Parsed macOS / environment proxy configuration for enterprise VPN networks.
@immutable
class SystemProxySettings {
  const SystemProxySettings({
    this.httpEnable = false,
    this.httpProxy = '',
    this.httpPort = 0,
    this.httpsEnable = false,
    this.httpsProxy = '',
    this.httpsPort = 0,
    this.exceptionsList = const <String>[],
  });

  factory SystemProxySettings.fromMap(Map<Object?, Object?> raw) {
    final exceptionsRaw = raw['exceptionsList'];
    final exceptions = <String>[];
    if (exceptionsRaw is List) {
      for (final item in exceptionsRaw) {
        final trimmed = item?.toString().trim() ?? '';
        if (trimmed.isNotEmpty) {
          exceptions.add(trimmed);
        }
      }
    }
    return SystemProxySettings(
      httpEnable: raw['httpEnable'] == true,
      httpProxy: (raw['httpProxy']?.toString() ?? '').trim(),
      httpPort: _parsePort(raw['httpPort']),
      httpsEnable: raw['httpsEnable'] == true,
      httpsProxy: (raw['httpsProxy']?.toString() ?? '').trim(),
      httpsPort: _parsePort(raw['httpsPort']),
      exceptionsList: List<String>.unmodifiable(exceptions),
    );
  }

  final bool httpEnable;
  final String httpProxy;
  final int httpPort;
  final bool httpsEnable;
  final String httpsProxy;
  final int httpsPort;
  final List<String> exceptionsList;

  static int _parsePort(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// Resolves a `dart:io` `HttpClient.findProxy` directive for [uri].
  String resolveProxyForUri(
    Uri uri, {
    Map<String, String>? environment,
  }) {
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty || _isLoopbackHost(host)) {
      return 'DIRECT';
    }

    final env = environment ?? Platform.environment;
    final envNoProxy = env['NO_PROXY'] ?? env['no_proxy'] ?? '';
    if (_matchesBypassList(host, _splitNoProxy(envNoProxy))) {
      return 'DIRECT';
    }

    final isSecure = uri.scheme == 'https' || uri.scheme == 'wss';
    final envProxyRaw = isSecure
        ? (env['HTTPS_PROXY'] ??
              env['https_proxy'] ??
              env['HTTP_PROXY'] ??
              env['http_proxy'] ??
              '')
        : (env['HTTP_PROXY'] ?? env['http_proxy'] ?? '');
    final envProxy = _formatEnvProxy(envProxyRaw);
    if (envProxy != null) {
      return 'PROXY $envProxy; DIRECT';
    }

    if (_matchesBypassList(host, exceptionsList)) {
      return 'DIRECT';
    }

    if (isSecure && httpsEnable && httpsProxy.isNotEmpty && httpsPort > 0) {
      return 'PROXY $httpsProxy:$httpsPort; DIRECT';
    }
    if (httpEnable && httpProxy.isNotEmpty && httpPort > 0) {
      return 'PROXY $httpProxy:$httpPort; DIRECT';
    }
    return 'DIRECT';
  }

  static bool _isLoopbackHost(String host) {
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '[::1]' ||
        host.endsWith('.localhost');
  }

  static List<String> _splitNoProxy(String raw) {
    if (raw.trim().isEmpty) return const <String>[];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static String? _formatEnvProxy(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(
      trimmed.contains('://') ? trimmed : 'http://$trimmed',
    );
    if (parsed == null || parsed.host.isEmpty) return null;
    final port = parsed.hasPort ? parsed.port : 8080;
    return '${parsed.host}:$port';
  }

  static bool _matchesBypassList(String host, List<String> rules) {
    final hostIpv4 = _parseIpv4(host);
    for (final rawRule in rules) {
      final rule = rawRule.trim().toLowerCase();
      if (rule.isEmpty) continue;
      if (rule == '*') return true;
      if (rule == host) return true;
      if (rule.startsWith('*.') && host.endsWith(rule.substring(1))) {
        return true;
      }
      if (rule.startsWith('.') && host.endsWith(rule)) {
        return true;
      }
      if (hostIpv4 != null && rule.contains('/')) {
        if (_matchesIpv4Cidr(hostIpv4, rule)) {
          return true;
        }
      }
    }
    return false;
  }

  static int? _parseIpv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return null;
    var result = 0;
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return null;
      result = (result << 8) | octet;
    }
    return result;
  }

  static bool _matchesIpv4Cidr(int ip, String cidr) {
    final slashIndex = cidr.indexOf('/');
    if (slashIndex <= 0) return false;
    final networkRaw = cidr.substring(0, slashIndex);
    final prefix = int.tryParse(cidr.substring(slashIndex + 1));
    if (prefix == null || prefix < 0 || prefix > 32) return false;

    // Support macOS shorthand like 169.254/16 as well as 169.254.0.0/16.
    final octets = networkRaw.split('.');
    if (octets.isEmpty || octets.length > 4) return false;
    while (octets.length < 4) {
      octets.add('0');
    }
    final networkIp = _parseIpv4(octets.join('.'));
    if (networkIp == null) return false;
    if (prefix == 0) return true;
    final mask = (~0 << (32 - prefix)) & 0xFFFFFFFF;
    return (ip & mask) == (networkIp & mask);
  }
}

/// Global [HttpOverrides] that honors macOS System Proxy / enterprise VPN
/// settings in addition to standard environment variables.
class EnterpriseHttpOverrides extends HttpOverrides {
  EnterpriseHttpOverrides._();

  static final EnterpriseHttpOverrides instance = EnterpriseHttpOverrides._();

  static const MethodChannel _channel = MethodChannel(
    'plus.svc.xworkmate/network_proxy',
  );

  SystemProxySettings _cachedSettings = const SystemProxySettings();
  Timer? _refreshTimer;

  /// Installs [EnterpriseHttpOverrides] as [HttpOverrides.global] and loads
  /// initial macOS system proxy settings without blocking app startup.
  static Future<void> install() async {
    HttpOverrides.global = instance;
    if (!kIsWeb && Platform.isMacOS) {
      await instance.refresh().timeout(
        const Duration(milliseconds: 250),
        onTimeout: () {},
      );
      instance._startPeriodicRefresh();
    }
  }

  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(refresh());
    });
  }

  /// Refreshes cached system proxy settings from the native macOS host.
  Future<void> refresh() async {
    if (kIsWeb || !Platform.isMacOS) return;
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getSystemProxySettings',
      );
      if (result != null) {
        _cachedSettings = SystemProxySettings.fromMap(result);
      }
    } on MissingPluginException {
      // Safe no-op in widget/unit test environments without native channel.
    } catch (_) {
      // Preserve last known proxy settings if transient lookup fails.
    }
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) => _cachedSettings.resolveProxyForUri(uri);
    return client;
  }
}
