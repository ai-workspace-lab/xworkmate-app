import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/ui_feature_manifest.dart';
import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';

Future<void> showMobileAssistantTargetSheet(
  BuildContext context, {
  required AppController controller,
  required Future<void> Function(AssistantExecutionTarget target) onSelected,
}) {
  final features = controller.featuresFor(UiFeaturePlatform.mobile);
  final targets = controller.visibleAssistantExecutionTargets(
    features.availableExecutionTargets,
  );
  final current = controller.currentAssistantExecutionTarget;
  return showMobileAssistantSheet(
    context,
    title: appText('运行目标', 'Execution Target'),
    children: targets
        .map(
          (target) => ListTile(
            key: Key('mobile-assistant-target-item-${target.name}'),
            leading: Icon(
              target.isGateway
                  ? Icons.cloud_queue_rounded
                  : Icons.smart_toy_outlined,
            ),
            title: Text(target.label),
            trailing: target == current
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () {
              Navigator.of(context).pop();
              unawaited(onSelected(target));
            },
          ),
        )
        .toList(growable: false),
  );
}

Future<void> showMobileAssistantProviderSheet(
  BuildContext context, {
  required AppController controller,
  required AssistantExecutionTarget target,
  required SingleAgentProvider selectedProvider,
  required Future<void> Function(SingleAgentProvider provider) onSelected,
}) {
  final providers = controller.providerCatalogForExecutionTarget(target);
  return showMobileAssistantSheet(
    context,
    title: appText('Provider', 'Provider'),
    children: providers.isEmpty
        ? [
            Padding(
              key: const Key('mobile-assistant-provider-empty-state'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Text(
                appText(
                  'Bridge 尚未提供可用 Provider。不会自动伪造默认 Provider。',
                  'Bridge has not provided any provider. No default provider is fabricated.',
                ),
              ),
            ),
          ]
        : providers
              .map(
                (provider) => ListTile(
                  key: Key(
                    'mobile-assistant-provider-item-${provider.providerId}',
                  ),
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text(mobileProviderBadgeLabel(provider)),
                  ),
                  title: Text(provider.label),
                  subtitle: provider.unavailableReason.trim().isEmpty
                      ? null
                      : Text(provider.unavailableReason),
                  enabled: provider.enabled,
                  trailing: provider == selectedProvider
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: provider.enabled
                      ? () {
                          Navigator.of(context).pop();
                          unawaited(onSelected(provider));
                        }
                      : null,
                ),
              )
              .toList(growable: false),
  );
}

Future<void> showMobileAssistantPermissionSheet(
  BuildContext context, {
  required AppController controller,
}) {
  final current = controller.assistantPermissionLevel;
  return showMobileAssistantSheet(
    context,
    title: appText('权限', 'Permissions'),
    children: AssistantPermissionLevel.values
        .map(
          (level) => ListTile(
            key: Key('mobile-assistant-permission-item-${level.name}'),
            leading: Icon(mobilePermissionIcon(level)),
            title: Text(level.label),
            trailing: level == current ? const Icon(Icons.check_rounded) : null,
            onTap: () {
              Navigator.of(context).pop();
              unawaited(controller.setAssistantPermissionLevel(level));
            },
          ),
        )
        .toList(growable: false),
  );
}

Future<void> showMobileAssistantThinkingSheet(
  BuildContext context, {
  required String value,
  required ValueChanged<String> onSelected,
}) {
  const values = <String>['low', 'medium', 'high', 'max'];
  return showMobileAssistantSheet(
    context,
    title: appText('推理强度', 'Reasoning'),
    children: values
        .map(
          (item) => ListTile(
            key: Key('mobile-assistant-thinking-item-$item'),
            leading: const Icon(Icons.psychology_alt_outlined),
            title: Text(mobileThinkingLabel(item)),
            trailing: item == value ? const Icon(Icons.check_rounded) : null,
            onTap: () {
              Navigator.of(context).pop();
              onSelected(item);
            },
          ),
        )
        .toList(growable: false),
  );
}

Future<void> showMobileAssistantSheet(
  BuildContext context, {
  required String title,
  required List<Widget> children,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 6, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('mobile-assistant-sheet-close'),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(child: ListView(shrinkWrap: true, children: children)),
            ],
          ),
        ),
      );
    },
  );
}

String mobileThinkingLabel(String value) {
  return switch (value) {
    'low' => appText('低推理', 'Low'),
    'medium' => appText('中推理', 'Medium'),
    'high' => appText('高推理', 'High'),
    'max' => appText('最大推理', 'Max'),
    _ => value,
  };
}

IconData mobilePermissionIcon(AssistantPermissionLevel level) {
  return switch (level) {
    AssistantPermissionLevel.defaultAccess => Icons.verified_user_outlined,
    AssistantPermissionLevel.fullAccess => Icons.error_outline_rounded,
  };
}

String mobileProviderBadgeLabel(SingleAgentProvider provider) {
  final badge = provider.badge.trim();
  if (badge.isNotEmpty) {
    return badge;
  }
  final label = provider.label.trim();
  return label.isEmpty ? '?' : label.characters.first;
}
