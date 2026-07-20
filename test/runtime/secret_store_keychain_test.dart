import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/file_store_support.dart';
import 'package:xworkmate/runtime/secret_store.dart';

class _FakeKeychainClient implements SecureStorageClient {
  final Map<String, String> values = <String, String>{};
  int deleteAllCalls = 0;
  final List<String> writeOrder = <String>[];

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
    writeOrder.add(key);
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    deleteAllCalls += 1;
    values.clear();
  }
}

void main() {
  late Directory tempRoot;
  late Directory secretDirectory;
  late _FakeKeychainClient keychain;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('keychain-bind-test-');
    secretDirectory = Directory('${tempRoot.path}/secrets');
    keychain = _FakeKeychainClient();
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  File markerFile() => File('${secretDirectory.path}/.keychain-bound');

  Future<File> writeSecretFile(String key, String value) async {
    await secretDirectory.create(recursive: true);
    final file = File(
      '${secretDirectory.path}/${encodeStableFileKey(key)}.secret',
    );
    await file.writeAsString('$value\n');
    return file;
  }

  group('bindKeychainSecretStorage', () {
    test(
      'fresh install wipes keychain remnants and writes the marker',
      () async {
        keychain.values['xworkmate.account.session.token'] = 'stale-token';

        await bindKeychainSecretStorage(
          keychain: keychain,
          secretDirectory: secretDirectory,
        );

        expect(keychain.deleteAllCalls, 1);
        expect(keychain.values, isEmpty);
        expect(markerFile().existsSync(), isTrue);
      },
    );

    test('bound container keeps existing keychain values', () async {
      await secretDirectory.create(recursive: true);
      await markerFile().writeAsString('bound\n');
      keychain.values['xworkmate.vault.token'] = 'keep-me';

      await bindKeychainSecretStorage(
        keychain: keychain,
        secretDirectory: secretDirectory,
      );

      expect(keychain.deleteAllCalls, 0);
      expect(keychain.values['xworkmate.vault.token'], 'keep-me');
    });

    test(
      'upgrade migrates .secret files into the keychain then removes them',
      () async {
        final vaultFile = await writeSecretFile(
          'xworkmate.vault.token',
          'vault-secret',
        );
        final tokenFile = await writeSecretFile(
          'xworkmate.account.session.token',
          'session-secret',
        );
        keychain.values['xworkmate.vault.token'] = 'remnant-to-wipe';

        await bindKeychainSecretStorage(
          keychain: keychain,
          secretDirectory: secretDirectory,
        );

        // 清残留必须发生在迁移写入之前,否则迁入的值会被一并清掉。
        expect(keychain.deleteAllCalls, 1);
        expect(keychain.values['xworkmate.vault.token'], 'vault-secret');
        expect(
          keychain.values['xworkmate.account.session.token'],
          'session-secret',
        );
        expect(vaultFile.existsSync(), isFalse);
        expect(tokenFile.existsSync(), isFalse);
        expect(markerFile().existsSync(), isTrue);
      },
    );

    test('a bound container still migrates leftover .secret files', () async {
      await secretDirectory.create(recursive: true);
      await markerFile().writeAsString('bound\n');
      final leftover = await writeSecretFile(
        'xworkmate.ollama.cloud.api_key',
        'leftover-key',
      );

      await bindKeychainSecretStorage(
        keychain: keychain,
        secretDirectory: secretDirectory,
      );

      expect(keychain.deleteAllCalls, 0);
      expect(keychain.values['xworkmate.ollama.cloud.api_key'], 'leftover-key');
      expect(leftover.existsSync(), isFalse);
    });

    test('an undecodable secret filename is left in place', () async {
      await secretDirectory.create(recursive: true);
      final stray = File('${secretDirectory.path}/%not-base64%.secret');
      await stray.writeAsString('mystery\n');

      await bindKeychainSecretStorage(
        keychain: keychain,
        secretDirectory: secretDirectory,
      );

      expect(stray.existsSync(), isTrue);
      expect(keychain.values, isEmpty);
      expect(markerFile().existsSync(), isTrue);
    });

    test('an empty secret file is dropped without a keychain write', () async {
      final empty = await writeSecretFile('xworkmate.vault.token', '   ');

      await bindKeychainSecretStorage(
        keychain: keychain,
        secretDirectory: secretDirectory,
      );

      expect(empty.existsSync(), isFalse);
      expect(keychain.values, isEmpty);
    });
  });

  group('FileSecureStorageClient.deleteAll', () {
    test('removes every .secret file but nothing else', () async {
      final client = FileSecureStorageClient(() async => secretDirectory);
      await client.write(key: 'a.key', value: 'one');
      await client.write(key: 'b.key', value: 'two');
      final unrelated = File('${secretDirectory.path}/.keychain-bound');
      await unrelated.writeAsString('bound\n');

      await client.deleteAll();

      expect(await client.read(key: 'a.key'), isNull);
      expect(await client.read(key: 'b.key'), isNull);
      expect(unrelated.existsSync(), isTrue);
    });
  });
}
