part of 'runtime_models.dart';

class GatewayChatAttachmentPayload {
  const GatewayChatAttachmentPayload({
    required this.type,
    required this.mimeType,
    required this.fileName,
    required this.content,
  });

  final String type;
  final String mimeType;
  final String fileName;
  final String content;

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'mimeType': mimeType,
      'fileName': fileName,
      'content': content,
    };
  }
}

class GatewayInstanceSummary {
  const GatewayInstanceSummary({
    required this.id,
    required this.host,
    required this.ip,
    required this.version,
    required this.platform,
    required this.deviceFamily,
    required this.modelIdentifier,
    required this.lastInputSeconds,
    required this.mode,
    required this.reason,
    required this.text,
    required this.timestampMs,
  });

  final String id;
  final String? host;
  final String? ip;
  final String? version;
  final String? platform;
  final String? deviceFamily;
  final String? modelIdentifier;
  final int? lastInputSeconds;
  final String? mode;
  final String? reason;
  final String text;
  final double timestampMs;
}

class GatewaySkillSummary {
  const GatewaySkillSummary({
    required this.name,
    required this.description,
    required this.source,
    required this.skillKey,
    required this.primaryEnv,
    required this.eligible,
    required this.disabled,
    required this.missingBins,
    required this.missingEnv,
    required this.missingConfig,
  });

  final String name;
  final String description;
  final String source;
  final String skillKey;
  final String? primaryEnv;
  final bool eligible;
  final bool disabled;
  final List<String> missingBins;
  final List<String> missingEnv;
  final List<String> missingConfig;
}

class GatewayConnectorSummary {
  const GatewayConnectorSummary({
    required this.id,
    required this.label,
    required this.detailLabel,
    required this.accountName,
    required this.configured,
    required this.enabled,
    required this.running,
    required this.connected,
    required this.status,
    required this.lastError,
    required this.meta,
  });

  final String id;
  final String label;
  final String detailLabel;
  final String? accountName;
  final bool configured;
  final bool enabled;
  final bool running;
  final bool connected;
  final String status;
  final String? lastError;
  final List<String> meta;
}

class GatewayModelSummary {
  const GatewayModelSummary({
    required this.id,
    required this.name,
    required this.provider,
    required this.contextWindow,
    required this.maxOutputTokens,
  });

  final String id;
  final String name;
  final String provider;
  final int? contextWindow;
  final int? maxOutputTokens;
}

class GatewayCronJobSummary {
  const GatewayCronJobSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
    required this.agentId,
    required this.scheduleLabel,
    required this.nextRunAtMs,
    required this.lastRunAtMs,
    required this.lastStatus,
    required this.lastError,
  });

  final String id;
  final String name;
  final String? description;
  final bool enabled;
  final String? agentId;
  final String scheduleLabel;
  final int? nextRunAtMs;
  final int? lastRunAtMs;
  final String? lastStatus;
  final String? lastError;
}

class GatewayDevicePairingList {
  const GatewayDevicePairingList({required this.pending, required this.paired});

  final List<GatewayPendingDevice> pending;
  final List<GatewayPairedDevice> paired;

  const GatewayDevicePairingList.empty()
    : pending = const <GatewayPendingDevice>[],
      paired = const <GatewayPairedDevice>[];
}

class GatewayPendingDevice {
  const GatewayPendingDevice({
    required this.requestId,
    required this.deviceId,
    required this.displayName,
    required this.role,
    required this.scopes,
    required this.remoteIp,
    required this.isRepair,
    required this.requestedAtMs,
  });

  final String requestId;
  final String deviceId;
  final String? displayName;
  final String? role;
  final List<String> scopes;
  final String? remoteIp;
  final bool isRepair;
  final int? requestedAtMs;

  String get label {
    final display = displayName?.trim() ?? '';
    return display.isEmpty ? deviceId : display;
  }
}

class GatewayPairedDevice {
  const GatewayPairedDevice({
    required this.deviceId,
    required this.displayName,
    required this.roles,
    required this.scopes,
    required this.remoteIp,
    required this.tokens,
    required this.createdAtMs,
    required this.approvedAtMs,
    required this.currentDevice,
  });

  final String deviceId;
  final String? displayName;
  final List<String> roles;
  final List<String> scopes;
  final String? remoteIp;
  final List<GatewayDeviceTokenSummary> tokens;
  final int? createdAtMs;
  final int? approvedAtMs;
  final bool currentDevice;

  String get label {
    final display = displayName?.trim() ?? '';
    return display.isEmpty ? deviceId : display;
  }
}

class GatewayDeviceTokenSummary {
  const GatewayDeviceTokenSummary({
    required this.role,
    required this.scopes,
    required this.createdAtMs,
    required this.rotatedAtMs,
    required this.revokedAtMs,
    required this.lastUsedAtMs,
  });

  final String role;
  final List<String> scopes;
  final int? createdAtMs;
  final int? rotatedAtMs;
  final int? revokedAtMs;
  final int? lastUsedAtMs;

  bool get revoked => revokedAtMs != null;
}

class SecretReferenceEntry {
  const SecretReferenceEntry({
    required this.name,
    required this.provider,
    required this.module,
    required this.maskedValue,
    required this.status,
  });

  final String name;
  final String provider;
  final String module;
  final String maskedValue;
  final String status;
}

class SecretAuditEntry {
  const SecretAuditEntry({
    required this.timeLabel,
    required this.action,
    required this.provider,
    required this.target,
    required this.module,
    required this.status,
  });

  final String timeLabel;
  final String action;
  final String provider;
  final String target;
  final String module;
  final String status;

  Map<String, dynamic> toJson() {
    return {
      'timeLabel': timeLabel,
      'action': action,
      'provider': provider,
      'target': target,
      'module': module,
      'status': status,
    };
  }

  factory SecretAuditEntry.fromJson(Map<String, dynamic> json) {
    return SecretAuditEntry(
      timeLabel: json['timeLabel'] as String? ?? '',
      action: json['action'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      target: json['target'] as String? ?? '',
      module: json['module'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }
}

class DerivedTaskItem {
  const DerivedTaskItem({
    required this.id,
    required this.title,
    required this.owner,
    required this.status,
    required this.surface,
    required this.startedAtLabel,
    required this.durationLabel,
    required this.summary,
    required this.sessionKey,
  });

  final String id;
  final String title;
  final String owner;
  final String status;
  final String surface;
  final String startedAtLabel;
  final String durationLabel;
  final String summary;
  final String sessionKey;
}

class LocalDeviceIdentity {
  const LocalDeviceIdentity({
    required this.deviceId,
    required this.publicKeyBase64Url,
    required this.privateKeyBase64Url,
    required this.createdAtMs,
  });

  final String deviceId;
  final String publicKeyBase64Url;
  final String privateKeyBase64Url;
  final int createdAtMs;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deviceId': deviceId,
      'publicKeyBase64Url': publicKeyBase64Url,
      'privateKeyBase64Url': privateKeyBase64Url,
      'createdAtMs': createdAtMs,
    };
  }

  factory LocalDeviceIdentity.fromJson(Map<String, dynamic> json) {
    return LocalDeviceIdentity(
      deviceId: json['deviceId'] as String? ?? '',
      publicKeyBase64Url: json['publicKeyBase64Url'] as String? ?? '',
      privateKeyBase64Url: json['privateKeyBase64Url'] as String? ?? '',
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 多 Agent 协作角色
