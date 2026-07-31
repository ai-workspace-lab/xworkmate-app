import 'package:flutter/foundation.dart';

import '../../i18n/app_language.dart';
import 'harness_delivery_target.dart';

/// A conversation plugin decides *how* the current conversation is processed.
/// It is deliberately separate from the publish connector, which decides
/// *where* the result goes — the two are chosen independently.
enum ConversationPluginId { harnessWorkflow }

extension ConversationPluginIdCopy on ConversationPluginId {
  String get label => switch (this) {
    ConversationPluginId.harnessWorkflow => appText(
      'Harness Workflow',
      'Harness Workflow',
    ),
  };
}

@immutable
class ConversationPluginSelection {
  const ConversationPluginSelection({this.pluginId, this.harnessTargetId = ''});

  /// null means "run no plugin" — the conversation is used as-is.
  final ConversationPluginId? pluginId;

  /// Required when [pluginId] is [ConversationPluginId.harnessWorkflow].
  final String harnessTargetId;

  static const ConversationPluginSelection none = ConversationPluginSelection();

  bool get runsPlugin => pluginId != null;

  /// Why this selection cannot run yet, resolved against the user's configured
  /// targets. Empty means it is ready.
  List<String> validationIssues(List<HarnessTarget> availableTargets) {
    if (pluginId == null) return const <String>[];
    final target = resolveHarnessTarget(availableTargets);
    if (target == null) {
      return <String>[
        appText('请选择一个 Harness 交付目标。', 'Select a Harness delivery target.'),
      ];
    }
    return target.validationIssues();
  }

  HarnessTarget? resolveHarnessTarget(List<HarnessTarget> availableTargets) {
    if (pluginId != ConversationPluginId.harnessWorkflow) return null;
    final wanted = harnessTargetId.trim();
    if (wanted.isEmpty) return null;
    for (final target in availableTargets) {
      if (target.id == wanted) return target;
    }
    return null;
  }

  ConversationPluginSelection copyWith({
    ConversationPluginId? pluginId,
    bool clearPluginId = false,
    String? harnessTargetId,
  }) {
    return ConversationPluginSelection(
      pluginId: clearPluginId ? null : (pluginId ?? this.pluginId),
      harnessTargetId: harnessTargetId ?? this.harnessTargetId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ConversationPluginSelection &&
      other.pluginId == pluginId &&
      other.harnessTargetId == harnessTargetId;

  @override
  int get hashCode => Object.hash(pluginId, harnessTargetId);
}
