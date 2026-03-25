import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../widgets/surface_card.dart';

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
              '只有在这里显式授权的目录才会被扫描为单机智能体 skills。设置中心修改会写入 settings.yaml；外部直接改 settings.yaml 也会热加载回 UI 与技能缓存。',
              'Only directories explicitly granted here are scanned as single-agent skills. Settings Center changes write back to settings.yaml, and external settings.yaml edits hot-reload into the UI and skill cache.',
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
                onAuthorize: () => _authorizeDirectory(
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
                  onAuthorize: () =>
                      _authorizeDirectory(suggestedPath: directory.path),
                ),
                const SizedBox(height: 10),
              ],
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _authorizeDirectory(),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.create_new_folder_outlined),
                label: Text(appText('添加自定义目录', 'Add Custom Directory')),
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
              'macOS 会通过目录选择器显式授予只读访问，并持久化授权 bookmark；移除目录会立即停止扫描该目录。',
              'On macOS the directory picker grants explicit read-only access and persists the authorization bookmark. Removing a directory stops scanning it immediately.',
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
    required Future<void> Function() onAuthorize,
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
                onPressed: _busy ? null : onAuthorize,
                icon: Icon(
                  directory == null
                      ? Icons.folder_open_rounded
                      : Icons.refresh_rounded,
                ),
                label: Text(
                  directory == null
                      ? appText('授权目录', 'Authorize')
                      : appText('重新授权', 'Re-authorize'),
                ),
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
      final next = normalizeAuthorizedSkillDirectories(
        directories: <AuthorizedSkillDirectory>[
          ...widget.controller.authorizedSkillDirectories.where(
            (item) => !_matchesResolvedPath(
              item.path,
              granted.path,
              homeDirectory: widget.controller.userHomeDirectory,
            ),
          ),
          granted,
        ],
      );
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
