import 'package:flutter/foundation.dart';

import '../../i18n/app_language.dart';

/// The role a bound repository plays inside a [HarnessTarget] (plan
/// docs/plans/2026-07-26-closed-loop-agent-harness-plugin.md §3). Determines
/// execution order via [HarnessRepoBinding.order] — infra changes typically
/// land before the app that depends on them, gitops after both.
enum HarnessRepoRole { infra, app, service, playbooks, gitops }

extension HarnessRepoRoleCopy on HarnessRepoRole {
  String get label => switch (this) {
    HarnessRepoRole.infra => appText('基础设施', 'Infrastructure'),
    HarnessRepoRole.app => appText('应用', 'App'),
    HarnessRepoRole.service => appText('服务', 'Service'),
    HarnessRepoRole.playbooks => appText('部署脚本', 'Playbooks'),
    HarnessRepoRole.gitops => appText('GitOps', 'GitOps'),
  };

  static HarnessRepoRole fromJsonValue(String? value) {
    return HarnessRepoRole.values.firstWhere(
      (item) => item.name == value,
      orElse: () => HarnessRepoRole.service,
    );
  }
}

/// Which git event authorizes a deploy to a [HarnessEnvironment] — the
/// environment routing rigidity the plan requires (§3, §4 step `deploy`):
/// a step targeting an environment must check the current branch/ref against
/// this before acting.
enum HarnessTriggerKind { pullRequest, mainPush, tag }

extension HarnessTriggerKindCopy on HarnessTriggerKind {
  String get label => switch (this) {
    HarnessTriggerKind.pullRequest => appText('PR', 'Pull request'),
    HarnessTriggerKind.mainPush => appText('主干推送', 'Main push'),
    HarnessTriggerKind.tag => appText('打 Tag', 'Tag'),
  };

  static HarnessTriggerKind fromJsonValue(String? value) {
    return HarnessTriggerKind.values.firstWhere(
      (item) => item.name == value,
      orElse: () => HarnessTriggerKind.pullRequest,
    );
  }
}

/// How a deploy to a [HarnessEnvironment] is actually carried out.
enum HarnessDeployKind { ghWorkflowDispatch, docoCdWebhook, ansible }

extension HarnessDeployKindCopy on HarnessDeployKind {
  String get label => switch (this) {
    HarnessDeployKind.ghWorkflowDispatch => appText(
      'GitHub Actions workflow_dispatch',
      'GitHub Actions workflow_dispatch',
    ),
    HarnessDeployKind.docoCdWebhook => appText(
      'Doco-CD webhook',
      'Doco-CD webhook',
    ),
    HarnessDeployKind.ansible => appText('Ansible playbook', 'Ansible playbook'),
  };

  static HarnessDeployKind fromJsonValue(String? value) {
    return HarnessDeployKind.values.firstWhere(
      (item) => item.name == value,
      orElse: () => HarnessDeployKind.ghWorkflowDispatch,
    );
  }
}

/// One repository the Harness plugin is allowed to act on, and where.
///
/// The app never holds credentials for this repo — [checkoutPath] is a path
/// on the gateway agent's host, not on this device (plan §1 non-goals).
@immutable
class HarnessRepoBinding {
  const HarnessRepoBinding({
    required this.name,
    required this.checkoutPath,
    this.url = '',
    this.role = HarnessRepoRole.service,
    this.defaultBranch = 'main',
    this.order = 0,
  });

  /// Repo identity, e.g. `ai-workspace-infra/platform-ops-toolkit`.
  final String name;

  /// Where this repo is checked out on the gateway agent's host.
  final String checkoutPath;

  final String url;
  final HarnessRepoRole role;
  final String defaultBranch;

  /// Execution order across repos in one [HarnessTarget] — `change`/`deploy`
  /// walk ascending, `rollback` walks descending (plan §4).
  final int order;

  bool get isValid => name.trim().isNotEmpty && checkoutPath.trim().isNotEmpty;

