// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'gateway_runtime.dart';
import 'runtime_models.dart';
import 'secure_config_store.dart';
import 'runtime_controllers_settings.dart';
import 'runtime_controllers_gateway.dart';
import 'runtime_controllers_entities.dart';

class DerivedTasksController extends ChangeNotifier {
  List<DerivedTaskItem> queueInternal = const <DerivedTaskItem>[];
  List<DerivedTaskItem> runningInternal = const <DerivedTaskItem>[];
  List<DerivedTaskItem> historyInternal = const <DerivedTaskItem>[];
  List<DerivedTaskItem> failedInternal = const <DerivedTaskItem>[];
  List<DerivedTaskItem> scheduledInternal = const <DerivedTaskItem>[];

  List<DerivedTaskItem> get queue => queueInternal;
  List<DerivedTaskItem> get running => runningInternal;
  List<DerivedTaskItem> get history => historyInternal;
  List<DerivedTaskItem> get failed => failedInternal;
  List<DerivedTaskItem> get scheduled => scheduledInternal;

  int get totalCount =>
      queueInternal.length +
      runningInternal.length +
      historyInternal.length +
      failedInternal.length;

  void recompute({
    required List<GatewaySessionSummary> sessions,
    required List<GatewayCronJobSummary> cronJobs,
    required String currentSessionKey,
    required bool hasPendingRun,
    required String activeAgentName,
  }) {
    final sorted = sessions.toList(growable: false)
      ..sort(
        (left, right) =>
            (right.updatedAtMs ?? 0).compareTo(left.updatedAtMs ?? 0),
      );
    final queue = <DerivedTaskItem>[];
    final running = <DerivedTaskItem>[];
    final history = <DerivedTaskItem>[];
    final failed = <DerivedTaskItem>[];
    for (final session in sorted) {
      final item = DerivedTaskItem(
        id: session.key,
        title: session.label,
        owner: activeAgentName,
        status: statusForSessionInternal(
          session: session,
          currentSessionKey: currentSessionKey,
          hasPendingRun: hasPendingRun,
        ),
        surface: session.surface ?? session.kind ?? 'Assistant',
        startedAtLabel: timeLabelInternal(session.updatedAtMs),
        durationLabel: durationLabelInternal(session.updatedAtMs),
        summary:
            session.lastMessagePreview ?? session.subject ?? 'Session activity',
        sessionKey: session.key,
      );
      switch (item.status) {
        case 'Running':
          running.add(item);
        case 'Failed':
          failed.add(item);
        case 'Queued':
          queue.add(item);
        default:
          history.add(item);
      }
    }
    queueInternal = queue;
    runningInternal = running;
    historyInternal = history;
    failedInternal = failed;
    scheduledInternal = cronJobs
        .map(
          (job) => DerivedTaskItem(
            id: job.id,
            title: job.name,
            owner: job.agentId?.trim().isNotEmpty == true
                ? job.agentId!
                : activeAgentName,
            status: job.enabled ? 'Scheduled' : 'Disabled',
            surface: 'Cron',
            startedAtLabel: timeLabelInternal(job.nextRunAtMs?.toDouble()),
            durationLabel: job.scheduleLabel,
            summary:
                job.description ??
                job.lastError ??
                job.lastStatus ??
                'Scheduled automation',
            sessionKey: 'cron:${job.id}',
          ),
        )
        .toList(growable: false);
    notifyListeners();
  }

  String statusForSessionInternal({
    required GatewaySessionSummary session,
    required String currentSessionKey,
    required bool hasPendingRun,
  }) {
    if (session.abortedLastRun == true) {
      return 'Failed';
    }
    if (hasPendingRun && matchesSessionKey(session.key, currentSessionKey)) {
      return 'Running';
    }
    if ((session.lastMessagePreview ?? '').isEmpty) {
      return 'Queued';
    }
    return 'Open';
  }

  String timeLabelInternal(double? timestampMs) {
    if (timestampMs == null) {
      return 'Unknown';
    }
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs.toInt());
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String durationLabelInternal(double? timestampMs) {
    if (timestampMs == null) {
      return 'n/a';
    }
    final delta = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestampMs.toInt()),
    );
    if (delta.inMinutes < 1) {
      return 'just now';
    }
    if (delta.inHours < 1) {
      return '${delta.inMinutes}m ago';
    }
    if (delta.inDays < 1) {
      return '${delta.inHours}h ago';
    }
    return '${delta.inDays}d ago';
  }
}

String normalizeMainSessionKey(String? value) {
  return value?.trim() ?? '';
}

String makeAgentSessionKey({required String agentId, required String baseKey}) {
  final trimmedAgent = agentId.trim();
  final trimmedBase = baseKey.trim();
  if (trimmedAgent.isEmpty) {
    return trimmedBase;
  }
  return 'agent:$trimmedAgent:$trimmedBase';
}

bool matchesSessionKey(String incoming, String current) {
  final left = incoming.trim().toLowerCase();
  final right = current.trim().toLowerCase();
  return left == right;
}

String encodePrettyJson(Object value) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(value);
}

String ephemeralIdInternal() =>
    DateTime.now().microsecondsSinceEpoch.toString();
