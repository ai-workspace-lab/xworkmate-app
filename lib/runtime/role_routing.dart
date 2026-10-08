// Role routing contract with xworkmate-bridge.
//
// The bridge owns the role policy, model catalog and hard gates; the app only
// chooses auto/manual, shows what the bridge actually selected, and relays the
// user's permission decisions. See xworkmate-bridge
// docs/architecture/role-routing-engineer-loop.md.

enum RoleRoutingMode { off, auto, manual }

class BridgeRoleModelOption {
  const BridgeRoleModelOption({required this.key, required this.displayName});

  final String key;
  final String displayName;

  String get label => displayName.trim().isNotEmpty ? displayName : key;
}

class BridgeRoleOption {
  const BridgeRoleOption({
    required this.role,
    required this.enabled,
    required this.models,
    required this.requiresWorkspace,
  });

  final String role;
  final bool enabled;
  final List<BridgeRoleModelOption> models;
  final bool requiresWorkspace;
}

class BridgeRoleRoutingCatalog {
  const BridgeRoleRoutingCatalog({
    required this.configured,
    required this.enabled,
    required this.policyVersion,
    required this.roles,
    required this.error,
  });

  static const BridgeRoleRoutingCatalog unavailable = BridgeRoleRoutingCatalog(
    configured: false,
    enabled: false,
    policyVersion: '',
    roles: <BridgeRoleOption>[],
    error: '',
  );

  factory BridgeRoleRoutingCatalog.fromCapabilities(
    Map<String, dynamic> capabilitiesRaw,
  ) {
    final raw = _asMap(capabilitiesRaw['roleRouting']);
    if (raw.isEmpty) {
      return unavailable;
    }
    final roles = <BridgeRoleOption>[];
    for (final item in _asList(raw['roles'])) {
      final entry = _asMap(item);
      final role = _string(entry['role']);
      if (role.isEmpty) {
        continue;
      }
      roles.add(
        BridgeRoleOption(
          role: role,
          enabled: entry['enabled'] == true,
          requiresWorkspace: entry['requiresWorkspace'] == true,
          models: _asList(entry['models'])
              .map(_asMap)
              .where((model) => _string(model['key']).isNotEmpty)
              .map(
                (model) => BridgeRoleModelOption(
                  key: _string(model['key']),
                  displayName: _string(model['displayName']),
                ),
              )
              .toList(growable: false),
        ),
      );
    }
    return BridgeRoleRoutingCatalog(
      configured: raw['configured'] == true,
      enabled: raw['enabled'] == true && raw['valid'] != false,
      policyVersion: _string(raw['policyVersion']),
      roles: List<BridgeRoleOption>.unmodifiable(roles),
      error: _string(raw['error']),
    );
  }

  final bool configured;
  final bool enabled;
  final String policyVersion;
  final List<BridgeRoleOption> roles;
  final String error;

  List<BridgeRoleOption> get enabledRoles =>
      roles.where((role) => role.enabled).toList(growable: false);

  BridgeRoleOption? role(String id) {
    for (final option in roles) {
      if (option.role == id) {
        return option;
      }
    }
    return null;
  }
}

class RoleRoutingSelection {
  const RoleRoutingSelection({
    required this.mode,
    this.role = '',
    this.modelKey = '',
  });

  static const RoleRoutingSelection off = RoleRoutingSelection(
    mode: RoleRoutingMode.off,
  );

  final RoleRoutingMode mode;
  final String role;

  /// Policy model key chosen manually; empty keeps the policy order.
  final String modelKey;

  bool get isActive => mode != RoleRoutingMode.off;

  /// Fields merged into the bridge `routing` object.
  Map<String, dynamic> toRoutingJson() {
    switch (mode) {
      case RoleRoutingMode.off:
        return const <String, dynamic>{};
      case RoleRoutingMode.auto:
        return <String, dynamic>{
          'roleMode': 'auto',
          if (role.trim().isNotEmpty) 'role': role.trim(),
        };
      case RoleRoutingMode.manual:
        return <String, dynamic>{
          'roleMode': modelKey.trim().isEmpty ? 'auto' : 'manual',
          'role': role.trim(),
          if (modelKey.trim().isNotEmpty) 'roleModel': modelKey.trim(),
        };
    }
  }
}

class RoleTaskPermissionOption {
  const RoleTaskPermissionOption({
    required this.optionId,
    required this.name,
    required this.kind,
  });

  final String optionId;
  final String name;
  final String kind;

  bool get allows => kind.startsWith('allow');
}

class RoleTaskPermissionRequest {
  const RoleTaskPermissionRequest({
    required this.requestId,
    required this.sessionId,
    required this.title,
    required this.toolKind,
    required this.options,
  });

  static RoleTaskPermissionRequest? fromJsonOrNull(Object? value) {
    final raw = _asMap(value);
    final requestId = _string(raw['requestId']);
    final sessionId = _string(raw['sessionId']);
    if (requestId.isEmpty || sessionId.isEmpty) {
      return null;
    }
    final toolCall = _asMap(raw['toolCall']);
    return RoleTaskPermissionRequest(
      requestId: requestId,
      sessionId: sessionId,
      title: _string(toolCall['title']),
      toolKind: _string(toolCall['kind']),
      options: _asList(raw['options'])
          .map(_asMap)
          .where((option) => _string(option['optionId']).isNotEmpty)
          .map(
            (option) => RoleTaskPermissionOption(
              optionId: _string(option['optionId']),
              name: _string(option['name']),
              kind: _string(option['kind']),
            ),
          )
          .toList(growable: false),
    );
  }

  final String requestId;
  final String sessionId;
  final String title;
  final String toolKind;
  final List<RoleTaskPermissionOption> options;
}

/// What the bridge actually selected and where the task stands.
class RoleTaskStatus {
  const RoleTaskStatus({
    required this.phase,
    required this.role,
    required this.providerId,
    required this.modelId,
    required this.policyVersion,
    required this.message,
  });

  final String phase;
  final String role;
  final String providerId;
  final String modelId;
  final String policyVersion;

  /// Rejection or failure reason reported by the bridge.
  final String message;

  bool get terminal =>
      phase == 'completed' ||
      phase == 'failed' ||
      phase == 'cancelled' ||
      phase == 'rejected';
}

/// A parsed `type: task` session update from the bridge.
class RoleTaskEvent {
  const RoleTaskEvent({
    required this.phase,
    required this.status,
    required this.permission,
  });

  static RoleTaskEvent? fromUpdatePayloadOrNull(Map<String, dynamic> payload) {
    if (_string(payload['type']) != 'task') {
      return null;
    }
    final task = _asMap(payload['task']);
    final phase = _string(task['phase']);
    if (phase.isEmpty) {
      return null;
    }
    final detail = _asMap(task['detail']);
    return RoleTaskEvent(
      phase: phase,
      status: RoleTaskStatus(
        phase: phase,
        role: _string(task['role']).isNotEmpty
            ? _string(task['role'])
            : _string(detail['role']),
        providerId: _string(task['providerId']),
        modelId: _string(task['modelId']),
        policyVersion: _string(task['policyVersion']),
        message: _string(detail['message']).isNotEmpty
            ? _string(detail['message'])
            : _string(detail['error']),
      ),
      permission:
          phase == 'permission_requested' || phase == 'permission_resolved'
          ? RoleTaskPermissionRequest.fromJsonOrNull(detail)
          : null,
    );
  }

  final String phase;
  final RoleTaskStatus status;
  final RoleTaskPermissionRequest? permission;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const <Object?>[];
}

String _string(Object? value) => value?.toString().trim() ?? '';
