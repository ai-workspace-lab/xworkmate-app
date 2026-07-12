/// Pure parsing for composed assistant prompts.
///
/// A composed prompt is a sequence of leading structured blocks
/// (`Attached files:`, `Preferred skills:`, `Execution context:`,
/// `Builtin plugins:`) followed by the user's actual request body. This parser
/// splits the two so the request body can be surfaced on its own — both for UI
/// display (collapse the structured blocks behind the meta toggle) and for the
/// gateway task prompt (hoist the blocks out so they sit as siblings of the
/// TaskThread workspace context instead of being buried under `User request:`).
///
/// Kept dependency-free (no Flutter imports) so both the UI layer and the app
/// controller can use it without an import cycle.
class PromptDebugSnapshotInternal {
  const PromptDebugSnapshotInternal({
    required this.bodyText,
    this.attachmentsBlock,
    this.executionContextBlock,
  });

  final String bodyText;
  final String? attachmentsBlock;
  final String? executionContextBlock;

  static PromptDebugSnapshotInternal fromMessage(String text) {
    var cursor = 0;
    String? attachments;
    String? preferredSkills;
    String? executionContext;
    String? builtinPlugins;

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
      final builtinPluginsBlock = consumeBlock('Builtin plugins');
      if (builtinPluginsBlock != null) {
        builtinPlugins = builtinPluginsBlock;
        continue;
      }
      break;
    }

    final remainder = text.substring(cursor).trimLeft();
    final executionContextParts = <String>[
      ?preferredSkills,
      ?executionContext,
      ?builtinPlugins,
    ];

    return PromptDebugSnapshotInternal(
      bodyText: remainder.trim(),
      attachmentsBlock: attachments,
      executionContextBlock: executionContextParts.isEmpty
          ? null
          : executionContextParts.join('\n\n'),
    );
  }
}
