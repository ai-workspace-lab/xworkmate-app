import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/platform_environment.dart';

void main() {
  test('resolveCodexHomeDirectory uses USERPROFILE on windows', () {
    final codexHome = resolveCodexHomeDirectory(
      environment: const <String, String>{'USERPROFILE': r'C:\Users\tester'},
      operatingSystem: 'windows',
    );

    expect(codexHome, r'C:\Users\tester\.codex');
  });

  test('resolveCodexHomeDirectory honors explicit CODEX_HOME', () {
    final codexHome = resolveCodexHomeDirectory(
      environment: const <String, String>{
        'CODEX_HOME': r'D:\Tools\CodexHome',
        'USERPROFILE': r'C:\Users\tester',
      },
      operatingSystem: 'windows',
    );

    expect(codexHome, r'D:\Tools\CodexHome');
  });

  test('defaultCodexBinaryCandidates include common windows locations', () {
    final candidates = defaultCodexBinaryCandidates(
      environment: const <String, String>{
        'USERPROFILE': r'C:\Users\tester',
        'APPDATA': r'C:\Users\tester\AppData\Roaming',
        'LOCALAPPDATA': r'C:\Users\tester\AppData\Local',
      },
      operatingSystem: 'windows',
    );

    expect(candidates, contains(r'C:\Users\tester\.cargo\bin\codex.exe'));
    expect(
      candidates,
      contains(r'C:\Users\tester\AppData\Roaming\npm\codex.cmd'),
    );
    expect(
      candidates,
      contains(r'C:\Users\tester\AppData\Local\Programs\codex\codex.exe'),
    );
  });

  test('resolveGatewayClientId returns windows specific identifier', () {
    expect(
      resolveGatewayClientId(operatingSystem: 'windows'),
      'openclaw-windows',
    );
  });
}
