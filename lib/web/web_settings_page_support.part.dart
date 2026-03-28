part of 'web_settings_page.dart';

void _setIfDifferent(TextEditingController controller, String value) {
  if (controller.text == value) {
    return;
  }
  controller.value = controller.value.copyWith(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
    composing: TextRange.empty,
  );
}

String _themeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => appText('浅色', 'Light'),
    ThemeMode.dark => appText('深色', 'Dark'),
    ThemeMode.system => appText('跟随系统', 'System'),
  };
}

String _targetLabel(AssistantExecutionTarget target) {
  return switch (target) {
    AssistantExecutionTarget.singleAgent => appText(
      'Single Agent',
      'Single Agent',
    ),
    AssistantExecutionTarget.local => appText('Local Gateway', 'Local Gateway'),
    AssistantExecutionTarget.remote => appText(
      'Remote Gateway',
      'Remote Gateway',
    ),
  };
}

enum _StatusChipTone { idle, ready }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final _StatusChipTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final background = switch (tone) {
      _StatusChipTone.idle => palette.surfaceSecondary,
      _StatusChipTone.ready => palette.accent.withValues(alpha: 0.14),
    };
    final foreground = switch (tone) {
      _StatusChipTone.idle => palette.textSecondary,
      _StatusChipTone.ready => palette.accent,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
