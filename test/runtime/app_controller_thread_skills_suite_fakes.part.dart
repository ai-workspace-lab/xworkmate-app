part of 'app_controller_thread_skills_suite.dart';

class _FakeSkillDirectoryAccessService implements SkillDirectoryAccessService {
  _FakeSkillDirectoryAccessService({required this.userHomeDirectory});

  final String userHomeDirectory;

  @override
  bool get isSupported => true;

  @override
  Future<String> resolveUserHomeDirectory() async {
    return userHomeDirectory;
  }

  @override
  Future<List<AuthorizedSkillDirectory>> authorizeDirectories({
    List<String> suggestedPaths = const <String>[],
  }) async {
    return const <AuthorizedSkillDirectory>[];
  }

  @override
  Future<AuthorizedSkillDirectory?> authorizeDirectory({
    String suggestedPath = '',
  }) async {
    final normalized = normalizeAuthorizedSkillDirectoryPath(suggestedPath);
    if (normalized.isEmpty) {
      return null;
    }
    return AuthorizedSkillDirectory(path: normalized);
  }

  @override
  Future<SkillDirectoryAccessHandle?> openDirectory(
    AuthorizedSkillDirectory directory,
  ) async {
    final normalized = normalizeAuthorizedSkillDirectoryPath(directory.path);
    if (normalized.isEmpty) {
      return null;
    }
    return SkillDirectoryAccessHandle(path: normalized, onClose: () async {});
  }
}

class _AcpSkillsStatusServer {
  _AcpSkillsStatusServer._(this._server, {required this.skills});

  final HttpServer _server;
  List<Map<String, dynamic>> skills;
  Map<String, dynamic>? skillsError;

  int get port => _server.port;

  static Future<_AcpSkillsStatusServer> start({
    required List<Map<String, dynamic>> skills,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _AcpSkillsStatusServer._(
      server,
      skills: skills.map((item) => Map<String, dynamic>.from(item)).toList(),
    );
    unawaited(fake._listen());
    return fake;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _listen() async {
    await for (final request in _server) {
      if (request.uri.path == '/acp/rpc' && request.method == 'POST') {
        await _handleRpc(request);
        continue;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  Future<void> _handleRpc(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final envelope = jsonDecode(body) as Map<String, dynamic>;
    final id = envelope['id'];
    final method = envelope['method']?.toString().trim() ?? '';

    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      'text/event-stream',
    );
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

    switch (method) {
      case 'acp.capabilities':
        await _writeSse(request, <String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{
            'singleAgent': true,
            'multiAgent': true,
            'providers': const <String>['opencode'],
            'capabilities': <String, dynamic>{
              'single_agent': true,
              'multi_agent': true,
              'providers': const <String>['opencode'],
            },
          },
        });
        return;
      case 'skills.status':
        if (skillsError != null) {
          await _writeSse(request, <String, dynamic>{
            'jsonrpc': '2.0',
            'id': id,
            'error': skillsError,
          });
          return;
        }
        await _writeSse(request, <String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{'skills': skills},
        });
        return;
      default:
        await _writeSse(request, <String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, dynamic>{
            'code': -32601,
            'message': 'unknown method: $method',
          },
        });
    }
  }

  Future<void> _writeSse(
    HttpRequest request,
    Map<String, dynamic> payload,
  ) async {
    request.response.write('data: ${jsonEncode(payload)}\n\n');
    await request.response.flush();
    await request.response.close();
  }
}
