import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/ui_feature_manifest.dart';
import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import 'assistant_page_composer_support.dart';

class AssistantTaskDialogModeControlsInternal extends StatelessWidget {
  const AssistantTaskDialogModeControlsInternal({
    super.key,
    required this.controller,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final uiFeatures = controller.featuresFor(
      resolveUiFeaturePlatformFromContext(context),
    );
    final supportedExecutionTargets = compactAssistantExecutionTargets(
      uiFeatures.availableExecutionTargets,
    );
    if (supportedExecutionTargets.isEmpty) {
      return const SizedBox.shrink();
    }
    final visibleExecutionTargets = controller.visibleAssistantExecutionTargets(
      supportedExecutionTargets,
    );
    final resolutionTargets = visibleExecutionTargets.isNotEmpty
        ? visibleExecutionTargets
        : supportedExecutionTargets;

    final currentExecutionTarget =
        resolveAssistantExecutionTargetFromVisibleTargets(
          resolutionTargets,
          currentTarget: controller.assistantExecutionTarget,
        );
    final executionTarget = collapseAssistantExecutionTargetForDisplay(
      currentExecutionTarget,
    );
    final providerMenuProviders = controller.providerCatalogForExecutionTarget(
      executionTarget,
    );

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _TaskDialogExecutionTargetMenuButtonInternal(
          controller: controller,
          executionTarget: executionTarget,
          supportedExecutionTargets: supportedExecutionTargets,
          visibleExecutionTargets: visibleExecutionTargets,
        ),
        _TaskDialogProviderMenuButtonInternal(
          controller: controller,
          executionTarget: executionTarget,
          selectedProvider: controller.assistantProviderForSession(
            controller.currentSessionKey,
          ),
          providers: providerMenuProviders,
        ),
      ],
    );
  }
}

class _TaskDialogExecutionTargetMenuButtonInternal extends StatelessWidget {
  const _TaskDialogExecutionTargetMenuButtonInternal({
    required this.controller,
    required this.executionTarget,
    required this.supportedExecutionTargets,
    required this.visibleExecutionTargets,
  });

  final AppController controller;
  final AssistantExecutionTarget executionTarget;
  final List<AssistantExecutionTarget> supportedExecutionTargets;
  final List<AssistantExecutionTarget> visibleExecutionTargets;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selectedLabel = executionTarget.label;

    return PopupMenuButton<AssistantExecutionTarget>(
      key: const Key('assistant-execution-target-button'),
      tooltip: appText('任务对话模式', 'Task Dialog Mode'),
      onSelected: (value) {
        unawaited(_handleExecutionTargetSelected(value));
      },
      itemBuilder: (context) => supportedExecutionTargets
          .map((value) {
            final enabled = visibleExecutionTargets.contains(value);
            return PopupMenuItem<AssistantExecutionTarget>(
              value: value,
              enabled: enabled,
              key: Key('assistant-execution-target-menu-item-${value.name}'),
              child: Row(
                children: [
                  Icon(value.icon, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(value.label)),
                  if (value == executionTarget)
                    const Icon(Icons.check_rounded, size: 18),
                ],
              ),
            );
          })
          .toList(growable: false),
      child: _TaskDialogSelectorChipInternal(
        leading: Icon(executionTarget.icon, size: 14, color: palette.textMuted),
        label: selectedLabel,
        tooltip: appText('任务对话模式', 'Task Dialog Mode'),
      ),
    );
  }

  Future<void> _handleExecutionTargetSelected(
    AssistantExecutionTarget value,
  ) async {
    final resolvedTarget = resolveAssistantExecutionTargetFromVisibleTargets(
      visibleExecutionTargets,
      currentTarget: value,
    );
    await controller.setAssistantExecutionTarget(resolvedTarget);
  }
}

class _TaskDialogProviderMenuButtonInternal extends StatelessWidget {
  const _TaskDialogProviderMenuButtonInternal({
    required this.controller,
    required this.executionTarget,
    required this.selectedProvider,
    required this.providers,
  });

  final AppController controller;
  final AssistantExecutionTarget executionTarget;
  final SingleAgentProvider selectedProvider;
  final List<SingleAgentProvider> providers;

  @override
  Widget build(BuildContext context) {
    final displayProvider = selectedProvider.isUnspecified
        ? _fallbackDisplayProvider()
        : selectedProvider;
    final isEnabled = providers.isNotEmpty;

    return PopupMenuButton<SingleAgentProvider>(
      key: const Key('assistant-provider-button'),
      enabled: isEnabled,
      tooltip: appText('智能体 Provider', 'Agent Provider'),
      onSelected: (provider) {
        unawaited(_handleProviderSelected(provider));
      },
      itemBuilder: (context) => providers
          .map(
            (provider) => PopupMenuItem<SingleAgentProvider>(
              value: provider,
              key: Key('assistant-provider-menu-item-${provider.providerId}'),
              child: Row(
                children: [
                  SingleAgentProviderBadgeInternal(
                    key: Key(
                      'assistant-provider-menu-badge-${provider.providerId}',
                    ),
                    provider: provider,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(provider.label)),
                  if (provider == displayProvider)
                    const Icon(Icons.check_rounded, size: 18),
                ],
              ),
            ),
          )
          .toList(growable: false),
      child: _TaskDialogSelectorChipInternal(
        leading: SingleAgentProviderBadgeInternal(
          key: const Key('assistant-provider-badge'),
          provider: displayProvider,
        ),
        label: displayProvider.label,
        tooltip: appText('智能体 Provider', 'Agent Provider'),
      ),
    );
  }

  SingleAgentProvider _fallbackDisplayProvider() {
    return SingleAgentProvider(
      providerId: '',
      label: appText('未提供', 'Unavailable'),
      badge: '?',
      supportedTargets: <AssistantExecutionTarget>[executionTarget],
      enabled: false,
    );
  }

  Future<void> _handleProviderSelected(SingleAgentProvider provider) async {
    if (providers.isEmpty) {
      return;
    }
    await controller.setAssistantProvider(provider);
  }
}

class _TaskDialogSelectorChipInternal extends StatelessWidget {
  const _TaskDialogSelectorChipInternal({
    required this.leading,
    required this.label,
    required this.tooltip,
  });

  final Widget leading;
  final String label;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: palette.strokeSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(width: 6),
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: palette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
