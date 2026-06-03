import 'package:flutter/foundation.dart';

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();

  factory AppLogger() {
    return _instance;
  }

  AppLogger._internal();

  final List<String> _logs = [];
  final int maxLines = 200;

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logLine = '[$timestamp] APP: $message';
    _logs.add(logLine);
    if (_logs.length > maxLines) {
      _logs.removeAt(0);
    }
    debugPrint(logLine);
  }

  List<String> getLogs() {
    return List.unmodifiable(_logs);
  }
}

// Global helper for easy logging
void appLog(String message) {
  AppLogger().log(message);
}
