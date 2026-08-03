import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/plugins/builtin_plugin_catalog.dart';
import 'package:xworkmate/features/plugins/builtin_plugin_input_slot.dart';
import 'package:xworkmate/features/plugins/builtin_plugin_workflow.dart';

void main() {
  group('E-commerce plugin group', () {
    test('the group axis is orthogonal to the artifact kind axis', () {
      // The whole reason the group axis exists: these plugins produce images
      // and video, so on the kind axis alone they would be indistinguishable
      // from the generic Images / Video plugins.
      final hero = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.ecommerceHeroId,
      )!;
      final generic = BuiltinPluginCatalog.byId(BuiltinPluginCatalog.imageId)!;
      expect(hero.kind, generic.kind);
      expect(hero.group, isNot(generic.group));
      expect(hero.group, BuiltinPluginGroup.ecommerce);
      expect(generic.group, BuiltinPluginGroup.general);
    });

    test('catalog exposes three e-commerce plugins with unique ids', () {
      expect(BuiltinPluginCatalog.ecommerceGroup, hasLength(3));
      final ids = BuiltinPluginCatalog.ecommerceGroup
          .map((plugin) => plugin.id)
          .toSet();
      expect(ids, {
        BuiltinPluginCatalog.ecommerceHeroId,
        BuiltinPluginCatalog.ecommerceDetailId,
        BuiltinPluginCatalog.ecommerceVideoId,
      });
    });

    test('all merges both groups and byId resolves across them', () {
      expect(
        BuiltinPluginCatalog.all,
        hasLength(
          BuiltinPluginCatalog.firstBatch.length +
              BuiltinPluginCatalog.ecommerceGroup.length,
        ),
      );
      final ids = BuiltinPluginCatalog.all
          .map((plugin) => plugin.id)
          .toList(growable: false);
      expect(ids.toSet(), hasLength(ids.length), reason: 'ids must be unique');
      for (final plugin in BuiltinPluginCatalog.all) {
        expect(BuiltinPluginCatalog.byId(plugin.id), same(plugin));
      }
    });

    test('byGroup partitions the catalog and groups keeps display order', () {
      expect(
        BuiltinPluginCatalog.byGroup(BuiltinPluginGroup.general),
        BuiltinPluginCatalog.firstBatch,
      );
      expect(
        BuiltinPluginCatalog.byGroup(BuiltinPluginGroup.ecommerce),
        BuiltinPluginCatalog.ecommerceGroup,
      );
      expect(BuiltinPluginCatalog.groups, <BuiltinPluginGroup>[
        BuiltinPluginGroup.general,
        BuiltinPluginGroup.ecommerce,
      ]);
    });

    test('every e-commerce plugin keeps the shared catalog invariants', () {
      for (final plugin in BuiltinPluginCatalog.ecommerceGroup) {
        expect(plugin.outputFormats, isNotEmpty, reason: plugin.id);
        expect(plugin.workflow.steps, isNotEmpty, reason: plugin.id);
        final stepIds = plugin.workflow.steps
            .map((step) => step.id)
            .toList(growable: false);
        expect(stepIds.toSet(), hasLength(stepIds.length), reason: plugin.id);
        expect(
          plugin.composerTemplate,
          startsWith(BuiltinPluginCatalog.contextBindingZh),
          reason: plugin.id,
        );
        expect(
          plugin.composerTemplate,
          contains('currentTaskWorkspace'),
          reason: plugin.id,
        );
      }
    });
  });

  group('Typed input slots', () {
    test('every e-commerce plugin declares slots with unique ids', () {
      for (final plugin in BuiltinPluginCatalog.ecommerceGroup) {
        expect(plugin.inputSlots, isNotEmpty, reason: plugin.id);
        final ids = plugin.inputSlots
            .map((slot) => slot.id)
            .toList(growable: false);
        expect(ids.toSet(), hasLength(ids.length), reason: plugin.id);
        for (final slot in plugin.inputSlots) {
          expect(slot.id.trim(), isNotEmpty, reason: plugin.id);
          expect(slot.roleZh.trim(), isNotEmpty, reason: '${plugin.id}/${slot.id}');
          expect(slot.roleEn.trim(), isNotEmpty, reason: '${plugin.id}/${slot.id}');
        }
      }
    });

    test('every plugin requires at least one slot so it cannot run blind', () {
      for (final plugin in BuiltinPluginCatalog.ecommerceGroup) {
        expect(
          plugin.workflow.requiredInputSlots,
          isNotEmpty,
          reason: plugin.id,
        );
      }
    });

    test('hero plugin binds each styling attribute to its own slot', () {
      final hero = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.ecommerceHeroId,
      )!;
      final byId = <String, BuiltinPluginInputSlot>{
        for (final slot in hero.inputSlots) slot.id: slot,
      };
      expect(
        byId.keys,
        containsAll(<String>[
          'product',
          'model',
          'scene',
          'lighting',
          'print',
          'colorway',
          'views',
          'ratio',
        ]),
      );
      expect(byId['product']!.required, isTrue);
      expect(byId['model']!.required, isFalse);
      expect(byId['model']!.type, BuiltinPluginSlotType.referenceImage);
      expect(byId['views']!.type, BuiltinPluginSlotType.choice);
      expect(byId['views']!.choices, isNotEmpty);
      // Multi-swatch prints and multi-colorway batches are the point.
      expect(byId['print']!.acceptsMultiple, isTrue);
      expect(byId['colorway']!.acceptsMultiple, isTrue);
    });

    test('reference slots state what to ignore, not just what to take', () {
      final hero = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.ecommerceHeroId,
      )!;
      final model = hero.inputSlots.firstWhere((slot) => slot.id == 'model');
      final printSlot = hero.inputSlots.firstWhere(
        (slot) => slot.id == 'print',
      );
      // Without a negative constraint a reference image bleeds its whole
      // content into the result — this is the failure the slot model exists
      // to prevent.
      expect(model.roleZh, contains('不要'));
      expect(printSlot.roleZh, contains('不要'));
    });

    test('slots render into the composer template with their roles', () {
      final hero = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.ecommerceHeroId,
      )!;
      final rendered = hero.composerTemplateZh;
      for (final slot in hero.inputSlots) {
        expect(rendered, contains(slot.labelZh), reason: slot.id);
        expect(rendered, contains(slot.roleZh), reason: slot.id);
      }
      expect(rendered, contains('必填'));
      expect(rendered, contains('可选'));
      // Unfilled slots must not be hallucinated into the output.
      expect(rendered, contains('未提供的条目直接忽略'));
    });

    test('choice slots render their allowed values', () {
      final hero = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.ecommerceHeroId,
      )!;
      final ratio = hero.inputSlots.firstWhere((slot) => slot.id == 'ratio');
      expect(hero.composerTemplateZh, contains(ratio.choices.join(' / ')));
    });

    test('plugins without slots render exactly as before', () {
      final document = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.documentId,
      )!;
      expect(document.inputSlots, isEmpty);
      expect(document.workflow.hasInputSlots, isFalse);
      expect(
        document.composerTemplateZh,
        endsWith(document.workflow.inputPromptZh),
      );
      expect(document.composerTemplateZh, isNot(contains('参考输入与各自的作用')));
    });

    test('slot JSON roundtrip preserves the rendered template', () {
      for (final plugin in BuiltinPluginCatalog.ecommerceGroup) {
        final restored = BuiltinPluginWorkflow.fromJson(
          plugin.workflow.toJson(),
        );
        expect(restored.inputSlots, hasLength(plugin.inputSlots.length));
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
      }
    });

    test('a v2 manifest without slots still parses', () {
      final legacy = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.ecommerceHeroId,
      )!.workflow.toJson();
      legacy.remove('inputSlots');
      final restored = BuiltinPluginWorkflow.fromJson(legacy);
      expect(restored.inputSlots, isEmpty);
      expect(restored.hasInputSlots, isFalse);
      expect(restored.steps, isNotEmpty);
    });
  });

  group('Text rendering strategy', () {
    test('detail page keeps copy out of the generated frame', () {
      final detail = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.ecommerceDetailId,
      )!;
      final backdrops = detail.workflow.steps.firstWhere(
        (step) => step.id == 'backdrops',
      );
      final textLayer = detail.workflow.steps.firstWhere(
        (step) => step.id == 'text-layer',
      );
      // Generation must not paint Chinese copy; the vector layer owns it.
      expect(backdrops.instructionZh, contains('不允许出现任何文字'));
      expect(textLayer.outputFormats, contains('svg'));
      expect(textLayer.requiredSkills, contains('image-svg-pptx-pro-skill'));
      // The vector step has to come after generation, or there is nothing to
      // composite onto.
      final stepIds = detail.workflow.steps
          .map((step) => step.id)
          .toList(growable: false);
      expect(
        stepIds.indexOf('text-layer'),
        greaterThan(stepIds.indexOf('backdrops')),
      );
      expect(
        stepIds.indexOf('compose'),
        greaterThan(stepIds.indexOf('text-layer')),
      );
    });

    test('hero plugin also overlays copy instead of painting it', () {
      final hero = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.ecommerceHeroId,
      )!;
      final copy = hero.workflow.steps.firstWhere(
        (step) => step.id == 'copy-layer',
      );
      expect(copy.requiredSkills, contains('image-svg-pptx-pro-skill'));
    });

    test('detail page fixes a page width so modules stitch seamlessly', () {
      final detail = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.ecommerceDetailId,
      )!;
      expect(detail.composerTemplateZh, contains('750px'));
      final compose = detail.workflow.steps.firstWhere(
        (step) => step.id == 'compose',
      );
      expect(compose.hasFallback, isTrue);
    });
  });

  group('Viral video remake', () {
    test('takes a source link and analyses it before generating', () {
      final video = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.ecommerceVideoId,
      )!;
      final source = video.inputSlots.firstWhere((slot) => slot.id == 'source');
      expect(source.type, BuiltinPluginSlotType.url);
      expect(source.required, isTrue);

      final stepIds = video.workflow.steps
          .map((step) => step.id)
          .toList(growable: false);
      // Ingest and beat extraction must precede any generation.
      expect(stepIds.indexOf('ingest'), lessThan(stepIds.indexOf('frames')));
      expect(
        stepIds.indexOf('beat-sheet'),
        lessThan(stepIds.indexOf('rewrite')),
      );
      expect(stepIds.indexOf('rewrite'), lessThan(stepIds.indexOf('frames')));
    });

    test('ingest degrades to a manual upload instead of guessing', () {
      final video = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.ecommerceVideoId,
      )!;
      final ingest = video.workflow.steps.firstWhere(
        (step) => step.id == 'ingest',
      );
      expect(ingest.hasFallback, isTrue);
      expect(ingest.retryable, isTrue);
      expect(ingest.requiredSkills, contains('video-understanding'));
    });

    test('reproduces structure, never the source footage or audio', () {
      final video = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.ecommerceVideoId,
      )!;
      final rendered = video.composerTemplateZh;
      expect(rendered, contains('不得复制其画面内容或音轨'));
      expect(rendered, contains('不要照搬原片台词'));
      expect(rendered, contains('不要使用原片音轨'));
    });
  });
}
