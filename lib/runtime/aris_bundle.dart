import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'runtime_models.dart';

class ArisBundleManifest {
  const ArisBundleManifest({
    required this.schemaVersion,
    required this.name,
    required this.bundleVersion,
    required this.upstreamRepository,
    required this.upstreamCommit,
    required this.llmChatServerPath,
    required this.llmChatRequirementsPath,
    required this.roleSkills,
    required this.codexRoleSkills,
  });

  final int schemaVersion;
  final String name;
  final String bundleVersion;
  final String upstreamRepository;
  final String upstreamCommit;
  final String llmChatServerPath;
  final String llmChatRequirementsPath;
  final Map<MultiAgentRole, List<String>> roleSkills;
  final Map<MultiAgentRole, List<String>> codexRoleSkills;

  factory ArisBundleManifest.fromJson(Map<String, dynamic> json) {
    Map<MultiAgentRole, List<String>> parseRoleSkills(Object? raw) {
      if (raw is! Map) {
        return const <MultiAgentRole, List<String>>{};
      }
      final parsed = <MultiAgentRole, List<String>>{};
      for (final entry in raw.entries) {
        final role = MultiAgentRole.values.firstWhere(
          (item) => item.name == entry.key.toString(),
          orElse: () => MultiAgentRole.engineer,
        );
        final value = entry.value;
        final items = value is List
            ? value
                  .map((item) => item.toString().trim())
                  .where((item) => item.isNotEmpty)
                  .toList(growable: false)
            : const <String>[];
        parsed[role] = items;
      }
      return parsed;
    }

    return ArisBundleManifest(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      name: json['name'] as String? ?? 'ARIS',
      bundleVersion: json['bundleVersion'] as String? ?? '',
      upstreamRepository: json['upstreamRepository'] as String? ?? '',
      upstreamCommit: json['upstreamCommit'] as String? ?? '',
      llmChatServerPath: json['llmChatServerPath'] as String? ?? '',
      llmChatRequirementsPath:
          json['llmChatRequirementsPath'] as String? ?? '',
      roleSkills: parseRoleSkills(json['roleSkills']),
      codexRoleSkills: parseRoleSkills(json['codexRoleSkills']),
    );
  }
}

class ResolvedArisBundle {
  const ResolvedArisBundle({
    required this.rootPath,
    required this.manifest,
  });

  final String rootPath;
  final ArisBundleManifest manifest;

  String resolve(String relativePath) => '$rootPath/$relativePath';

  String get llmChatServerPath => resolve(manifest.llmChatServerPath);
  String get llmChatRequirementsPath => resolve(manifest.llmChatRequirementsPath);

  List<String> skillPathsForRole(
    MultiAgentRole role, {
    bool preferCodex = false,
  }) {
    final preferred = preferCodex
        ? manifest.codexRoleSkills[role]
        : manifest.roleSkills[role];
    if (preferred != null && preferred.isNotEmpty) {
      return preferred.map(resolve).toList(growable: false);
    }
    final fallback = preferCodex
        ? manifest.roleSkills[role] ?? const <String>[]
        : manifest.codexRoleSkills[role] ?? const <String>[];
    return fallback.map(resolve).toList(growable: false);
  }
}

class ArisBundleRepository {
  ArisBundleRepository({
    AssetBundle? assetBundle,
    Future<String> Function()? rootPathResolver,
    Future<List<String>> Function()? assetKeysResolver,
  }) : _assetBundle = assetBundle ?? rootBundle,
       _rootPathResolver = rootPathResolver,
       _assetKeysResolver = assetKeysResolver;

  static const String assetPrefix = 'assets/aris/';
  static const String manifestAssetPath = '${assetPrefix}manifest.json';

  final AssetBundle _assetBundle;
  final Future<String> Function()? _rootPathResolver;
  final Future<List<String>> Function()? _assetKeysResolver;

  ArisBundleManifest? _manifestCache;
  ResolvedArisBundle? _bundleCache;

