import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/plugins/harness_delivery_target.dart';
import 'package:xworkmate/i18n/app_language.dart';

HarnessTarget _sampleTarget() {
  return const HarnessTarget(
    id: 'target-1',
    org: 'ai-workspace-lab',
    project: 'platform-ops',
    repos: <HarnessRepoBinding>[
      HarnessRepoBinding(
        name: 'ai-workspace-infra/gitops',
        checkoutPath: '/srv/repos/gitops',
        role: HarnessRepoRole.gitops,
        order: 20,
      ),
      HarnessRepoBinding(
        name: 'ai-workspace-infra/platform-ops-toolkit',
        checkoutPath: '/srv/repos/platform-ops-toolkit',
        role: HarnessRepoRole.infra,
        order: 0,
      ),
      HarnessRepoBinding(
        name: 'ai-workspace-lab/xworkmate-app',
        checkoutPath: '/srv/repos/xworkmate-app',
        role: HarnessRepoRole.app,
        order: 10,
      ),
    ],
    environments: <HarnessEnvironment>[
      HarnessEnvironment(
        name: 'sit',
        trigger: HarnessTriggerKind.pullRequest,
        deploy: HarnessDeployKind.ghWorkflowDispatch,
      ),
      HarnessEnvironment(
        name: 'uat',
        trigger: HarnessTriggerKind.mainPush,
        deploy: HarnessDeployKind.ansible,
        healthProbe: 'https://console-uat.onwalk.net/healthz',
      ),
      HarnessEnvironment(
        name: 'prod',
        trigger: HarnessTriggerKind.tag,
        deploy: HarnessDeployKind.docoCdWebhook,
      ),
    ],
  );
}

