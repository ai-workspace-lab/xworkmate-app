// ignore_for_file: unused_import, unnecessary_import

import 'dart:convert';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import 'runtime_models_profiles.dart';
import 'runtime_models_configs.dart';
import 'runtime_models_settings_snapshot.dart';
import 'runtime_models_runtime_payloads.dart';
import 'runtime_models_gateway_entities.dart';
import 'runtime_models_multi_agent.dart';

enum RuntimeConnectionMode { unconfigured, local, remote }

extension RuntimeConnectionModeCopy on RuntimeConnectionMode {
  String get label => switch (this) {
    RuntimeConnectionMode.unconfigured => appText('未配置', 'Unconfigured'),
    RuntimeConnectionMode.local => appText('本地', 'Local'),
    RuntimeConnectionMode.remote => appText('远程', 'Remote'),
  };

  static RuntimeConnectionMode fromJsonValue(String? value) {
    return RuntimeConnectionMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => RuntimeConnectionMode.unconfigured,
    );
  }
}

enum RuntimeConnectionStatus { offline, connecting, connected, error }

extension RuntimeConnectionStatusCopy on RuntimeConnectionStatus {
  String get label => switch (this) {
    RuntimeConnectionStatus.offline => appText('离线', 'Offline'),
    RuntimeConnectionStatus.connecting => appText('连接中', 'Connecting'),
    RuntimeConnectionStatus.connected => appText('已连接', 'Connected'),
    RuntimeConnectionStatus.error => appText('错误', 'Error'),
  };
}

bool isLegacyAutoAssistantExecutionTargetValue(String? value) {
  return value?.trim().toLowerCase() == 'auto';
}

enum AssistantExecutionTarget { gateway }

extension AssistantExecutionTargetCopy on AssistantExecutionTarget {
  String get label => switch (this) {
    AssistantExecutionTarget.gateway => appText('Gateway', 'Gateway'),
  };

  String get promptValue => switch (this) {
    AssistantExecutionTarget.gateway => 'gateway',
  };

  bool get isGateway => this == AssistantExecutionTarget.gateway;

  String get compactLabel => switch (this) {
    AssistantExecutionTarget.gateway => appText('Gateway', 'Gateway'),
  };

  static AssistantExecutionTarget fromJsonValue(String? value) {
    return AssistantExecutionTarget.gateway;
  }
}

List<AssistantExecutionTarget> compactAssistantExecutionTargets(
  Iterable<AssistantExecutionTarget> targets,
) {
  if (targets.contains(AssistantExecutionTarget.gateway)) {
    return const <AssistantExecutionTarget>[AssistantExecutionTarget.gateway];
  }
  return const <AssistantExecutionTarget>[AssistantExecutionTarget.gateway];
}

AssistantExecutionTarget collapseAssistantExecutionTargetForDisplay(
  AssistantExecutionTarget target,
) => target;

AssistantExecutionTarget resolveGatewayExecutionTargetFromVisibleTargets(
  Iterable<AssistantExecutionTarget> visibleTargets, {
  AssistantExecutionTarget? currentTarget,
}) {
  final visible = visibleTargets.toList(growable: false);
  if (currentTarget != null && currentTarget.isGateway) {
    if (visible.contains(AssistantExecutionTarget.gateway)) {
      return AssistantExecutionTarget.gateway;
    }
  }
  if (visible.contains(AssistantExecutionTarget.gateway)) {
    return AssistantExecutionTarget.gateway;
  }
  return AssistantExecutionTarget.gateway;
}

String normalizeSingleAgentProviderId(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return '';
  }
  final normalizedWhitespace = trimmed.replaceAll(RegExp(r'\s+'), '-');
  final buffer = StringBuffer();
  var previousWasSeparator = false;
  var hasOutput = false;
  for (final rune in normalizedWhitespace.runes) {
    final char = String.fromCharCode(rune);
    final isAlphaNumeric =
        (rune >= 97 && rune <= 122) || (rune >= 48 && rune <= 57);
    final isSeparator = char == '-' || char == '_' || char == '.';
    if (isAlphaNumeric) {
      buffer.write(char);
      previousWasSeparator = false;
      hasOutput = true;
      continue;
    }
    if (isSeparator && !previousWasSeparator && hasOutput) {
      buffer.write('-');
      previousWasSeparator = true;
    }
  }
  return buffer.toString().replaceAll(RegExp(r'^[-_.]+|[-_.]+$'), '');
}

String singleAgentProviderFallbackLabelInternal(String providerId) {
  final normalized = normalizeSingleAgentProviderId(providerId);
  if (normalized.isEmpty) {
    return appText('Bridge Provider', 'Bridge Provider');
  }
  return normalized
      .split(RegExp(r'[-_.]+'))
      .where((item) => item.isNotEmpty)
      .map((item) => '${item[0].toUpperCase()}${item.substring(1)}')
      .join(' ');
}

String singleAgentProviderFallbackBadgeInternal({
  required String providerId,
  required String label,
}) {
  final normalized = normalizeSingleAgentProviderId(providerId);
  final known = <String, String>{
    'codex': 'C',
    'opencode': 'O',
    'claude': 'Cl',
    'gemini': 'G',
  };
  final explicit = known[normalized];
  if (explicit != null) {
    return explicit;
  }
  final stripped = label.replaceAll(RegExp(r'\s+'), '');
  if (stripped.isEmpty) {
    return '?';
  }
  final length = stripped.length >= 2 ? 2 : 1;
  return stripped.substring(0, length).toUpperCase();
}

