// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'app_controller_execution_target_switch_suite_connection.dart';
import 'app_controller_execution_target_switch_suite_thread.dart';
import 'app_controller_execution_target_switch_suite_fixtures.dart';
import 'app_controller_execution_target_switch_suite_fakes.dart';

void registerExecutionTargetSwitchSuiteTests() {
  registerExecutionTargetSwitchConnectionTests();
  registerExecutionTargetSwitchThreadTests();
}
