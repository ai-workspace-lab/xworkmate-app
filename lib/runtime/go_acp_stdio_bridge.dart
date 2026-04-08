import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'embedded_agent_launch_policy.dart';
import 'go_core.dart';

typedef GoAcpStdioProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      String? workingDirectory,
    });

class GoAcpStdioBridge {
  GoAcpStdioBridge({
    GoCoreLocator? goCoreLocator,
    GoAcpStdioProcessStarter? processStarter,
  }) : _goCoreLocator = goCoreLocator ?? GoCoreLocator(),
       _processStarter =
           processStarter ??
           ((executable, arguments, {environment, workingDirectory}) {
             return Process.start(
               executable,
               arguments,
               environment: environment,
               workingDirectory: workingDirectory,
             );
           });

  final GoCoreLocator _goCoreLocator;
  final GoAcpStdioProcessStarter _processStarter;

  final StreamController<Map<String, dynamic>> _notificationsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Future<void>? _startupFuture;
  int _requestCounter = 0;

  Stream<Map<String, dynamic>> get notifications =>
      _notificationsController.stream;

  Future<Map<String, dynamic>> request({
    required String method,
    required Map<String, dynamic> params,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    await _ensureStarted();
    final process = _process;
    if (process == null) {
      throw StateError('Missing Go ACP stdio process.');
    }
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-$method-${_requestCounter++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    process.stdin.writeln(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Go ACP stdio request timed out: $method',
          timeout,
        ),
      );
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> dispose() async {
    final process = _process;
    _process = null;
    _startupFuture = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Go ACP stdio bridge disposed before response.'),
        );
      }
    }
    _pending.clear();
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    if (process != null) {
      try {
        await process.stdin.close();
      } catch (_) {
        // Ignore broken pipes during disposal.
      }
      try {
        process.kill();
      } catch (_) {
        // Best effort only.
      }
    }
    await _notificationsController.close();
  }

  Future<void> _ensureStarted() async {
    if (_process != null) {
      return;
    }
    final inFlight = _startupFuture;
    if (inFlight != null) {
      return inFlight;
    }
    final next = _start();
    _startupFuture = next;
    try {
      await next;
    } finally {
      _startupFuture = null;
    }
  }

  Future<void> _start() async {
    final launch = await _goCoreLocator.locate();
    if (launch == null) {
      throw StateError('Go core is unavailable.');
    }
    if (shouldBlockGoCoreLaunch(
      launch,
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    )) {
      throw UnsupportedError(
        'App Store builds only allow the bundled Go core helper inside the app bundle.',
      );
    }
    final process = await _processStarter(
      launch.executable,
      <String>[...launch.arguments, 'acp-stdio'],
      environment: Platform.environment,
      workingDirectory: launch.workingDirectory,
    );
    _process = process;
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdoutLine, onError: _handleProcessError);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((_) {}, onError: _handleProcessError);
    unawaited(
      process.exitCode.then((exitCode) {
        if (_process != process) {
          return;
        }
        _process = null;
        _failPending(
          StateError('Go ACP stdio process exited with code $exitCode'),
        );
      }),
    );
    await request(method: 'acp.capabilities', params: const <String, dynamic>{});
  }

  void _handleStdoutLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) {
      return;
    }
    final json = _decodeMap(trimmed);
    final id = json['id']?.toString().trim();
    if (id != null && id.isNotEmpty) {
      final completer = _pending[id];
      if (completer == null || completer.isCompleted) {
        return;
      }
      final error = _castMap(json['error']);
      if (error.isNotEmpty) {
        completer.completeError(
          StateError(
            error['message']?.toString() ?? 'Go ACP stdio request failed',
          ),
        );
        return;
      }
      completer.complete(json);
      return;
    }
    if ((json['method']?.toString().trim() ?? '').isNotEmpty &&
        !_notificationsController.isClosed) {
      _notificationsController.add(json);
    }
  }

  void _handleProcessError(Object error) {
    _failPending(error);
  }

  void _failPending(Object error) {
    final pending = Map<String, Completer<Map<String, dynamic>>>.from(_pending);
    _pending.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  Map<String, dynamic> _decodeMap(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  Map<String, dynamic> _castMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }
}
