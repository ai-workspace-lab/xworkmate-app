import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app/app_controller_web.dart';
import '../app/ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../widgets/assistant_artifact_sidebar.dart';
import '../widgets/desktop_workspace_scaffold.dart';
import '../widgets/pane_resize_handle.dart';
import '../widgets/surface_card.dart';
import 'web_focus_panel.dart';

part 'web_assistant_page_core.part.dart';
