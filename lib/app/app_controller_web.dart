import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/runtime_models.dart';
import '../web/web_acp_client.dart';
import '../web/web_ai_gateway_client.dart';
import '../web/web_artifact_proxy_client.dart';
import '../web/web_relay_gateway_client.dart';
import '../web/web_session_repository.dart';
import '../web/web_store.dart';
import '../web/web_workspace_controllers.dart';
import 'app_capabilities.dart';
import 'ui_feature_manifest.dart';

part 'app_controller_web_core.part.dart';
part 'app_controller_web_sessions.part.dart';
part 'app_controller_web_workspace.part.dart';
part 'app_controller_web_session_actions.part.dart';
part 'app_controller_web_gateway_config.part.dart';
part 'app_controller_web_gateway_relay.part.dart';
part 'app_controller_web_gateway_chat.part.dart';
part 'app_controller_web_helpers.part.dart';
