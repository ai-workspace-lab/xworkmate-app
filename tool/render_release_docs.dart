import 'dart:io';

import 'package:yaml/yaml.dart';

const _platformOrder = <String>['mobile', 'desktop', 'web'];
const _tierOrder = <String>['stable', 'beta', 'experimental'];
const _buildModeOrder = <String>['debug', 'profile', 'release'];

void main() {
  final manifest = FeatureManifest.load();
  final git = GitSnapshot.capture();

  _writeDoc(
    'docs/planning/xworkmate-ui-feature-matrix.md',
    _renderFeatureMatrix(manifest, git),
  );
  _writeDoc(
    'docs/planning/xworkmate-ui-feature-roadmap.md',
    _renderFeatureRoadmap(manifest, git),
  );
  _writeDoc(
    'docs/releases/xworkmate-release-notes.md',
    _renderReleaseNotes(manifest, git),
  );
  _writeDoc('docs/releases/xworkmate-changelog.md', _renderChangelog(git));

  stdout.writeln(
    'Rendered docs/planning/xworkmate-ui-feature-matrix.md, '
    'docs/planning/xworkmate-ui-feature-roadmap.md, '
    'docs/releases/xworkmate-release-notes.md, '
    'and docs/releases/xworkmate-changelog.md',
  );
}

