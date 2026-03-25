import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../i18n/app_language.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'section_tabs.dart';
import 'surface_card.dart';

typedef AssistantArtifactSnapshotLoader =
    Future<AssistantArtifactSnapshot> Function();
typedef AssistantArtifactPreviewLoader =
    Future<AssistantArtifactPreview> Function(AssistantArtifactEntry entry);

enum AssistantArtifactSidebarTab { results, files, changes, preview }

class AssistantArtifactSidebar extends StatefulWidget {
  const AssistantArtifactSidebar({
    super.key,
    required this.sessionKey,
    required this.threadTitle,
    required this.workspaceRef,
    required this.workspaceRefKind,
    required this.onCollapse,
    required this.loadSnapshot,
    required this.loadPreview,
  });

  final String sessionKey;
  final String threadTitle;
  final String workspaceRef;
  final WorkspaceRefKind workspaceRefKind;
  final VoidCallback onCollapse;
  final AssistantArtifactSnapshotLoader loadSnapshot;
  final AssistantArtifactPreviewLoader loadPreview;

  @override
  State<AssistantArtifactSidebar> createState() =>
      _AssistantArtifactSidebarState();
}

class _AssistantArtifactSidebarState extends State<AssistantArtifactSidebar> {
  AssistantArtifactSidebarTab _activeTab = AssistantArtifactSidebarTab.results;
  AssistantArtifactSnapshot? _snapshot;
  AssistantArtifactEntry? _selectedEntry;
  AssistantArtifactPreview _preview = const AssistantArtifactPreview.empty();
  Object? _loadError;
  bool _loadingSnapshot = false;
  bool _loadingPreview = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshSnapshot());
  }

  @override
  void didUpdateWidget(covariant AssistantArtifactSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionKey != widget.sessionKey ||
        oldWidget.workspaceRef != widget.workspaceRef ||
        oldWidget.workspaceRefKind != widget.workspaceRefKind) {
      _activeTab = AssistantArtifactSidebarTab.results;
      _selectedEntry = null;
      _preview = const AssistantArtifactPreview.empty();
      unawaited(_refreshSnapshot());
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final snapshot = _snapshot;
    final entriesForPreview = _previewCandidates(snapshot);
    final selectedEntry = _selectedEntry;

    return SurfaceCard(
      key: const Key('assistant-artifact-pane'),
      tone: SurfaceCardTone.chrome,
      padding: EdgeInsets.zero,
      borderRadius: AppRadius.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.threadTitle.trim().isEmpty
                            ? appText('当前线程', 'Current thread')
                            : widget.threadTitle.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Tooltip(
                        message: widget.workspaceRef.trim(),
                        child: Row(
                          children: [
                            Icon(
                              widget.workspaceRefKind ==
                                      WorkspaceRefKind.objectStore
                                  ? Icons.storage_rounded
                                  : Icons.folder_open_rounded,
                              size: 14,
                              color: palette.textSecondary,
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            Expanded(
                              child: Text(
                                _workspaceSummary(
                                  widget.workspaceRef,
                                  widget.workspaceRefKind,
                                ),
                                key: const Key(
                                  'assistant-artifact-pane-workspace-ref',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('assistant-artifact-pane-refresh'),
                  tooltip: appText('刷新产物', 'Refresh artifacts'),
                  onPressed: _loadingSnapshot ? null : _refreshSnapshot,
                  icon: _loadingSnapshot
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                ),
                IconButton(
                  key: const Key('assistant-artifact-pane-collapse'),
                  tooltip: appText('收起右侧栏', 'Collapse sidebar'),
                  onPressed: widget.onCollapse,
                  icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: SectionTabs(
              size: SectionTabsSize.small,
              items: AssistantArtifactSidebarTab.values
                  .map(_labelForTab)
                  .toList(growable: false),
              value: _labelForTab(_activeTab),
              onChanged: (value) {
                final nextTab = AssistantArtifactSidebarTab.values.firstWhere(
                  (item) => _labelForTab(item) == value,
                  orElse: () => AssistantArtifactSidebarTab.results,
                );
                setState(() {
                  _activeTab = nextTab;
                });
                if (nextTab == AssistantArtifactSidebarTab.preview &&
                    selectedEntry == null &&
                    entriesForPreview.isNotEmpty) {
                  unawaited(_selectEntry(entriesForPreview.first));
                }
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _buildTabBody(
                context,
                snapshot: snapshot,
                previewCandidates: entriesForPreview,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBody(
    BuildContext context, {
    required AssistantArtifactSnapshot? snapshot,
    required List<AssistantArtifactEntry> previewCandidates,
  }) {
    if (_loadError != null) {
      return _SidebarEmptyState(
        key: const Key('assistant-artifact-pane-empty'),
        icon: Icons.error_outline_rounded,
        title: appText('产物载入失败', 'Artifacts failed to load'),
        message: _loadError.toString(),
      );
    }
    if (snapshot == null && _loadingSnapshot) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot == null) {
      return _SidebarEmptyState(
        key: const Key('assistant-artifact-pane-empty'),
        icon: Icons.inbox_outlined,
        title: appText('暂无产物', 'No artifacts yet'),
        message: appText(
          '展开右侧栏后会按需加载当前线程的工作目录内容。',
          'Open the sidebar to load the current thread workspace on demand.',
        ),
      );
    }
    return switch (_activeTab) {
      AssistantArtifactSidebarTab.results => _ArtifactEntryList(
        key: const Key('assistant-artifact-tab-results'),
        entries: snapshot.resultEntries,
        emptyMessage: snapshot.resultMessage,
        onSelectEntry: _selectEntry,
        selectedEntry: _selectedEntry,
      ),
      AssistantArtifactSidebarTab.files => _ArtifactEntryList(
        key: const Key('assistant-artifact-tab-files'),
        entries: snapshot.fileEntries,
        emptyMessage: snapshot.filesMessage,
        onSelectEntry: _selectEntry,
        selectedEntry: _selectedEntry,
      ),
      AssistantArtifactSidebarTab.changes => _ArtifactChangeList(
        key: const Key('assistant-artifact-tab-changes'),
        changes: snapshot.changes,
        emptyMessage: snapshot.changesMessage,
      ),
      AssistantArtifactSidebarTab.preview => _ArtifactPreviewPanel(
        key: const Key('assistant-artifact-tab-preview'),
        entry: _selectedEntry,
        preview: _preview,
        loading: _loadingPreview,
        fallbackEntries: previewCandidates,
        onSelectEntry: _selectEntry,
      ),
    };
  }

  List<AssistantArtifactEntry> _previewCandidates(
    AssistantArtifactSnapshot? snapshot,
  ) {
    if (snapshot == null) {
      return const <AssistantArtifactEntry>[];
    }
    final seen = <String>{};
    final merged = <AssistantArtifactEntry>[
      ...snapshot.resultEntries,
      ...snapshot.fileEntries,
    ];
    return merged
        .where((item) => seen.add(item.relativePath))
        .toList(growable: false);
  }

  Future<void> _refreshSnapshot() async {
    setState(() {
      _loadingSnapshot = true;
      _loadError = null;
    });
    try {
      final snapshot = await widget.loadSnapshot();
      if (!mounted) {
        return;
      }
      final nextSelected = _reconcileSelection(
        snapshot,
        previous: _selectedEntry,
      );
      setState(() {
        _snapshot = snapshot;
        _selectedEntry = nextSelected;
        _loadingSnapshot = false;
      });
      if (_activeTab == AssistantArtifactSidebarTab.preview &&
          nextSelected != null) {
        await _loadPreview(nextSelected);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingSnapshot = false;
        _loadError = error;
      });
    }
  }

  AssistantArtifactEntry? _reconcileSelection(
    AssistantArtifactSnapshot snapshot, {
    AssistantArtifactEntry? previous,
  }) {
    final candidates = _previewCandidates(snapshot);
    if (previous == null) {
      return candidates.isEmpty ? null : candidates.first;
    }
    for (final item in candidates) {
      if (item.relativePath == previous.relativePath) {
        return item;
      }
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<void> _selectEntry(AssistantArtifactEntry entry) async {
    setState(() {
      _selectedEntry = entry;
      _activeTab = AssistantArtifactSidebarTab.preview;
    });
    await _loadPreview(entry);
  }

  Future<void> _loadPreview(AssistantArtifactEntry entry) async {
    setState(() {
      _loadingPreview = true;
      _preview = const AssistantArtifactPreview.empty();
    });
    try {
      final preview = await widget.loadPreview(entry);
      if (!mounted) {
        return;
      }
      setState(() {
        _preview = preview;
        _loadingPreview = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _preview = AssistantArtifactPreview.empty(message: error.toString());
        _loadingPreview = false;
      });
    }
  }

  String _labelForTab(AssistantArtifactSidebarTab tab) {
    return switch (tab) {
      AssistantArtifactSidebarTab.results => appText('结果', 'Results'),
      AssistantArtifactSidebarTab.files => appText('全部文件', 'All files'),
      AssistantArtifactSidebarTab.changes => appText('变更', 'Changes'),
      AssistantArtifactSidebarTab.preview => appText('预览', 'Preview'),
    };
  }

  static String _workspaceSummary(String workspaceRef, WorkspaceRefKind kind) {
    final trimmed = workspaceRef.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (kind == WorkspaceRefKind.objectStore) {
      return trimmed.replaceFirst('object://thread/', '');
    }
    final normalized = trimmed.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((item) => item.isNotEmpty)
        .toList();
    if (segments.length <= 2) {
      return normalized;
    }
    return '${segments[segments.length - 2]}/${segments.last}';
  }
}

class AssistantArtifactSidebarRevealButton extends StatelessWidget {
  const AssistantArtifactSidebarRevealButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('assistant-artifact-pane-toggle'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sidebar),
        child: Container(
          width: 44,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.chromeHighlight.withValues(alpha: 0.96),
                palette.chromeSurface,
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadius.sidebar),
            border: Border.all(
              color: palette.chromeStroke.withValues(alpha: 0.88),
              width: 0.9,
            ),
            boxShadow: [palette.chromeShadowAmbient],
          ),
          child: Icon(
            Icons.keyboard_double_arrow_left_rounded,
            size: 20,
            color: palette.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _ArtifactEntryList extends StatelessWidget {
  const _ArtifactEntryList({
    super.key,
    required this.entries,
    required this.emptyMessage,
    required this.onSelectEntry,
    required this.selectedEntry,
  });

  final List<AssistantArtifactEntry> entries;
  final String emptyMessage;
  final ValueChanged<AssistantArtifactEntry> onSelectEntry;
  final AssistantArtifactEntry? selectedEntry;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _SidebarEmptyState(
        key: const Key('assistant-artifact-pane-empty'),
        icon: Icons.folder_open_outlined,
        title: appText('暂无文件', 'No files'),
        message: emptyMessage,
      );
    }
    final palette = context.palette;
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final selected =
            selectedEntry?.relativePath == entry.relativePath &&
            selectedEntry?.workspaceRef == entry.workspaceRef;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey<String>(
              'assistant-artifact-entry-${entry.relativePath}',
            ),
            onTap: () => onSelectEntry(entry),
            borderRadius: BorderRadius.circular(AppRadius.button),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: selected
                    ? palette.accentMuted.withValues(alpha: 0.88)
                    : palette.chromeSurface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(AppRadius.button),
                border: Border.all(
                  color: selected ? palette.accent : palette.chromeStroke,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _iconForEntry(entry),
                    size: 18,
                    color: selected ? palette.accent : palette.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          entry.relativePath,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          _metaLabel(entry),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (entry.previewable)
                    Icon(
                      Icons.visibility_outlined,
                      size: 16,
                      color: palette.textMuted,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static IconData _iconForEntry(AssistantArtifactEntry entry) {
    if (entry.mimeType.startsWith('image/')) {
      return Icons.image_outlined;
    }
    if (entry.mimeType == 'text/markdown') {
      return Icons.description_outlined;
    }
    if (entry.mimeType == 'text/html') {
      return Icons.language_rounded;
    }
    return Icons.insert_drive_file_outlined;
  }

  static String _metaLabel(AssistantArtifactEntry entry) {
    final parts = <String>[
      if (entry.mimeType.trim().isNotEmpty) entry.mimeType,
      if (entry.sizeBytes != null) _formatBytes(entry.sizeBytes!),
      if (entry.updatedAtMs != null)
        _formatTimestamp(entry.updatedAtMs!.toInt()),
    ];
    return parts.join(' · ');
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _formatTimestamp(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.year}-$month-$day $hour:$minute';
  }
}

class _ArtifactChangeList extends StatelessWidget {
  const _ArtifactChangeList({
    super.key,
    required this.changes,
    required this.emptyMessage,
  });

  final List<AssistantArtifactChangeEntry> changes;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty) {
      return _SidebarEmptyState(
        key: const Key('assistant-artifact-pane-empty'),
        icon: Icons.change_circle_outlined,
        title: appText('暂无变更', 'No changes'),
        message: emptyMessage,
      );
    }
    final palette = context.palette;
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      itemCount: changes.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) {
        final change = changes[index];
        return Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: palette.chromeSurface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: palette.chromeStroke),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: palette.accentMuted,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  change.displayLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: palette.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  change.path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ArtifactPreviewPanel extends StatelessWidget {
  const _ArtifactPreviewPanel({
    super.key,
    required this.entry,
    required this.preview,
    required this.loading,
    required this.fallbackEntries,
    required this.onSelectEntry,
  });

  final AssistantArtifactEntry? entry;
  final AssistantArtifactPreview preview;
  final bool loading;
  final List<AssistantArtifactEntry> fallbackEntries;
  final ValueChanged<AssistantArtifactEntry> onSelectEntry;

  @override
  Widget build(BuildContext context) {
    final resolvedEntry = entry;
    final theme = Theme.of(context);
    final palette = context.palette;
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (resolvedEntry == null) {
      return _SidebarEmptyState(
        key: const Key('assistant-artifact-pane-empty'),
        icon: Icons.preview_outlined,
        title: appText('暂无预览对象', 'No preview target'),
        message: appText(
          '从结果或全部文件里选择一个文件后，会在这里轻量渲染。',
          'Select a file from results or all files to preview it here.',
        ),
      );
    }
    if (preview.kind == AssistantArtifactPreviewKind.empty &&
        preview.message.trim().isNotEmpty) {
      return _SidebarEmptyState(
        key: const Key('assistant-artifact-pane-empty'),
        icon: Icons.preview_outlined,
        title: resolvedEntry.label,
        message: preview.message,
      );
    }

    final body = switch (preview.kind) {
      AssistantArtifactPreviewKind.markdown => MarkdownBody(
        key: const Key('assistant-artifact-preview-markdown'),
        data: preview.content,
        selectable: true,
        extensionSet: md.ExtensionSet.gitHubWeb,
      ),
      AssistantArtifactPreviewKind.html => Html(
        key: const Key('assistant-artifact-preview-html'),
        data: preview.content,
        style: <String, Style>{
          'body': Style(
            margin: Margins.zero,
            padding: HtmlPaddings.zero,
            fontSize: FontSize(13),
            color: palette.textPrimary,
          ),
        },
      ),
      AssistantArtifactPreviewKind.text => SelectableText(
        preview.content,
        key: const Key('assistant-artifact-preview-text'),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'Menlo',
          height: 1.4,
        ),
      ),
      AssistantArtifactPreviewKind.unsupported => Column(
        key: const Key('assistant-artifact-preview-unsupported'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preview.message.trim().isEmpty
                ? appText(
                    '当前文件类型不支持轻量预览。',
                    'Lightweight preview is unavailable for this file type.',
                  )
                : preview.message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          if (fallbackEntries.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              appText('可继续查看的文件', 'Other files you can preview'),
              style: theme.textTheme.labelLarge?.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ...fallbackEntries.take(6).map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: InkWell(
                  onTap: () => onSelectEntry(item),
                  child: Text(
                    item.relativePath,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.accent,
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
      AssistantArtifactPreviewKind.empty => const SizedBox.shrink(),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            resolvedEntry.label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            resolvedEntry.relativePath,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          body,
        ],
      ),
    );
  }
}

class _SidebarEmptyState extends StatelessWidget {
  const _SidebarEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: palette.textMuted),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