  HarnessRepoBinding copyWith({
    String? name,
    String? checkoutPath,
    String? url,
    HarnessRepoRole? role,
    String? defaultBranch,
    int? order,
  }) {
    return HarnessRepoBinding(
      name: name ?? this.name,
      checkoutPath: checkoutPath ?? this.checkoutPath,
      url: url ?? this.url,
      role: role ?? this.role,
      defaultBranch: defaultBranch ?? this.defaultBranch,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'checkoutPath': checkoutPath,
    if (url.isNotEmpty) 'url': url,
    'role': role.name,
    'defaultBranch': defaultBranch,
    'order': order,
  };

  factory HarnessRepoBinding.fromJson(Map<String, dynamic> json) {
    return HarnessRepoBinding(
      name: json['name']?.toString().trim() ?? '',
      checkoutPath: json['checkoutPath']?.toString().trim() ?? '',
      url: json['url']?.toString().trim() ?? '',
      role: HarnessRepoRoleCopy.fromJsonValue(json['role'] as String?),
      defaultBranch: json['defaultBranch']?.toString().trim().isNotEmpty == true
          ? json['defaultBranch'].toString().trim()
          : 'main',
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HarnessRepoBinding &&
      other.name == name &&
      other.checkoutPath == checkoutPath &&
      other.url == url &&
      other.role == role &&
      other.defaultBranch == defaultBranch &&
      other.order == order;

  @override
  int get hashCode =>
      Object.hash(name, checkoutPath, url, role, defaultBranch, order);
}

/// One deployable environment within a [HarnessTarget] — the routing table
/// step `deploy`/`promote` (plan §4) check against.
@immutable
class HarnessEnvironment {
  const HarnessEnvironment({
    required this.name,
    required this.trigger,
    required this.deploy,
    this.healthProbe = '',
    this.requiresHumanGate = false,
  });

  /// Environment name, e.g. `sit`, `uat`, `prod`.
  final String name;
  final HarnessTriggerKind trigger;
  final HarnessDeployKind deploy;

  /// URL or command asserted after deploy (plan §4 evidence — no probe means
  /// this environment cannot satisfy the `deploy`/`verify` evidence check).
  final String healthProbe;

  /// Explicit human-gate override. A tag-triggered environment is gated
  /// regardless of this flag — see [effectiveRequiresHumanGate].
  final bool requiresHumanGate;

  /// The plan's `promote` step is a forced human gate (§4 #10): any
  /// tag-triggered environment (the production release path) requires
  /// approval even if [requiresHumanGate] was left false.
  bool get effectiveRequiresHumanGate =>
      requiresHumanGate || trigger == HarnessTriggerKind.tag;

  bool get isValid => name.trim().isNotEmpty;

  HarnessEnvironment copyWith({
    String? name,
    HarnessTriggerKind? trigger,
    HarnessDeployKind? deploy,
    String? healthProbe,
    bool? requiresHumanGate,
  }) {
    return HarnessEnvironment(
      name: name ?? this.name,
      trigger: trigger ?? this.trigger,
      deploy: deploy ?? this.deploy,
      healthProbe: healthProbe ?? this.healthProbe,
      requiresHumanGate: requiresHumanGate ?? this.requiresHumanGate,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'trigger': trigger.name,
    'deploy': deploy.name,
    if (healthProbe.isNotEmpty) 'healthProbe': healthProbe,
    if (requiresHumanGate) 'requiresHumanGate': requiresHumanGate,
  };

  factory HarnessEnvironment.fromJson(Map<String, dynamic> json) {
    return HarnessEnvironment(
      name: json['name']?.toString().trim() ?? '',
      trigger: HarnessTriggerKindCopy.fromJsonValue(json['trigger'] as String?),
      deploy: HarnessDeployKindCopy.fromJsonValue(json['deploy'] as String?),
      healthProbe: json['healthProbe']?.toString().trim() ?? '',
      requiresHumanGate: json['requiresHumanGate'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HarnessEnvironment &&
      other.name == name &&
      other.trigger == trigger &&
      other.deploy == deploy &&
      other.healthProbe == healthProbe &&
      other.requiresHumanGate == requiresHumanGate;

  @override
  int get hashCode =>
      Object.hash(name, trigger, deploy, healthProbe, requiresHumanGate);
}

/// A configured delivery target for the closed-loop Harness plugin: an
/// org/project's repos and environments (plan §3). Distinct from
/// `currentTaskWorkspace` (the produced-artifact directory, still injected
/// separately) — this describes what the plugin is allowed to change and
/// where, not where it writes its own reports.
@immutable
class HarnessTarget {
  const HarnessTarget({
    required this.id,
    required this.org,
    required this.project,
    this.repos = const <HarnessRepoBinding>[],
    this.environments = const <HarnessEnvironment>[],
    this.requiredSkills = const <String>[],
  });

  /// Stable id, unique across a user's configured targets.
  final String id;
  final String org;
  final String project;
  final List<HarnessRepoBinding> repos;
  final List<HarnessEnvironment> environments;

  /// Gateway-side skill packages the agent must load before acting on this
  /// target (e.g. `github-actions-operational-dispatch`). The App never executes these —
  /// it only carries the name through to the delivery context block so the
  /// plan/think step on the gateway loads the matching rules before it picks
  /// a workflow (plan §one: select happens before plan/think, not after).
  final List<String> requiredSkills;

  String get label => '$org/$project';

  /// [repos] sorted by [HarnessRepoBinding.order] ascending — the order the
  /// `change`/`artifact`/`deploy` steps must walk forward through (plan §4).
  List<HarnessRepoBinding> get reposInExecutionOrder {
    final sorted = List<HarnessRepoBinding>.of(repos)
      ..sort((left, right) => left.order.compareTo(right.order));
    return List<HarnessRepoBinding>.unmodifiable(sorted);
  }

  /// The same repos in reverse — the order the `rollback` step must walk
  /// (gitops before app before infra, undoing `change` last-in-first-out).
  List<HarnessRepoBinding> get reposInRollbackOrder =>
      List<HarnessRepoBinding>.unmodifiable(reposInExecutionOrder.reversed);

  HarnessEnvironment? environmentByName(String name) {
    final normalized = name.trim();
    for (final environment in environments) {
      if (environment.name == normalized) {
        return environment;
      }
    }
    return null;
  }

  /// The environment whose [HarnessEnvironment.trigger] matches, or null if
  /// none is routed to that trigger. A step must refuse to run when the
  /// branch/ref it is acting on doesn't match any routed environment —
  /// this is the routing rigidity check itself, not just a lookup.
  HarnessEnvironment? environmentForTrigger(HarnessTriggerKind trigger) {
    for (final environment in environments) {
      if (environment.trigger == trigger) {
        return environment;
      }
    }
    return null;
  }

  /// Problems that must block the `bind` step (plan §4 #1) from succeeding.
  /// Empty means the target is ready to be bound. Kept as a list (not a
  /// single bool) so the UI/agent can show every issue at once instead of
  /// one-at-a-time.
  List<String> validationIssues() {
    final issues = <String>[];
    if (org.trim().isEmpty) {
      issues.add(appText('组织（org）不能为空', 'org must not be empty'));
    }
    if (project.trim().isEmpty) {
      issues.add(appText('项目（project）不能为空', 'project must not be empty'));
    }
    if (repos.isEmpty) {
      issues.add(appText('至少需要绑定一个仓库', 'at least one repo must be bound'));
    }
    final seenRepoNames = <String>{};
    for (final repo in repos) {
      if (!repo.isValid) {
        issues.add(
          appText(
            '仓库 "${repo.name}" 缺少名称或 checkout 路径',
            'repo "${repo.name}" is missing a name or checkout path',
          ),
        );
        continue;
      }
      if (!seenRepoNames.add(repo.name)) {
        issues.add(
          appText('仓库名重复："${repo.name}"', 'duplicate repo name: "${repo.name}"'),
        );
      }
    }
    if (environments.isEmpty) {
      issues.add(
        appText('至少需要声明一个环境', 'at least one environment must be declared'),
      );
    }
    final seenEnvironmentNames = <String>{};
    for (final environment in environments) {
      if (!environment.isValid) {
        issues.add(appText('存在未命名的环境', 'an environment is missing a name'));
        continue;
      }
      if (!seenEnvironmentNames.add(environment.name)) {
        issues.add(
          appText(
            '环境名重复："${environment.name}"',
            'duplicate environment name: "${environment.name}"',
          ),
        );
      }
    }
    return issues;
  }

  bool get isValid => validationIssues().isEmpty;

  HarnessTarget copyWith({
    String? id,
    String? org,
    String? project,
    List<HarnessRepoBinding>? repos,
    List<HarnessEnvironment>? environments,
    List<String>? requiredSkills,
  }) {
    return HarnessTarget(
      id: id ?? this.id,
      org: org ?? this.org,
      project: project ?? this.project,
      repos: repos ?? this.repos,
      environments: environments ?? this.environments,
      requiredSkills: requiredSkills ?? this.requiredSkills,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'org': org,
    'project': project,
    'repos': repos.map((repo) => repo.toJson()).toList(growable: false),
    'environments': environments
        .map((environment) => environment.toJson())
        .toList(growable: false),
    if (requiredSkills.isNotEmpty) 'requiredSkills': requiredSkills,
  };

  factory HarnessTarget.fromJson(Map<String, dynamic> json) {
    final rawRepos = json['repos'];
    final rawEnvironments = json['environments'];
    final rawSkills = json['requiredSkills'];
    return HarnessTarget(
      id: json['id']?.toString().trim() ?? '',
      org: json['org']?.toString().trim() ?? '',
      project: json['project']?.toString().trim() ?? '',
      repos: rawRepos is List
          ? rawRepos
              .whereType<Map<String, dynamic>>()
              .map(HarnessRepoBinding.fromJson)
              .toList(growable: false)
          : const <HarnessRepoBinding>[],
      environments: rawEnvironments is List
          ? rawEnvironments
              .whereType<Map<String, dynamic>>()
              .map(HarnessEnvironment.fromJson)
              .toList(growable: false)
          : const <HarnessEnvironment>[],
      requiredSkills: rawSkills is List
          ? rawSkills.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HarnessTarget &&
      other.id == id &&
      other.org == org &&
      other.project == project &&
      listEquals(other.repos, repos) &&
      listEquals(other.environments, environments) &&
      listEquals(other.requiredSkills, requiredSkills);

  @override
  int get hashCode => Object.hash(
    id,
    org,
    project,
    Object.hashAll(repos),
    Object.hashAll(environments),
    Object.hashAll(requiredSkills),
  );
}

/// Drops targets with a blank [HarnessTarget.id] and de-duplicates by id
/// (last one wins), mirroring the tolerant-normalization pattern used for
/// other persisted lists in this codebase (e.g.
/// `normalizeAuthorizedSkillDirectories`). Order among the remaining targets
/// is preserved.
List<HarnessTarget> normalizeHarnessTargets({
  Iterable<HarnessTarget>? targets,
}) {
  final incoming = targets?.toList(growable: false) ?? const <HarnessTarget>[];
  final byId = <String, HarnessTarget>{};
  final order = <String>[];
  for (final target in incoming) {
    final id = target.id.trim();
    if (id.isEmpty) {
      continue;
    }
    if (!byId.containsKey(id)) {
      order.add(id);
    }
    byId[id] = target;
  }
  return List<HarnessTarget>.unmodifiable(
    order.map((id) => byId[id]!).toList(growable: false),
  );
}

/// Renders the "Harness delivery context:" block (plan §3) — appended after
/// the existing `TaskThread workspace context:` block
/// (`app_controller_desktop_thread_actions.dart`'s
/// `taskWorkspaceContextPromptInternal`), never replacing it: that block's
/// `currentTaskWorkspace` still holds where the plugin writes its own
/// plans/reports, while this block scopes which repos/environments the
/// plugin is allowed to act on.
String renderHarnessDeliveryContextBlockZh(HarnessTarget target) {
  final buffer = StringBuffer()
    ..writeln('Harness delivery context:')
    ..writeln('- org: ${target.org}')
    ..writeln('- project: ${target.project}');
  if (target.requiredSkills.isNotEmpty) {
    buffer.writeln('- skills: ${target.requiredSkills.join(', ')}');
  }
  buffer.writeln('- repos:');
  for (final repo in target.reposInExecutionOrder) {
    buffer.writeln(
      '  - ${repo.name} (${repo.role.label}, order: ${repo.order}): '
      '${repo.checkoutPath}',
    );
  }
  buffer.writeln('- environments:');
  for (final environment in target.environments) {
    final gate = environment.effectiveRequiresHumanGate ? '，需人工确认' : '';
    buffer.writeln(
      '  - ${environment.name}（触发：${environment.trigger.label}，'
      '发布方式：${environment.deploy.label}$gate）',
    );
  }
  return buffer.toString();
}

String renderHarnessDeliveryContextBlockEn(HarnessTarget target) {
  final buffer = StringBuffer()
    ..writeln('Harness delivery context:')
    ..writeln('- org: ${target.org}')
    ..writeln('- project: ${target.project}');
  if (target.requiredSkills.isNotEmpty) {
    buffer.writeln('- skills: ${target.requiredSkills.join(', ')}');
  }
  buffer.writeln('- repos:');
  for (final repo in target.reposInExecutionOrder) {
    buffer.writeln(
      '  - ${repo.name} (${repo.role.label}, order: ${repo.order}): '
      '${repo.checkoutPath}',
    );
  }
  buffer.writeln('- environments:');
  for (final environment in target.environments) {
    final gate = environment.effectiveRequiresHumanGate
        ? ', requires human approval'
        : '';
    buffer.writeln(
      '  - ${environment.name} (trigger: ${environment.trigger.label}, '
      'deploy: ${environment.deploy.label}$gate)',
    );
  }
  return buffer.toString();
}

String renderHarnessDeliveryContextBlock(HarnessTarget target) => appText(
  renderHarnessDeliveryContextBlockZh(target),
  renderHarnessDeliveryContextBlockEn(target),
);
