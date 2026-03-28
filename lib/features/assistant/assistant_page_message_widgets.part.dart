part of 'assistant_page.dart';

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.label,
    required this.text,
    required this.alignRight,
    required this.tone,
    required this.messageViewMode,
  });

  final String label;
  final String text;
  final bool alignRight;
  final _BubbleTone tone;
  final AssistantMessageViewMode messageViewMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final showLabel = !(alignRight && label == appText('你', 'You'));
    final backgroundColor = switch (tone) {
      _BubbleTone.user => palette.surfaceSecondary,
      _BubbleTone.agent => palette.surfaceTertiary.withValues(alpha: 0.78),
      _BubbleTone.assistant => palette.surfacePrimary,
    };
    final labelColor = switch (tone) {
      _BubbleTone.user => palette.textSecondary,
      _BubbleTone.agent => palette.success,
      _BubbleTone.assistant => palette.textMuted,
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showLabel) ...[
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: labelColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              _MessageBubbleBody(
                text: text.isEmpty ? appText('暂无内容。', 'No content yet.') : text,
                renderMarkdown:
                    messageViewMode == AssistantMessageViewMode.rendered &&
                    tone != _BubbleTone.user,
                compactUserMetadata: tone == _BubbleTone.user,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubbleBody extends StatefulWidget {
  const _MessageBubbleBody({
    required this.text,
    required this.renderMarkdown,
    required this.compactUserMetadata,
  });

  final String text;
  final bool renderMarkdown;
  final bool compactUserMetadata;

  @override
  State<_MessageBubbleBody> createState() => _MessageBubbleBodyState();
}

class _MessageBubbleBodyState extends State<_MessageBubbleBody> {
  bool _attachmentsExpanded = false;
  bool _executionContextExpanded = false;
  bool _hovered = false;

  @override
  void didUpdateWidget(covariant _MessageBubbleBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _attachmentsExpanded = false;
      _executionContextExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final messageBodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.5,
    );
    if (!widget.renderMarkdown) {
      final parsed = _PromptDebugSnapshot.fromMessage(widget.text);
      final canCompactMetadata =
          widget.compactUserMetadata &&
          (parsed.attachmentsBlock != null ||
              parsed.executionContextBlock != null);
      if (!canCompactMetadata) {
        return SelectableText(widget.text, style: messageBodyStyle);
      }

      final bodyText = parsed.bodyText.trim().isEmpty
          ? appText('暂无内容。', 'No content yet.')
          : parsed.bodyText;
      final showAttachments =
          _attachmentsExpanded && parsed.attachmentsBlock != null;
      final showExecutionContext =
          _executionContextExpanded && parsed.executionContextBlock != null;
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(bodyText, style: messageBodyStyle),
          if (_hovered || showAttachments || showExecutionContext) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (parsed.attachmentsBlock != null)
                  _MessageMetaToggleButton(
                    key: const Key('assistant-user-meta-attachments-toggle'),
                    icon: Icons.attach_file_rounded,
                    expanded: _attachmentsExpanded,
                    tooltip: _attachmentsExpanded
                        ? appText('折叠附件信息', 'Collapse attached files')
                        : appText('展开附件信息', 'Expand attached files'),
                    onTap: () {
                      setState(() {
                        _attachmentsExpanded = !_attachmentsExpanded;
                      });
                    },
                  ),
                if (parsed.executionContextBlock != null)
                  _MessageMetaToggleButton(
                    key: const Key('assistant-user-meta-context-toggle'),
                    icon: Icons.tune_rounded,
                    expanded: _executionContextExpanded,
                    tooltip: _executionContextExpanded
                        ? appText('折叠执行上下文', 'Collapse execution context')
                        : appText('展开执行上下文', 'Expand execution context'),
                    onTap: () {
                      setState(() {
                        _executionContextExpanded = !_executionContextExpanded;
                      });
                    },
                  ),
              ],
            ),
          ],
          if (showAttachments) ...[
            const SizedBox(height: 6),
            _MessageMetaBlock(
              key: const Key('assistant-user-meta-attachments-block'),
              content: parsed.attachmentsBlock!,
            ),
          ],
          if (showExecutionContext) ...[
            const SizedBox(height: 6),
            _MessageMetaBlock(
              key: const Key('assistant-user-meta-context-block'),
              content: parsed.executionContextBlock!,
            ),
          ],
        ],
      );

      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: content,
      );
    }

    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: messageBodyStyle?.copyWith(height: 1.55),
      h1: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      h2: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      h3: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      code: theme.textTheme.bodyMedium?.copyWith(
        fontFamily: 'Menlo',
        height: 1.4,
      ),
      codeblockDecoration: BoxDecoration(
        color: context.palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      blockquoteDecoration: BoxDecoration(
        color: context.palette.surfaceSecondary.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      tableBorder: TableBorder.all(color: context.palette.strokeSoft),
      tableHead: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );

    return MarkdownBody(
      data: widget.text,
      selectable: true,
      styleSheet: styleSheet,
      extensionSet: md.ExtensionSet.gitHubWeb,
      sizedImageBuilder: (config) => SelectableText(
        config.alt?.trim().isNotEmpty == true
            ? '![${config.alt!.trim()}](${config.uri.toString()})'
            : config.uri.toString(),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: context.palette.textSecondary,
          height: 1.4,
        ),
      ),
      onTapLink: (text, href, title) {},
    );
  }
}

