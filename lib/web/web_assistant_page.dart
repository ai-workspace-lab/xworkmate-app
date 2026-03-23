import 'package:flutter/material.dart';

import '../app/app_controller_web.dart';
import '../app/ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../widgets/desktop_workspace_scaffold.dart';
import '../widgets/status_badge.dart';
import '../widgets/surface_card.dart';
import '../widgets/top_bar.dart';

class WebAssistantPage extends StatefulWidget {
  const WebAssistantPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebAssistantPage> createState() => _WebAssistantPageState();
}

class _WebAssistantPageState extends State<WebAssistantPage> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _query = '';

  @override
  void dispose() {
    _inputController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final uiFeatures = controller.featuresFor(UiFeaturePlatform.web);
        final allDirect = controller.conversationsForTarget(
          AssistantExecutionTarget.singleAgent,
        );
        final allRelay = controller.conversationsForTarget(
          AssistantExecutionTarget.remote,
        );
        final direct = _filterConversations(allDirect);
        final relay = _filterConversations(allRelay);
        final currentTarget = controller.assistantExecutionTarget;
        final availableTargets = uiFeatures.availableExecutionTargets
            .where(
              (target) =>
                  target == AssistantExecutionTarget.singleAgent ||
                  target == AssistantExecutionTarget.remote,
            )
            .toList(growable: false);
        final connected =
            currentTarget == AssistantExecutionTarget.singleAgent
            ? controller.canUseAiGatewayConversation
            : controller.connection.status == RuntimeConnectionStatus.connected;
        final currentMessages = controller.chatMessages;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });

        return DesktopWorkspaceScaffold(
          breadcrumbs: <AppBreadcrumbItem>[
            AppBreadcrumbItem(
              label: appText('主页', 'Home'),
              icon: Icons.home_rounded,
              onTap: controller.navigateHome,
            ),
            AppBreadcrumbItem(label: WorkspaceDestination.assistant.label),
          ],
          eyebrow: appText('Web Workspace', 'Web Workspace'),
          title: appText('助手', 'Assistant'),
          subtitle: appText(
            '单机智能体与 Relay Gateway 共用一个入口，左侧保留会话/任务历史。',
            'Use one Assistant surface for Single Agent and Relay Gateway, with embedded conversation history on the left.',
          ),
          toolbar: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => controller.createConversation(
                  target: controller.assistantExecutionTarget,
                ),
                icon: const Icon(Icons.edit_square),
                label: Text(appText('新对话', 'New conversation')),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    controller.openSettings(tab: SettingsTab.gateway),
                icon: const Icon(Icons.tune_rounded),
                label: Text(appText('连接设置', 'Connection settings')),
              ),
              _TargetChip(
                targets: availableTargets,
                value: currentTarget,
                onChanged: (value) {
                  if (value != null) {
                    controller.setAssistantExecutionTarget(value);
                  }
                },
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final vertical = constraints.maxWidth < 980;
              final rail = _ConversationRail(
                controller: controller,
                query: _query,
                searchController: _searchController,
                onQueryChanged: (value) {
                  setState(() => _query = value.trim().toLowerCase());
                },
                onClearQuery: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                showDirect: uiFeatures.supportsDirectAi,
                showRelay: uiFeatures.supportsRelayGateway,
                direct: direct,
                relay: relay,
              );
              final panel = _ConversationPanel(
                controller: controller,
                inputController: _inputController,
                scrollController: _scrollController,
                connected: connected,
                currentMessages: currentMessages,
              );

              if (vertical) {
                return Column(
                  children: [
                    SizedBox(height: 300, child: rail),
                    const SizedBox(height: 8),
                    Expanded(child: panel),
                  ],
                );
              }

              return Row(
                children: [
                  SizedBox(width: 320, child: rail),
                  const SizedBox(width: 8),
                  Expanded(child: panel),
                ],
              );
            },
          ),
        );
      },
    );
  }

  List<WebConversationSummary> _filterConversations(
    List<WebConversationSummary> items,
  ) {
    if (_query.isEmpty) {
      return items;
    }
    return items
        .where((item) {
          final haystack = '${item.title}\n${item.preview}'.toLowerCase();
          return haystack.contains(_query);
        })
        .toList(growable: false);
  }
}

class _ConversationRail extends StatelessWidget {
  const _ConversationRail({
    required this.controller,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.showDirect,
    required this.showRelay,
    required this.direct,
    required this.relay,
  });

