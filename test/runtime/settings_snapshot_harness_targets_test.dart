import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/plugins/harness_delivery_target.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('SettingsSnapshot.harnessTargets', () {
    test('defaults to an empty list', () {
      expect(SettingsSnapshot.defaults().harnessTargets, isEmpty);
    });

    test('toJson omits the key when there are no targets', () {
      final json = SettingsSnapshot.defaults().toJson();
      expect(json.containsKey('harnessTargets'), isFalse);
    });

    test('JSON without a harnessTargets key still loads with an empty list',
        () {
      // Simulates settings.yaml written before this field existed.
      final json = SettingsSnapshot.defaults().toJson();
      expect(json.containsKey('harnessTargets'), isFalse);
      final restored = SettingsSnapshot.fromJson(json);
      expect(restored.harnessTargets, isEmpty);
    });

    test('a populated target list roundtrips through toJson/fromJson', () {
      const target = HarnessTarget(
        id: 'target-1',
        org: 'ai-workspace-lab',
        project: 'platform-ops',
        repos: <HarnessRepoBinding>[
          HarnessRepoBinding(
            name: 'ai-workspace-infra/platform-ops-toolkit',
            checkoutPath: '/srv/repos/platform-ops-toolkit',
            role: HarnessRepoRole.infra,
          ),
        ],
        environments: <HarnessEnvironment>[
          HarnessEnvironment(
            name: 'uat',
            trigger: HarnessTriggerKind.mainPush,
            deploy: HarnessDeployKind.ansible,
          ),
        ],
      );
      final snapshot = SettingsSnapshot.defaults().copyWith(
        harnessTargets: <HarnessTarget>[target],
      );
      final restored = SettingsSnapshot.fromJson(snapshot.toJson());
      expect(restored.harnessTargets, <HarnessTarget>[target]);
    });

    test('copyWith normalizes: blank ids dropped, duplicate ids collapsed',
        () {
      const blank = HarnessTarget(id: '', org: 'o', project: 'p');
      const first = HarnessTarget(id: 'a', org: 'first', project: 'p');
      const dup = HarnessTarget(id: 'a', org: 'second', project: 'p');
      final snapshot = SettingsSnapshot.defaults().copyWith(
        harnessTargets: <HarnessTarget>[blank, first, dup],
      );
      expect(snapshot.harnessTargets, hasLength(1));
      expect(snapshot.harnessTargets.single.org, 'second');
    });

    test('fromJson tolerates malformed harnessTargets entries', () {
      final json = SettingsSnapshot.defaults().toJson();
      json['harnessTargets'] = <Object?>[
        'not-a-map',
        42,
        <String, dynamic>{'id': 'ok', 'org': 'o', 'project': 'p'},
      ];
      final restored = SettingsSnapshot.fromJson(json);
      expect(restored.harnessTargets, hasLength(1));
      expect(restored.harnessTargets.single.id, 'ok');
    });
  });
}