class _PromptDebugSnapshot {
  const _PromptDebugSnapshot({
    required this.bodyText,
    this.attachmentsBlock,
    this.executionContextBlock,
  });

  final String bodyText;
  final String? attachmentsBlock;
  final String? executionContextBlock;

  static _PromptDebugSnapshot fromMessage(String text) {
    var cursor = 0;
    String? attachments;
    String? preferredSkills;
    String? executionContext;

    void skipLeadingNewlines() {
      while (cursor < text.length && text[cursor] == '\n') {
        cursor++;
      }
    }

    String? consumeBlock(String heading) {
      final prefix = '$heading:\n';
      if (!text.startsWith(prefix, cursor)) {
        return null;
      }
      final blockStart = cursor;
      final divider = text.indexOf('\n\n', blockStart);
      if (divider == -1) {
        cursor = text.length;
        return text.substring(blockStart).trimRight();
      }
      cursor = divider + 2;
      return text.substring(blockStart, divider).trimRight();
    }

    while (cursor < text.length) {
      skipLeadingNewlines();
      final attachmentBlock = consumeBlock('Attached files');
      if (attachmentBlock != null) {
        attachments = attachmentBlock;
        continue;
      }
      final skillBlock = consumeBlock('Preferred skills');
      if (skillBlock != null) {
        preferredSkills = skillBlock;
        continue;
      }
      final executionBlock = consumeBlock('Execution context');
      if (executionBlock != null) {
        executionContext = executionBlock;
        continue;
      }
      break;
    }

    final remainder = text.substring(cursor).trimLeft();
    final executionContextParts = <String>[?preferredSkills, ?executionContext];

    return _PromptDebugSnapshot(
      bodyText: remainder.trim(),
      attachmentsBlock: attachments,
      executionContextBlock: executionContextParts.isEmpty
          ? null
          : executionContextParts.join('\n\n'),
    );
  }
}

class _MessageMetaToggleButton extends StatelessWidget {
  const _MessageMetaToggleButton({
    super.key,
    required this.icon,
    required this.expanded,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool expanded;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final iconColor = expanded ? palette.accent : palette.textMuted;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: expanded
                ? palette.surfaceSecondary
                : palette.surfacePrimary.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: expanded
                  ? palette.accent.withValues(alpha: 0.34)
                  : palette.strokeSoft,
            ),
          ),
          child: Icon(icon, size: 12, color: iconColor),
        ),
      ),
    );
  }
}

class _MessageMetaBlock extends StatelessWidget {
  const _MessageMetaBlock({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: SelectableText(
        content,
        style: theme.textTheme.bodySmall?.copyWith(
          color: palette.textSecondary,
          height: 1.35,
        ),
      ),
    );
  }
}

