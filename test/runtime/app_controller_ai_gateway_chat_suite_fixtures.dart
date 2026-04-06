// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'app_controller_ai_gateway_chat_suite_core.dart';
import 'app_controller_ai_gateway_chat_suite_chat.dart';
import 'app_controller_ai_gateway_chat_suite_single_agent.dart';
import 'app_controller_ai_gateway_chat_suite_fakes.dart';

Future<AppController> createAppControllerInternal({
  required SecureConfigStore store,
  List<SingleAgentProvider> availableSingleAgentProvidersOverride =
      const <SingleAgentProvider>[],
  RuntimeCoordinator? runtimeCoordinator,
  GoTaskServiceClient? goTaskServiceClient,
}) async {
  final controller = AppController(
    store: store,
    availableSingleAgentProvidersOverride:
        availableSingleAgentProvidersOverride,
    runtimeCoordinator: runtimeCoordinator,
    goTaskServiceClient: goTaskServiceClient,
  );
  addTearDown(controller.dispose);
  await waitForInternal(() => !controller.initializing);
  return controller;
}

Future<Directory> createTempDirectoryInternal(String prefix) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final tempDirectory = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() async {
    if (await tempDirectory.exists()) {
      await deleteDirectoryWithRetryInternal(tempDirectory);
    }
  });
  return tempDirectory;
}

SecureConfigStore createStoreFromTempDirectoryInternal(
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

Future<void> deleteDirectoryWithRetryInternal(Directory directory) async {
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

List<ManagedMountTargetState> withAvailableMountTargetsInternal(
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

Future<void> waitForInternal(
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
