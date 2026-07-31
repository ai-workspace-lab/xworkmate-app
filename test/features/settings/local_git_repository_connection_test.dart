import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xworkmate/features/settings/local_git_repository_connection.dart';

void main() {
  test('verifies a GitHub repository over HTTPS without a process', () async {
    Uri? requestedUrl;

    final result = await verifyGitHubRepositoryConnection(
      repository: 'haitaopanhq/knowledge',
      token: 'test-token',
      get: (url, {required headers}) async {
        requestedUrl = url;
        expect(headers['Authorization'], 'Bearer test-token');
        return http.Response('{}', 200);
      },
    );

    expect(result.success, isTrue);
    expect(
      requestedUrl,
      Uri.parse('https://api.github.com/repos/haitaopanhq/knowledge'),
    );
  });

  test(
    'rejects a repository outside GitHub without sending a request',
    () async {
      var invoked = false;

      final result = await verifyGitHubRepositoryConnection(
        repository: 'https://git.example.com/acme/knowledge.git',
        token: 'test-token',
        get: (_, {required headers}) async {
          invoked = true;
          return http.Response('{}', 200);
        },
      );

      expect(result.success, isFalse);
      expect(invoked, isFalse);
    },
  );

  test('publishes Markdown with the GitHub Contents API', () async {
    Uri? requestedUrl;
    String? requestBody;

    final result = await publishConversationToGitHub(
      repository: 'haitaopanhq/knowledge',
      token: 'test-token',
      branch: 'main',
      path: 'conversations/hello.md',
      markdown: '# Hello',
      put: (url, {required headers, required body}) async {
        requestedUrl = url;
        requestBody = body;
        return http.Response('{}', 201);
      },
    );

    expect(result.success, isTrue);
    expect(
      requestedUrl,
      Uri.parse(
        'https://api.github.com/repos/haitaopanhq/knowledge/contents/conversations/hello.md',
      ),
    );
    expect(
      jsonDecode(requestBody!)["content"],
      base64Encode(utf8.encode('# Hello')),
    );
  });
}
