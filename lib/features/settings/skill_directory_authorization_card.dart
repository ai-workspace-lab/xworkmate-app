import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../widgets/surface_card.dart';

enum _SkillDirectoryAuthorizationMode { direct, picker }

class SkillDirectoryAuthorizationCard extends StatefulWidget {
  const SkillDirectoryAuthorizationCard({super.key, required this.controller});

  final AppController controller;

  @override
  State<SkillDirectoryAuthorizationCard> createState() =>
      _SkillDirectoryAuthorizationCardState();
}

class _SkillDirectoryAuthorizationCardState
    extends State<SkillDirectoryAuthorizationCard> {
  bool _busy = false;
  String? _statusMessage;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final palette = context.palette;
    final homeDirectory = controller.userHomeDirectory;
    final authorizedDirectories = controller.authorizedSkillDirectories;
    final presetPaths = controller.recommendedAuthorizedSkillDirectoryPaths;
    final customDirectories = authorizedDirectories
        .where(
          (directory) => !presetPaths.any(
            (preset) => _matchesResolvedPath(
              preset,
              directory.path,
              homeDirectory: homeDirectory,
            ),
          ),
        )
        .toList(growable: false);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appText('SKILLS 目录授权', 'SKILLS Directory Authorization'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            appText(
              '预设目录支持直接按路径加入；也可以把终端输出里的目录或单个技能包路径直接贴进来批量导入。系统目录选择器保留在同行旁侧，作为可选授权方式。设置中心修改会写入 settings.yaml。',
              'Preset roots can be added directly by path, and terminal output containing directories or single skill package paths can be pasted for batch import. The system directory picker remains available as an optional side action. Settings Center writes changes back to settings.yaml.',
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _InfoRow(
            label: appText('同步文件', 'Synced File'),
            value: controller.settingsYamlPath,
          ),
          _InfoRow(
            label: appText('已授权目录', 'Granted Directories'),
            value: '${authorizedDirectories.length}',
          ),
          const SizedBox(height: 16),
          if (!controller.supportsSkillDirectoryAuthorization)
            _InlineBanner(
              color: Colors.orange,
              icon: Icons.info_outline_rounded,
              message: appText(
                '当前平台不支持目录授权文件选择器。',
                'The current platform does not support the directory authorization picker.',
              ),
            )
          else ...[
            for (final presetPath in presetPaths) ...[
              _buildDirectoryRow(
                context,
                title: presetPath,
                subtitle: _resolvePathForDisplay(
                  presetPath,
                  homeDirectory: homeDirectory,
                ),
                directory: _findAuthorizedDirectory(
                  authorizedDirectories,
                  presetPath,
                  homeDirectory: homeDirectory,
                ),
                onDirectAuthorize: () => _saveDirectoriesFromPaths(<String>[
                  _resolvePathForDisplay(
                    presetPath,
                    homeDirectory: homeDirectory,
                  ),
                ]),
                onPickerAuthorize: () => _authorizeDirectory(
                  suggestedPath: _resolvePathForDisplay(
                    presetPath,
                    homeDirectory: homeDirectory,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (customDirectories.isNotEmpty) ...[
              Text(
                appText('自定义目录', 'Custom Directories'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              for (final directory in customDirectories) ...[
                _buildDirectoryRow(
                  context,
                  title: _displayNameForPath(directory.path),
                  subtitle: directory.path,
                  directory: directory,
                  onDirectAuthorize: () =>
                      _saveDirectoriesFromPaths(<String>[directory.path]),
                  onPickerAuthorize: () =>
                      _authorizeDirectory(suggestedPath: directory.path),
                ),
                const SizedBox(height: 10),
              ],
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const ValueKey('skill-directory-batch-add-button'),
                onPressed: _busy ? null : _showDirectoryAuthorizationDialog,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.playlist_add_rounded),
                label: Text(appText('批量添加自定义目录', 'Add Custom Directories')),
              ),
            ),
          ],
          if ((_statusMessage ?? _errorMessage) != null) ...[
            const SizedBox(height: 16),
            _InlineBanner(
              color: _errorMessage == null ? Colors.green : Colors.red,
              icon: _errorMessage == null
                  ? Icons.check_circle_rounded
                  : Icons.error_outline_rounded,
              message: _errorMessage ?? _statusMessage!,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            appText(
              '按路径添加会立即写入扫描列表；如果 macOS 对某个目录仍缺系统级访问权限，可使用旁侧目录向导补授 bookmark。移除目录会立即停止扫描该目录。',
              'Direct path add updates the scan list immediately. If macOS still needs system-level access for a directory, use the adjacent picker flow to grant a bookmark. Removing a directory stops scanning it immediately.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required AuthorizedSkillDirectory? directory,
    required Future<void> Function() onDirectAuthorize,
    required Future<void> Function() onPickerAuthorize,
  }) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              _StatusChip(authorized: directory != null),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : onDirectAuthorize,
                icon: Icon(
                  directory == null
                      ? Icons.playlist_add_rounded
                      : Icons.refresh_rounded,
                ),
                label: Text(
                  directory == null
                      ? appText('按路径授权', 'Authorize by Path')
                      : appText('重新同步', 'Resync Path'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : onPickerAuthorize,
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(appText('目录向导', 'Directory Picker')),
              ),
              if (directory != null)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _removeDirectory(directory),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(appText('移除', 'Remove')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  AuthorizedSkillDirectory? _findAuthorizedDirectory(
    List<AuthorizedSkillDirectory> directories,
    String candidatePath, {
    required String homeDirectory,
  }) {
    for (final directory in directories) {
      if (_matchesResolvedPath(
        directory.path,
        candidatePath,
        homeDirectory: homeDirectory,
      )) {
        return directory;
      }
    }
    return null;
  }

  Future<void> _showDirectoryAuthorizationDialog() async {
    final result = await showDialog<_SkillDirectoryAuthorizationDialogResult>(
      context: context,
      builder: (context) => _SkillDirectoryAuthorizationDialog(
        presetPaths: widget.controller.recommendedAuthorizedSkillDirectoryPaths
            .map(
              (path) => _resolvePathForDisplay(
                path,
                homeDirectory: widget.controller.userHomeDirectory,
              ),
            )
            .toList(growable: false),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    if (result.mode == _SkillDirectoryAuthorizationMode.picker) {
      await _authorizeDirectories(suggestedPaths: result.paths);
      return;
    }
    await _saveDirectoriesFromPaths(result.paths);
  }

  Future<void> _authorizeDirectory({String suggestedPath = ''}) async {
    setState(() {
      _busy = true;
      _statusMessage = null;
      _errorMessage = null;
    });
    try {
      final granted = await widget.controller.authorizeSkillDirectory(
        suggestedPath: suggestedPath,
      );
      if (granted == null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _busy = false;
          _statusMessage = appText(
            '已取消目录授权。',
            'Directory authorization canceled.',
          );
        });
        return;
      }
      final next = _mergedAuthorizedDirectories(<AuthorizedSkillDirectory>[
        granted,
      ]);
      await widget.controller.saveAuthorizedSkillDirectories(next);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _statusMessage = appText(
          '目录已授权并同步到 settings.yaml。',
          'Directory authorized and synced to settings.yaml.',
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _authorizeDirectories({
    List<String> suggestedPaths = const <String>[],
  }) async {
    setState(() {
      _busy = true;
      _statusMessage = null;
      _errorMessage = null;
    });
    try {
      final granted = await widget.controller.authorizeSkillDirectories(
        suggestedPaths: suggestedPaths,
      );
      if (granted.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _busy = false;
          _statusMessage = appText(
            '已取消目录授权。',
            'Directory authorization canceled.',
          );
        });
        return;
      }
      await widget.controller.saveAuthorizedSkillDirectories(
        _mergedAuthorizedDirectories(granted),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _statusMessage = appText(
          '已授权 ${granted.length} 个目录并同步到 settings.yaml。',
          'Authorized ${granted.length} directories and synced them to settings.yaml.',
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _saveDirectoriesFromPaths(List<String> rawPaths) async {
    final paths = _extractAuthorizedPathCandidates(rawPaths.join('\n'));
    if (paths.isEmpty) {
      setState(() {
        _statusMessage = null;
        _errorMessage = appText(
          '没有识别到可用路径。请每行提供一个以 / 或 ~/ 开头的目录、技能包目录，或 SKILL.md 文件路径。',
          'No usable paths were detected. Provide one directory, skill package directory, or SKILL.md path per line starting with / or ~/.',
        );
      });
      return;
    }
    setState(() {
      _busy = true;
      _statusMessage = null;
      _errorMessage = null;
    });
    try {
      final next = _mergedAuthorizedDirectories(
        paths.map(_authorizedDirectoryForPath).toList(growable: false),
      );
      await widget.controller.saveAuthorizedSkillDirectories(next);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _statusMessage = appText(
          '已同步 ${paths.length} 个路径到 settings.yaml；如 macOS 仍无法读取，可再使用目录向导补授权。',
          'Synced ${paths.length} paths to settings.yaml. If macOS still cannot read one, use the picker flow to grant access.',
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _removeDirectory(AuthorizedSkillDirectory directory) async {
    setState(() {
      _busy = true;
      _statusMessage = null;
      _errorMessage = null;
    });
    try {
      final next = widget.controller.authorizedSkillDirectories
          .where(
            (item) => !_matchesResolvedPath(
              item.path,
              directory.path,
              homeDirectory: widget.controller.userHomeDirectory,
            ),
          )
          .toList(growable: false);
      await widget.controller.saveAuthorizedSkillDirectories(next);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _statusMessage = appText(
          '目录已移除并停止扫描。',
          'Directory removed and no longer scanned.',
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _errorMessage = error.toString();
      });
    }
  }

  List<AuthorizedSkillDirectory> _mergedAuthorizedDirectories(
    List<AuthorizedSkillDirectory> granted,
  ) {
    final homeDirectory = widget.controller.userHomeDirectory;
    final existing = widget.controller.authorizedSkillDirectories
        .where(
          (item) => !granted.any(
            (entry) => _matchesResolvedPath(
              item.path,
              entry.path,
              homeDirectory: homeDirectory,
            ),
          ),
        )
        .toList(growable: false);
    return normalizeAuthorizedSkillDirectories(
      directories: <AuthorizedSkillDirectory>[...existing, ...granted],
    );
  }

  String _resolvePathForDisplay(String path, {required String homeDirectory}) {
    final normalized = normalizeAuthorizedSkillDirectoryPath(path);
    if (normalized.startsWith('~/') && homeDirectory.trim().isNotEmpty) {
      return '$homeDirectory/${normalized.substring(2)}';
    }
    return normalized;
  }

  bool _matchesResolvedPath(
    String left,
    String right, {
    required String homeDirectory,
  }) {
    return _resolvePathForDisplay(left, homeDirectory: homeDirectory) ==
        _resolvePathForDisplay(right, homeDirectory: homeDirectory);
  }

  String _displayNameForPath(String path) {
    final normalized = normalizeAuthorizedSkillDirectoryPath(path);
    final segments = normalized.split(RegExp(r'[\\/]'));
    return segments.isEmpty ? normalized : segments.last;
  }

  AuthorizedSkillDirectory _authorizedDirectoryForPath(String path) {
    final normalized = normalizeAuthorizedSkillDirectoryPath(path);
    final existing = _findAuthorizedDirectory(
      widget.controller.authorizedSkillDirectories,
      normalized,
      homeDirectory: widget.controller.userHomeDirectory,
    );
    return AuthorizedSkillDirectory(
      path: normalized,
      bookmark: existing?.bookmark ?? '',
    );
  }
}

List<String> _extractAuthorizedPathCandidates(String rawInput) {
  final extracted = <String>[];
  final seen = <String>{};
  for (final line in rawInput.split(RegExp(r'[\r\n]+'))) {
    for (final candidate in _extractAuthorizedPathCandidatesFromLine(line)) {
      final normalized = normalizeAuthorizedSkillDirectoryPath(candidate);
      if (normalized.isNotEmpty && seen.add(normalized)) {
        extracted.add(normalized);
      }
    }
  }
  return extracted;
}

Iterable<String> _extractAuthorizedPathCandidatesFromLine(String line) sync* {
  var normalizedLine = line.trim();
  if (normalizedLine.isEmpty) {
    return;
  }
  normalizedLine = normalizedLine
      .replaceFirst(RegExp(r'^[\-\*\u2022]\s*'), '')
      .replaceFirst(RegExp(r'^\d+[.)]\s*'), '')
      .replaceFirst(
        RegExp(r'^(?:path|paths|dir|directory|路径|目录)\s*[:=]\s*'),
        '',
      );
  final matches = RegExp(
    r"""["']((?:~/|/)[^"']+)["']|`((?:~/|/)[^`]+)`|((?:~/|/)[^,\s;]+)""",
  ).allMatches(normalizedLine);
  if (matches.isNotEmpty) {
    for (final match in matches) {
      final candidate =
          match.group(1) ?? match.group(2) ?? match.group(3) ?? '';
      if (candidate.isNotEmpty) {
        yield candidate;
      }
    }
    return;
  }
  final unwrapped = normalizedLine.replaceAll(
    RegExp(r"""^[\[\(\{<"'`]+|[\]\)\}>,"';`]+$"""),
    '',
  );
  if (unwrapped.startsWith('/') || unwrapped.startsWith('~/')) {
    yield unwrapped;
  }
}

class _SkillDirectoryAuthorizationDialogResult {
  const _SkillDirectoryAuthorizationDialogResult({
    required this.mode,
    required this.paths,
  });

  final _SkillDirectoryAuthorizationMode mode;
  final List<String> paths;
}

class _SkillDirectoryAuthorizationDialog extends StatefulWidget {
  const _SkillDirectoryAuthorizationDialog({required this.presetPaths});

  final List<String> presetPaths;

  @override
  State<_SkillDirectoryAuthorizationDialog> createState() =>
      _SkillDirectoryAuthorizationDialogState();
}

class _SkillDirectoryAuthorizationDialogState
    extends State<_SkillDirectoryAuthorizationDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsedPaths = _extractAuthorizedPathCandidates(_controller.text);
    return AlertDialog(
      title: Text(appText('批量添加自定义目录', 'Add Custom Directories')),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText(
                '默认直接贴路径即可添加；系统目录选择器放在旁侧作为可选动作。支持一行一个目录，也支持直接粘贴终端输出。',
                'Paste paths directly to add them by default. The system directory picker stays beside it as an optional action. Supports one directory per line or pasted terminal output.',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final path in widget.presetPaths)
                  ActionChip(
                    label: Text(path),
                    onPressed: () {
                      final current = _controller.text.trim();
                      _controller.text = current.isEmpty
                          ? path
                          : '$current\n$path';
                      _controller.selection = TextSelection.collapsed(
                        offset: _controller.text.length,
                      );
                      setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('skill-directory-path-input'),
              controller: _controller,
              minLines: 5,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: appText(
                  '一行一个目录或技能包路径，也可直接粘贴命令输出\n~/.agents/skills\n~/.codex/skills\n/Users/shenlan/workspaces/demo/skills/docx\n/Users/shenlan/workspaces/demo/skills/docx/SKILL.md',
                  'One directory or skill package path per line, or paste command output\n~/.agents/skills\n~/.codex/skills\n/Users/shenlan/workspaces/demo/skills/docx\n/Users/shenlan/workspaces/demo/skills/docx/SKILL.md',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              appText(
                '已识别 ${parsedPaths.length} 个路径',
                'Detected ${parsedPaths.length} paths',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appText('取消', 'Cancel')),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              key: const ValueKey('skill-directory-direct-add-button'),
              onPressed: parsedPaths.isEmpty
                  ? null
                  : () {
                      Navigator.of(context).pop(
                        _SkillDirectoryAuthorizationDialogResult(
                          mode: _SkillDirectoryAuthorizationMode.direct,
                          paths: parsedPaths,
                        ),
                      );
                    },
              icon: const Icon(Icons.playlist_add_rounded),
              label: Text(appText('按路径添加', 'Add by Path')),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const ValueKey('skill-directory-picker-button'),
              onPressed: () {
                Navigator.of(context).pop(
                  _SkillDirectoryAuthorizationDialogResult(
                    mode: _SkillDirectoryAuthorizationMode.picker,
                    paths: parsedPaths,
                  ),
                );
              },
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(appText('目录向导', 'Directory Picker')),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.authorized});

  final bool authorized;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = authorized ? Colors.green : palette.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        authorized ? appText('已授权', 'Granted') : appText('未授权', 'Not granted'),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InlineBanner extends StatelessWidget {
  const _InlineBanner({
    required this.color,
    required this.icon,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
