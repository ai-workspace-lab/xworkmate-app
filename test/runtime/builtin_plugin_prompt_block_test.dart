import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/assistant_page_message_widgets.dart';
import 'package:xworkmate/features/plugins/builtin_plugin_catalog.dart';

void main() {
  group('Builtin plugins prompt block', () {
    test('plugin templates contain no blank lines that would split the block',
        () {
      for (final plugin in BuiltinPluginCatalog.firstBatch) {
        expect(
          plugin.composerTemplate.contains('\n\n'),
          isFalse,
          reason: '${plugin.id} template must stay a single prompt block',
        );
      }
    });

    test('message renderer hides the Builtin plugins block from the body', () {
      final plugin = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.spreadsheetId,
      )!;
      final message =
          'Execution context:\n'
          '- target: gateway\n'
          '- permission: default\n'
          '\n'
          'Builtin plugins:\n${plugin.composerTemplate}\n'
          '\n'
          '整理本季度销售数据';
      final snapshot = PromptDebugSnapshotInternal.fromMessage(message);
      expect(snapshot.bodyText, '整理本季度销售数据');
      expect(snapshot.executionContextBlock, contains('Builtin plugins:'));
      expect(
        snapshot.executionContextBlock,
        contains(BuiltinPluginCatalog.contextBindingZh),
      );
    });

    test('renderer keeps plain prompts without plugin blocks untouched', () {
      final snapshot = PromptDebugSnapshotInternal.fromMessage('普通消息内容');
      expect(snapshot.bodyText, '普通消息内容');
      expect(snapshot.executionContextBlock, isNull);
    });
  });
}
