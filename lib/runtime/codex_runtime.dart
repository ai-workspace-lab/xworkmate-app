import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app/app_store_policy.dart';
import '../app/app_metadata.dart';
import 'platform_environment.dart';

/// Codex sandbox mode for controlling file system access.
enum CodexSandboxMode {
  readOnly('read-only'),
  workspaceWrite('workspace-write'),
  dangerFullAccess('danger-full-access');

  final String value;
  const CodexSandboxMode(this.value);
}

/// Codex approval policy for controlling automatic execution.
enum CodexApprovalPolicy {
  suggest('suggest'),
  autoEdit('auto-edit'),
  fullAuto('full-auto');

  final String value;
  const CodexApprovalPolicy(this.value);
}

/// Codex authentication mode.
enum CodexAuthMode {
  apiKey('api-key'),
  chatgpt('chatgpt'),
  chatgptAuthTokens('chatgptAuthTokens');

  final String value;
  const CodexAuthMode(this.value);
}

/// Codex thread information.
class CodexThread {
  final String id;
  final String? path;
  final bool ephemeral;
  final DateTime? createdAt;

  const CodexThread({
    required this.id,
    this.path,
    this.ephemeral = false,
    this.createdAt,
  });

  factory CodexThread.fromJson(Map<String, dynamic> json) {
    return CodexThread(
      id: json['id'] as String,
      path: json['path'] as String?,
      ephemeral: json['ephemeral'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (path != null) 'path': path,
    'ephemeral': ephemeral,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  };
}

/// Codex turn information.
class CodexTurn {
  final String id;
  final String threadId;
  final String status;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const CodexTurn({
    required this.id,
    required this.threadId,
    required this.status,
    this.startedAt,
    this.completedAt,
  });

  factory CodexTurn.fromJson(Map<String, dynamic> json) {
    return CodexTurn(
      id: json['id'] as String,
      threadId: json['threadId'] as String,
      status: json['status'] as String,
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
    );
  }
}

/// Codex account information.
class CodexAccount {
  final String? email;
  final String? plan;
  final bool hasCredits;
  final double? creditsBalance;
  final List<CodexRateLimit> rateLimits;

  const CodexAccount({
    this.email,
    this.plan,
    this.hasCredits = false,
    this.creditsBalance,
    this.rateLimits = const [],
  });

  factory CodexAccount.fromJson(Map<String, dynamic> json) {
    return CodexAccount(
      email: json['email'] as String?,
      plan: json['plan'] as String?,
      hasCredits: json['hasCredits'] as bool? ?? false,
      creditsBalance: (json['creditsBalance'] as num?)?.toDouble(),
      rateLimits:
          (json['rateLimits'] as List?)
              ?.map((e) => CodexRateLimit.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Codex rate limit information.
class CodexRateLimit {
  final String type;
  final int percentRemaining;
  final DateTime? resetsAt;

  const CodexRateLimit({
    required this.type,
    required this.percentRemaining,
    this.resetsAt,
  });

  factory CodexRateLimit.fromJson(Map<String, dynamic> json) {
    return CodexRateLimit(
      type: json['type'] as String,
      percentRemaining: json['percentRemaining'] as int? ?? 0,
      resetsAt: json['resetsAt'] != null
          ? DateTime.tryParse(json['resetsAt'] as String)
          : null,
    );
  }
}

/// Codex user input for turn/start.
class CodexUserInput {
  final String type;
  final String content;
  final List<CodexAttachment>? attachments;

  const CodexUserInput({
    this.type = 'message',
    required this.content,
    this.attachments,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'content': content,
    if (attachments != null && attachments!.isNotEmpty)
      'attachments': attachments!.map((a) => a.toJson()).toList(),
  };
}

/// Codex file attachment.
class CodexAttachment {
  final String path;
  final String? name;

  const CodexAttachment({required this.path, this.name});

  Map<String, dynamic> toJson() => {
    'path': path,
    if (name != null) 'name': name,
  };
}

/// Base class for Codex events.
sealed class CodexEvent {
  const CodexEvent();
}

/// Log event from Codex.
class CodexLogEvent extends CodexEvent {
  final String level;
  final String message;
  final DateTime timestamp;

  const CodexLogEvent({
    required this.level,
    required this.message,
    required this.timestamp,
  });
}

/// Notification event from Codex App Server.
class CodexNotificationEvent extends CodexEvent {
  final String method;
  final Map<String, dynamic> params;

  const CodexNotificationEvent({required this.method, required this.params});
}

/// Turn event (item/started, item/completed, etc.).
class CodexTurnEvent extends CodexEvent {
  final String type;
  final String? threadId;
  final String? turnId;
  final String? itemId;
  final Map<String, dynamic> data;

  const CodexTurnEvent({
    required this.type,
    this.threadId,
    this.turnId,
    this.itemId,
    required this.data,
  });

  factory CodexTurnEvent.fromNotification(CodexNotificationEvent notification) {
    final params = notification.params;
    return CodexTurnEvent(
      type: notification.method,
      threadId: params['threadId'] as String?,
      turnId: params['turnId'] as String?,
      itemId: params['itemId'] as String?,
      data: params,
    );
  }

  /// Check if this is a text delta event.
  bool get isTextDelta => type == 'item/agentMessage/delta';

  /// Get text delta content.
  String? get textDelta => data['delta'] as String?;
}

/// Error from Codex RPC.
class CodexRpcError implements Exception {
  final int code;
  final String message;
  final dynamic data;

  const CodexRpcError({required this.code, required this.message, this.data});

  factory CodexRpcError.fromJson(Map<String, dynamic> json) {
    return CodexRpcError(
      code: json['code'] as int? ?? -1,
      message: json['message'] as String? ?? 'Unknown error',
      data: json['data'],
    );
  }

  @override
  String toString() => 'CodexRpcError($code): $message';
}

/// Connection state for CodexRuntime.
enum CodexConnectionState {
  disconnected,
  connecting,
  connected,
  initializing,
  ready,
  error,
}

/// Codex App Server RPC client.
class CodexRuntime extends ChangeNotifier {
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final StreamController<CodexEvent> _events = StreamController.broadcast();

  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  int _requestId = 0;

  CodexConnectionState _state = CodexConnectionState.disconnected;
  String? _lastError;
  bool _isInitialized = false;
  CodexAccount? _account;

  // Getters
  CodexConnectionState get state => _state;
  String? get lastError => _lastError;
  bool get isConnected => _process != null;
  bool get isReady => _isInitialized && _state == CodexConnectionState.ready;
  CodexAccount? get account => _account;
  Stream<CodexEvent> get events => _events.stream;

  /// Find Codex binary in PATH or common locations.
  Future<String?> findCodexBinary() async {
    // Check environment variable first
    final envPath = Platform.environment['CODEX_PATH'];
    if (envPath != null && envPath.isNotEmpty) {
      final file = File(envPath);
      if (await file.exists()) {
        return envPath;
      }
    }

    // Try common locations
    final paths = defaultCodexBinaryCandidates();

    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        return path;
      }
    }

    // Try to find via platform-native lookup.
    try {
      final result = await Process.run(
        _lookupExecutableProgram(),
        _lookupExecutableArguments(),
      );
      if (result.exitCode == 0) {
        final lines = LineSplitter.split(
          result.stdout as String,
        ).map((line) => line.trim()).where((line) => line.isNotEmpty);
        for (final path in lines) {
          if (await File(path).exists()) {
            return path;
          }
        }
      }
    } catch (_) {
      // Ignore
    }

    return null;
  }

  /// Start Codex App Server in stdio mode.
  Future<void> startStdio({
    required String codexPath,
    String? cwd,
    CodexSandboxMode sandbox = CodexSandboxMode.workspaceWrite,
    CodexApprovalPolicy approval = CodexApprovalPolicy.suggest,
    List<String> extraArgs = const [],
  }) async {
    if (blocksAppStoreEmbeddedAgentProcesses(
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    )) {
      throw UnsupportedError(
        'App Store builds do not allow launching a local Codex app-server process.',
      );
    }
    if (_process != null) {
      throw StateError('Codex already running');
    }

    _state = CodexConnectionState.connecting;
    _lastError = null;
    notifyListeners();

    try {
      final args = [
        'app-server',
        '--listen',
        'stdio://',
        '-s',
        sandbox.value,
        '-a',
        approval.value,
        ...extraArgs,
      ];
      final launch = _resolveLaunchConfiguration(codexPath, args);

      _process = await Process.start(
        launch.executable,
        launch.arguments,
        workingDirectory: cwd,
        runInShell: launch.runInShell,
      );

      _setupStdioStreams();
      await _initialize();
    } catch (e) {
      _state = CodexConnectionState.error;
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  @visibleForTesting
  static CodexLaunchConfiguration resolveLaunchConfigurationForTest(
    String codexPath,
    List<String> arguments, {
    String? operatingSystem,
  }) {
    return _resolveLaunchConfiguration(
      codexPath,
      arguments,
      operatingSystem: operatingSystem,
    );
  }

  static CodexLaunchConfiguration _resolveLaunchConfiguration(
    String codexPath,
    List<String> arguments, {
    String? operatingSystem,
  }) {
    final host = detectRuntimeHostPlatform(operatingSystem: operatingSystem);
    final normalizedPath = codexPath.toLowerCase();
    final isBatchWrapper =
        host == RuntimeHostPlatform.windows &&
        (normalizedPath.endsWith('.cmd') || normalizedPath.endsWith('.bat'));
    if (isBatchWrapper) {
      return CodexLaunchConfiguration(
        executable: 'cmd.exe',
        arguments: <String>['/c', codexPath, ...arguments],
      );
    }
    return CodexLaunchConfiguration(
      executable: codexPath,
      arguments: arguments,
    );
  }

  static String _lookupExecutableProgram({String? operatingSystem}) {
    return detectRuntimeHostPlatform(operatingSystem: operatingSystem) ==
            RuntimeHostPlatform.windows
        ? 'where'
        : 'which';
  }

  static List<String> _lookupExecutableArguments() {
    return const <String>['codex'];
  }

  void _setupStdioStreams() {
    final process = _process!;
    final stdoutLines = <String>[];
    final stderrLines = <String>[];

    // stdout: JSON-RPC message stream (may have interleaved log lines)
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .listen(
          (line) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) return;

            // Try to parse as JSON-RPC
            if (trimmed.startsWith('{')) {
              _handleMessage(trimmed);
            } else {
              // Non-JSON output, emit as log
              stdoutLines.add(trimmed);
              if (stdoutLines.length > 100) stdoutLines.removeAt(0);
              _events.add(
                CodexLogEvent(
                  level: 'debug',
                  message: trimmed,
                  timestamp: DateTime.now(),
                ),
              );
            }
          },
          onError: (error) {
            _events.add(
              CodexLogEvent(
                level: 'error',
                message: 'stdout error: $error',
                timestamp: DateTime.now(),
              ),
            );
          },
        );

    // stderr: Log output
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .listen(
          (line) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) return;

            stderrLines.add(trimmed);
            if (stderrLines.length > 100) stderrLines.removeAt(0);

            _events.add(
              CodexLogEvent(
                level: 'info',
                message: trimmed,
                timestamp: DateTime.now(),
              ),
            );
          },
          onError: (error) {
            _events.add(
              CodexLogEvent(
                level: 'error',
                message: 'stderr error: $error',
                timestamp: DateTime.now(),
              ),
            );
          },
        );

    // Handle process exit
    process.exitCode.then((exitCode) {
      _events.add(
        CodexLogEvent(
          level: exitCode == 0 ? 'info' : 'warn',
          message: 'Codex exited with code $exitCode',
          timestamp: DateTime.now(),
        ),
      );
      _process = null;
      _state = CodexConnectionState.disconnected;
      _isInitialized = false;
      notifyListeners();
    });
  }

  Future<void> _initialize() async {
    _state = CodexConnectionState.initializing;
    notifyListeners();

    try {
      final result = await request(
        'initialize',
        params: {
          'clientInfo': {'name': 'xworkmate', 'version': kAppVersion},
          'capabilities': {'optOutNotificationMethods': []},
        },
      );

      // Store any account info from response
      if (result.containsKey('account')) {
        _account = CodexAccount.fromJson(
          result['account'] as Map<String, dynamic>,
        );
      }

      // Send initialized notification
      await _sendNotification('initialized', params: {});

      _isInitialized = true;
      _state = CodexConnectionState.ready;
      notifyListeners();
    } catch (e) {
      _state = CodexConnectionState.error;
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  void _handleMessage(String line) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;

      if (json.containsKey('id') && json.containsKey('result')) {
        // Success response
        final id = json['id'].toString();
        final completer = _pendingRequests.remove(id);
        if (completer != null && !completer.isCompleted) {
          completer.complete(json['result'] as Map<String, dynamic>);
        }
      } else if (json.containsKey('id') && json.containsKey('error')) {
        // Error response
        final id = json['id'].toString();
        final completer = _pendingRequests.remove(id);
        if (completer != null && !completer.isCompleted) {
          completer.completeError(
            CodexRpcError.fromJson(json['error'] as Map<String, dynamic>),
          );
        }
      } else if (json.containsKey('method')) {
        // Notification
        final method = json['method'] as String;
        final params = json['params'] as Map<String, dynamic>? ?? {};
        _events.add(CodexNotificationEvent(method: method, params: params));
      }
    } catch (e) {
      _events.add(
        CodexLogEvent(
          level: 'warn',
          message: 'Failed to parse message: $e',
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  /// Send RPC request and wait for response.
  Future<Map<String, dynamic>> request(
    String method, {
    Map<String, dynamic> params = const {},
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final process = _process;
    if (process == null) {
      throw StateError('Codex not running');
    }

    final id = '${DateTime.now().microsecondsSinceEpoch}-${_requestId++}';
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final message = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });

    process.stdin.writeln(message);

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('Request $method timed out');
      },
    );
  }

  /// Send notification (no response expected).
  Future<void> _sendNotification(
    String method, {
    required Map<String, dynamic> params,
  }) async {
    final process = _process;
    if (process == null) {
      throw StateError('Codex not running');
    }

    final message = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });

    process.stdin.writeln(message);
  }

  /// Create a new thread.
  Future<CodexThread> startThread({
    required String cwd,
    String? model,
    CodexSandboxMode? sandbox,
    CodexApprovalPolicy? approval,
    Map<String, dynamic>? settings,
    bool ephemeral = false,
  }) async {
    final params = <String, dynamic>{
      'cwd': cwd,
      ...?model == null ? null : <String, dynamic>{'model': model},
      ...?sandbox == null ? null : <String, dynamic>{'sandbox': sandbox.value},
      ...?approval == null
          ? null
          : <String, dynamic>{'approvalPolicy': approval.value},
      if (ephemeral) 'ephemeral': true,
      ...?settings == null ? null : <String, dynamic>{'settings': settings},
    };

    final result = await request('thread/start', params: params);
    return CodexThread.fromJson(result);
  }

  /// Resume an existing thread.
  Future<CodexThread> resumeThread({
    required String threadId,
    String? cwd,
  }) async {
    final params = <String, dynamic>{
      'threadId': threadId,
      ...?cwd == null ? null : <String, dynamic>{'cwd': cwd},
    };

    final result = await request('thread/resume', params: params);
    return CodexThread.fromJson(result);
  }

  /// Send a message and stream events.
  Stream<CodexTurnEvent> sendMessage({
    required String threadId,
    required String prompt,
    List<CodexAttachment>? attachments,
    Duration timeout = const Duration(minutes: 10),
  }) async* {
    // Start turn
    await request(
      'turn/start',
      params: {
        'threadId': threadId,
        'userInput': CodexUserInput(
          content: prompt,
          attachments: attachments,
        ).toJson(),
      },
    );

    // Listen for events until turn/completed
    await for (final event in _events.stream) {
      if (event is CodexNotificationEvent) {
        final turnEvent = CodexTurnEvent.fromNotification(event);

        // Filter to events for this thread/turn
        if (turnEvent.threadId != threadId) continue;

        yield turnEvent;

        // Check for completion
        if (turnEvent.type == 'turn/completed') {
          break;
        }
      }
    }
  }

  /// Interrupt current turn.
  Future<void> interrupt({required String threadId}) async {
    await request('turn/interrupt', params: {'threadId': threadId});
  }

  /// Get account information.
  Future<CodexAccount> getAccount() async {
    final result = await request('account/read', params: {});
    _account = CodexAccount.fromJson(result);
    notifyListeners();
    return _account!;
  }

  /// List available models.
  Future<List<Map<String, dynamic>>> listModels({
    bool includeHidden = false,
  }) async {
    final result = await request(
      'model/list',
      params: {'includeHidden': includeHidden},
    );
    return (result['models'] as List).cast<Map<String, dynamic>>();
  }

  /// List available skills.
  Future<List<Map<String, dynamic>>> listSkills({required String cwd}) async {
    final result = await request(
      'skills/list',
      params: {
        'cwds': [cwd],
      },
    );
    return (result['skills'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Stop Codex process.
  Future<void> stop() async {
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

    await _stderrSubscription?.cancel();
    _stderrSubscription = null;

    _process?.kill(ProcessSignal.sigterm);
    await _process?.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _process?.kill(ProcessSignal.sigkill);
        return -1;
      },
    );

    _process = null;
    _isInitialized = false;
    _state = CodexConnectionState.disconnected;
    _pendingRequests.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _events.close();
    super.dispose();
  }
}

class CodexLaunchConfiguration {
  const CodexLaunchConfiguration({
    required this.executable,
    required this.arguments,
    this.runInShell = false,
  });

  final String executable;
  final List<String> arguments;
  final bool runInShell;
}
