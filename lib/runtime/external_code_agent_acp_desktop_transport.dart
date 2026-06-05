import 'dart:async';
import 'dart:io';

import 'acp_endpoint_paths.dart';
import 'gateway_acp_client.dart';
import 'go_task_service_client.dart';
import 'runtime_models.dart';

class ExternalCodeAgentAcpDesktopTransport implements GoTaskServiceClient {
  ExternalCodeAgentAcpDesktopTransport({
    required GatewayAcpClient client,
    required Uri? Function(AssistantExecutionTarget target) endpointResolver,
    Uri? Function(GoTaskServiceRequest request)? taskEndpointResolver,
    Duration recoveryPollDelay = const Duration(seconds: 2),
    int? recoveryMaxAttempts,
  }) : _client = client,
       _endpointResolver = endpointResolver,
       _taskEndpointResolver = taskEndpointResolver,
       _recoveryPollDelay = recoveryPollDelay,
       _recoveryMaxAttempts = recoveryMaxAttempts;

  final GatewayAcpClient _client;
  final Uri? Function(AssistantExecutionTarget target) _endpointResolver;
  final Uri? Function(GoTaskServiceRequest request)? _taskEndpointResolver;
  final Duration _recoveryPollDelay;
  final int? _recoveryMaxAttempts;

