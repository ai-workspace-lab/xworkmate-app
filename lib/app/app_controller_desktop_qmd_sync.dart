import 'dart:async';
import 'package:flutter/foundation.dart';
import '../runtime/agent_context_client.dart';
import '../runtime/runtime_models.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_runtime_helpers.dart';
import 'app_controller_desktop_thread_sessions.dart';

extension AppControllerDesktopQmdSync on AppController {
  bool isQmdRemoteSessionKeyInternal(String sessionKey) {
    final normalized = normalizedAssistantSessionKeyInternal(sessionKey).toLowerCase();
    return normalized.startsWith('qmd:pin:') || normalized.startsWith('qmd:thread:');
  }

  Future<AgentContextClient?> resolveAgentContextClientInternal() async {
    if (agentContextClientOverride != null) {
      return agentContextClientOverride;
    }
    final endpoint = resolveBridgeAcpEndpointInternal();
    if (endpoint == null) {
      return null;
    }
    final token = await resolveBridgeArtifactAuthorizationHeaderInternal(endpoint);
    return HttpAgentContextClient(
      bridgeBase: endpoint,
      authToken: token ?? '',
    );
  }

  String formatQmdSourceTagInternal(String? rawSource) {
    final s = (rawSource ?? '').trim().toLowerCase();
    return switch (s) {
      'codex' => '[Codex]',
      'claude' => '[Claude]',
      'opencode' => '[OpenCode]',
      'pi' => '[Pi]',
      'dsh' => '[DSH]',
      'dsbot' => '[DSBot]',
      'qmd' => '[QMD]',
      '' => '[QMD]',
      _ => '[${rawSource!.trim()}]',
    };
  }

  String inferThreadSourceTagInternal(QmdContextThread thread) {
    final scopeLower = thread.scope.toLowerCase();
    final titleLower = thread.title.toLowerCase();
    if (scopeLower.contains('claude') || titleLower.contains('claude')) {
      return '[Claude]';
    }
    if (scopeLower.contains('codex') || titleLower.contains('codex')) {
      return '[Codex]';
    }
    if (scopeLower.contains('opencode') || titleLower.contains('opencode')) {
      return '[OpenCode]';
    }
    if (scopeLower.contains('pi') || titleLower.contains('pi')) {
      return '[Pi]';
    }
    return '[QMD]';
  }

