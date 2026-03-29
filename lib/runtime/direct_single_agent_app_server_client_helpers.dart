// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'runtime_models.dart';
import 'direct_single_agent_app_server_client_protocol.dart';
import 'direct_single_agent_app_server_client_transport.dart';
import 'direct_single_agent_app_server_client_core.dart';

Uri buildRestUriInternal(
  Uri base,
  String path, {
  Map<String, String>? queryParameters,
}) {
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return base.replace(
    path: normalizedPath,
    queryParameters: queryParameters,
    fragment: null,
  );
}

Future<Map<String, dynamic>> fetchJsonInternal(
  Uri uri, {
  required String gatewayToken,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(uri);
    final normalizedToken = gatewayToken.trim();
    if (normalizedToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $normalizedToken',
      );
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return decodeMapInternal(body);
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> postJsonInternal(
  Uri uri, {
  required Object? body,
  required String gatewayToken,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.postUrl(uri);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    final normalizedToken = gatewayToken.trim();
    if (normalizedToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $normalizedToken',
      );
    }
    if (body != null) {
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (text.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    return decodeMapInternal(text);
  } finally {
    client.close(force: true);
  }
}

Future<List<Object?>> fetchJsonListInternal(
  Uri uri, {
  required String gatewayToken,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(uri);
    final normalizedToken = gatewayToken.trim();
    if (normalizedToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $normalizedToken',
      );
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is List<Object?>) {
      return decoded;
    }
    if (decoded is List) {
      return decoded.cast<Object?>();
    }
    return const <Object?>[];
  } finally {
    client.close(force: true);
  }
}

String? extractThreadIdInternal(Map<String, dynamic> payload) {
  final topLevelId = payload['id']?.toString().trim() ?? '';
  if (topLevelId.isNotEmpty) {
    return topLevelId;
  }
  final thread = asMapInternal(payload['thread']);
  final nestedId = thread['id']?.toString().trim() ?? '';
  if (nestedId.isNotEmpty) {
    return nestedId;
  }
  return null;
}

String? extractModelInternal(Map<String, dynamic> payload) {
  final model = payload['model']?.toString().trim() ?? '';
  if (model.isNotEmpty) {
    return model;
  }
  return null;
}

String? extractThreadPathInternal(Map<String, dynamic> payload) {
  final directPath = payload['path']?.toString().trim() ?? '';
  if (directPath.isNotEmpty) {
    return directPath;
  }
  final thread = asMapInternal(payload['thread']);
  final nestedPath = thread['path']?.toString().trim() ?? '';
  if (nestedPath.isNotEmpty) {
    return nestedPath;
  }
  return null;
}

Map<String, dynamic> decodeMapInternal(Object raw) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
  if (raw is Map) {
    return raw.cast<String, dynamic>();
  }
  final decoded = jsonDecode(raw.toString());
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return decoded.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

Map<String, dynamic> asMapInternal(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

bool isLocalHostInternal(String host) {
  final normalized = host.trim().toLowerCase();
  if (normalized.isEmpty ||
      normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1') {
    return true;
  }
  final address = InternetAddress.tryParse(normalized);
  return address?.isLoopback ?? false;
}
