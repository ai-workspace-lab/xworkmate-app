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
import 'app_controller_thread_skills_suite_shared_roots.dart';
import 'app_controller_thread_skills_suite_thread_isolation.dart';
import 'app_controller_thread_skills_suite_workspace_fallback.dart';
import 'app_controller_thread_skills_suite_acp.dart';
import 'app_controller_thread_skills_suite_fixtures.dart';
import 'app_controller_thread_skills_suite_fakes.dart';

void registerThreadSkillsSuiteTests() {
  registerThreadSkillsSharedRootTests();
  registerThreadSkillsThreadIsolationTests();
  registerThreadSkillsWorkspaceFallbackTests();
  registerThreadSkillsAcpTests();
}