  Future<void> refreshQmdRemoteTasksInternal() async {
    try {
      final client = await resolveAgentContextClientInternal();
      if (client == null) {
        return;
      }
      final catalog = await client.fetchCatalog(limit: 50);
      final threadPage = await client.listThreads(limit: 50);

      final nextRecords = <String, TaskThread>{};
      final nextSummaries = <String, GatewaySessionSummary>{};

      // 1. Process Pinned Tasks from QMD Catalog
      for (final pin in catalog.pinnedTasks) {
        final sessionKey = 'qmd:pin:${pin.id}';
        final tag = formatQmdSourceTagInternal(pin.source);
        final title = pin.title.startsWith('[') ? pin.title : '$tag ${pin.title}';
        final scopeStr = pin.scope ?? pin.id;
        final preview = pin.projectName != null && pin.projectName!.isNotEmpty
            ? '[QMD 钉选] ${pin.projectName} ($scopeStr)'
            : '[QMD 钉选] $scopeStr';
        final updatedMs = pin.updatedAt?.millisecondsSinceEpoch.toDouble() ??
            DateTime.now().millisecondsSinceEpoch.toDouble();

        final thread = TaskThread(
          threadId: sessionKey,
          createdAtMs: updatedMs,
          title: title,
          ownerScope: const ThreadOwnerScope(
            realm: ThreadRealm.local,
            subjectType: ThreadSubjectType.user,
            subjectId: 'qmd',
            displayName: 'QMD',
          ),
          workspaceBinding: WorkspaceBinding(
            workspaceId: 'qmd',
            workspaceKind: WorkspaceKind.remoteFs,
            workspacePath: pin.scope ?? 'qmd',
            displayPath: pin.scope ?? 'qmd',
            writable: false,
          ),
          executionBinding: const ExecutionBinding(
            executionMode: ThreadExecutionMode.gateway,
            executorId: 'qmd',
            providerId: 'qmd',
            endpointId: 'qmd',
          ),
          contextState: const ThreadContextState(
            messages: <GatewayChatMessage>[],
            selectedModelId: '',
            selectedSkillKeys: <String>[],
            permissionLevel: AssistantPermissionLevel.defaultAccess,
            messageViewMode: AssistantMessageViewMode.rendered,
            latestResolvedRuntimeModel: '',
            latestResolvedProviderId: 'qmd',
          ),
          lifecycleState: const ThreadLifecycleState(
            archived: false,
            status: 'pinned',
            lastRunAtMs: null,
            lastResultCode: null,
          ),
          updatedAtMs: updatedMs,
        );

        final summary = GatewaySessionSummary(
          key: sessionKey,
          kind: 'assistant',
          displayName: title,
          surface: 'Assistant',
          subject: preview,
          room: null,
          space: null,
          updatedAtMs: updatedMs,
          sessionId: sessionKey,
          systemSent: false,
          abortedLastRun: false,
          thinkingLevel: null,
          verboseLevel: null,
          inputTokens: null,
          outputTokens: null,
          totalTokens: null,
          model: 'qmd',
          contextTokens: null,
          derivedTitle: title,
          lastMessagePreview: preview,
        );

        nextRecords[sessionKey] = thread;
        nextSummaries[sessionKey] = summary;
      }

      // 2. Process Recent / Listed Threads
      final combinedThreads = <String, QmdContextThread>{};
      for (final t in catalog.recentThreads) {
        combinedThreads[t.id] = t;
      }
      for (final t in threadPage.threads) {
        combinedThreads[t.id] = t;
      }

      for (final t in combinedThreads.values) {
        final sessionKey = 'qmd:thread:${t.id}';
        final tag = inferThreadSourceTagInternal(t);
        final title = t.title.startsWith('[') ? t.title : '$tag ${t.title}';
        final prLabel = t.prNumber != null ? '#${t.prNumber} ' : '';
        final scopeLabel = t.scope.isNotEmpty ? t.scope : t.id;
        final preview = '[QMD 任务] $prLabel$scopeLabel';
        final updatedMs = t.updatedAt?.millisecondsSinceEpoch.toDouble() ??
            DateTime.now().millisecondsSinceEpoch.toDouble();
        final isClosed = t.state.toLowerCase() == 'closed';

        final thread = TaskThread(
          threadId: sessionKey,
          createdAtMs: updatedMs,
          title: title,
          ownerScope: const ThreadOwnerScope(
            realm: ThreadRealm.local,
            subjectType: ThreadSubjectType.user,
            subjectId: 'qmd',
            displayName: 'QMD',
          ),
          workspaceBinding: WorkspaceBinding(
            workspaceId: 'qmd',
            workspaceKind: WorkspaceKind.remoteFs,
            workspacePath: t.scope,
            displayPath: t.scope,
            writable: false,
          ),
          executionBinding: const ExecutionBinding(
            executionMode: ThreadExecutionMode.gateway,
            executorId: 'qmd',
            providerId: 'qmd',
            endpointId: 'qmd',
          ),
          contextState: const ThreadContextState(
            messages: <GatewayChatMessage>[],
            selectedModelId: '',
            selectedSkillKeys: <String>[],
            permissionLevel: AssistantPermissionLevel.defaultAccess,
            messageViewMode: AssistantMessageViewMode.rendered,
            latestResolvedRuntimeModel: '',
            latestResolvedProviderId: 'qmd',
          ),
          lifecycleState: ThreadLifecycleState(
            archived: isClosed,
            status: isClosed ? 'completed' : 'active',
            lastRunAtMs: null,
            lastResultCode: null,
          ),
          updatedAtMs: updatedMs,
        );

        final summary = GatewaySessionSummary(
          key: sessionKey,
          kind: 'assistant',
          displayName: title,
          surface: 'Assistant',
          subject: preview,
          room: null,
          space: null,
          updatedAtMs: updatedMs,
          sessionId: sessionKey,
          systemSent: false,
          abortedLastRun: false,
          thinkingLevel: null,
          verboseLevel: null,
          inputTokens: null,
          outputTokens: null,
          totalTokens: null,
          model: 'qmd',
          contextTokens: null,
          derivedTitle: title,
          lastMessagePreview: preview,
        );

        nextRecords[sessionKey] = thread;
        nextSummaries[sessionKey] = summary;
      }

      qmdRemoteThreadRecordsInternal
        ..clear()
        ..addAll(nextRecords);
      qmdRemoteSessionSummariesInternal
        ..clear()
        ..addAll(nextSummaries);

      recomputeTasksInternal();
    } catch (e, stack) {
      debugPrint('[QMD Sync] refreshQmdRemoteTasksInternal error: $e\n$stack');
    }
  }

