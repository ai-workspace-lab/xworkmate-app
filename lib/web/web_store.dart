import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../runtime/runtime_models.dart';

class WebStore {
  static const settingsKey = 'xworkmate.web.settings.snapshot';
  static const threadsKey = 'xworkmate.web.assistant.threads';
  static const aiGatewayApiKeyKey = 'xworkmate.web.ai_gateway.api_key';
  static const relayTokenKey = 'xworkmate.web.relay.token';
  static const relayPasswordKey = 'xworkmate.web.relay.password';
  static const relayDeviceIdentityKey = 'xworkmate.web.relay.device_identity';
  static const sessionApiTokenKey = 'xworkmate.web.session.api_token';
  static const sessionClientIdKey = 'xworkmate.web.session.client_id';
  static const themeModeKey = 'xworkmate.web.theme_mode';

  SharedPreferences? _prefs;

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<SettingsSnapshot> loadSettingsSnapshot() async {
    await initialize();
    return SettingsSnapshot.fromJsonString(_prefs!.getString(settingsKey));
  }

  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) async {
    await initialize();
    await _prefs!.setString(settingsKey, snapshot.toJsonString());
  }

  Future<List<AssistantThreadRecord>> loadAssistantThreadRecords() async {
    await initialize();
    final raw = _prefs!.getString(threadsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <AssistantThreadRecord>[];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                AssistantThreadRecord.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false);
    } catch (_) {
      return const <AssistantThreadRecord>[];
    }
  }

  Future<void> saveAssistantThreadRecords(
    List<AssistantThreadRecord> records,
  ) async {
    await initialize();
    await _prefs!.setString(
      threadsKey,
      jsonEncode(records.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  Future<String> loadAiGatewayApiKey() async {
    await initialize();
    return (_prefs!.getString(aiGatewayApiKeyKey) ?? '').trim();
  }

  Future<void> saveAiGatewayApiKey(String value) async {
    await initialize();
    await _prefs!.setString(aiGatewayApiKeyKey, value.trim());
  }

  Future<String> loadRelayToken() async {
    await initialize();
    return (_prefs!.getString(relayTokenKey) ?? '').trim();
  }

  Future<void> saveRelayToken(String value) async {
    await initialize();
    await _prefs!.setString(relayTokenKey, value.trim());
  }

  Future<String> loadRelayPassword() async {
    await initialize();
    return (_prefs!.getString(relayPasswordKey) ?? '').trim();
  }

  Future<void> saveRelayPassword(String value) async {
    await initialize();
    await _prefs!.setString(relayPasswordKey, value.trim());
  }

  Future<String> loadWebSessionApiToken() async {
    await initialize();
    return (_prefs!.getString(sessionApiTokenKey) ?? '').trim();
  }

  Future<void> saveWebSessionApiToken(String value) async {
    await initialize();
    await _prefs!.setString(sessionApiTokenKey, value.trim());
  }

  Future<String> loadOrCreateWebSessionClientId() async {
    await initialize();
    final existing = (_prefs!.getString(sessionClientIdKey) ?? '').trim();
    if (existing.isNotEmpty) {
      return existing;
    }
    final next = _generateClientId();
    await _prefs!.setString(sessionClientIdKey, next);
    return next;
  }

  Future<LocalDeviceIdentity?> loadRelayDeviceIdentity() async {
    await initialize();
    final raw = _prefs!.getString(relayDeviceIdentityKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      return LocalDeviceIdentity.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRelayDeviceIdentity(LocalDeviceIdentity identity) async {
    await initialize();
    await _prefs!.setString(
      relayDeviceIdentityKey,
      jsonEncode(identity.toJson()),
    );
  }

  Future<ThemeMode> loadThemeMode() async {
    await initialize();
    return switch ((_prefs!.getString(themeModeKey) ?? '').trim()) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    await initialize();
    await _prefs!.setString(themeModeKey, mode.name);
  }

  static String? maskValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length <= 4) {
      return '*' * trimmed.length;
    }
    return '${trimmed.substring(0, 2)}${'*' * (trimmed.length - 4)}${trimmed.substring(trimmed.length - 2)}';
  }

  static String _generateClientId() {
    final random = Random();
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = List<String>.generate(
      4,
      (_) => random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0'),
      growable: false,
    ).join();
    return 'web-$timestamp-$suffix';
  }
}
