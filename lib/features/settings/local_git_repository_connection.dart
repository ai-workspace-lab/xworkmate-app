import 'dart:convert';

import 'package:http/http.dart' as http;

const String githubRepositoryTokenRef = 'custom.github_repository.token';

class GitHubRepositoryConnectorConfig {
  const GitHubRepositoryConnectorConfig({
    this.repository = '',
    this.branch = 'main',
    this.publishPath = 'conversations',
    this.tokenRef = githubRepositoryTokenRef,
    this.connected = false,
  });

  final String repository;
  final String branch;
  final String publishPath;
  final String tokenRef;
  final bool connected;

  bool get isConfigured =>
      connected &&
      GitHubRepositoryTarget.tryParse(repository) != null &&
      branch.trim().isNotEmpty &&
      publishPath.trim().isNotEmpty &&
      tokenRef.trim().isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'repository': repository,
    'branch': branch,
    'publishPath': publishPath,
    'tokenRef': tokenRef,
    'connected': connected,
  };

  factory GitHubRepositoryConnectorConfig.fromJson(Map<String, dynamic> json) {
    return GitHubRepositoryConnectorConfig(
      repository: json['repository']?.toString().trim() ?? '',
      branch: json['branch']?.toString().trim().isNotEmpty == true
          ? json['branch'].toString().trim()
          : 'main',
      publishPath: json['publishPath']?.toString().trim().isNotEmpty == true
          ? json['publishPath'].toString().trim()
          : 'conversations',
      tokenRef: json['tokenRef']?.toString().trim().isNotEmpty == true
          ? json['tokenRef'].toString().trim()
          : githubRepositoryTokenRef,
      connected: json['connected'] as bool? ?? false,
    );
  }
}

class GitHubRepositoryTarget {
  const GitHubRepositoryTarget({required this.owner, required this.repository});

  final String owner;
  final String repository;

  static GitHubRepositoryTarget? tryParse(String raw) {
    final value = raw.trim();
    final sshMatch = RegExp(
      r'^git@github\.com:([^/\s]+)/([^/\s]+?)(?:\.git)?$',
    ).firstMatch(value);
    final httpsMatch = RegExp(
      r'^https://github\.com/([^/\s]+)/([^/\s]+?)(?:\.git)?/?$',
    ).firstMatch(value);
    final shorthandMatch = RegExp(r'^([^/\s]+)/([^/\s]+)$').firstMatch(value);
    final match = sshMatch ?? httpsMatch ?? shorthandMatch;
    if (match == null) return null;
    return GitHubRepositoryTarget(
      owner: match.group(1)!,
      repository: match.group(2)!,
    );
  }
}

/// A token-free one-line summary of where a publish would land, safe to show
/// in the settings card and the conversation workflow dialog.
String describeGitHubConnectorTarget(GitHubRepositoryConnectorConfig config) {
  final target = GitHubRepositoryTarget.tryParse(config.repository);
  final repository = target == null
      ? config.repository.trim()
      : '${target.owner}/${target.repository}';
  return '$repository · ${config.branch.trim()} · ${config.publishPath.trim()}';
}

String renderGitHubConversationMarkdown({
  required String title,
  required Iterable<({String role, String text})> messages,
}) {
  final buffer = StringBuffer()
    ..writeln(
      '# ${title.trim().isEmpty ? 'XWorkmate conversation' : title.trim()}',
    )
    ..writeln()
    ..writeln('> Published from XWorkmate')
    ..writeln();
  for (final message in messages) {
    final text = message.text.trim();
    if (text.isEmpty) continue;
    final role = switch (message.role.trim().toLowerCase()) {
      'user' => 'User',
      'assistant' => 'Assistant',
      'tool' => 'Tool',
      final other when other.isNotEmpty => other,
      _ => 'Message',
    };
    buffer
      ..writeln('## $role')
      ..writeln()
      ..writeln(text)
      ..writeln();
  }
  return buffer.toString().trimRight();
}

