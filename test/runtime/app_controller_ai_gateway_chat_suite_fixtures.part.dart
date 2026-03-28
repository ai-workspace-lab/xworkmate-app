part of 'app_controller_ai_gateway_chat_suite.dart';

Future<AppController> _createAppController({
  required SecureConfigStore store,
  List<SingleAgentProvider> availableSingleAgentProvidersOverride =
      const <SingleAgentProvider>[],
  RuntimeCoordinator? runtimeCoordinator,
  SingleAgentRunner? singleAgentRunner,
}) async {
  final controller = AppController(
    store: store,
    availableSingleAgentProvidersOverride:
        availableSingleAgentProvidersOverride,
    runtimeCoordinator: runtimeCoordinator,
    singleAgentRunner: singleAgentRunner,
  );
  addTearDown(controller.dispose);
  await _waitFor(() => !controller.initializing);
  return controller;
}

Future<Directory> _createTempDirectory(String prefix) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final tempDirectory = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() async {
    if (await tempDirectory.exists()) {
      await _deleteDirectoryWithRetry(tempDirectory);
    }
  });
  return tempDirectory;
}

SecureConfigStore _createStoreFromTempDirectory(
  Directory tempDirectory, {
  String databaseFileName = 'settings.db',
  bool enableSecureStorage = false,
  Future<String> Function()? defaultSupportDirectoryPathResolver,
}) {
  return SecureConfigStore(
    enableSecureStorage: enableSecureStorage,
    databasePathResolver: () async => '${tempDirectory.path}/$databaseFileName',
    fallbackDirectoryPathResolver: () async => tempDirectory.path,
    defaultSupportDirectoryPathResolver: defaultSupportDirectoryPathResolver,
  );
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 5; attempt += 1) {
    if (!await directory.exists()) {
      return;
    }
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 4) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 80 * (attempt + 1)));
    }
  }
}

List<ManagedMountTargetState> _withAvailableMountTargets(
  List<ManagedMountTargetState> current,
  List<String> availableIds,
) {
  final nextIds = availableIds.toSet();
  return current
      .map(
        (item) => item.copyWith(
          available: nextIds.contains(item.targetId),
          discoveryState: nextIds.contains(item.targetId) ? 'ready' : 'idle',
          syncState: nextIds.contains(item.targetId) ? 'ready' : 'idle',
        ),
      )
      .toList(growable: false);
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
