import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/plugins/builtin_plugin_catalog.dart';

void main() {
  group('BuiltinPluginCatalog batch 1', () {
    test('exposes the five first-batch plugins with unique ids', () {
      expect(BuiltinPluginCatalog.firstBatch, hasLength(5));
      final ids = BuiltinPluginCatalog.firstBatch
          .map((plugin) => plugin.id)
          .toSet();
      expect(ids, hasLength(5));
      expect(ids, {
        BuiltinPluginCatalog.documentId,
        BuiltinPluginCatalog.spreadsheetId,
        BuiltinPluginCatalog.presentationId,
        BuiltinPluginCatalog.imageId,
        BuiltinPluginCatalog.videoId,
      });
    });

    test('every plugin declares outputs and a non-empty composer template',
        () {
      for (final plugin in BuiltinPluginCatalog.firstBatch) {
        expect(plugin.outputFormats, isNotEmpty, reason: plugin.id);
        expect(plugin.composerTemplateZh.trim(), isNotEmpty,
            reason: plugin.id);
        expect(plugin.composerTemplateEn.trim(), isNotEmpty,
            reason: plugin.id);
      }
    });

    test('every plugin template binds to the TaskThread workspace context',
        () {
      for (final plugin in BuiltinPluginCatalog.firstBatch) {
        expect(
          plugin.composerTemplate,
          contains('TaskThread workspace context'),
          reason: plugin.id,
        );
        expect(
          plugin.composerTemplate,
          contains('currentTaskWorkspace'),
          reason: plugin.id,
        );
        expect(
          plugin.composerTemplate,
          startsWith(BuiltinPluginCatalog.contextBindingZh),
          reason: plugin.id,
        );
      }
    });

    test('document plugin exports markdown, pdf, and word', () {
      final plugin = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.documentId,
      );
      expect(plugin, isNotNull);
      expect(plugin!.outputFormats, containsAll(<String>['md', 'pdf', 'docx']));
    });

    test('spreadsheet plugin exports csv and open spreadsheet formats', () {
      final plugin = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.spreadsheetId,
      );
      expect(plugin, isNotNull);
      expect(plugin!.outputFormats, containsAll(<String>['csv', 'ods']));
    });

    test('presentation plugin depends on the pptx reconstruction skills', () {
      final plugin = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.presentationId,
      );
      expect(plugin, isNotNull);
      expect(
        plugin!.requiredSkills,
        containsAll(<String>[
          'image-svg-pptx-pro-skill',
          'xiaobei-skill-image-to-vba',
        ]),
      );
      expect(plugin.composerTemplateZh, contains('image-svg-pptx-pro-skill'));
      expect(
        plugin.composerTemplateZh,
        contains('xiaobei-skill-image-to-vba'),
      );
    });

    test('video plugin composes via hyperframe or it-infra-evolution-video-v2',
        () {
      final plugin = BuiltinPluginCatalog.byId(BuiltinPluginCatalog.videoId);
      expect(plugin, isNotNull);
      expect(
        plugin!.requiredSkills,
        containsAll(<String>['hyperframe', 'it-infra-evolution-video-v2']),
      );
      expect(plugin.composerTemplateZh, contains('hyperframe'));
      expect(
        plugin.composerTemplateZh,
        contains('it-infra-evolution-video-v2'),
      );
    });

    test('byId returns null for unknown plugins', () {
      expect(BuiltinPluginCatalog.byId('builtin.unknown'), isNull);
      expect(BuiltinPluginCatalog.byId(''), isNull);
    });
  });
}