String buildGitHubConversationPath({
  required String directory,
  required String title,
  required DateTime timestamp,
}) {
  final normalizedDirectory = directory
      .trim()
      .split('/')
      .where((part) => part.isNotEmpty && part != '.' && part != '..')
      .join('/');
  final slug = title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final safeSlug = slug.isEmpty ? 'conversation' : slug;
  final local = timestamp.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final suffix =
      '${local.year}${two(local.month)}${two(local.day)}-'
      '${two(local.hour)}${two(local.minute)}${two(local.second)}';
  final fileName = '$safeSlug-$suffix.md';
  return normalizedDirectory.isEmpty
      ? fileName
      : '$normalizedDirectory/$fileName';
}

class GitHubApiResult {
  const GitHubApiResult._({required this.success, required this.message});

  factory GitHubApiResult.success(String message) =>
      GitHubApiResult._(success: true, message: message);

  factory GitHubApiResult.failure(String message) =>
      GitHubApiResult._(success: false, message: message);

  final bool success;
  final String message;
}

typedef GitHubRequest =
    Future<http.Response> Function(
      Uri url, {
      required Map<String, String> headers,
    });

typedef GitHubWriteRequest =
    Future<http.Response> Function(
      Uri url, {
      required Map<String, String> headers,
      required String body,
    });

/// Connects to GitHub over HTTPS. It never starts a system process or reads an
/// SSH key; the user-provided fine-grained token is sent only to GitHub.
Future<GitHubApiResult> verifyGitHubRepositoryConnection({
  required String repository,
  required String token,
  GitHubRequest? get,
}) async {
  final target = GitHubRepositoryTarget.tryParse(repository);
  if (target == null) {
    return GitHubApiResult.failure(
      'Enter a GitHub repository URL or owner/repository.',
    );
  }
  if (token.trim().isEmpty) {
    return GitHubApiResult.failure('Enter a GitHub fine-grained token.');
  }
  try {
    final response = await (get ?? http.get)(
      Uri.https(
        'api.github.com',
        '/repos/${target.owner}/${target.repository}',
      ),
      headers: _headers(token),
    );
    return response.statusCode == 200
        ? GitHubApiResult.success('GitHub repository connection verified.')
        : GitHubApiResult.failure(
            'GitHub could not access this repository. Check repository access and the token’s Contents permission.',
          );
  } catch (_) {
    return GitHubApiResult.failure(
      'Could not reach GitHub. Check your network connection.',
    );
  }
}

/// Creates or updates a Markdown conversation with GitHub’s Contents API.
Future<GitHubApiResult> publishConversationToGitHub({
  required String repository,
  required String token,
  required String branch,
  required String path,
  required String markdown,
  GitHubWriteRequest? put,
}) async {
  final target = GitHubRepositoryTarget.tryParse(repository);
  if (target == null ||
      token.trim().isEmpty ||
      branch.trim().isEmpty ||
      path.trim().isEmpty) {
    return GitHubApiResult.failure(
      'Repository, token, branch, and publish path are required.',
    );
  }
  final encodedPath = path
      .trim()
      .split('/')
      .where((part) => part.isNotEmpty && part != '.' && part != '..')
      .map(Uri.encodeComponent)
      .join('/');
  if (encodedPath.isEmpty) {
    return GitHubApiResult.failure('Enter a valid publish path.');
  }
  try {
    final response = await (put ?? http.put)(
      Uri.https(
        'api.github.com',
        '/repos/${target.owner}/${target.repository}/contents/$encodedPath',
      ),
      headers: _headers(token),
      body: jsonEncode(<String, String>{
        'message': 'docs: publish XWorkmate conversation',
        'content': base64Encode(utf8.encode(markdown)),
        'branch': branch.trim(),
      }),
    );
    return response.statusCode == 200 || response.statusCode == 201
        ? GitHubApiResult.success('Conversation published to GitHub.')
        : GitHubApiResult.failure(
            'GitHub could not publish this conversation.',
          );
  } catch (_) {
    return GitHubApiResult.failure(
      'Could not reach GitHub. Check your network connection.',
    );
  }
}

Map<String, String> _headers(String token) => <String, String>{
  'Accept': 'application/vnd.github+json',
  'Authorization': 'Bearer ${token.trim()}',
  'X-GitHub-Api-Version': '2026-03-10',
  'User-Agent': 'XWorkmate',
};
