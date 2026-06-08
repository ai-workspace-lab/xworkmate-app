import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import 'workspace_provision_models.dart';

class WorkspaceManagementSteps extends StatelessWidget {
  const WorkspaceManagementSteps({super.key, required this.steps});

  final List<ProvisionStep> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('workspace-management-steps'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          appText('执行进度', 'Progress'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (final step in steps)
                _StepRow(step: step, isLast: step == steps.last),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.isLast});

  final ProvisionStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _color(theme);
    return Container(
      key: Key('workspace-management-step-${step.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, height: 24, child: _icon(color)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if ((step.message ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    step.message!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _color(ThemeData theme) {
    return switch (step.status) {
      StepStatus.success => Colors.green,
      StepStatus.failed => theme.colorScheme.error,
      StepStatus.running => theme.colorScheme.primary,
      StepStatus.skipped => theme.colorScheme.tertiary,
      StepStatus.pending => theme.colorScheme.outline,
    };
  }

  Widget _icon(Color color) {
    return switch (step.status) {
      StepStatus.running => CircularProgressIndicator(
          strokeWidth: 2,
          color: color,
        ),
      StepStatus.success => Icon(Icons.check_circle, color: color, size: 20),
      StepStatus.failed => Icon(Icons.cancel, color: color, size: 20),
      StepStatus.skipped => Icon(Icons.remove_circle, color: color, size: 20),
      StepStatus.pending => Icon(Icons.radio_button_unchecked, color: color, size: 20),
    };
  }
}