const Set<String> kSupportedExternalAcpEndpointSchemes = <String>{
  'ws',
  'wss',
  'http',
  'https',
};

bool isSupportedExternalAcpEndpoint(String endpoint) {
  final trimmed = endpoint.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(trimmed);
  final scheme = uri?.scheme.trim().toLowerCase() ?? '';
  return kSupportedExternalAcpEndpointSchemes.contains(scheme);
}

class SingleAgentProvider {
  const SingleAgentProvider({
    required this.providerId,
    required this.label,
    required this.badge,
    this.source = SingleAgentProviderSource.externalExtension,
  });

  static const SingleAgentProvider unspecified = SingleAgentProvider(
    providerId: '',
    label: '',
    badge: '',
  );

  static const SingleAgentProvider codex = SingleAgentProvider(
    providerId: 'codex',
    label: 'Codex',
    badge: 'C',
  );

  static const SingleAgentProvider opencode = SingleAgentProvider(
    providerId: 'opencode',
    label: 'OpenCode',
    badge: 'O',
  );

  static const SingleAgentProvider claude = SingleAgentProvider(
    providerId: 'claude',
    label: 'Claude',
    badge: 'Cl',
  );

  static const SingleAgentProvider gemini = SingleAgentProvider(
    providerId: 'gemini',
    label: 'Gemini',
    badge: 'G',
  );

  final String providerId;
  final String label;
  final String badge;
  final SingleAgentProviderSource source;

  bool get isUnspecified => providerId.trim().isEmpty;
  bool get isExternalExtension =>
      source == SingleAgentProviderSource.externalExtension;

  SingleAgentProvider copyWith({
    String? providerId,
    String? label,
    String? badge,
    SingleAgentProviderSource? source,
  }) {
    final resolvedProviderId = normalizeSingleAgentProviderId(
      providerId ?? this.providerId,
    );
    final resolvedLabel = (label ?? this.label).trim();
    final resolvedBadge = (badge ?? this.badge).trim();
    return SingleAgentProvider(
      providerId: resolvedProviderId,
      label: resolvedLabel.isEmpty
          ? singleAgentProviderFallbackLabelInternal(resolvedProviderId)
          : resolvedLabel,
      badge: resolvedBadge.isEmpty
          ? singleAgentProviderFallbackBadgeInternal(
              providerId: resolvedProviderId,
              label: resolvedLabel,
            )
          : resolvedBadge,
      source: source ?? this.source,
    );
  }

  static SingleAgentProvider fromJsonValue(
    String? value, {
    String? label,
    String? badge,
  }) {
    final normalized = normalizeSingleAgentProviderId(value ?? '');
    final base = switch (normalized) {
      'codex' => codex,
      'opencode' => opencode,
      'claude' => claude,
      'gemini' => gemini,
      'auto' || '' => unspecified,
      _ => SingleAgentProvider(
        providerId: normalized,
        label: singleAgentProviderFallbackLabelInternal(normalized),
        badge: singleAgentProviderFallbackBadgeInternal(
          providerId: normalized,
          label: singleAgentProviderFallbackLabelInternal(normalized),
        ),
      ),
    };
    return base.copyWith(label: label, badge: badge);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SingleAgentProvider && other.providerId == providerId);

  @override
  int get hashCode => providerId.hashCode;
}

extension SingleAgentProviderCopy on SingleAgentProvider {
  static SingleAgentProvider fromJsonValue(
    String? value, {
    String? label,
    String? badge,
  }) => SingleAgentProvider.fromJsonValue(value, label: label, badge: badge);
}

enum SingleAgentProviderSource { externalExtension }

List<SingleAgentProvider> normalizeSingleAgentProviderList(
  Iterable<SingleAgentProvider> providers,
) {
  final normalized = <SingleAgentProvider>[];
  final seen = <String>{};
  for (final provider in providers) {
    if (seen.add(provider.providerId)) {
      normalized.add(provider);
    }
  }
  return normalized;
}

const List<SingleAgentProvider> kPresetExternalAcpProviders =
    <SingleAgentProvider>[
      SingleAgentProvider.codex,
      SingleAgentProvider.opencode,
      SingleAgentProvider.gemini,
    ];

const String kCanonicalGatewayProviderId = 'openclaw';
const String kCanonicalGatewayProviderLabel = 'OpenClaw';

const List<SingleAgentProvider> kBridgeOwnedSingleAgentProviders =
    <SingleAgentProvider>[
      SingleAgentProvider.codex,
      SingleAgentProvider.opencode,
      SingleAgentProvider.gemini,
    ];

bool isBridgeOwnedSingleAgentProviderId(String providerId) {
  final normalized = normalizeSingleAgentProviderId(providerId);
  return kBridgeOwnedSingleAgentProviders.any(
    (item) => item.providerId == normalized,
  );
}

List<SingleAgentProvider> normalizeBridgeOwnedSingleAgentProviderList(
  Iterable<SingleAgentProvider> providers,
) {
  return normalizeSingleAgentProviderList(
    providers.where(
      (provider) => isBridgeOwnedSingleAgentProviderId(provider.providerId),
    ),
  );
}