  @override
  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) async {
    var streamedText = '';
    String? completedMessage;
    Map<String, dynamic>? runningTaskSnapshot;
    try {
      final endpointOverride = _taskEndpointResolver == null
          ? _endpointResolver(request.target)
          : _taskEndpointResolver.call(request);
      if (endpointOverride == null) {
        throw const GatewayAcpException(
          'xworkmate-bridge is not connected',
          code: 'BRIDGE_NOT_CONNECTED',
        );
      }
      final response = await _client.request(
        method: request.resumeSession ? 'session.message' : 'session.start',
        params: request.toExternalAcpParams(),
        endpointOverride: endpointOverride,
        onNotification: (notification) {
          final update = goTaskServiceUpdateFromAcpNotification(notification);
          if (update == null) {
            return;
          }
          if (update.sessionId != request.sessionId ||
              update.threadId != request.threadId) {
            return;
          }
          if (update.isDelta) {
            streamedText += update.text;
          }
          if (update.isDone && update.message.trim().isNotEmpty) {
            completedMessage = update.message.trim();
          }
          if (OpenClawTaskAssociation.fromJsonOrNull(update.payload) != null) {
            runningTaskSnapshot = <String, dynamic>{...update.payload};
          }
          onUpdate(update);
        },
      );
      return goTaskServiceResultFromAcpResponse(
        response,
        route: request.route,
        streamedText: streamedText,
        completedMessage: completedMessage,
      );
    } on GatewayAcpException catch (error) {
      if (_isRecoverableTaskStreamClosure(error)) {
        final recovered = await _recoverTaskResultAfterStreamClosure(
          request,
          taskEndpoint: _taskEndpointResolver == null
              ? _endpointResolver(request.target)
              : _taskEndpointResolver.call(request),
          streamedText: streamedText,
          completedMessage: completedMessage,
          runningTaskSnapshot: runningTaskSnapshot,
        );
        if (recovered != null) {
          return recovered;
        }
      }
      rethrow;
    } on SocketException catch (error) {
      final timeout = _socketExceptionLooksLikeConnectTimeout(error);
      throw GatewayAcpException(
        timeout
            ? 'ACP HTTP connection timed out before the request was confirmed'
            : 'ACP HTTP connection failed before the request was confirmed',
        code: timeout
            ? gatewayAcpHttpConnectTimeoutCode
            : gatewayAcpHttpConnectFailedCode,
        details: <String, dynamic>{'originalError': error.toString()},
      );
    } catch (error) {
      throw GatewayAcpException(
        error.toString(),
        code: 'EXTERNAL_ACP_GATEWAY_ERROR',
      );
    }
  }

  bool _isRecoverableTaskStreamClosure(GatewayAcpException error) {
    return error.code == 'ACP_HTTP_CONNECTION_CLOSED' ||
        error.code == 'ACP_SSE_NO_RESULT';
  }

  Future<GoTaskServiceResult?> _recoverTaskResultAfterStreamClosure(
    GoTaskServiceRequest request, {
    required Uri? taskEndpoint,
    required String streamedText,
    required String? completedMessage,
    Map<String, dynamic>? runningTaskSnapshot,
  }) async {
    final endpoint = _sessionSnapshotEndpoint(taskEndpoint);
    if (endpoint == null) {
      return null;
    }
    final association = OpenClawTaskAssociation.fromJsonOrNull(
      runningTaskSnapshot,
    );
    if (association == null) {
      return null;
    }
    final attempts = _recoveryAttemptsForRequest(request);
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      if (attempt > 0) {
        await Future<void>.delayed(_recoveryPollDelay);
      }
      Map<String, dynamic> response;
      try {
        response = await _client.request(
          method: 'xworkmate.tasks.get',
          params: association.toTaskGetParams(),
          endpointOverride: endpoint,
        );
      } on GatewayAcpException {
        continue;
      } on SocketException {
        continue;
      }
      final snapshot = _castMap(response['result']);
      final status = (snapshot['status'] ?? '').toString().trim().toLowerCase();
      final terminal =
          status == 'completed' ||
          status == 'failed' ||
          status == 'cancelled' ||
          status == 'canceled';
      if (!terminal) {
        continue;
      }
      if (status == 'failed' || status == 'cancelled' || status == 'canceled') {
        return goTaskServiceResultFromAcpResponse(
          <String, dynamic>{
            'jsonrpc': '2.0',
            'id': 'recovered-from-terminal-task-snapshot',
            'result': _failureResultFromTaskSnapshot(snapshot, status),
          },
          route: request.route,
          streamedText: streamedText,
          completedMessage: completedMessage,
        );
      }
      final result = _recoveredResultFromTaskSnapshot(snapshot);
      final resultArtifacts = _castMap(result['artifacts']);
      final artifactItems = resultArtifacts['items'] ?? resultArtifacts;
      final hasArtifacts =
          result.isNotEmpty &&
          (artifactItems is List && artifactItems.isNotEmpty ||
              result['artifacts'] is List &&
                  (result['artifacts'] as List).isNotEmpty);
      if (!hasArtifacts && status == 'completed' && attempt < attempts - 1) {
        continue;
      }
      if (result.isNotEmpty) {
        return goTaskServiceResultFromAcpResponse(
          <String, dynamic>{
            'jsonrpc': '2.0',
            'id': 'recovered-from-session-snapshot',
            'result': result,
          },
          route: request.route,
          streamedText: streamedText,
          completedMessage: completedMessage,
        );
      }
    }
    return null;
  }

  @override
  Future<GoTaskServiceResult> getTask({
    required AssistantExecutionTarget target,
    required OpenClawTaskAssociation association,
    required GoTaskServiceRoute route,
  }) async {
    final endpoint = _sessionSnapshotEndpoint(_endpointResolver(target));
    if (endpoint == null) {
      throw const GatewayAcpException(
        'xworkmate-bridge is not connected',
        code: 'BRIDGE_NOT_CONNECTED',
      );
    }
    final response = await _client.request(
      method: 'xworkmate.tasks.get',
      params: association.toTaskGetParams(),
      endpointOverride: endpoint,
    );
    return goTaskServiceResultFromAcpResponse(response, route: route);
  }

  int _recoveryAttemptsForRequest(GoTaskServiceRequest request) {
    final configured = _recoveryMaxAttempts;
    if (configured != null) {
      return configured <= 0 ? 1 : configured;
    }
    return 1;
  }

  Uri? _sessionSnapshotEndpoint(Uri? taskEndpoint) {
    final controlEndpoint = resolveAcpHttpRpcEndpoint(
      _endpointResolver(AssistantExecutionTarget.gateway),
    );
    if (controlEndpoint != null) {
      return controlEndpoint;
    }
    return resolveAcpHttpRpcEndpoint(taskEndpoint);
  }

  @override
  Future<void> cancelTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
    OpenClawTaskAssociation? association,
  }) async {
    if (association != null) {
      final endpoint = _sessionSnapshotEndpoint(_endpointResolver(target));
      if (endpoint != null) {
        await _client.request(
          method: 'xworkmate.tasks.cancel',
          params: association.toTaskGetParams(),
          endpointOverride: endpoint,
        );
        return;
      }
    }
    await _client.cancelSession(
      sessionId: sessionId,
      threadId: threadId,
      endpointOverride: _endpointResolver(target),
    );
  }

  @override
  Future<void> dispose() => _client.dispose();
  Map<String, dynamic> _recoveredResultFromTaskSnapshot(
    Map<String, dynamic> snapshot,
  ) {
    final result = <String, dynamic>{
      ..._castMap(snapshot['result']),
      ...snapshot,
    };
    final artifactRecord = _castMap(snapshot['artifacts']);
    final artifactItems = artifactRecord['items'];
    if (artifactItems is List && artifactItems.isNotEmpty) {
      result['artifacts'] = List<Map<String, dynamic>>.from(artifactItems);
    } else if (result['artifacts'] is Map) {
      final nestedArtifacts = _castMap(result['artifacts']);
      final nestedItems = nestedArtifacts['items'];
      if (nestedItems is List && nestedItems.isNotEmpty) {
        result['artifacts'] = List<Map<String, dynamic>>.from(nestedItems);
      }
    }
    for (final entry in <String, String>{
      'remoteWorkingDirectory': 'remoteWorkingDirectory',
      'remoteWorkspaceRefKind': 'remoteWorkspaceRefKind',
      'resultSummary': 'summary',
    }.entries) {
      final value = artifactRecord[entry.key]?.toString().trim() ?? '';
      if (value.isNotEmpty &&
          (result[entry.value]?.toString().trim().isEmpty ?? true)) {
        result[entry.value] = value;
      }
    }
    return result;
  }

  Map<String, dynamic> _failureResultFromTaskSnapshot(
    Map<String, dynamic> snapshot,
    String status,
  ) {
    final error = _castMap(snapshot['error']);
    final rawMessage =
        error['message'] ??
        error['error'] ??
        snapshot['message'] ??
        snapshot['error'];
    final message = rawMessage?.toString().trim() ?? '';
    final rawCode = error['code'] ?? snapshot['code'];
    final code = rawCode?.toString().trim() ?? '';
    final result = <String, dynamic>{
      'success': false,
      'status': status,
      'turnId': snapshot['turnId']?.toString().trim() ?? '',
      'error': message.isNotEmpty ? message : 'Bridge session ended: $status',
      'message': message.isNotEmpty ? message : 'Bridge session ended: $status',
    };
    if (code.isNotEmpty) {
      result['code'] = code;
    }
    return result;
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

  bool _socketExceptionLooksLikeConnectTimeout(SocketException error) {
    final lowered = error.toString().toLowerCase();
    return lowered.contains('connection timed out') ||
        lowered.contains('timed out') ||
        lowered.contains('timeout');
  }
}
