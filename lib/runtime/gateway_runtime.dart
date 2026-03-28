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

part 'gateway_runtime_core.part.dart';