  final AppController controller;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final bool showDirect;
  final bool showRelay;
  final List<WebConversationSummary> direct;
  final List<WebConversationSummary> relay;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      borderRadius: 10,
      tone: SurfaceCardTone.chrome,
      child: Column(
        key: const Key('assistant-task-rail'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              hintText: appText('搜索会话', 'Search conversations'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: onClearQuery,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                if (showDirect)
                  _ConversationGroup(
                    title: appText('Single Agent', 'Single Agent'),
                    icon: Icons.hub_rounded,
                    items: direct,
                    emptyLabel: appText(
                      '还没有单机智能体对话',
                      'No Single Agent conversations yet',
                    ),
                    onSelect: controller.switchConversation,
                  ),
                if (showDirect && showRelay) const SizedBox(height: 12),
                if (showRelay)
                  _ConversationGroup(
                    title: appText(
                      'Relay OpenClaw Gateway',
                      'Relay OpenClaw Gateway',
                    ),
                    icon: Icons.cloud_outlined,
                    items: relay,
                    emptyLabel: appText(
                      '还没有 Relay 对话',
                      'No Relay conversations yet',
                    ),
                    onSelect: controller.switchConversation,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationGroup extends StatelessWidget {
  const _ConversationGroup({
    required this.title,
    required this.icon,
    required this.items,
    required this.emptyLabel,
    required this.onSelect,
  });

  final String title;
  final IconData icon;
  final List<WebConversationSummary> items;
  final String emptyLabel;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: palette.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text(
            emptyLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SurfaceCard(
              onTap: () => onSelect(item.sessionKey),
              borderRadius: 10,
              padding: const EdgeInsets.all(12),
              color: item.current ? palette.accentMuted : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (item.pending)
                    const Padding(
                      padding: EdgeInsets.only(left: 8, top: 2),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel({
    required this.controller,
    required this.inputController,
    required this.scrollController,
    required this.connected,
    required this.currentMessages,
  });

  final AppController controller;
  final TextEditingController inputController;
  final ScrollController scrollController;
  final bool connected;
  final List<GatewayChatMessage> currentMessages;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final currentTarget = controller.assistantExecutionTarget;
    final targetReady = currentTarget == AssistantExecutionTarget.singleAgent
        ? controller.canUseAiGatewayConversation
        : controller.connection.status == RuntimeConnectionStatus.connected;

    return Column(
      children: [
        SurfaceCard(
          borderRadius: 10,
          tone: SurfaceCardTone.chrome,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.currentConversationTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      controller.assistantConnectionTargetLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                status: StatusInfo(
                  controller.assistantConnectionStatusLabel,
                  targetReady ? StatusTone.success : StatusTone.warning,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (!connected)
          SurfaceCard(
            borderRadius: 10,
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    currentTarget == AssistantExecutionTarget.singleAgent
                        ? appText(
                            '当前单机智能体配置还不完整，请先在 Settings 中保存 AI Gateway 地址、API Key 和默认模型。',
                            'Single Agent is not ready yet. Save the AI Gateway endpoint, API key, and default model in Settings first.',
                          )
                        : appText(
                            '当前 Relay Gateway 尚未连接，请先在 Settings 中保存配置并连接。',
                            'Relay Gateway is offline. Save the relay config and connect from Settings first.',
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: () =>
                      controller.openSettings(tab: SettingsTab.gateway),
                  child: Text(appText('打开设置', 'Open settings')),
                ),
              ],
            ),
          ),
        if (!connected) const SizedBox(height: 8),
        Expanded(
          child: SurfaceCard(
            borderRadius: 10,
            padding: EdgeInsets.zero,
            tone: SurfaceCardTone.chrome,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: currentMessages.length,
                    itemBuilder: (context, index) {
                      final message = currentMessages[index];
                      return _MessageBubble(message: message);
                    },
                  ),
                ),
                Container(height: 1, color: palette.strokeSoft),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: inputController,
                              minLines: 3,
                              maxLines: 6,
                              decoration: InputDecoration(
                                hintText: appText(
                                  '输入需求、补充上下文、继续追问',
                                  'Describe the task, add context, or continue the conversation',
                                ),
                              ),
                              onSubmitted: (_) {
                                if (!connected) {
                                  return;
                                }
                                final value = inputController.text;
                                inputController.clear();
                                controller.sendMessage(value);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              currentTarget ==
                                      AssistantExecutionTarget.singleAgent
                                  ? appText(
                                      'Web 端单机智能体只保留纯网络能力，不提供本地文件和 CLI。',
                                      'Single Agent on web keeps network-only capabilities and does not expose local files or CLI.',
                                    )
                                  : appText(
                                      'Web 端 Relay 模式使用远程 OpenClaw Gateway，不区分 local / remote。',
                                      'Relay mode on web uses the remote OpenClaw Gateway and does not expose local / remote splits.',
                                    ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: connected
                                ? () {
                                    final value = inputController.text;
                                    inputController.clear();
                                    controller.sendMessage(value);
                                  }
                                : () => controller.openSettings(
                                    tab: SettingsTab.gateway,
                                  ),
                            icon: Icon(
                              connected
                                  ? Icons.arrow_upward_rounded
                                  : Icons.settings_rounded,
                            ),
                            label: Text(
                              connected
                                  ? appText('提交', 'Submit')
                                  : appText('配置', 'Configure'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final GatewayChatMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final assistant = message.role.trim().toLowerCase() == 'assistant';
    final color = message.error
        ? palette.danger.withValues(alpha: 0.14)
        : assistant
        ? palette.surfacePrimary
        : palette.accentMuted;

    return Align(
      alignment: assistant ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.strokeSoft),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assistant ? 'Assistant' : 'You',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(message.text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.targets,
    required this.value,
    required this.onChanged,
  });

  final List<AssistantExecutionTarget> targets;
  final AssistantExecutionTarget value;
  final ValueChanged<AssistantExecutionTarget?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<AssistantExecutionTarget>(
        value: value,
        onChanged: onChanged,
        items: targets
            .map((target) {
              return DropdownMenuItem<AssistantExecutionTarget>(
                value: target,
                child: Text(_targetLabel(target)),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

String _targetLabel(AssistantExecutionTarget target) {
  return switch (target) {
    AssistantExecutionTarget.singleAgent => appText(
      'Single Agent',
      'Single Agent',
    ),
    AssistantExecutionTarget.remote => appText(
      'Relay OpenClaw Gateway',
      'Relay OpenClaw Gateway',
    ),
    _ => '',
  };
}
