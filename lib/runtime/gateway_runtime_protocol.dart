// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:web_socket_channel/io.dart';
import '../app/app_metadata.dart';
import 'device_identity_store.dart';
import 'platform_environment.dart';
import 'runtime_models.dart';
import 'secure_config_store.dart';
import 'gateway_runtime_events.dart';
import 'gateway_runtime_errors.dart';
import 'gateway_runtime_helpers.dart';
import 'gateway_runtime_core.dart';

const kGatewayProtocolVersion = 3;
const kDefaultOperatorConnectScopes = <String>[
  'operator.admin',
  'operator.read',
  'operator.write',
  'operator.approvals',
  'operator.pairing',
];
