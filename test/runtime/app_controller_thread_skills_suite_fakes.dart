// ignore_for_file: unused_import, unnecessary_import

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/runtime/skill_directory_access.dart';
import 'app_controller_thread_skills_suite_core.dart';
import 'app_controller_thread_skills_suite_shared_roots.dart';
import 'app_controller_thread_skills_suite_thread_isolation.dart';
import 'app_controller_thread_skills_suite_workspace_fallback.dart';
import 'app_controller_thread_skills_suite_acp.dart';
import 'app_controller_thread_skills_suite_fixtures.dart';

class FakeSkillDirectoryAccessServiceInternal
    implements SkillDirectoryAccessService {
  FakeSkillDirectoryAccessServiceInternal({required this.userHomeDirectory});

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

class AcpSkillsStatusServerInternal {
  AcpSkillsStatusServerInternal._(this.serverInternal, {required this.skills});

  final HttpServer serverInternal;
  List<Map<String, dynamic>> skills;
  Map<String, dynamic>? skillsError;

  int get port => serverInternal.port;

  static Future<AcpSkillsStatusServerInternal> start({
    required List<Map<String, dynamic>> skills,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = AcpSkillsStatusServerInternal._(
      server,
      skills: skills.map((item) => Map<String, dynamic>.from(item)).toList(),
    );
    unawaited(fake.listenInternal());
    return fake;
  }

  Future<void> close() async {
    await serverInternal.close(force: true);
  }

  Future<void> listenInternal() async {
    await for (final request in serverInternal) {
      if (request.uri.path == '/acp/rpc' && request.method == 'POST') {
        await handleRpcInternal(request);
        continue;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  Future<void> handleRpcInternal(HttpRequest request) async {
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
        await writeSseInternal(request, <String, dynamic>{
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
          await writeSseInternal(request, <String, dynamic>{
            'jsonrpc': '2.0',
            'id': id,
            'error': skillsError,
          });
          return;
        }
        await writeSseInternal(request, <String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{'skills': skills},
        });
        return;
      default:
        await writeSseInternal(request, <String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, dynamic>{
            'code': -32601,
            'message': 'unknown method: $method',
          },
        });
    }
  }

  Future<void> writeSseInternal(
    HttpRequest request,
    Map<String, dynamic> payload,
  ) async {
    request.response.write('data: ${jsonEncode(payload)}\n\n');
    await request.response.flush();
    await request.response.close();
  }
}
