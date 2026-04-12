import 'dart:convert';

import '../models/app_models.dart';
import 'runtime_models_connection.dart';

const int appUiStateSchemaVersion = 2;

class AppUiState {
  const AppUiState({
    required this.schemaVersion,
    required this.assistantLastSessionKey,
    required this.assistantNavigationDestinations,
    required this.savedGatewayTargets,
  });

  final int schemaVersion;
  final String assistantLastSessionKey;
  final List<AssistantFocusEntry> assistantNavigationDestinations;
  final List<String> savedGatewayTargets;

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
    } catch (_) {
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
    if (normalizedTarget != 'gateway' ||
        !seen.add(normalizedTarget)) {
      continue;
    }
    normalized.add(normalizedTarget);
  }
  return List<String>.unmodifiable(normalized);
}
