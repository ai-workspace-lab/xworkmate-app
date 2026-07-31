import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/local_git_repository_connection.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test('GitHub repository connector defaults to disconnected', () {
    final snapshot = SettingsSnapshot.defaults();
    expect(snapshot.githubRepository.isConfigured, isFalse);
    expect(snapshot.toJson().containsKey('githubRepository'), isFalse);
  });

  test('configured GitHub repository roundtrips without a token value', () {
    const config = GitHubRepositoryConnectorConfig(
      repository: 'ai-workspace-lab/xworkmate-app',
      branch: 'main',
      publishPath: 'conversations',
      connected: true,
    );
    final restored = SettingsSnapshot.fromJson(
      SettingsSnapshot.defaults().copyWith(githubRepository: config).toJson(),
    );

    expect(restored.githubRepository.repository, config.repository);
    expect(restored.githubRepository.isConfigured, isTrue);
    expect(restored.toJson()['githubRepository'], isNot(contains('token')));
  });
}
