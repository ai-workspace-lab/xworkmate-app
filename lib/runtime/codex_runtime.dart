import 'dart:async';

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
class CodexRuntime {}

List<Map<String, dynamic>> _decodeModelListResponse(
  Map<String, dynamic> result,
) {
  final rawModels = <Object?>[
    ...switch (result['models']) {
      final List<Object?> items => items,
      _ => const <Object?>[],
    },
    if (switch (result['models']) {
      final List<Object?> items => items.isEmpty,
      _ => true,
    })
      ...switch (result['data']) {
        final List<Object?> items => items,
        _ => const <Object?>[],
      },
  ];
  final seen = <String>{};
  final items = <Map<String, dynamic>>[];
  for (final item in rawModels) {
    if (item is! Map) {
      continue;
    }
    final model = item.cast<String, dynamic>();
    final rawId = model['id'] ?? model['name'];
    final id = rawId is String ? rawId.trim() : '';
    if (id.isEmpty || !seen.add(id)) {
      continue;
    }
    items.add(model);
  }
  return items;
}

Object _normalizeModelListError(Object error) {
  if (error is TimeoutException) {
    return TimeoutException('Codex model refresh timed out');
  }
  if (error is CodexRpcError) {
    final message = error.message.trim();
    final lower = message.toLowerCase();
    if (lower.contains('cloudflare') || lower.contains('403 forbidden')) {
      return CodexRpcError(
        code: error.code,
        message: 'Codex model refresh blocked by Cloudflare (403)',
        data: error.data,
      );
    }
    if (lower.contains('timeout waiting for child process to exit')) {
      return TimeoutException(
        'Codex model refresh timed out waiting for child process exit',
      );
    }
    if (lower.contains('missing field `models`')) {
      return CodexRpcError(
        code: error.code,
        message: 'Codex model list payload used an unsupported schema',
        data: error.data,
      );
    }
  }
  return error;
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
