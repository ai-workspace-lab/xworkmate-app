import 'package:flutter/foundation.dart';

import 'dart:convert';

import '../models/app_models.dart';
import 'runtime_models_connection.dart';

const int appUiStateSchemaVersion = 2;

/// Clamp a persisted composer offset back into something usable. A stored
/// value can be stale (written on a much taller window) or corrupt; the pane
/// clamps again at layout time, but a NaN or an absurd number would otherwise
/// survive in the file forever.
double normalizeComposerHeightAdjustment(double? value) {
  if (value == null || !value.isFinite) {
    return 0;
  }
  return value.clamp(-2000.0, 2000.0).toDouble();
}

class AppUiState {
  const AppUiState({
    required this.schemaVersion,
    required this.assistantLastSessionKey,
    required this.assistantNavigationDestinations,
    required this.savedGatewayTargets,
    this.assistantComposerHeightAdjustment = 0,
  });

  final int schemaVersion;
  final String assistantLastSessionKey;
  final List<AssistantFocusEntry> assistantNavigationDestinations;
  final List<String> savedGatewayTargets;

  /// How far the user dragged the composer boundary away from its content-
  /// derived default, in logical pixels. Signed: negative shrinks the composer.
  /// Stored as an offset rather than an absolute height so it still means the
  /// same thing when the content, the window or the font scale changes.
  ///
  /// Deliberately NOT guarded by a schema bump: `fromJson` rejects a mismatched
  /// version outright, so bumping would throw away the user's saved navigation
  /// destinations and gateway targets. An optional field with a default reads
  /// correctly from old state and is ignored by older builds.
  final double assistantComposerHeightAdjustment;

  factory AppUiState.defaults() {
    return const AppUiState(
      schemaVersion: appUiStateSchemaVersion,
      assistantLastSessionKey: '',
      assistantNavigationDestinations: kAssistantNavigationDestinationDefaults,
      savedGatewayTargets: <String>[],
    );
  }

  AppUiState copyWith({
    int? schemaVersion,
    String? assistantLastSessionKey,
    List<AssistantFocusEntry>? assistantNavigationDestinations,
    List<String>? savedGatewayTargets,
    double? assistantComposerHeightAdjustment,
  }) {
    return AppUiState(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      assistantLastSessionKey:
          assistantLastSessionKey ?? this.assistantLastSessionKey,
      assistantNavigationDestinations:
          assistantNavigationDestinations ??
          this.assistantNavigationDestinations,
      savedGatewayTargets: normalizeSavedGatewayTargets(
        savedGatewayTargets ?? this.savedGatewayTargets,
      ),
      assistantComposerHeightAdjustment:
          assistantComposerHeightAdjustment ??
          this.assistantComposerHeightAdjustment,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'assistantLastSessionKey': assistantLastSessionKey,
      'assistantNavigationDestinations': assistantNavigationDestinations
          .map((item) => item.name)
          .toList(growable: false),
      'savedGatewayTargets': savedGatewayTargets,
      'assistantComposerHeightAdjustment': assistantComposerHeightAdjustment,
    };
  }

  factory AppUiState.fromJson(Map<String, dynamic> json) {
    final parsedSchemaVersion = (json['schemaVersion'] as num?)?.toInt() ?? -1;
    if (parsedSchemaVersion != appUiStateSchemaVersion) {
      throw const FormatException('Unsupported app ui state schema version.');
    }
    final rawAssistantNavigationDestinations =
        json['assistantNavigationDestinations'];
    final assistantNavigationDestinations =
        rawAssistantNavigationDestinations is List
        ? normalizeAssistantNavigationDestinations(
            rawAssistantNavigationDestinations
                .map(
                  (item) =>
                      AssistantFocusEntryCopy.fromJsonValue(item?.toString()),
                )
                .whereType<AssistantFocusEntry>(),
          )
        : kAssistantNavigationDestinationDefaults;
    return AppUiState(
      schemaVersion: parsedSchemaVersion,
      assistantLastSessionKey: json['assistantLastSessionKey'] as String? ?? '',
      assistantNavigationDestinations: assistantNavigationDestinations,
      savedGatewayTargets: normalizeSavedGatewayTargets(
        (json['savedGatewayTargets'] as List? ?? const <Object>[]).map(
          (item) => item?.toString() ?? '',
        ),
      ),
      assistantComposerHeightAdjustment: normalizeComposerHeightAdjustment(
        // `as num?` would throw on a string; a single bad field must not cost
        // the user every other preference in the file.
        switch (json['assistantComposerHeightAdjustment']) {
          final num value => value.toDouble(),
          _ => null,
        },
      ),
    );
  }

  static AppUiState fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return AppUiState.defaults();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return AppUiState.defaults();
      }
      return AppUiState.fromJson(decoded);
    } catch (e, stackTrace) {
      debugPrint('Error: $e\n$stackTrace');
      return AppUiState.defaults();
    }
  }

  String toJsonString() => jsonEncode(toJson());

  bool isGatewayTargetSaved(AssistantExecutionTarget target) {
    const targetKey = 'gateway';
    return targetKey.isNotEmpty && savedGatewayTargets.contains(targetKey);
  }

  AppUiState markGatewayTargetSaved(AssistantExecutionTarget target) {
    const targetKey = 'gateway';
    if (targetKey.isEmpty || savedGatewayTargets.contains(targetKey)) {
      return this;
    }
    return copyWith(
      savedGatewayTargets: <String>[...savedGatewayTargets, targetKey],
    );
  }
}

List<String> normalizeSavedGatewayTargets(Iterable<String> rawTargets) {
  final normalized = <String>[];
  final seen = <String>{};
  for (final item in rawTargets) {
    final normalizedTarget = item.trim().toLowerCase();
    if (normalizedTarget != 'gateway' || !seen.add(normalizedTarget)) {
      continue;
    }
    normalized.add(normalizedTarget);
  }
  return List<String>.unmodifiable(normalized);
}
