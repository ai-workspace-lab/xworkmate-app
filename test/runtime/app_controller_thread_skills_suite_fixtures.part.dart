part of 'app_controller_thread_skills_suite.dart';

Future<void> _writeSkill(
  Directory root,
  String folderName, {
  required String description,
  required String skillName,
}) async {
  final directory = Directory('${root.path}/$folderName');
  await directory.create(recursive: true);
  await File(
    '${directory.path}/SKILL.md',
  ).writeAsString('---\nname: $skillName\ndescription: $description\n---\n');
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<SecureConfigStore> _createStore(String rootPath) async {
  final store = SecureConfigStore(
    enableSecureStorage: false,
    databasePathResolver: () async => '$rootPath/settings.sqlite3',
    fallbackDirectoryPathResolver: () async => rootPath,
    defaultSupportDirectoryPathResolver: () async => rootPath,
  );
  await store.initialize();
  await store.saveSettingsSnapshot(
    _singleAgentTestSettings(workspacePath: rootPath),
  );
  return store;
}

SettingsSnapshot _singleAgentTestSettings({
  required String workspacePath,
  int gatewayPort = 9,
}) {
  final defaults = SettingsSnapshot.defaults();
  return defaults.copyWith(
    gatewayProfiles: replaceGatewayProfileAt(
      replaceGatewayProfileAt(
        defaults.gatewayProfiles,
        kGatewayLocalProfileIndex,
        defaults.primaryLocalGatewayProfile.copyWith(
          host: '127.0.0.1',
          port: gatewayPort,
          tls: false,
        ),
      ),
      kGatewayRemoteProfileIndex,
      defaults.primaryRemoteGatewayProfile.copyWith(
        host: '127.0.0.1',
        port: gatewayPort,
        tls: false,
      ),
    ),
    assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
    workspacePath: workspacePath,
  );
}
