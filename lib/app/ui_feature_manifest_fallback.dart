// ignore_for_file: unused_import, unnecessary_import

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import 'ui_feature_manifest_core.dart';

const String fallbackUiFeatureManifestYamlInternal = '''
release_policy:
  debug: [stable, beta, experimental]
  profile: [stable, beta]
  release: [stable]

mobile:
  navigation:
    assistant:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile assistant destination
      ui_surface: mobile_shell
    tasks:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile tasks destination
      ui_surface: mobile_shell
    workspace:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace hub destination
      ui_surface: mobile_shell
    secrets:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile secrets destination
      ui_surface: mobile_shell
    settings:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings destination
      ui_surface: mobile_shell
  workspace:
    skills:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace skills launcher
      ui_surface: mobile_workspace_hub
    nodes:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace nodes launcher
      ui_surface: mobile_workspace_hub
    agents:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace agents launcher
      ui_surface: mobile_workspace_hub
    mcp_server:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace MCP launcher
      ui_surface: mobile_workspace_hub
    claw_hub:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile workspace ClawHub launcher
      ui_surface: mobile_workspace_hub
    connectors:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile workspace connectors launcher
      ui_surface: mobile_workspace_hub
    ai_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace LLM API launcher
      ui_surface: mobile_workspace_hub
    account:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile workspace account launcher
      ui_surface: mobile_workspace_hub
  assistant:
    direct_ai:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Mobile does not expose direct AI assistant mode
      ui_surface: assistant_page
    local_gateway:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Mobile does not expose local gateway assistant mode
      ui_surface: assistant_page
    relay_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile relay gateway assistant mode
      ui_surface: assistant_page
    file_attachments:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile file attachment action in assistant composer
      ui_surface: assistant_page
    multi_agent:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile multi-agent toggle in assistant composer
      ui_surface: assistant_page
    local_runtime:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Mobile does not expose desktop runtime controls
      ui_surface: assistant_page
  settings:
    general:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings general tab
      ui_surface: settings_page
    workspace:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings workspace tab
      ui_surface: settings_page
    gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings gateway tab
      ui_surface: settings_page
    account_access:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile account access section
      ui_surface: settings_page
    vault_server:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile Vault server integration section
      ui_surface: settings_page
    gateway_setup_code:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile gateway setup code editor
      ui_surface: settings_page
    agents:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile settings multi-agent tab
      ui_surface: settings_page
    appearance:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings appearance tab
      ui_surface: settings_page
    diagnostics:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings diagnostics tab
      ui_surface: settings_page
    experimental:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile settings experimental tab
      ui_surface: settings_page
    about:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Mobile settings about tab
      ui_surface: settings_page
    experimental_canvas:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile experimental canvas host toggle
      ui_surface: settings_page
    experimental_bridge:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile experimental bridge toggle
      ui_surface: settings_page
    experimental_debug:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Mobile experimental debug runtime toggle
      ui_surface: settings_page

desktop:
  navigation:
    assistant:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop assistant destination
      ui_surface: sidebar_navigation
    tasks:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop tasks destination
      ui_surface: sidebar_navigation
    skills:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop skills destination
      ui_surface: sidebar_navigation
    nodes:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop nodes destination
      ui_surface: sidebar_navigation
    agents:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop agents destination
      ui_surface: sidebar_navigation
    mcp_server:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop MCP Hub destination
      ui_surface: sidebar_navigation
    claw_hub:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop ClawHub destination
      ui_surface: sidebar_navigation
    secrets:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop secrets destination
      ui_surface: sidebar_navigation
    ai_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop LLM API destination
      ui_surface: sidebar_navigation
    settings:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings destination
      ui_surface: sidebar_navigation
    account:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop account destination
      ui_surface: sidebar_navigation
  workspace:
    claw_hub:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop workspace ClawHub tab
      ui_surface: modules_page
    connectors:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop workspace connectors tab
      ui_surface: modules_page
  assistant:
    direct_ai:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop direct AI assistant mode
      ui_surface: assistant_page
    local_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop local gateway assistant mode
      ui_surface: assistant_page
    relay_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop relay gateway assistant mode
      ui_surface: assistant_page
    file_attachments:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop file attachment action in assistant composer
      ui_surface: assistant_page
    multi_agent:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop multi-agent toggle in assistant composer
      ui_surface: assistant_page
    local_runtime:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop local runtime and gateway orchestration entry
      ui_surface: assistant_page
  settings:
    general:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings general tab
      ui_surface: settings_page
    workspace:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings workspace tab
      ui_surface: settings_page
    gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings gateway tab
      ui_surface: settings_page
    account_access:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop account access section
      ui_surface: settings_page
    vault_server:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop Vault server integration section
      ui_surface: settings_page
    gateway_setup_code:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop gateway setup code editor
      ui_surface: settings_page
    agents:
      enabled: false
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop settings multi-agent tab
      ui_surface: settings_page
    appearance:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings appearance tab
      ui_surface: settings_page
    diagnostics:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings diagnostics tab
      ui_surface: settings_page
    experimental:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop settings experimental tab
      ui_surface: settings_page
    about:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Desktop settings about tab
      ui_surface: settings_page
    experimental_canvas:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop experimental canvas host toggle
      ui_surface: settings_page
    experimental_bridge:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop experimental bridge toggle
      ui_surface: settings_page
    experimental_debug:
      enabled: true
      release_tier: experimental
      build_modes: [debug, profile, release]
      description: Desktop experimental debug runtime toggle
      ui_surface: settings_page

web:
  navigation:
    assistant:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web assistant destination
      ui_surface: web_shell
    tasks:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web tasks destination
      ui_surface: web_shell
    skills:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web skills destination
      ui_surface: web_shell
    nodes:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web nodes destination
      ui_surface: web_shell
    secrets:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web secrets destination
      ui_surface: web_shell
    ai_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web LLM API destination
      ui_surface: web_shell
    settings:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web settings destination
      ui_surface: web_shell
  assistant:
    direct_ai:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web direct AI assistant mode
      ui_surface: web_assistant_page
    relay_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web relay gateway assistant mode
      ui_surface: web_assistant_page
    file_attachments:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web file attachment action in assistant composer
      ui_surface: web_assistant_page
    multi_agent:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web multi-agent toggle in assistant composer
      ui_surface: web_assistant_page
    local_gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web local gateway assistant mode
      ui_surface: web_assistant_page
    local_runtime:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Web does not expose desktop runtime controls
      ui_surface: web_assistant_page
  settings:
    general:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web settings general tab
      ui_surface: web_settings_page
    gateway:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web settings gateway tab
      ui_surface: web_settings_page
    account_access:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Web does not expose account access section
      ui_surface: web_settings_page
    vault_server:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Web does not expose vault server integration
      ui_surface: web_settings_page
    gateway_setup_code:
      enabled: false
      release_tier: experimental
      build_modes: []
      description: Web does not expose gateway setup code editor
      ui_surface: web_settings_page
    appearance:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web settings appearance tab
      ui_surface: web_settings_page
    about:
      enabled: true
      release_tier: stable
      build_modes: [debug, profile, release]
      description: Web settings about tab
      ui_surface: web_settings_page
''';
