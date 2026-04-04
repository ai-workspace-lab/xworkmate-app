import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/settings_page_gateway_acp.dart';
import 'package:xworkmate/i18n/app_language.dart';

void main() {
  group('external ACP desktop UI copy', () {
    test('example copy recommends https base URLs for hosted services', () {
      setActiveAppLanguage(AppLanguage.en);
      addTearDown(() => setActiveAppLanguage(AppLanguage.zh));

      final text = externalAcpEndpointExamplesText();

      expect(text, contains('https://agent.example.com'));
      expect(text, contains('base URL'));
      expect(text, contains('/acp'));
      expect(text, contains('/acp/rpc'));
    });

    test('example copy still applies when hosted ACP uses a base path', () {
      setActiveAppLanguage(AppLanguage.en);
      addTearDown(() => setActiveAppLanguage(AppLanguage.zh));

      final text = externalAcpEndpointExamplesText();

      expect(text, contains('base URL'));
      expect(text, contains('/acp'));
    });

    test(
      'websocket-only error suggests using https base URL for hosted ACP',
      () {
        setActiveAppLanguage(AppLanguage.en);
        addTearDown(() => setActiveAppLanguage(AppLanguage.zh));

        final text = describeExternalAcpTestFailure(
          const FormatException('Missing ACP HTTP endpoint')
              .toString()
              .replaceFirst('FormatException: ', 'ACP_HTTP_ENDPOINT_MISSING: '),
          endpoint: Uri.parse('wss://acp-server.example.com:443'),
        );

        expect(text, contains('https://host[:port]'));
        expect(text, contains('raw ACP WebSocket listener'));
      },
    );

    test(
      'missing JSON document points hosted endpoints at /acp/rpc bridge',
      () {
        setActiveAppLanguage(AppLanguage.en);
        addTearDown(() => setActiveAppLanguage(AppLanguage.zh));

        final text = describeExternalAcpTestFailure(
          const FormatException('Missing JSON document'),
          endpoint: Uri.parse('https://acp-server.example.com:443'),
        );

        expect(text, contains('/acp/rpc'));
        expect(text, contains('HTTP ACP bridge'));
      },
    );

    test('tls handshake errors explain server-side tls diagnosis', () {
      setActiveAppLanguage(AppLanguage.en);
      addTearDown(() => setActiveAppLanguage(AppLanguage.zh));

      final text = describeExternalAcpTestFailure(
        'HandshakeException: Handshake error in client (OS Error: TLSV1_ALERT_INTERNAL_ERROR)',
        endpoint: Uri.parse('https://acp-server.example.com/opencode'),
      );

      expect(text, contains('TLS handshake failed'));
      expect(text, contains('curl or openssl'));
      expect(text, contains('subpath'));
    });
  });
}
