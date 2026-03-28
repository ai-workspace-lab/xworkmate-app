part of 'web_focus_panel.dart';

class _AssistantFocusEmptyState extends StatelessWidget {
  const _AssistantFocusEmptyState({
    required this.message,
    required this.available,
    required this.onAdd,
  });

  final String message;
  final List<AssistantFocusEntry> available;
  final Future<void> Function(AssistantFocusEntry destination) onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surfaceSecondary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
              height: 1.35,
            ),
          ),
        ),
        if (available.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: available
                .map(
                  (destination) => ActionChip(
                    key: ValueKey<String>(
                      'assistant-focus-add-${destination.name}',
                    ),
                    avatar: Icon(destination.icon, size: 16),
                    label: Text(destination.label),
                    onPressed: () async {
                      await onAdd(destination);
                    },
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}
