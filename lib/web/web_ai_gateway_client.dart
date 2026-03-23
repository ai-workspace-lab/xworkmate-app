import 'dart:convert';

import 'package:http/http.dart' as http;

import '../runtime/runtime_models.dart';

class WebAiGatewayClient {
  const WebAiGatewayClient();

  Uri? normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    final pathSegments = uri.pathSegments.where((item) => item.isNotEmpty);
    return uri.replace(
      pathSegments: pathSegments.isEmpty ? const <String>['v1'] : pathSegments,
      query: null,
      fragment: null,
    );
  }

  Future<AiGatewayConnectionCheck> testConnection({
    required String baseUrl,
    required String apiKey,
  }) async {
    final normalizedBaseUrl = normalizeBaseUrl(baseUrl);
    if (normalizedBaseUrl == null) {
      return const AiGatewayConnectionCheck(
        state: 'invalid',
        message: 'Missing LLM API Endpoint',
        endpoint: '',
        modelCount: 0,
      );
    }
    final trimmedApiKey = apiKey.trim();
    final endpoint = _modelsUri(normalizedBaseUrl).toString();
    if (trimmedApiKey.isEmpty) {
      return AiGatewayConnectionCheck(
        state: 'invalid',
        message: 'Missing LLM API Token',
        endpoint: endpoint,
        modelCount: 0,
      );
    }
    try {
      final models = await loadModels(
        baseUrl: normalizedBaseUrl.toString(),
        apiKey: trimmedApiKey,
      );
      if (models.isEmpty) {
        return AiGatewayConnectionCheck(
          state: 'empty',
          message: 'Authenticated but no models were returned',
          endpoint: endpoint,
          modelCount: 0,
        );
      }
      return AiGatewayConnectionCheck(
        state: 'ready',
        message: 'Authenticated · ${models.length} model(s) available',
        endpoint: endpoint,
        modelCount: models.length,
      );
    } catch (error) {
      return AiGatewayConnectionCheck(
        state: 'error',
        message: networkErrorLabel(error),
        endpoint: endpoint,
        modelCount: 0,
      );
    }
  }

  Future<List<GatewayModelSummary>> loadModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final normalizedBaseUrl = normalizeBaseUrl(baseUrl);
    if (normalizedBaseUrl == null || apiKey.trim().isEmpty) {
      return const <GatewayModelSummary>[];
    }
    final response = await http.get(
      _modelsUri(normalizedBaseUrl),
      headers: _headers(apiKey),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebAiGatewayException(
        message: _httpErrorLabel(
          response.statusCode,
          _extractErrorDetail(response.body),
        ),
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(_extractFirstJsonDocument(response.body));
    final payload = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    final rawModels = <Object?>[
      ..._asList(payload['data']),
      if (_asList(payload['data']).isEmpty) ..._asList(payload['models']),
    ];
    final seen = <String>{};
    final items = <GatewayModelSummary>[];
    for (final item in rawModels) {
      final map = _asMap(item);
      final modelId =
          _stringValue(map['id']) ?? _stringValue(map['name']) ?? '';
      if (modelId.isEmpty || !seen.add(modelId)) {
        continue;
      }
      items.add(
        GatewayModelSummary(
          id: modelId,
          name: _stringValue(map['name']) ?? modelId,
          provider:
              _stringValue(map['provider']) ??
              _stringValue(map['owned_by']) ??
              'Single Agent',
          contextWindow:
              _intValue(map['contextWindow']) ??
              _intValue(map['context_window']),
          maxOutputTokens:
              _intValue(map['maxOutputTokens']) ??
              _intValue(map['max_output_tokens']),
        ),
      );
    }
    return items;
  }

  Future<String> completeChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<GatewayChatMessage> history,
  }) async {
    final normalizedBaseUrl = normalizeBaseUrl(baseUrl);
    if (normalizedBaseUrl == null) {
      throw const WebAiGatewayException(message: 'Missing LLM API Endpoint');
    }
    final response = await http.post(
      _chatUri(normalizedBaseUrl),
      headers: <String, String>{
        ..._headers(apiKey),
        'content-type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(<String, dynamic>{
        'model': model,
        'stream': false,
        'messages': history
            .where((message) {
              final role = message.role.trim().toLowerCase();
              return (role == 'user' || role == 'assistant') &&
                  message.text.trim().isNotEmpty;
            })
            .map(
              (message) => <String, String>{
                'role': message.role.trim().toLowerCase() == 'assistant'
                    ? 'assistant'
                    : 'user',
                'content': message.text.trim(),
              },
            )
            .toList(growable: false),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebAiGatewayException(
        message: _httpErrorLabel(
          response.statusCode,
          _extractErrorDetail(response.body),
        ),
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(_extractFirstJsonDocument(response.body));
    final payload = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    final choices = _asList(payload['choices']);
    final firstChoice = choices.isEmpty
        ? const <String, dynamic>{}
        : _asMap(choices.first);
    final message = _asMap(firstChoice['message']);
    final content = _stringValue(message['content']) ?? '';
    if (content.trim().isNotEmpty) {
      return content.trim();
    }
    final delta = _asMap(firstChoice['delta']);
    final deltaContent = _stringValue(delta['content']) ?? '';
    if (deltaContent.trim().isNotEmpty) {
      return deltaContent.trim();
    }
    throw const FormatException('Missing assistant content');
  }

  String networkErrorLabel(Object error) {
    if (error is WebAiGatewayException) {
      return error.message;
    }
    return 'Failed: $error';
  }

  Uri _modelsUri(Uri baseUrl) {
    final pathSegments = baseUrl.pathSegments
        .where((item) => item.isNotEmpty)
        .toList(growable: true);
    if (pathSegments.isEmpty) {
      pathSegments.add('v1');
    }
    if (pathSegments.last != 'models') {
      pathSegments.add('models');
    }
    return baseUrl.replace(
      pathSegments: pathSegments,
      query: null,
      fragment: null,
    );
  }

  Uri _chatUri(Uri baseUrl) {
    final pathSegments = baseUrl.pathSegments
        .where((item) => item.isNotEmpty)
        .toList(growable: true);
    if (pathSegments.isEmpty) {
      pathSegments.add('v1');
    }
    if (pathSegments.last == 'models') {
      pathSegments.removeLast();
    }
    if (pathSegments.length >= 2 &&
        pathSegments[pathSegments.length - 2] == 'chat' &&
        pathSegments.last == 'completions') {
      return baseUrl.replace(pathSegments: pathSegments);
    }
    pathSegments.addAll(const <String>['chat', 'completions']);
    return baseUrl.replace(
      pathSegments: pathSegments,
      query: null,
      fragment: null,
    );
  }

  Map<String, String> _headers(String apiKey) {
    final trimmedApiKey = apiKey.trim();
    return <String, String>{
      'accept': 'application/json',
      if (trimmedApiKey.isNotEmpty) 'authorization': 'Bearer $trimmedApiKey',
      if (trimmedApiKey.isNotEmpty) 'x-api-key': trimmedApiKey,
    };
  }

  String _httpErrorLabel(int statusCode, String detail) {
    final base = switch (statusCode) {
      400 => 'Bad request (400)',
      401 => 'Authentication failed (401)',
      403 => 'Access denied (403)',
      404 => 'Endpoint not found (404)',
      429 => 'Rate limited by AI endpoint (429)',
      >= 500 => 'AI endpoint unavailable ($statusCode)',
      _ => 'AI endpoint responded $statusCode',
    };
    return detail.isEmpty ? base : '$base · $detail';
  }

  String _extractErrorDetail(String body) {
    if (body.trim().isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(_extractFirstJsonDocument(body));
      final map = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      final error = _asMap(map['error']);
      return (_stringValue(error['message']) ??
              _stringValue(map['message']) ??
              _stringValue(map['detail']) ??
              '')
          .trim();
    } on FormatException {
      return '';
    }
  }

  String _extractFirstJsonDocument(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty response body');
    }
    final start = trimmed.indexOf(RegExp(r'[\{\[]'));
    if (start < 0) {
      throw const FormatException('Missing JSON document');
    }
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < trimmed.length; index++) {
      final char = trimmed[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (char == '{' || char == '[') {
        depth += 1;
      } else if (char == '}' || char == ']') {
        depth -= 1;
        if (depth == 0) {
          return trimmed.substring(start, index + 1);
        }
      }
    }
    throw const FormatException('Unterminated JSON document');
  }
}

class WebAiGatewayException implements Exception {
  const WebAiGatewayException({required this.message, this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

List<Object?> _asList(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

String? _stringValue(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _intValue(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}
