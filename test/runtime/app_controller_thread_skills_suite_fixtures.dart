// ignore_for_file: unused_import, unnecessary_import

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/runtime/skill_directory_access.dart';
import 'app_controller_thread_skills_suite_core.dart';
import 'app_controller_thread_skills_suite_shared_roots.dart';
import 'app_controller_thread_skills_suite_thread_isolation.dart';
import 'app_controller_thread_skills_suite_workspace_fallback.dart';
import 'app_controller_thread_skills_suite_acp.dart';
import 'app_controller_thread_skills_suite_fakes.dart';

Future<void> writeSkillInternal(
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

Future<void> waitForInternal(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<SecureConfigStore> createStoreInternal(String rootPath) async {
  final store = SecureConfigStore(
    enableSecureStorage: false,
    databasePathResolver: () async => '$rootPath/settings.sqlite3',
    fallbackDirectoryPathResolver: () async => rootPath,
    defaultSupportDirectoryPathResolver: () async => rootPath,
  );
  await store.initialize();
  await store.saveSettingsSnapshot(
    singleAgentTestSettingsInternal(workspacePath: rootPath),
  );
  return store;
}

SettingsSnapshot singleAgentTestSettingsInternal({
  required String workspacePath,
  int gatewayPort = 9,
  String singleAgentProviderEndpoint = '',
  String singleAgentProviderAuthRef = '',
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
    externalAcpEndpoints: replaceExternalAcpEndpointForProvider(
      defaults.externalAcpEndpoints,
      SingleAgentProvider.opencode,
      defaults.externalAcpEndpointForProvider(
        SingleAgentProvider.opencode,
      ).copyWith(
        endpoint: singleAgentProviderEndpoint,
        authRef: singleAgentProviderAuthRef,
      ),
    ),
  );
}
