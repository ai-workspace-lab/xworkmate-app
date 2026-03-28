part of 'web_assistant_page.dart';

class _ChromePill extends StatelessWidget {
  const _ChromePill({
    this.icon,
    required this.label,
    this.emphasized = false,
    this.compact = false,
  });

  final IconData? icon;
  final String label;
  final bool emphasized;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: emphasized ? palette.surfacePrimary : palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderDropdownShell extends StatelessWidget {
  const _HeaderDropdownShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.palette.surfacePrimary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      child: child,
    );
  }
}

class _SessionSettingField extends StatelessWidget {
  const _SessionSettingField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.palette.surfacePrimary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: context.palette.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _CompactDropdown<T> extends StatelessWidget {
  const _CompactDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T item) labelBuilder;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: items.contains(value) ? value : items.first,
        onChanged: onChanged,
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: Text(labelBuilder(item)),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _WebComposerAttachment {
  const _WebComposerAttachment({
    required this.file,
    required this.name,
    required this.mimeType,
    required this.icon,
  });

  final XFile file;
  final String name;
  final String mimeType;
  final IconData icon;

  factory _WebComposerAttachment.fromXFile(XFile file) {
    final extension = file.name.split('.').last.toLowerCase();
    final mimeType = file.mimeType?.trim().isNotEmpty == true
        ? file.mimeType!.trim()
        : switch (extension) {
            'png' => 'image/png',
            'jpg' || 'jpeg' => 'image/jpeg',
            'gif' => 'image/gif',
            'webp' => 'image/webp',
            'json' => 'application/json',
            'csv' => 'text/csv',
            'txt' || 'log' || 'md' || 'yaml' || 'yml' => 'text/plain',
            'pdf' => 'application/pdf',
            _ => 'application/octet-stream',
          };
    final icon = mimeType.startsWith('image/')
        ? Icons.image_outlined
        : mimeType == 'application/pdf'
        ? Icons.picture_as_pdf_outlined
        : Icons.insert_drive_file_outlined;
    return _WebComposerAttachment(
      file: file,
      name: file.name,
      mimeType: mimeType,
      icon: icon,
    );
  }
}

List<WebConversationSummary> _filterConversations(
  List<WebConversationSummary> items,
  String query,
) {
  if (query.trim().isEmpty) {
    return items;
  }
  final normalized = query.trim().toLowerCase();
  return items
      .where((item) {
        final haystack = '${item.title}\n${item.preview}'.toLowerCase();
        return haystack.contains(normalized);
      })
      .toList(growable: false);
}

String _relativeTimeLabel(double updatedAtMs) {
  final delta = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(updatedAtMs.round()),
  );
  if (delta.inMinutes < 1) {
    return appText('刚刚', 'now');
  }
  if (delta.inHours < 1) {
    return '${delta.inMinutes}m';
  }
  if (delta.inDays < 1) {
    return '${delta.inHours}h';
  }
  return '${delta.inDays}d';
}

String _thinkingLabel(String level) {
  return switch (level) {
    'low' => appText('低', 'Low'),
    'medium' => appText('中', 'Medium'),
    'high' => appText('高', 'High'),
    _ => level,
  };
}

String _targetLabel(AssistantExecutionTarget target) {
  return switch (target) {
    AssistantExecutionTarget.singleAgent => appText('单机智能体', 'Single Agent'),
    AssistantExecutionTarget.local => appText(
      '本地 OpenClaw Gateway',
      'Local Gateway',
    ),
    AssistantExecutionTarget.remote => appText(
      '远程 OpenClaw Gateway',
      'Remote Gateway',
    ),
  };
}
