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
import 'gateway_runtime_protocol.dart';
import 'gateway_runtime_events.dart';
import 'gateway_runtime_helpers.dart';
import 'gateway_runtime_core.dart';

class GatewayRuntimeException implements Exception {
  GatewayRuntimeException(this.message, {this.code, this.details});

  final String message;
  final String? code;
  final Object? details;

  String? get detailCode => stringValue(asMap(details)['code']);

  @override
  String toString() => code == null ? message : '$code: $message';
}
