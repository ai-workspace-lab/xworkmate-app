import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import 'workspace_provision_models.dart';

abstract class WorkspaceSshExecutor {
  Future<SshResult> execute(SshConfig config, String command);
  Stream<String> executeStreaming(SshConfig config, String command);
}

class DartSshExecutor implements WorkspaceSshExecutor {
  const DartSshExecutor();

  @override
  Future<SshResult> execute(SshConfig config, String command) async {
    final client = await _connect(config);
    try {
      final result = await client.runWithResult(command);
      return SshResult(
        exitCode: result.exitCode ?? -1,
        stdout: utf8.decode(result.stdout, allowMalformed: true),
        stderr: utf8.decode(result.stderr, allowMalformed: true),
      );
    } finally {
      client.close();
      await client.done.catchError((_) {});
    }
  }

  @override
  Stream<String> executeStreaming(SshConfig config, String command) async* {
    final client = await _connect(config);
    SSHSession? session;
    try {
      session = await client.execute(command);
      final controller = StreamController<String>();
      final subscriptions = <StreamSubscription<List<int>>>[
        session.stdout.listen(
          (chunk) => controller.add(utf8.decode(chunk, allowMalformed: true)),
          onError: controller.addError,
        ),
        session.stderr.listen(
          (chunk) => controller.add(utf8.decode(chunk, allowMalformed: true)),
          onError: controller.addError,
        ),
      ];
      unawaited(
        session.done.then((_) async {
          for (final subscription in subscriptions) {
            await subscription.cancel();
          }
          await controller.close();
        }),
      );
      await for (final chunk in controller.stream) {
        yield chunk;
      }
      if ((session.exitCode ?? 0) != 0) {
        yield 'REMOTE_EXIT_CODE=${session.exitCode ?? -1}';
      }
    } finally {
      session?.close();
      client.close();
      await client.done.catchError((_) {});
    }
  }

  Future<SSHClient> _connect(SshConfig config) async {
    final socket = await SSHSocket.connect(
      config.host,
      config.port,
    ).timeout(config.connectTimeout);
    final identities = await _identities(config);
    final client = SSHClient(
      socket,
      username: config.username,
      identities: identities.isEmpty ? null : identities,
      onPasswordRequest: config.authMethod == AuthMethod.password
          ? () => config.password
          : null,
      onVerifyHostKey: (hostKey, fingerprint) => true,
    );
    await client.authenticated.timeout(config.connectTimeout);
    return client;
  }

  Future<List<SSHKeyPair>> _identities(SshConfig config) async {
    if (config.authMethod != AuthMethod.sshKey) {
      return const <SSHKeyPair>[];
    }
    final inline = config.privateKey?.trim();
    if (inline != null && inline.isNotEmpty) {
      return SSHKeyPair.fromPem(inline);
    }
    final path = config.privateKeyPath?.trim();
    if (path != null && path.isNotEmpty) {
      return SSHKeyPair.fromPem(await File(path).readAsString());
    }
    return const <SSHKeyPair>[];
  }
}

String shellQuote(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}