  Future<void> loadQmdThreadBriefingForSessionInternal(String sessionKey) async {
    final normalized = normalizedAssistantSessionKeyInternal(sessionKey);
    if (!isQmdRemoteSessionKeyInternal(normalized)) {
      return;
    }

    try {
      final client = await resolveAgentContextClientInternal();
      if (client == null) {
        return;
      }

      if (normalized.startsWith('qmd:thread:')) {
        final threadId = normalized.substring('qmd:thread:'.length);
        final briefing = await client.fetchBriefing(threadId);
        final markdown = _renderBriefingMarkdown(briefing);

        final message = GatewayChatMessage(
          id: 'qmd-briefing-$threadId',
          role: 'assistant',
          text: markdown,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: 'stop',
          pending: false,
          error: false,
        );
        localSessionMessagesInternal[normalized] = <GatewayChatMessage>[message];
      } else if (normalized.startsWith('qmd:pin:')) {
        final pinId = normalized.substring('qmd:pin:'.length);
        final record = qmdRemoteThreadRecordsInternal[normalized];
        final summary = qmdRemoteSessionSummariesInternal[normalized];
        final title = record?.title ?? summary?.displayName ?? pinId;
        final preview = summary?.lastMessagePreview ?? '';

        final markdown = '''
# 📌 钉选任务: $title

- **任务 ID**: `$pinId`
- **状态**: `${record?.lifecycleState.status ?? 'active'}`
- **说明**: $preview

> 此任务为 QMD 远程聚合钉选任务，当前为只读同步模式。
'''.trim();

        final message = GatewayChatMessage(
          id: 'qmd-pin-$pinId',
          role: 'assistant',
          text: markdown,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: 'stop',
          pending: false,
          error: false,
        );
        localSessionMessagesInternal[normalized] = <GatewayChatMessage>[message];
      }
    } catch (e) {
      debugPrint('[QMD Sync] Failed to load briefing for $sessionKey: $e');
    }
  }

  String _renderBriefingMarkdown(QmdThreadBriefing briefing) {
    final t = briefing.thread;
    final buffer = StringBuffer();
    buffer.writeln('# 📋 任务简报: ${t.title}');
    buffer.writeln();
    buffer.writeln('- **状态**: `${t.state}`');
    if (t.scope.isNotEmpty) buffer.writeln('- **范围 (Scope)**: `${t.scope}`');
    if (t.headBranch != null && t.headBranch!.isNotEmpty) {
      buffer.writeln('- **分支**: `${t.headBranch}`');
    }
    if (t.prNumber != null) {
      buffer.writeln('- **PR**: #${t.prNumber} (${t.prState ?? 'open'})');
    }
    buffer.writeln();

    if (briefing.contributors.isNotEmpty) {
      buffer.writeln('### 👥 协同者');
      for (final c in briefing.contributors) {
        final timeStr = c.lastSeenAt?.toLocal().toIso8601String() ?? '未知';
        buffer.writeln('- **${c.source}**: ${c.sessions} 会话 (最近活跃: $timeStr)');
      }
      buffer.writeln();
    }

    if (briefing.items.isNotEmpty) {
      buffer.writeln('### 📝 进展与事项');
      for (final item in briefing.items) {
        final kindIcon = switch (item.kind) {
          'decision' => '⚖️',
          'todo' => '☑️',
          'fact' => '💡',
          _ => '•',
        };
        final sourcesStr = item.sources.isNotEmpty ? ' *(${item.sources.join(', ')})*' : '';
        buffer.writeln('$kindIcon **[${item.status}]** ${item.text}$sourcesStr');
        if (item.detail != null && item.detail!.isNotEmpty) {
          buffer.writeln('  > ${item.detail}');
        }
      }
      buffer.writeln();
    }

    buffer.writeln('> ℹ️ 当前会话为 QMD 远程同步任务（只读模式），通过 Bridge 实时对账。');
    return buffer.toString().trim();
  }
}
