import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';

class SettingsArchivedTasksPanel extends StatelessWidget {
  const SettingsArchivedTasksPanel({
    super.key,
    required this.sessions,
    required this.onRestore,
    required this.onDelete,
  });

  final List<GatewaySessionSummary> sessions;
  final Future<void> Function(String sessionKey) onRestore;
  final Future<void> Function(String sessionKey) onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('settings-archived-tasks-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: palette.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                appText('归档任务管理', 'Archived task management'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              appText('${sessions.length} 条', '${sessions.length} items'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sessions.isEmpty)
          _ArchivedTasksEmptyState()
        else
          Column(
            children: [
              for (final session in sessions) ...[
                _ArchivedTaskTile(
                  session: session,
                  onRestore: () => onRestore(session.key),
                  onDelete: () async {
                    final confirmed = await _confirmDelete(context, session);
                    if (confirmed) {
                      await onDelete(session.key);
                    }
                  },
                ),
                if (session != sessions.last)
                  Divider(height: 1, color: palette.strokeSoft),
              ],
            ],
          ),
      ],
    );
  }

  Future<bool> _confirmDelete(
    BuildContext context,
    GatewaySessionSummary session,
  ) async {
    final palette = context.palette;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText('彻底删除归档记录', 'Delete archived record')),
        content: Text(
          appText(
            '将从 XWorkmate 中删除「${session.label}」的任务记录、消息状态和本地线程工作目录。此操作不可撤销。',
            'This removes "${session.label}" from XWorkmate task records, message state, and the local thread workspace. This cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appText('取消', 'Cancel')),
          ),
          FilledButton.icon(
            key: const ValueKey('settings-archived-task-confirm-delete'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: palette.danger,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(appText('彻底删除', 'Delete permanently')),
          ),
        ],
      ),
    );
    if (result != true || !context.mounted) {
      return false;
    }
    return _confirmDeleteWithYes(context, session);
  }

  Future<bool> _confirmDeleteWithYes(
    BuildContext context,
    GatewaySessionSummary session,
  ) async {
    final palette = context.palette;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _DeleteYesConfirmationDialog(session: session, palette: palette),
    );
    return result ?? false;
  }
}

class _DeleteYesConfirmationDialog extends StatefulWidget {
  const _DeleteYesConfirmationDialog({
    required this.session,
    required this.palette,
  });

  final GatewaySessionSummary session;
  final AppPalette palette;

  @override
  State<_DeleteYesConfirmationDialog> createState() =>
      _DeleteYesConfirmationDialogState();
}

class _DeleteYesConfirmationDialogState
    extends State<_DeleteYesConfirmationDialog> {
  final TextEditingController _confirmationController = TextEditingController();

  bool get _confirmed => _confirmationController.text.trim() == 'Yes';

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(appText('确认彻底删除', 'Confirm permanent delete')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            appText(
              '此操作会删除「${widget.session.label}」的归档记录和任务目录。请输入 Yes 继续。',
              'This deletes "${widget.session.label}" archived records and task directory. Type Yes to continue.',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('settings-archived-task-delete-yes-input'),
            controller: _confirmationController,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: appText('输入 Yes', 'Type Yes'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(appText('取消', 'Cancel')),
        ),
        FilledButton.icon(
          key: const ValueKey('settings-archived-task-confirm-delete-yes'),
          onPressed: _confirmed ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: widget.palette.danger,
            foregroundColor: Colors.white,
            disabledBackgroundColor: widget.palette.strokeSoft,
            disabledForegroundColor: widget.palette.textMuted,
          ),
          icon: const Icon(Icons.delete_forever_outlined),
          label: Text(appText('彻底删除', 'Delete permanently')),
        ),
      ],
    );
  }
}

class _ArchivedTasksEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('settings-archived-tasks-empty'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        children: [
          Icon(Icons.archive_outlined, size: 28, color: palette.textMuted),
          const SizedBox(height: 8),
          Text(
            appText('暂无归档任务', 'No archived tasks'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchivedTaskTile extends StatelessWidget {
  const _ArchivedTaskTile({
    required this.session,
    required this.onRestore,
    required this.onDelete,
  });

  final GatewaySessionSummary session;
  final Future<void> Function() onRestore;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final preview = session.lastMessagePreview?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: palette.surfaceSecondary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.strokeSoft),
            ),
            child: Icon(
              Icons.archive_outlined,
              color: palette.textSecondary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _archivedTaskUpdatedAtLabel(session.updatedAtMs),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              FilledButton.tonalIcon(
                key: ValueKey<String>(
                  'settings-archived-task-restore-${session.key}',
                ),
                onPressed: () async {
                  await onRestore();
                },
                icon: const Icon(Icons.unarchive_outlined),
                label: Text(appText('解除归档', 'Restore')),
              ),
              IconButton(
                key: ValueKey<String>(
                  'settings-archived-task-delete-${session.key}',
                ),
                tooltip: appText('彻底删除归档记录', 'Delete archived record'),
                onPressed: () async {
                  await onDelete();
                },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _archivedTaskUpdatedAtLabel(double? updatedAtMs) {
  if (updatedAtMs == null) {
    return appText('无更新时间', 'No update time');
  }
  final timestamp = DateTime.fromMillisecondsSinceEpoch(updatedAtMs.round());
  final date =
      '${timestamp.year.toString().padLeft(4, '0')}-'
      '${timestamp.month.toString().padLeft(2, '0')}-'
      '${timestamp.day.toString().padLeft(2, '0')}';
  final time =
      '${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}';
  return appText('归档前更新于 $date $time', 'Updated before archive $date $time');
}