  Future<ArisBundleManifest> loadManifest() async {
    final cached = _manifestCache;
    if (cached != null) {
      return cached;
    }
    final raw = await _assetBundle.loadString(manifestAssetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final manifest = ArisBundleManifest.fromJson(decoded);
    _manifestCache = manifest;
    return manifest;
  }

  Future<ResolvedArisBundle> ensureReady() async {
    final cached = _bundleCache;
    if (cached != null) {
      return cached;
    }
    final manifest = await loadManifest();
    final rootPath = await _resolveRootPath();
    final markerFile = File('$rootPath/.bundle-version');
    final directory = Directory(rootPath);
    final needsExtract =
        !await directory.exists() ||
        !await markerFile.exists() ||
        (await markerFile.readAsString()).trim() != manifest.bundleVersion;

    if (needsExtract) {
      await _extractBundle(rootPath, manifest);
    }

    final bundle = ResolvedArisBundle(rootPath: rootPath, manifest: manifest);
    _bundleCache = bundle;
    return bundle;
  }

  Future<Map<String, String>> loadSkillContents(List<String> absolutePaths) async {
    final loaded = <String, String>{};
    for (final path in absolutePaths) {
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      loaded[path] = await file.readAsString();
    }
    return loaded;
  }

  Future<int> countSkillFiles() async {
    final bundle = await ensureReady();
    final skillsDir = Directory(bundle.resolve('skills'));
    if (!await skillsDir.exists()) {
      return 0;
    }
    return skillsDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('SKILL.md'))
        .length;
  }

  Future<String> _resolveRootPath() async {
    final override = await _rootPathResolver?.call();
    final trimmed = override?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    final supportDirectory = await getApplicationSupportDirectory();
    return '${supportDirectory.path}/xworkmate/aris-bundle';
  }

  Future<void> _extractBundle(
    String rootPath,
    ArisBundleManifest manifest,
  ) async {
    final directory = Directory(rootPath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);

    final resolver = _assetKeysResolver;
    final assetKeys = resolver != null
        ? await resolver()
        : (await AssetManifest.loadFromAssetBundle(_assetBundle))
              .listAssets()
              .where((item) => item.startsWith(assetPrefix))
              .toList(growable: false);
    final requiredAssets = _requiredAssetKeys(
      manifest: manifest,
      assetKeys: assetKeys,
    );

    for (final assetKey in requiredAssets) {
      final relativePath = assetKey.substring(assetPrefix.length);
      if (relativePath.isEmpty) {
        continue;
      }
      final data = await _assetBundle.load(assetKey);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final file = File('$rootPath/$relativePath');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }

    await File(
      '$rootPath/.bundle-version',
    ).writeAsString(manifest.bundleVersion, flush: true);
  }

  List<String> _requiredAssetKeys({
    required ArisBundleManifest manifest,
    required List<String> assetKeys,
  }) {
    final required = <String>{manifestAssetPath};
    final requiredPrefixes = <String>{
      _parentAssetPrefix(manifest.llmChatServerPath),
      _parentAssetPrefix(manifest.llmChatRequirementsPath),
    }..removeWhere((item) => item.isEmpty);

    for (final skillPath in <String>[
      ...manifest.roleSkills.values.expand((items) => items),
      ...manifest.codexRoleSkills.values.expand((items) => items),
    ]) {
      requiredPrefixes.add(_parentAssetPrefix(skillPath));
    }

    for (final assetKey in assetKeys) {
      if (required.contains(assetKey)) {
        continue;
      }
      if (requiredPrefixes.any((prefix) => assetKey.startsWith(prefix))) {
        required.add(assetKey);
      }
    }
    return required.toList(growable: false)..sort();
  }

  String _parentAssetPrefix(String relativePath) {
    final trimmed = relativePath.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.endsWith('/')) {
      return assetPrefix + trimmed;
    }
    final slashIndex = trimmed.lastIndexOf('/');
    if (slashIndex < 0) {
      return assetPrefix;
    }
    return '$assetPrefix${trimmed.substring(0, slashIndex + 1)}';
  }
}