void _writeDoc(String relativePath, String contents) {
  final file = File(relativePath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

String _renderFeatureMatrix(FeatureManifest manifest, GitSnapshot git) {
  final buffer = StringBuffer()
    ..writeln('# XWorkmate UI Feature Matrix')
    ..writeln()
    ..writeln(_generatedPreamble(git))
    ..writeln()
    ..writeln('## Release Policy')
    ..writeln()
    ..writeln('| Build Mode | 可见 Tier | 说明 |')
    ..writeln('| --- | --- | --- |');

  for (final buildMode in _buildModeOrder) {
    final tiers = manifest.releasePolicy[buildMode] ?? const <String>[];
    final note = switch (buildMode) {
      'debug' => '内部开发与功能联调',
      'profile' => '预发布验收与性能验证',
      'release' => '面向用户交付的正式版本',
      _ => '-',
    };
    buffer.writeln(
      '| `${_escapeMarkdown(buildMode)}` | `${tiers.join(', ')}` | $note |',
    );
  }

  buffer
    ..writeln()
    ..writeln(
      '`release_policy` 是全局上限；单个 flag 还必须同时满足 '
      '`enabled: true` 和自身 `build_modes` 才会真正出现在 UI 中。',
    )
    ..writeln()
    ..writeln('## Snapshot Summary')
    ..writeln()
    ..writeln(
      '| 平台 | Flag 总数 | 已启用 | Stable | Beta | Experimental | Disabled |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- |');

  var total = 0;
  var totalEnabled = 0;
  var totalDisabled = 0;
  final tierTotals = <String, int>{for (final tier in _tierOrder) tier: 0};

  for (final platform in _platformOrder) {
    final records = manifest.recordsFor(platform);
    final enabled = records.where((record) => record.enabled).length;
    final disabled = records.length - enabled;
    total += records.length;
    totalEnabled += enabled;
    totalDisabled += disabled;

    final perTier = <String, int>{for (final tier in _tierOrder) tier: 0};
    for (final record in records.where((record) => record.enabled)) {
      perTier[record.releaseTier] = (perTier[record.releaseTier] ?? 0) + 1;
      tierTotals[record.releaseTier] =
          (tierTotals[record.releaseTier] ?? 0) + 1;
    }

    buffer.writeln(
      '| `${_escapeMarkdown(platform)}` | ${records.length} | $enabled | '
      '${perTier['stable']} | ${perTier['beta']} | '
      '${perTier['experimental']} | $disabled |',
    );
  }

  buffer
    ..writeln(
      '| `total` | $total | $totalEnabled | ${tierTotals['stable']} | '
      '${tierTotals['beta']} | ${tierTotals['experimental']} | $totalDisabled |',
    )
    ..writeln();

  for (final platform in _platformOrder) {
    buffer
      ..writeln('## ${_titleCase(platform)}')
      ..writeln()
      ..writeln('| 模块 | Flag | 状态 | Tier | Build Modes | UI Surface | 说明 |')
      ..writeln('| --- | --- | --- | --- | --- | --- | --- |');

    for (final record in manifest.recordsFor(platform)) {
      final modes = record.buildModes.isEmpty
          ? '-'
          : _escapeMarkdown(record.buildModes.join(', '));
      final state = record.enabled ? 'enabled' : 'disabled';
      buffer.writeln(
        '| `${_escapeMarkdown(record.module)}` | '
        '`${_escapeMarkdown(record.name)}` | $state | '
        '`${_escapeMarkdown(record.releaseTier)}` | '
        '`$modes` | '
        '`${_escapeMarkdown(record.uiSurface)}` | '
        '${_escapeMarkdown(record.description)} |',
      );
    }

    buffer.writeln();
  }

  return buffer.toString();
}

String _renderFeatureRoadmap(FeatureManifest manifest, GitSnapshot git) {
  final buffer = StringBuffer()
    ..writeln('# XWorkmate UI Feature Flag Roadmap')
    ..writeln()
    ..writeln(_generatedPreamble(git))
    ..writeln()
    ..writeln('## 规划规则')
    ..writeln()
    ..writeln(
      '- `release_policy` 决定 build mode 的总开关上限：`debug` 可见 '
      '`stable / beta / experimental`，`profile` 可见 `stable / beta`，'
      '`release` 仅可见 `stable`。',
    )
    ..writeln('- 单个 flag 的交付状态由三层共同决定：`enabled`、`release_tier`、`build_modes`。')
    ..writeln(
      '- `enabled: false` 或 `build_modes: []` 的项，会在文档里继续保留，'
      '但不会进入当前 build mode 的用户可见范围。',
    )
    ..writeln()
    ..writeln('## Build Visibility Summary')
    ..writeln()
    ..writeln(
      '| 平台 | Debug Visible | Profile Visible | Release Visible | Suppressed |',
    )
    ..writeln('| --- | --- | --- | --- | --- |');

  for (final platform in _platformOrder) {
    final debugVisible = manifest.visibleFlags(platform, 'debug').length;
    final profileVisible = manifest.visibleFlags(platform, 'profile').length;
    final releaseVisible = manifest.visibleFlags(platform, 'release').length;
    final suppressed = manifest
        .recordsFor(platform)
        .where((record) => !record.visibleIn('debug', manifest.releasePolicy))
        .length;
    buffer.writeln(
      '| `${_escapeMarkdown(platform)}` | $debugVisible | $profileVisible | '
      '$releaseVisible | $suppressed |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Release Baseline')
    ..writeln()
    ..writeln('| 平台 | 数量 | Flag 列表 |')
    ..writeln('| --- | --- | --- |');

  for (final platform in _platformOrder) {
    final releaseFlags = manifest.visibleFlags(platform, 'release');
    buffer.writeln(
      '| `${_escapeMarkdown(platform)}` | ${releaseFlags.length} | '
      '${_flagList(releaseFlags)} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Profile-only Lane')
    ..writeln()
    ..writeln('| 平台 | 数量 | 相比 Release 新增 |')
    ..writeln('| --- | --- | --- |');

  for (final platform in _platformOrder) {
    final profileOnly = _difference(
      manifest.visibleFlags(platform, 'profile'),
      manifest.visibleFlags(platform, 'release'),
    );
    buffer.writeln(
      '| `${_escapeMarkdown(platform)}` | ${profileOnly.length} | '
      '${_flagList(profileOnly)} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Debug-only Experimental Lane')
    ..writeln()
    ..writeln('| 平台 | 数量 | 相比 Profile 新增 |')
    ..writeln('| --- | --- | --- |');

  for (final platform in _platformOrder) {
    final debugOnly = _difference(
      manifest.visibleFlags(platform, 'debug'),
      manifest.visibleFlags(platform, 'profile'),
    );
    buffer.writeln(
      '| `${_escapeMarkdown(platform)}` | ${debugOnly.length} | '
      '${_flagList(debugOnly)} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Explicitly Suppressed')
    ..writeln()
    ..writeln('| 平台 | 数量 | Flag 列表 |')
    ..writeln('| --- | --- | --- |');

  for (final platform in _platformOrder) {
    final suppressed = manifest
        .recordsFor(platform)
        .where((record) => !record.visibleIn('debug', manifest.releasePolicy))
        .toList(growable: false);
    buffer.writeln(
      '| `${_escapeMarkdown(platform)}` | ${suppressed.length} | '
      '${_flagList(suppressed)} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Tier Inventory')
    ..writeln();

  for (final platform in _platformOrder) {
    buffer.writeln('### ${_titleCase(platform)}');
    buffer.writeln();
    for (final tier in [..._tierOrder, 'disabled']) {
      final records = manifest
          .recordsFor(platform)
          .where((record) {
            if (!record.enabled) {
              return tier == 'disabled';
            }
            return record.releaseTier == tier;
          })
          .toList(growable: false);
      if (records.isEmpty) {
        continue;
      }
      buffer.writeln('- `$tier`: ${_flagList(records)}');
    }
    buffer.writeln();
  }

  return buffer.toString();
}

String _renderReleaseNotes(FeatureManifest manifest, GitSnapshot git) {
  final profileOnlyAll = <FeatureFlagRecord>[];
  final debugOnlyAll = <FeatureFlagRecord>[];

  for (final platform in _platformOrder) {
    profileOnlyAll.addAll(
      _difference(
        manifest.visibleFlags(platform, 'profile'),
        manifest.visibleFlags(platform, 'release'),
      ),
    );
    debugOnlyAll.addAll(
      _difference(
        manifest.visibleFlags(platform, 'debug'),
        manifest.visibleFlags(platform, 'profile'),
      ),
    );
  }

  final categorized = _categorizeCommits(git.commits);
  final buffer = StringBuffer()
    ..writeln('# XWorkmate Release Notes')
    ..writeln()
    ..writeln(_generatedPreamble(git))
    ..writeln()
    ..writeln('## Git Snapshot')
    ..writeln()
    ..writeln('| 字段 | 值 |')
    ..writeln('| --- | --- |')
    ..writeln('| Branch | `${_escapeMarkdown(git.branch)}` |')
    ..writeln('| Head Commit | `${_escapeMarkdown(git.headShort)}` |')
    ..writeln('| Head Tags | ${_inlineValue(git.headTags.join(', '))} |')
    ..writeln('| Latest Tag | ${_inlineValue(git.latestTag ?? '-')} |')
    ..writeln('| Previous Tag | ${_inlineValue(git.previousTag ?? '-')} |')
    ..writeln(
      '| Comparison Range | `${_escapeMarkdown(git.comparisonRangeLabel)}` |',
    )
    ..writeln('| Commit Count | ${git.commits.length} |')
    ..writeln()
    ..writeln('## Feature Snapshot')
    ..writeln()
    ..writeln('| 平台 | Debug | Profile | Release | Suppressed |')
    ..writeln('| --- | --- | --- | --- | --- |');

  for (final platform in _platformOrder) {
    buffer.writeln(
      '| `${_escapeMarkdown(platform)}` | '
      '${manifest.visibleFlags(platform, 'debug').length} | '
      '${manifest.visibleFlags(platform, 'profile').length} | '
      '${manifest.visibleFlags(platform, 'release').length} | '
      '${manifest.recordsFor(platform).where((record) => !record.visibleIn('debug', manifest.releasePolicy)).length} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Current Focus')
    ..writeln()
    ..writeln(
      '- `release` 当前面向用户暴露 ${manifest.visibleFlagCount('release')} 个 UI feature flags，'
      '全部来自 `stable` tier。',
    )
    ..writeln(
      '- `profile` 相比 `release` 额外开放 ${profileOnlyAll.length} 个预发布条目：'
      ' ${_flagList(profileOnlyAll, includePlatform: true)}。',
    )
    ..writeln(
      '- `debug` 相比 `profile` 额外开放 ${debugOnlyAll.length} 个实验条目：'
      ' ${_flagList(debugOnlyAll, includePlatform: true)}。',
    )
    ..writeln()
    ..writeln('## Commit Highlights')
    ..writeln();

  if (git.commits.isEmpty) {
    buffer.writeln('当前比较范围没有可渲染的 commits。');
    return buffer.toString();
  }

  for (final entry in categorized.entries) {
    if (entry.value.isEmpty) {
      continue;
    }
    buffer.writeln('### ${entry.key}');
    buffer.writeln();
    for (final commit in entry.value) {
      buffer.writeln(
        '- `${_escapeMarkdown(commit.hash)}` ${_escapeMarkdown(commit.subject)}',
      );
    }
    buffer.writeln();
  }

  return buffer.toString();
}

String _renderChangelog(GitSnapshot git) {
  final buffer = StringBuffer()
    ..writeln('# XWorkmate Changelog')
    ..writeln()
    ..writeln(_generatedPreamble(git))
    ..writeln()
    ..writeln('## Git Snapshot')
    ..writeln()
    ..writeln('| 字段 | 值 |')
    ..writeln('| --- | --- |')
    ..writeln('| Branch | `${_escapeMarkdown(git.branch)}` |')
    ..writeln('| Head Commit | `${_escapeMarkdown(git.headShort)}` |')
    ..writeln('| Head Tags | ${_inlineValue(git.headTags.join(', '))} |')
    ..writeln('| Latest Tag | ${_inlineValue(git.latestTag ?? '-')} |')
    ..writeln('| Previous Tag | ${_inlineValue(git.previousTag ?? '-')} |')
    ..writeln(
      '| Comparison Range | `${_escapeMarkdown(git.comparisonRangeLabel)}` |',
    )
    ..writeln()
    ..writeln('## Recent Tags')
    ..writeln()
    ..writeln('| Tag | Date |')
    ..writeln('| --- | --- |');

  for (final tag in git.recentTags) {
    buffer.writeln(
      '| `${_escapeMarkdown(tag.name)}` | `${_escapeMarkdown(tag.date)}` |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Commits')
    ..writeln()
    ..writeln('| Hash | Date | Author | Subject |')
    ..writeln('| --- | --- | --- | --- |');

  if (git.commits.isEmpty) {
    buffer.writeln(
      '| `-` | `-` | `-` | No commits found for the selected range |',
    );
    return buffer.toString();
  }

  for (final commit in git.commits) {
    buffer.writeln(
      '| `${_escapeMarkdown(commit.hash)}` | '
      '`${_escapeMarkdown(commit.date)}` | '
      '${_escapeMarkdown(commit.author)} | '
      '${_escapeMarkdown(commit.subject)} |',
    );
  }

  return buffer.toString();
}

String _generatedPreamble(GitSnapshot git) {
  return [
    '> Generated by `tool/render_release_docs.dart`',
    '> Source manifest: [`config/feature_flags.yaml`](../../config/feature_flags.yaml)',
    '> Generated at: `${_escapeMarkdown(git.generatedAt)}`',
  ].join('\n');
}

String _flagList(
  List<FeatureFlagRecord> records, {
  bool includePlatform = false,
}) {
  if (records.isEmpty) {
    return '-';
  }
  return records
      .map(
        (record) =>
            '`${_escapeMarkdown(includePlatform ? record.qualifiedId : record.id)}`',
      )
      .join(', ');
}

List<FeatureFlagRecord> _difference(
  List<FeatureFlagRecord> left,
  List<FeatureFlagRecord> right,
) {
  final rightIds = right.map((record) => record.id).toSet();
  return left
      .where((record) => !rightIds.contains(record.id))
      .toList(growable: false);
}

Map<String, List<GitCommit>> _categorizeCommits(List<GitCommit> commits) {
  final ordered = <String, List<GitCommit>>{
    'Features': <GitCommit>[],
    'Fixes': <GitCommit>[],
    'Build / Release': <GitCommit>[],
    'Docs': <GitCommit>[],
    'Tests': <GitCommit>[],
    'Refactors': <GitCommit>[],
    'Merges': <GitCommit>[],
    'Other': <GitCommit>[],
  };

  for (final commit in commits) {
    final subject = commit.subject.toLowerCase();
    final bucket = switch (true) {
      _ when subject.startsWith('merge ') => 'Merges',
      _
          when subject.startsWith('feat') ||
              subject.startsWith('add ') ||
              subject.startsWith('implement ') =>
        'Features',
      _ when subject.startsWith('fix') || subject.contains(' bug') => 'Fixes',
      _ when subject.startsWith('docs') || subject.startsWith('readme') =>
        'Docs',
      _ when subject.startsWith('test') => 'Tests',
      _ when subject.startsWith('refactor') => 'Refactors',
      _
          when subject.startsWith('build') ||
              subject.startsWith('release') ||
              subject.startsWith('ci') ||
              subject.startsWith('package') ||
              subject.contains('workflow') =>
        'Build / Release',
      _ => 'Other',
    };
    ordered[bucket]!.add(commit);
  }

  return ordered;
}

String _inlineValue(String value) {
  final normalized = value.trim().isEmpty ? '-' : value.trim();
  return '`${_escapeMarkdown(normalized)}`';
}

String _escapeMarkdown(String value) {
  return value.replaceAll('|', r'\|');
}

String _titleCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

class FeatureManifest {
  FeatureManifest({required this.releasePolicy, required this.records});

  factory FeatureManifest.load() {
    final yaml = loadYaml(File('config/feature_flags.yaml').readAsStringSync());
    final root = yaml as YamlMap;
    final releasePolicyRoot = root['release_policy'] as YamlMap? ?? YamlMap();
    final releasePolicy = <String, List<String>>{
      for (final buildMode in _buildModeOrder)
        buildMode: (releasePolicyRoot[buildMode] as YamlList? ?? YamlList())
            .map((value) => value.toString())
            .toList(growable: false),
    };

    final records = <FeatureFlagRecord>[];
    for (final platform in _platformOrder) {
      final platformRoot = root[platform] as YamlMap?;
      if (platformRoot == null) {
        continue;
      }
      for (final moduleEntry in platformRoot.entries) {
        final module = moduleEntry.key.toString();
        final featureRoot = moduleEntry.value as YamlMap;
        for (final featureEntry in featureRoot.entries) {
          final name = featureEntry.key.toString();
          final raw = featureEntry.value as YamlMap;
          records.add(
            FeatureFlagRecord(
              platform: platform,
              module: module,
              name: name,
              enabled: raw['enabled'] == true,
              releaseTier: raw['release_tier'].toString(),
              buildModes: (raw['build_modes'] as YamlList? ?? YamlList())
                  .map((value) => value.toString())
                  .toList(growable: false),
              description: raw['description'].toString(),
              uiSurface: raw['ui_surface'].toString(),
            ),
          );
        }
      }
    }

    return FeatureManifest(releasePolicy: releasePolicy, records: records);
  }

  final Map<String, List<String>> releasePolicy;
  final List<FeatureFlagRecord> records;

  List<FeatureFlagRecord> recordsFor(String platform) {
    return records
        .where((record) => record.platform == platform)
        .toList(growable: false);
  }

  List<FeatureFlagRecord> visibleFlags(String platform, String buildMode) {
    return recordsFor(platform)
        .where((record) => record.visibleIn(buildMode, releasePolicy))
        .toList(growable: false);
  }

  int visibleFlagCount(String buildMode) {
    return _platformOrder.fold<int>(
      0,
      (total, platform) => total + visibleFlags(platform, buildMode).length,
    );
  }
}

class FeatureFlagRecord {
  const FeatureFlagRecord({
    required this.platform,
    required this.module,
    required this.name,
    required this.enabled,
    required this.releaseTier,
    required this.buildModes,
    required this.description,
    required this.uiSurface,
  });

  final String platform;
  final String module;
  final String name;
  final bool enabled;
  final String releaseTier;
  final List<String> buildModes;
  final String description;
  final String uiSurface;

  String get id => '$module.$name';

  String get qualifiedId => '$platform.$module.$name';

  bool visibleIn(String buildMode, Map<String, List<String>> releasePolicy) {
    final allowedTiers = releasePolicy[buildMode] ?? const <String>[];
    return enabled &&
        buildModes.contains(buildMode) &&
        allowedTiers.contains(releaseTier);
  }
}

class GitSnapshot {
  GitSnapshot({
    required this.branch,
    required this.headShort,
    required this.headLong,
    required this.headTags,
    required this.latestTag,
    required this.previousTag,
    required this.comparisonRangeLabel,
    required this.generatedAt,
    required this.commits,
    required this.recentTags,
  });

  factory GitSnapshot.capture() {
    final branch =
        _git(['branch', '--show-current'], allowFailure: true).trim().isEmpty
        ? 'detached-head'
        : _git(['branch', '--show-current']);
    final headShort = _git(['rev-parse', '--short', 'HEAD']);
    final headLong = _git(['rev-parse', 'HEAD']);
    final headTags = _gitLines(['tag', '--points-at', 'HEAD']);
    final recentTags = _gitTagRefs().take(5).toList(growable: false);
    final latestTag = recentTags.isEmpty ? null : recentTags.first.name;

    String? previousTag;
    String comparisonRangeLabel;
    String? comparisonRange;

    if (headTags.isNotEmpty) {
      previousTag = recentTags
          .map((tag) => tag.name)
          .firstWhere((tag) => !headTags.contains(tag), orElse: () => '')
          .trim();
      if (previousTag.isEmpty) {
        previousTag = null;
      }
      final activeTag = headTags.first;
      comparisonRange = previousTag == null ? null : '$previousTag..$activeTag';
      comparisonRangeLabel = comparisonRange ?? activeTag;
    } else if (latestTag != null) {
      previousTag = recentTags.length > 1 ? recentTags[1].name : null;
      comparisonRange = '$latestTag..HEAD';
      comparisonRangeLabel = comparisonRange;
    } else {
      comparisonRange = null;
      comparisonRangeLabel = 'HEAD (latest 20 commits)';
    }

    final commits = _gitCommitLog(comparisonRange);

    return GitSnapshot(
      branch: branch,
      headShort: headShort,
      headLong: headLong,
      headTags: headTags,
      latestTag: latestTag,
      previousTag: previousTag,
      comparisonRangeLabel: comparisonRangeLabel,
      generatedAt: DateTime.now().toIso8601String(),
      commits: commits,
      recentTags: recentTags,
    );
  }

  final String branch;
  final String headShort;
  final String headLong;
  final List<String> headTags;
  final String? latestTag;
  final String? previousTag;
  final String comparisonRangeLabel;
  final String generatedAt;
  final List<GitCommit> commits;
  final List<GitTagRef> recentTags;
}

class GitCommit {
  const GitCommit({
    required this.hash,
    required this.date,
    required this.author,
    required this.subject,
  });

  final String hash;
  final String date;
  final String author;
  final String subject;
}

class GitTagRef {
  const GitTagRef({required this.name, required this.date});

  final String name;
  final String date;
}

List<GitCommit> _gitCommitLog(String? comparisonRange) {
  final args = <String>[
    'log',
    '--date=short',
    '--pretty=format:%h%x09%ad%x09%an%x09%s',
  ];

  if (comparisonRange == null) {
    args.addAll(<String>['-n', '20']);
  } else {
    args.add(comparisonRange);
  }

  final lines = _gitLines(args, allowFailure: true);
  return lines
      .map((line) => line.split('\t'))
      .where((parts) => parts.length >= 4)
      .map(
        (parts) => GitCommit(
          hash: parts[0],
          date: parts[1],
          author: parts[2],
          subject: parts.sublist(3).join('\t'),
        ),
      )
      .toList(growable: false);
}

List<GitTagRef> _gitTagRefs() {
  final lines = _gitLines(<String>[
    'for-each-ref',
    '--sort=-creatordate',
    '--format=%(refname:short)%09%(creatordate:short)',
    'refs/tags',
  ], allowFailure: true);

  return lines
      .map((line) => line.split('\t'))
      .where((parts) => parts.length >= 2)
      .map((parts) => GitTagRef(name: parts[0], date: parts[1]))
      .toList(growable: false);
}

String _git(List<String> args, {bool allowFailure = false}) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) {
    if (allowFailure) {
      return '';
    }
    throw ProcessException(
      'git',
      args,
      (result.stderr as String).trim(),
      result.exitCode,
    );
  }
  return (result.stdout as String).trim();
}

List<String> _gitLines(List<String> args, {bool allowFailure = false}) {
  final output = _git(args, allowFailure: allowFailure);
  if (output.trim().isEmpty) {
    return const <String>[];
  }
  return output
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}
