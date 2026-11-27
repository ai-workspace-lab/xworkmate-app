import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/enterprise_http_overrides.dart';

void main() {
  group('SystemProxySettings', () {
    test('always bypasses loopback hosts', () {
      const settings = SystemProxySettings(
        httpEnable: true,
        httpProxy: 'proxy.corp.local',
        httpPort: 8080,
        httpsEnable: true,
        httpsProxy: 'proxy.corp.local',
        httpsPort: 8443,
      );

      expect(
        settings.resolveProxyForUri(
          Uri.parse('http://127.0.0.1:8080/health'),
          environment: const <String, String>{},
        ),
        'DIRECT',
      );
      expect(
        settings.resolveProxyForUri(
          Uri.parse('https://localhost:3000/rpc'),
          environment: const <String, String>{},
        ),
        'DIRECT',
      );
      expect(
        settings.resolveProxyForUri(
          Uri.parse('ws://[::1]:18789/ws'),
          environment: const <String, String>{},
        ),
        'DIRECT',
      );
    });

    test('resolves HTTPS/WSS and HTTP/WS proxies from macOS settings', () {
      final settings = SystemProxySettings.fromMap(<Object?, Object?>{
        'httpEnable': true,
        'httpProxy': 'http-gw.corp.net',
        'httpPort': 8080,
        'httpsEnable': true,
        'httpsProxy': 'https-gw.corp.net',
        'httpsPort': 8443,
        'exceptionsList': <String>['*.local', '10.0.0.0/8', '169.254/16'],
      });

      expect(
        settings.resolveProxyForUri(
          Uri.parse('https://api.svc.plus/v1'),
          environment: const <String, String>{},
        ),
        'PROXY https-gw.corp.net:8443; DIRECT',
      );
      expect(
        settings.resolveProxyForUri(
          Uri.parse('wss://bridge.svc.plus/acp'),
          environment: const <String, String>{},
        ),
        'PROXY https-gw.corp.net:8443; DIRECT',
      );
      expect(
        settings.resolveProxyForUri(
          Uri.parse('http://example.com/status'),
          environment: const <String, String>{},
        ),
        'PROXY http-gw.corp.net:8080; DIRECT',
      );
    });

    test('honors exceptionsList domains and IPv4 CIDR ranges', () {
      const settings = SystemProxySettings(
        httpsEnable: true,
        httpsProxy: 'proxy.corp.net',
        httpsPort: 8443,
        exceptionsList: <String>[
          '*.corp.internal',
          '.local',
          '10.0.0.0/8',
          '169.254/16',
        ],
      );

      expect(
        settings.resolveProxyForUri(
          Uri.parse('https://gateway.corp.internal/acp'),
          environment: const <String, String>{},
        ),
        'DIRECT',
      );
      expect(
        settings.resolveProxyForUri(
          Uri.parse('https://10.20.30.40:8443/rpc'),
          environment: const <String, String>{},
        ),
        'DIRECT',
      );
      expect(
        settings.resolveProxyForUri(
          Uri.parse('https://169.254.10.1/metadata'),
          environment: const <String, String>{},
        ),
        'DIRECT',
      );
    });

    test('prefers environment proxy variables and NO_PROXY when set', () {
      const settings = SystemProxySettings(
        httpsEnable: true,
        httpsProxy: 'sys-proxy.corp.net',
        httpsPort: 8443,
      );

      expect(
        settings.resolveProxyForUri(
          Uri.parse('https://api.svc.plus/v1'),
          environment: const <String, String>{
            'HTTPS_PROXY': 'http://env-proxy.corp.net:3128',
          },
        ),
        'PROXY env-proxy.corp.net:3128; DIRECT',
      );
      expect(
        settings.resolveProxyForUri(
          Uri.parse('https://internal.svc.plus/v1'),
          environment: const <String, String>{
            'HTTPS_PROXY': 'http://env-proxy.corp.net:3128',
            'NO_PROXY': '*.svc.plus',
          },
        ),
        'DIRECT',
      );
    });
  });
}
