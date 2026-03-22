@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'DerivedTasksController maps sessions and cron jobs into task buckets',
    () {
      final controller = DerivedTasksController();

      controller.recompute(
        sessions: <GatewaySessionSummary>[
          GatewaySessionSummary(
            key: 'main',
            kind: 'chat',
            displayName: 'Main Session',
            surface: 'Assistant',
            subject: 'Implement feature',
            room: null,
            space: null,
            updatedAtMs: 2000,
            sessionId: 's1',
            systemSent: false,
            abortedLastRun: false,
            thinkingLevel: 'high',
            verboseLevel: 'normal',
            inputTokens: 10,
            outputTokens: 20,
            totalTokens: 30,
            model: 'gpt-5',
            contextTokens: 100,
            derivedTitle: 'Implement feature',
            lastMessagePreview: 'Working on it',
          ),
          GatewaySessionSummary(
            key: 'failed',
            kind: 'chat',
            displayName: 'Failed Session',
            surface: 'Assistant',
            subject: 'Broken flow',
            room: null,
            space: null,
            updatedAtMs: 1000,
            sessionId: 's2',
            systemSent: false,
            abortedLastRun: true,
            thinkingLevel: 'high',
            verboseLevel: 'normal',
            inputTokens: 10,
            outputTokens: 20,
            totalTokens: 30,
            model: 'gpt-5',
            contextTokens: 100,
            derivedTitle: 'Broken flow',
            lastMessagePreview: 'aborted',
          ),
        ],
        cronJobs: const <GatewayCronJobSummary>[
          GatewayCronJobSummary(
            id: 'cron-1',
            name: 'Morning Digest',
            description: 'Daily summary',
            enabled: true,
            agentId: 'research',
            scheduleLabel: '0 8 * * *',
            nextRunAtMs: 3000,
            lastRunAtMs: 1500,
            lastStatus: 'ok',
            lastError: null,
          ),
        ],
        currentSessionKey: 'main',
        hasPendingRun: true,
        activeAgentName: 'Coding Agent',
      );

      expect(controller.running, hasLength(1));
      expect(controller.running.first.title, 'Implement feature');
      expect(controller.failed, hasLength(1));
      expect(controller.failed.first.title, 'Broken flow');
      expect(controller.scheduled, hasLength(1));
      expect(controller.scheduled.first.title, 'Morning Digest');
      expect(controller.scheduled.first.surface, 'Cron');
    },
  );
}