class _ToolCallTile extends StatefulWidget {
  const _ToolCallTile({
    required this.toolName,
    required this.summary,
    required this.pending,
    required this.error,
    required this.onOpenDetail,
  });

  final String toolName;
  final String summary;
  final bool pending;
  final bool error;
  final VoidCallback onOpenDetail;

  @override
  State<_ToolCallTile> createState() => _ToolCallTileState();
}

class _ToolCallTileState extends State<_ToolCallTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final statusLabel = widget.pending
        ? 'running'
        : (widget.error ? 'error' : 'completed');
    final statusStyle = _pillStyleForStatus(context, statusLabel);
    final collapsedSummary = widget.summary.trim().isEmpty
        ? appText('工具调用进行中。', 'Tool call in progress.')
        : widget.summary.trim().replaceAll('\n', ' ');

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surfaceSecondary.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.card),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: statusStyle.foregroundColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.textSecondary,
                            ),
                            children: [
                              TextSpan(
                                text: widget.toolName,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const TextSpan(text: '  '),
                              TextSpan(text: collapsedSummary),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusPill(
                        label: _toolCallStatusLabel(statusLabel),
                        backgroundColor: statusStyle.backgroundColor,
                        textColor: statusStyle.foregroundColor,
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: palette.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  child: _expanded
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.sm,
                            0,
                            AppSpacing.sm,
                            AppSpacing.xs,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Divider(height: 1, color: palette.strokeSoft),
                              const SizedBox(height: 6),
                              Text(
                                widget.summary.trim().isEmpty
                                    ? appText(
                                        '工具调用进行中。',
                                        'Tool call in progress.',
                                      )
                                    : widget.summary.trim(),
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              TextButton(
                                onPressed: widget.onOpenDetail,
                                child: Text(appText('打开详情', 'Open detail')),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    this.backgroundColor,
    this.textColor,
  });

  final String label;
  final Color? backgroundColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            backgroundColor ??
            Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.badge),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: textColor),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectionState = controller.currentAssistantConnectionState;
    final color = connectionState.isSingleAgent
        ? (connectionState.connected
              ? context.palette.accentMuted
              : context.palette.surfaceSecondary)
        : switch (connectionState.status) {
            RuntimeConnectionStatus.connected => context.palette.accentMuted,
            RuntimeConnectionStatus.connecting =>
              context.palette.surfaceSecondary,
            RuntimeConnectionStatus.error => context.palette.danger.withValues(
              alpha: 0.10,
            ),
            RuntimeConnectionStatus.offline => context.palette.surfaceSecondary,
          };

    return Container(
      key: const Key('assistant-connection-chip'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      child: Text(
        '${controller.assistantConnectionStatusLabel} · ${controller.assistantConnectionTargetLabel}',
        style: theme.textTheme.labelMedium,
      ),
    );
  }
}

class _MessageViewModeChip extends StatelessWidget {
  const _MessageViewModeChip({required this.value, required this.onSelected});

  final AssistantMessageViewMode value;
  final Future<void> Function(AssistantMessageViewMode mode) onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return PopupMenuButton<AssistantMessageViewMode>(
      key: const Key('assistant-message-view-mode-button'),
      tooltip: appText('消息视图', 'Message view'),
      onSelected: (mode) => unawaited(onSelected(mode)),
      itemBuilder: (context) => AssistantMessageViewMode.values
          .map(
            (mode) => PopupMenuItem<AssistantMessageViewMode>(
              value: mode,
              child: Row(
                children: [
                  Expanded(child: Text(mode.label)),
                  if (mode == value) const Icon(Icons.check_rounded, size: 18),
                ],
              ),
            ),
          )
          .toList(growable: false),
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
            Icon(Icons.notes_rounded, size: 14, color: palette.textMuted),
            const SizedBox(width: 4),
            Text(value.label, style: theme.textTheme.labelMedium),
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
