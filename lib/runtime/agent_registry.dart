/// Agent registry for OpenClaw Gateway integration.
///
/// This module handles agent registration and discovery through the Gateway.
library agent_registry;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gateway_runtime.dart';

/// Agent capability description.
class AgentCapability {
  final String name;
  final String description;
  final Map<String, dynamic>? parameters;

  const AgentCapability({
    required this.name,
    required this.description,
    this.parameters,
  });

  factory AgentCapability.fromJson(Map<String, dynamic> json) {
    return AgentCapability(
      name: json['name'] as String,
      description: json['description'] as String,
      parameters: json['parameters'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        if (parameters != null) 'parameters': parameters,
      };
}

/// Agent registration information.
class AgentRegistration {
  final String agentId;
  final String agentType;
  final String name;
  final String version;
  final String token;
  final DateTime registeredAt;
  final DateTime? expiresAt;
  final List<AgentCapability> capabilities;

  const AgentRegistration({
    required this.agentId,
    required this.agentType,
    required this.name,
    required this.version,
    required this.token,
    required this.registeredAt,
    this.expiresAt,
    this.capabilities = const [],
  });

  factory AgentRegistration.fromJson(Map<String, dynamic> json) {
    return AgentRegistration(
      agentId: json['agentId'] as String,
      agentType: json['agentType'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      token: json['token'] as String,
      registeredAt: DateTime.parse(json['registeredAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
      capabilities: (json['capabilities'] as List?)
              ?.map((e) => AgentCapability.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'agentId': agentId,
        'agentType': agentType,
        'name': name,
        'version': version,
        'token': token,
        'registeredAt': registeredAt.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        'capabilities': capabilities.map((c) => c.toJson()).toList(),
      };
}

/// Agent information from registry.
class AgentInfo {
  final String agentId;
  final String agentType;
  final String name;
  final String status;
  final List<String> capabilities;
  final bool isOnline;
  final DateTime? lastSeen;

  const AgentInfo({
    required this.agentId,
    required this.agentType,
    required this.name,
    required this.status,
    this.capabilities = const [],
    this.isOnline = false,
    this.lastSeen,
  });

  factory AgentInfo.fromJson(Map<String, dynamic> json) {
    return AgentInfo(
      agentId: json['agentId'] as String,
      agentType: json['agentType'] as String,
      name: json['name'] as String,
      status: json['status'] as String,
      capabilities: (json['capabilities'] as List?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'] as String)
          : null,
    );
  }
}

/// Agent response from invoke.
class AgentResponse {
  final String content;
  final String? threadId;
  final String? turnId;
  final Map<String, dynamic>? metadata;

  const AgentResponse({
    required this.content,
    this.threadId,
    this.turnId,
    this.metadata,
  });

  factory AgentResponse.fromJson(Map<String, dynamic> json) {
    return AgentResponse(
      content: json['content'] as String? ?? '',
      threadId: json['threadId'] as String?,
      turnId: json['turnId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Exception for agent operations.
class AgentException implements Exception {
  final String message;
  final String? code;

  const AgentException(this.message, {this.code});

  @override
  String toString() => code != null ? 'AgentException($code): $message' : message;
}

/// Agent registry for managing agent registration and discovery.
class AgentRegistry with ChangeNotifier {
  final GatewayRuntime _gateway;

  AgentRegistration? _registration;
  List<AgentInfo> _agents = [];
  String? _lastError;
  bool _isRegistering = false;

  AgentRegistry(this._gateway);

  AgentRegistration? get registration => _registration;
  List<AgentInfo> get agents => List.unmodifiable(_agents);
  String? get lastError => _lastError;
  bool get isRegistered => _registration != null;
  bool get isRegistering => _isRegistering;

  /// Register this agent with the Gateway.
  Future<AgentRegistration> register({
    required String agentType,
    required String name,
    required String version,
    required List<AgentCapability> capabilities,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_gateway.isConnected) {
      throw AgentException('Gateway not connected', code: 'NOT_CONNECTED');
    }

    _isRegistering = true;
    _lastError = null;
    notifyListeners();

    try {
      final response = await _gateway.request('agent/register', params: {
        'agentType': agentType,
        'name': name,
        'version': version,
        'capabilities': capabilities.map((c) => c.toJson()).toList(),
        if (metadata != null) 'metadata': metadata,
        'transport': 'in-process',
      });

      _registration = AgentRegistration.fromJson(response as Map<String, dynamic>);
      notifyListeners();
      return _registration!;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      throw AgentException('Failed to register agent: $e', code: 'REGISTRATION_FAILED');
    } finally {
      _isRegistering = false;
      notifyListeners();
    }
  }

  /// Unregister this agent from the Gateway.
  Future<void> unregister() async {
    if (_registration == null) {
      return;
    }

    if (!_gateway.isConnected) {
      throw AgentException('Gateway not connected', code: 'NOT_CONNECTED');
    }

    try {
      await _gateway.request('agent/unregister', params: {
        'agentId': _registration!.agentId,
      });

      _registration = null;
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      throw AgentException('Failed to unregister agent: $e', code: 'UNREGISTRATION_FAILED');
    }
  }

  /// List all registered agents.
  Future<List<AgentInfo>> listAgents({String? agentType}) async {
    if (!_gateway.isConnected) {
      throw AgentException('Gateway not connected', code: 'NOT_CONNECTED');
    }

    try {
      final response = await _gateway.request('agent/list', params: {
        if (agentType != null) 'agentType': agentType,
      });

      final agentsJson = response['agents'] as List? ?? [];
      _agents = agentsJson
          .map((a) => AgentInfo.fromJson(a as Map<String, dynamic>))
          .toList();
      notifyListeners();
      return _agents;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      throw AgentException('Failed to list agents: $e', code: 'LIST_FAILED');
    }
  }

  /// Invoke a remote agent.
  Future<AgentResponse> invokeAgent({
    required String agentId,
    required String prompt,
    Map<String, dynamic>? context,
    String? threadId,
  }) async {
    if (!_gateway.isConnected) {
      throw AgentException('Gateway not connected', code: 'NOT_CONNECTED');
    }

    try {
      final response = await _gateway.request('agent/invoke', params: {
        'agentId': agentId,
        'prompt': prompt,
        if (context != null) 'context': context,
        if (threadId != null) 'threadId': threadId,
      });

      return AgentResponse.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      throw AgentException('Failed to invoke agent: $e', code: 'INVOKE_FAILED');
    }
  }

  /// Update agent status.
  Future<void> updateStatus({
    required String status,
    List<String>? capabilities,
  }) async {
    if (_registration == null) {
      throw AgentException('Agent not registered', code: 'NOT_REGISTERED');
    }

    if (!_gateway.isConnected) {
      throw AgentException('Gateway not connected', code: 'NOT_CONNECTED');
    }

    try {
      await _gateway.request('agent/updateStatus', params: {
        'agentId': _registration!.agentId,
        'status': status,
        if (capabilities != null) 'capabilities': capabilities,
      });
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      throw AgentException('Failed to update status: $e', code: 'UPDATE_FAILED');
    }
  }

  /// Sync memory with cloud.
  Future<Map<String, dynamic>> syncMemory({
    required String direction,
    String? sinceVersion,
  }) async {
    if (!_gateway.isConnected) {
      throw AgentException('Gateway not connected', code: 'NOT_CONNECTED');
    }

    try {
      final response = await _gateway.request('memory/sync', params: {
        'direction': direction, // 'pull', 'push', 'both'
        if (sinceVersion != null) 'sinceVersion': sinceVersion,
      });

      return response as Map<String, dynamic>;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      throw AgentException('Failed to sync memory: $e', code: 'SYNC_FAILED');
    }
  }

  /// Clear last error.
  void clearError() {
    _lastError = null;
    notifyListeners();
  }
}
