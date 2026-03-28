@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
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
import 'package:xworkmate/runtime/single_agent_runner.dart';

part 'app_controller_ai_gateway_chat_suite_core.part.dart';
part 'app_controller_ai_gateway_chat_suite_chat.part.dart';
part 'app_controller_ai_gateway_chat_suite_single_agent.part.dart';
part 'app_controller_ai_gateway_chat_suite_fakes.part.dart';
part 'app_controller_ai_gateway_chat_suite_fixtures.part.dart';

void main() {
  _registerAppControllerAiGatewayChatSuiteChatTests();
  _registerAppControllerAiGatewayChatSuiteSingleAgentTests();
}