void main() {
  setUp(() => setActiveAppLanguage(AppLanguage.zh));

  group('HarnessRepoBinding', () {
    test('JSON roundtrip preserves every field', () {
      const repo = HarnessRepoBinding(
        name: 'ai-workspace-infra/platform-ops-toolkit',
        checkoutPath: '/srv/repos/platform-ops-toolkit',
        url: 'https://github.com/ai-workspace-lab/platform-ops-toolkit',
        role: HarnessRepoRole.infra,
        defaultBranch: 'main',
        order: 0,
      );
      final restored = HarnessRepoBinding.fromJson(repo.toJson());
      expect(restored, repo);
    });

    test('isValid requires both name and checkoutPath', () {
      expect(
        const HarnessRepoBinding(name: '', checkoutPath: '/x').isValid,
        isFalse,
      );
      expect(
        const HarnessRepoBinding(name: 'x', checkoutPath: '').isValid,
        isFalse,
      );
      expect(
        const HarnessRepoBinding(name: 'x', checkoutPath: '/x').isValid,
        isTrue,
      );
    });

    test('fromJson tolerates unknown role and missing fields', () {
      final restored = HarnessRepoBinding.fromJson(const <String, dynamic>{
        'name': 'x',
        'checkoutPath': '/x',
        'role': 'not-a-real-role',
      });
      expect(restored.role, HarnessRepoRole.service);
      expect(restored.defaultBranch, 'main');
      expect(restored.order, 0);
    });
  });

  group('HarnessEnvironment', () {
    test('JSON roundtrip preserves every field', () {
      const environment = HarnessEnvironment(
        name: 'uat',
        trigger: HarnessTriggerKind.mainPush,
        deploy: HarnessDeployKind.ansible,
        healthProbe: 'https://example.test/healthz',
        requiresHumanGate: true,
      );
      final restored = HarnessEnvironment.fromJson(environment.toJson());
      expect(restored, environment);
    });

    test('tag-triggered environments require a human gate even when unset',
        () {
      const environment = HarnessEnvironment(
        name: 'prod',
        trigger: HarnessTriggerKind.tag,
        deploy: HarnessDeployKind.docoCdWebhook,
      );
      expect(environment.requiresHumanGate, isFalse);
      expect(environment.effectiveRequiresHumanGate, isTrue);
    });

    test('non-tag environments respect the explicit flag', () {
      const gated = HarnessEnvironment(
        name: 'uat',
        trigger: HarnessTriggerKind.mainPush,
        deploy: HarnessDeployKind.ansible,
        requiresHumanGate: true,
      );
      const ungated = HarnessEnvironment(
        name: 'sit',
        trigger: HarnessTriggerKind.pullRequest,
        deploy: HarnessDeployKind.ghWorkflowDispatch,
      );
      expect(gated.effectiveRequiresHumanGate, isTrue);
      expect(ungated.effectiveRequiresHumanGate, isFalse);
    });
  });

  group('HarnessTarget', () {
    test('JSON roundtrip preserves repos and environments', () {
      final target = _sampleTarget();
      final restored = HarnessTarget.fromJson(target.toJson());
      expect(restored, target);
    });

    test('reposInExecutionOrder sorts ascending by order', () {
      final target = _sampleTarget();
      expect(
        target.reposInExecutionOrder.map((repo) => repo.name).toList(),
        <String>[
          'ai-workspace-infra/platform-ops-toolkit',
          'ai-workspace-lab/xworkmate-app',
          'ai-workspace-infra/gitops',
        ],
      );
    });

    test('reposInRollbackOrder is the exact reverse of execution order', () {
      final target = _sampleTarget();
      expect(
        target.reposInRollbackOrder,
        target.reposInExecutionOrder.reversed.toList(),
      );
    });

    test('environmentByName and environmentForTrigger resolve correctly', () {
      final target = _sampleTarget();
      expect(target.environmentByName('uat')?.deploy, HarnessDeployKind.ansible);
      expect(target.environmentByName('missing'), isNull);
      expect(
        target.environmentForTrigger(HarnessTriggerKind.tag)?.name,
        'prod',
      );
    });

    test('a fully configured target has no validation issues', () {
      expect(_sampleTarget().validationIssues(), isEmpty);
      expect(_sampleTarget().isValid, isTrue);
    });

    test('bind-step validation flags every problem at once', () {
      const target = HarnessTarget(id: 't', org: '', project: '');
      final issues = target.validationIssues();
      expect(issues, isNotEmpty);
      expect(target.isValid, isFalse);
      // org empty, project empty, no repos, no environments — at least 4.
      expect(issues.length, greaterThanOrEqualTo(4));
    });

    test('validation flags an invalid repo and duplicate repo names', () {
      const target = HarnessTarget(
        id: 't',
        org: 'org',
        project: 'proj',
        repos: <HarnessRepoBinding>[
          HarnessRepoBinding(name: 'a', checkoutPath: '/a'),
          HarnessRepoBinding(name: 'a', checkoutPath: '/a-again'),
          HarnessRepoBinding(name: '', checkoutPath: ''),
        ],
        environments: <HarnessEnvironment>[
          HarnessEnvironment(
            name: 'sit',
            trigger: HarnessTriggerKind.pullRequest,
            deploy: HarnessDeployKind.ghWorkflowDispatch,
          ),
        ],
      );
      final issues = target.validationIssues();
      expect(issues, isNotEmpty);
      expect(target.isValid, isFalse);
    });

    test('validation flags duplicate environment names', () {
      const target = HarnessTarget(
        id: 't',
        org: 'org',
        project: 'proj',
        repos: <HarnessRepoBinding>[
          HarnessRepoBinding(name: 'a', checkoutPath: '/a'),
        ],
        environments: <HarnessEnvironment>[
          HarnessEnvironment(
            name: 'sit',
            trigger: HarnessTriggerKind.pullRequest,
            deploy: HarnessDeployKind.ghWorkflowDispatch,
          ),
          HarnessEnvironment(
            name: 'sit',
            trigger: HarnessTriggerKind.mainPush,
            deploy: HarnessDeployKind.ansible,
          ),
        ],
      );
      expect(target.isValid, isFalse);
    });
  });

  group('normalizeHarnessTargets', () {
    test('drops blank ids and de-duplicates by id, keeping the last', () {
      const first = HarnessTarget(id: 'a', org: 'o1', project: 'p1');
      const blank = HarnessTarget(id: '', org: 'o2', project: 'p2');
      const dup = HarnessTarget(id: 'a', org: 'o3', project: 'p3');
      final normalized = normalizeHarnessTargets(
        targets: <HarnessTarget>[first, blank, dup],
      );
      expect(normalized, hasLength(1));
      expect(normalized.single.org, 'o3');
    });

    test('preserves order among distinct ids', () {
      const a = HarnessTarget(id: 'a', org: 'o', project: 'p');
      const b = HarnessTarget(id: 'b', org: 'o', project: 'p');
      final normalized = normalizeHarnessTargets(targets: <HarnessTarget>[b, a]);
      expect(normalized.map((t) => t.id).toList(), <String>['b', 'a']);
    });
  });

  group('renderHarnessDeliveryContextBlock', () {
    test('zh rendering names the header, repos in order, and environments',
        () {
      setActiveAppLanguage(AppLanguage.zh);
      final block = renderHarnessDeliveryContextBlock(_sampleTarget());
      expect(block, contains('Harness delivery context:'));
      expect(block, contains('ai-workspace-lab'));
      expect(block, contains('platform-ops'));
      final infraIndex = block.indexOf('platform-ops-toolkit');
      final appIndex = block.indexOf('xworkmate-app');
      final gitopsIndex = block.indexOf('gitops');
      expect(infraIndex, lessThan(appIndex));
      expect(appIndex, lessThan(gitopsIndex));
      expect(block, contains('prod'));
      expect(block, contains('需人工确认'));
    });

    test('en rendering uses English labels and still orders repos', () {
      setActiveAppLanguage(AppLanguage.en);
      final block = renderHarnessDeliveryContextBlock(_sampleTarget());
      expect(block, contains('Harness delivery context:'));
      expect(block, contains('requires human approval'));
      final infraIndex = block.indexOf('platform-ops-toolkit');
      final appIndex = block.indexOf('xworkmate-app');
      final gitopsIndex = block.indexOf('gitops');
      expect(infraIndex, lessThan(appIndex));
      expect(appIndex, lessThan(gitopsIndex));
    });
  });
}
