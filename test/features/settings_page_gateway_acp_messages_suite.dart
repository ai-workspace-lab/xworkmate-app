import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/settings_page_gateway_acp.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

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

    test('transient body-read close prints normalized diagnostics', () {
      setActiveAppLanguage(AppLanguage.en);
      addTearDown(() => setActiveAppLanguage(AppLanguage.zh));

      final text = describeExternalAcpTestFailure(
        const GatewayAcpException(
          'ACP HTTP response stream closed before the body finished arriving',
          code: 'ACP_HTTP_STREAM_CLOSED',
          details: <String, dynamic>{
            'requestUrl': 'https://acp-server.svc.plus/codex/acp/rpc',
            'statusCode': 200,
            'contentType': 'application/json',
            'bodyRead': false,
          },
        ),
      );

      expect(text, contains('HTTP: 200'));
      expect(text, contains('content-type: application/json'));
      expect(text, contains('body received: no'));
      expect(text, contains('retries this transient error once automatically'));
    });

    test('success copy shows actual transport status and providers', () {
      setActiveAppLanguage(AppLanguage.en);
      addTearDown(() => setActiveAppLanguage(AppLanguage.zh));

      final text = describeExternalAcpTestSuccess(
        GatewayAcpCapabilities(
          singleAgent: true,
          multiAgent: true,
          providers: <SingleAgentProvider>{
            SingleAgentProvider.codex,
            SingleAgentProvider.opencode,
          },
          raw: <String, dynamic>{},
          diagnostics: <String, dynamic>{
            'transport': 'http',
            'statusCode': 200,
          },
        ),
      );

      expect(text, contains('HTTP 200'));
      expect(text, contains('ACP capabilities ok'));
      expect(text, contains('providers: codex/opencode'));
    });
  });
}
