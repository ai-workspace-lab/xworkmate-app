import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/app_store_policy.dart';
import '../../app/ui_feature_manifest.dart';
import '../../app/workspace_navigation.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/gateway_runtime.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import 'codex_integration_card.dart';
import 'skill_directory_authorization_card.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';

part 'settings_page_core.part.dart';
part 'settings_page_sections.part.dart';
part 'settings_page_gateway.part.dart';
part 'settings_page_gateway_connection.part.dart';
part 'settings_page_gateway_llm.part.dart';
part 'settings_page_presentation.part.dart';
part 'settings_page_multi_agent.part.dart';
part 'settings_page_support.part.dart';
part 'settings_page_device.part.dart';
part 'settings_page_widgets.part.dart';
