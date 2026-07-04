import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/plugins/builtin_plugin_catalog.dart';
import 'package:xworkmate/features/plugins/builtin_plugin_workflow.dart';

void main() {
  group('BuiltinPluginWorkflow model (batch 1)', () {
    test('every catalog workflow has ordered steps with unique ids', () {
      for (final plugin in BuiltinPluginCatalog.firstBatch) {
        final workflow = plugin.workflow;
        expect(workflow.steps, isNotEmpty, reason: plugin.id);
        expect(workflow.goalZh.trim(), isNotEmpty, reason: plugin.id);
        expect(workflow.goalEn.trim(), isNotEmpty, reason: plugin.id);
        expect(workflow.inputPromptZh.trim(), isNotEmpty, reason: plugin.id);
        expect(workflow.inputPromptEn.trim(), isNotEmpty, reason: plugin.id);
        final ids = workflow.steps.map((step) => step.id).toList();
        expect(ids.toSet(), hasLength(ids.length), reason: plugin.id);
        for (final step in workflow.steps) {
          expect(step.id.trim(), isNotEmpty, reason: '${plugin.id}/${step.id}');
          expect(
            step.instructionZh.trim(),
            isNotEmpty,
            reason: '${plugin.id}/${step.id}',
          );
          expect(
            step.instructionEn.trim(),
            isNotEmpty,
            reason: '${plugin.id}/${step.id}',
          );
        }
      }
    });

    test('derived outputs and skills preserve first-seen step order', () {
      final document = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.documentId,
      )!;
      expect(document.outputFormats, <String>['md', 'pdf', 'docx']);
      expect(document.requiredSkills, <String>['docx', 'pdf']);

      final spreadsheet = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.spreadsheetId,
      )!;
      expect(spreadsheet.outputFormats, <String>['csv', 'ods', 'xlsx']);
      expect(spreadsheet.requiredSkills, <String>['xlsx']);
    });

    test('presentation reconstruct step degrades instead of aborting', () {
      final presentation = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.presentationId,
      )!;
      final reconstruct = presentation.workflow.steps.firstWhere(
        (step) => step.id == 'reconstruct',
      );
      expect(reconstruct.hasFallback, isTrue);
      expect(presentation.composerTemplateZh, contains('失败降级'));
    });

    test('rendered template lists every step in order', () {
      for (final plugin in BuiltinPluginCatalog.firstBatch) {
        final rendered = plugin.composerTemplateZh;
        expect(rendered, startsWith(plugin.workflow.goalZh), reason: plugin.id);
        expect(
          rendered,
          endsWith(plugin.workflow.inputPromptZh),
          reason: plugin.id,
        );
        for (var i = 0; i < plugin.workflow.steps.length; i++) {
          expect(
            rendered,
            contains('${i + 1}. ${plugin.workflow.steps[i].instructionZh}'),
            reason: '${plugin.id}/step-$i',
          );
        }
      }
    });

    test('workflow JSON roundtrip preserves rendered templates', () {
      for (final plugin in BuiltinPluginCatalog.firstBatch) {
        final restored = BuiltinPluginWorkflow.fromJson(
          plugin.workflow.toJson(),
        );
        expect(
          restored.renderComposerTemplateZh(),
          plugin.workflow.renderComposerTemplateZh(),
          reason: plugin.id,
        );
        expect(
          restored.renderComposerTemplateEn(),
          plugin.workflow.renderComposerTemplateEn(),
          reason: plugin.id,
        );
        expect(
          restored.outputFormats,
          plugin.workflow.outputFormats,
          reason: plugin.id,
        );
        expect(
          restored.requiredSkills,
          plugin.workflow.requiredSkills,
          reason: plugin.id,
        );
      }
    });
  });
}
