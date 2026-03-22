enum LegacyRecoveryStatus {
  none,
  migrated,
  lockedLegacyState,
  failed,
}

extension LegacyRecoveryStatusCopy on LegacyRecoveryStatus {
  static LegacyRecoveryStatus fromJsonValue(String? value) {
    return switch (value?.trim()) {
      'migrated' => LegacyRecoveryStatus.migrated,
      'locked_legacy_state' => LegacyRecoveryStatus.lockedLegacyState,
      'failed' => LegacyRecoveryStatus.failed,
      _ => LegacyRecoveryStatus.none,
    };
  }

  String get jsonValue => switch (this) {
    LegacyRecoveryStatus.none => 'none',
    LegacyRecoveryStatus.migrated => 'migrated',
    LegacyRecoveryStatus.lockedLegacyState => 'locked_legacy_state',
    LegacyRecoveryStatus.failed => 'failed',
  };
}

class LegacyRecoveryReport {
  const LegacyRecoveryReport({
    this.status = LegacyRecoveryStatus.none,
    this.sourcePath,
    this.details = '',
  });

  final LegacyRecoveryStatus status;
  final String? sourcePath;
  final String details;

  bool get hasIssue =>
      status == LegacyRecoveryStatus.lockedLegacyState ||
      status == LegacyRecoveryStatus.failed;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'status': status.jsonValue,
      'sourcePath': sourcePath,
      'details': details,
    };
  }

  factory LegacyRecoveryReport.fromJson(Map<String, dynamic> json) {
    return LegacyRecoveryReport(
      status: LegacyRecoveryStatusCopy.fromJsonValue(
        json['status'] as String?,
      ),
      sourcePath: json['sourcePath'] as String?,
      details: json['details'] as String? ?? '',
    );
  }
}
