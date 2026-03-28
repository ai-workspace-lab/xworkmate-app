// ignore_for_file: unused_import, unnecessary_import

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'secure_config_store_suite_core.dart';
import 'secure_config_store_suite_settings.dart';
import 'secure_config_store_suite_secrets.dart';
import 'secure_config_store_suite_compatibility.dart';
import 'secure_config_store_suite_lifecycle.dart';
import 'secure_config_store_suite_fixtures.dart';

void main() {
  registerSecureConfigStoreSuiteSettingsTestsInternal();
  registerSecureConfigStoreSuiteSecretsTestsInternal();
  registerSecureConfigStoreSuiteCompatibilityTestsInternal();
  registerSecureConfigStoreSuiteLifecycleTestsInternal();
}
