import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import 'builtin_plugin_input_slot.dart';
import 'builtin_plugin_runtime.dart';
import 'builtin_plugin_workflow.dart';

/// First-batch built-in plugin kinds.
///
/// See docs/plans/2026-07-04-builtin-plugins-batch-1.md for the full plan.
enum BuiltinPluginKind { document, spreadsheet, presentation, image, video }

/// Business grouping of the catalog — a second axis, orthogonal to
/// [BuiltinPluginKind].
///
/// [BuiltinPluginKind] answers "what artifact comes out" (a deck, an image, a
/// video). That axis alone cannot host a scenario pack: the three e-commerce
/// plugins produce images and video, so on the kind axis they would collide
/// with the generic Images and Video plugins. The group axis answers "which
/// job is this for", letting a scenario ship as a coherent set.
///
/// See docs/plans/2026-08-03-ecommerce-plugin-group.md.
enum BuiltinPluginGroup { general, ecommerce }

extension BuiltinPluginGroupCopy on BuiltinPluginGroup {
  String get label => switch (this) {
    BuiltinPluginGroup.general => appText('通用', 'General'),
    BuiltinPluginGroup.ecommerce => appText('电商', 'E-commerce'),
  };

  String get descriptionZh => switch (this) {
    BuiltinPluginGroup.general => '把对话内容转成文档、表格、幻灯片、图片与视频。',
    BuiltinPluginGroup.ecommerce => '商品素材生产：头图、详情页与短视频，支持多参考图指定。',
  };

  String get descriptionEn => switch (this) {
    BuiltinPluginGroup.general =>
      'Turn conversations into documents, sheets, decks, images, and video.',
    BuiltinPluginGroup.ecommerce =>
      'Product asset production: hero images, detail pages, and short video, '
          'driven by typed reference images.',
  };

  String get description => appText(descriptionZh, descriptionEn);
}

/// Rollout status of a built-in plugin.
enum BuiltinPluginStatus { preview, beta, stable }

extension BuiltinPluginStatusCopy on BuiltinPluginStatus {
  String get label => switch (this) {
    BuiltinPluginStatus.preview => appText('预览', 'Preview'),
    BuiltinPluginStatus.beta => appText('测试', 'Beta'),
    BuiltinPluginStatus.stable => appText('稳定', 'Stable'),
  };
}

/// Static descriptor for a built-in plugin.
///
/// Built-in plugins are not a new execution channel. Each descriptor wraps a
/// [BuiltinPluginWorkflow] — a lightweight linear state machine whose steps
/// carry per-step instructions, outputs, skill dependencies, and failure
/// fallbacks (plan §8.1, batch 1). The composer template, output formats,
/// pipeline list, and skill dependencies are all derived from the workflow,
/// so the workflow definition is the single source of truth. Selecting a
/// plugin in the composer inserts the rendered template into the input;
/// generated files flow back through the existing artifact sidebar for
/// preview and follow-up edits.
@immutable
class BuiltinPluginDescriptor {
  const BuiltinPluginDescriptor({
    required this.id,
    required this.kind,
    required this.icon,
    required this.nameZh,
    required this.nameEn,
    required this.descriptionZh,
    required this.descriptionEn,
    required this.workflow,
    this.group = BuiltinPluginGroup.general,
    this.runtime = BuiltinPluginRuntimeBinding.builtinDart,
    this.status = BuiltinPluginStatus.preview,
  });

  final String id;
  final BuiltinPluginKind kind;

  /// Which scenario pack this plugin belongs to.
  final BuiltinPluginGroup group;
  final IconData icon;
  final String nameZh;
  final String nameEn;
  final String descriptionZh;
  final String descriptionEn;

  /// The plugin's workflow state machine — single source of truth for the
  /// composer template, output formats, pipeline list, and skill deps.
  final BuiltinPluginWorkflow workflow;

  /// Where this plugin's definition comes from (plan §8.4). First-batch
  /// plugins are compiled-in Dart; manifest / FFI / sidecar runtimes let
  /// third-party plugins written in other languages plug into the same
  /// catalog without an app release.
  final BuiltinPluginRuntimeBinding runtime;

  final BuiltinPluginStatus status;

  String get name => appText(nameZh, nameEn);

  String get description => appText(descriptionZh, descriptionEn);

  /// Output file formats, derived from workflow steps (first-seen order).
  List<String> get outputFormats => workflow.outputFormats;

  /// Skill packages / plugins this pipeline depends on (gateway workspace).
  List<String> get requiredSkills => workflow.requiredSkills;

  /// Typed inputs this plugin declares (reference images, copy, choices).
  List<BuiltinPluginInputSlot> get inputSlots => workflow.inputSlots;

  /// Human-readable pipeline steps, surfaced in the settings plugins panel.
  List<String> get pipelineStepsZh => workflow.pipelineTitlesZh;

  /// Composer text rendered from the workflow, without the context binding.
  String get composerTemplateZh => workflow.renderComposerTemplateZh();
  String get composerTemplateEn => workflow.renderComposerTemplateEn();

  /// Composer text with the shared TaskThread context binding prepended, so
  /// every plugin automatically anchors to the conversation thread and its
  /// task workspace (see [BuiltinPluginCatalog.contextBindingZh]).
  String get composerTemplate => appText(
        '${BuiltinPluginCatalog.contextBindingZh}\n$composerTemplateZh',
        '${BuiltinPluginCatalog.contextBindingEn}\n$composerTemplateEn',
      );

  String get formatSummary =>
      outputFormats.map((format) => format.toUpperCase()).join(' / ');
}

/// Catalog of the first batch of built-in plugins.
abstract final class BuiltinPluginCatalog {
  /// Shared context binding prepended to every plugin's composer template.
  ///
  /// Every dispatched task is wrapped with a `TaskThread workspace context:`
  /// block (sessionKey + currentTaskWorkspace, injected by
  /// `taskWorkspaceContextPromptInternal`). This line tells the agent to use
  /// that block: read this thread's conversation as the source material and
  /// write all plugin outputs into `currentTaskWorkspace` instead of guessing
  /// a directory.
  static const String contextBindingZh =
      '基于当前任务线程执行：以本线程对话上下文为素材来源；'
      '随任务自动下发的 TaskThread workspace context 中的 '
      'currentTaskWorkspace 即产物输出目录。';
  static const String contextBindingEn =
      'Run against the current task thread: use this thread\'s conversation '
      'as the source material, and write all outputs into the '
      'currentTaskWorkspace given by the auto-injected TaskThread workspace '
      'context.';

  static const String documentId = 'builtin.document';
  static const String spreadsheetId = 'builtin.spreadsheet';
  static const String presentationId = 'builtin.presentation';
  static const String imageId = 'builtin.image';
  static const String videoId = 'builtin.video';

  static const String ecommerceHeroId = 'builtin.ecommerce.hero';
  static const String ecommerceDetailId = 'builtin.ecommerce.detail';
  static const String ecommerceVideoId = 'builtin.ecommerce.video';

  static const List<BuiltinPluginDescriptor> firstBatch =
      <BuiltinPluginDescriptor>[
        BuiltinPluginDescriptor(
          id: documentId,
          kind: BuiltinPluginKind.document,
          icon: Icons.description_outlined,
          nameZh: '文档',
          nameEn: 'Documents',
          descriptionZh: '将任意对话内容整理为可编辑文档，同步导出 Markdown、PDF 与 Word。',
          descriptionEn:
              'Turn any conversation into an editable document, exported as '
              'Markdown, PDF, and Word.',
          workflow: BuiltinPluginWorkflow(
            goalZh: '请将本次对话的关键内容整理成一份可编辑文档：',
            goalEn:
                'Turn the key content of this conversation into an editable '
                'document:',
            inputPromptZh: '主题与补充要求：',
            inputPromptEn: 'Topic and extra requirements:',
            steps: <BuiltinPluginWorkflowStep>[
              BuiltinPluginWorkflowStep(
                id: 'outline',
                titleZh: '整理对话内容为结构化大纲',
                titleEn: 'Organize the conversation into a structured outline',
                instructionZh: '先给出结构化大纲（标题、章节、要点）',
                instructionEn:
                    'produce a structured outline first (title, sections, '
                    'key points)',
              ),
              BuiltinPluginWorkflowStep(
                id: 'markdown',
                titleZh: '生成 Markdown 源文件',
                titleEn: 'Generate the Markdown source file',
                instructionZh: '产出 Markdown 源文件（.md）',
                instructionEn: 'produce a Markdown source file (.md)',
                outputFormats: <String>['md'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'export',
                titleZh: '调用 docx / pdf 技能包导出 Word 与 PDF',
                titleEn: 'Export Word and PDF via the docx / pdf skills',
                instructionZh: '调用 docx 与 pdf 技能包导出 PDF 与 Word (.docx) 两个版本',
                instructionEn:
                    'invoke the docx and pdf skill packages to export PDF '
                    'and Word (.docx) versions',
                outputFormats: <String>['pdf', 'docx'],
                requiredSkills: <String>['docx', 'pdf'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'preview',
                titleZh: '右侧边栏预览，可继续对话修改',
                titleEn: 'Preview in the sidebar, iterate via conversation',
                instructionZh: '文件生成后在右侧边栏提供预览，后续我会继续提出修改',
                instructionEn:
                    'surface files in the artifact sidebar for preview and '
                    'follow-up edits',
              ),
            ],
          ),
        ),
        BuiltinPluginDescriptor(
          id: spreadsheetId,
          kind: BuiltinPluginKind.spreadsheet,
          icon: Icons.table_chart_outlined,
          nameZh: '电子表格',
          nameEn: 'Spreadsheets',
          descriptionZh: '将任意对话内容结构化为可编辑表格，导出 CSV 与开放电子表格格式。',
          descriptionEn:
              'Structure any conversation into an editable spreadsheet, '
              'exported as CSV and open spreadsheet formats.',
          workflow: BuiltinPluginWorkflow(
            goalZh: '请将本次对话中的数据整理成可编辑电子表格：',
            goalEn:
                'Organize the data in this conversation into an editable '
                'spreadsheet:',
            inputPromptZh: '数据范围与补充要求：',
            inputPromptEn: 'Data scope and extra requirements:',
            steps: <BuiltinPluginWorkflowStep>[
              BuiltinPluginWorkflowStep(
                id: 'headers',
                titleZh: '从对话中提炼表头与行数据',
                titleEn: 'Extract headers and row data from the conversation',
                instructionZh: '先确认表头与字段类型',
                instructionEn: 'confirm headers and field types first',
              ),
              BuiltinPluginWorkflowStep(
                id: 'export-open',
                titleZh: '产出 CSV 与 ODS（开放电子表格）',
                titleEn: 'Produce CSV and ODS (OpenDocument spreadsheet)',
                instructionZh: '产出 CSV 与开放电子表格 (.ods) 两种格式',
                instructionEn: 'produce CSV and OpenDocument (.ods) files',
                outputFormats: <String>['csv', 'ods'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'upgrade-xlsx',
                titleZh: '含公式或多工作表时升级为 xlsx',
                titleEn: 'Upgrade to xlsx for formulas or multiple sheets',
                instructionZh: '如需要公式或多个工作表，请改用 .xlsx',
                instructionEn:
                    'upgrade to .xlsx when formulas or multiple sheets are '
                    'needed',
                outputFormats: <String>['xlsx'],
                requiredSkills: <String>['xlsx'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'preview',
                titleZh: '右侧边栏预览，可继续对话修改',
                titleEn: 'Preview in the sidebar, iterate via conversation',
                instructionZh: '文件生成后在右侧边栏提供预览',
                instructionEn: 'preview generated files in the artifact sidebar',
              ),
            ],
          ),
        ),
        BuiltinPluginDescriptor(
          id: presentationId,
          kind: BuiltinPluginKind.presentation,
          icon: Icons.slideshow_outlined,
          nameZh: 'PPT 演示',
          nameEn: 'Presentations',
          descriptionZh: '将对话内容生成可编辑 PPT：图像还原为可编辑元素后合并成完整 pptx。',
          descriptionEn:
              'Generate an editable deck from the conversation: page images '
              'are reconstructed into editable pptx elements.',
          workflow: BuiltinPluginWorkflow(
            goalZh: '请将本次对话内容制作成一份可编辑 PPT：',
            goalEn: 'Build an editable deck from this conversation:',
            inputPromptZh: '主题与补充要求：',
            inputPromptEn: 'Topic and requirements:',
            steps: <BuiltinPluginWorkflowStep>[
              BuiltinPluginWorkflowStep(
                id: 'structure',
                titleZh: '整理成结构化输入（页面大纲、每页要点、视觉风格）',
                titleEn:
                    'Structure the input (outline, per-slide points, visual '
                    'style)',
                instructionZh: '先整理成结构化输入：页面大纲、每页要点与视觉风格',
                instructionEn:
                    'structure the input first: outline, per-slide points, '
                    'and visual style',
              ),
              BuiltinPluginWorkflowStep(
                id: 'page-images',
                titleZh: '生成一组页面图，或获取上下文中的已有图片',
                titleEn: 'Generate page images or reuse images from context',
                instructionZh: '生成一组页面图，或使用对话中已有的图片',
                instructionEn:
                    'generate page images or reuse images from the '
                    'conversation',
              ),
              BuiltinPluginWorkflowStep(
                id: 'reconstruct',
                titleZh: '调用 image-svg-pptx-pro-skill 与 xiaobei-skill-image-to-vba',
                titleEn:
                    'Invoke image-svg-pptx-pro-skill and '
                    'xiaobei-skill-image-to-vba',
                instructionZh:
                    '调用技能包 image-svg-pptx-pro-skill 与 '
                    'xiaobei-skill-image-to-vba，把图片还原成可编辑的 PPT 元素'
                    '（文本框、形状、矢量图）',
                instructionEn:
                    'invoke image-svg-pptx-pro-skill and '
                    'xiaobei-skill-image-to-vba to reconstruct images into '
                    'editable pptx elements (text boxes, shapes, vectors)',
                requiredSkills: <String>[
                  'image-svg-pptx-pro-skill',
                  'xiaobei-skill-image-to-vba',
                ],
                // Reconstruction is the flakiest step: budget two retries
                // before degrading to full-page image placeholders.
                maxRetries: 2,
                fallbackZh: '某页还原失败时用整页图片占位，不阻塞整份文件',
                fallbackEn:
                    'fall back to a full-page image for slides that cannot '
                    'be reconstructed, without blocking the whole deck',
              ),
              BuiltinPluginWorkflowStep(
                id: 'merge',
                titleZh: '合并成完整 .pptx，右侧边栏阅览后可继续修改',
                titleEn: 'Merge into a complete .pptx and preview',
                instructionZh: '最后合并成完整 .pptx，在右侧边栏提供预览，后续我会继续修改',
                instructionEn:
                    'merge into a complete .pptx and preview it in the '
                    'artifact sidebar for follow-up edits',
                outputFormats: <String>['pptx'],
              ),
            ],
          ),
        ),
        BuiltinPluginDescriptor(
          id: imageId,
          kind: BuiltinPluginKind.image,
          icon: Icons.image_outlined,
          nameZh: '图片',
          nameEn: 'Images',
          descriptionZh: '将对话内容输出为图片（JPEG/PNG），支持批量制作、预览与再修改。',
          descriptionEn:
              'Produce images (JPEG/PNG) from the conversation, with batch '
              'generation, preview, and follow-up edits.',
          workflow: BuiltinPluginWorkflow(
            goalZh: '请根据本次对话内容制作图片：',
            goalEn: 'Create images from this conversation:',
            inputPromptZh: '图片需求：',
            inputPromptEn: 'Requirements:',
            steps: <BuiltinPluginWorkflowStep>[
              BuiltinPluginWorkflowStep(
                id: 'requirements',
                titleZh: '提炼图片需求清单（数量、主题、尺寸、风格）',
                titleEn:
                    'List image requirements (count, subject, size, style)',
                instructionZh: '先列出图片需求清单（数量、每张主题、尺寸、风格）',
                instructionEn:
                    'list the image requirements first (count, subject per '
                    'image, size, style)',
              ),
              BuiltinPluginWorkflowStep(
                id: 'generate',
                titleZh: '逐张生成 PNG / JPEG',
                titleEn: 'Generate each image as PNG / JPEG',
                instructionZh: '逐张生成，输出 PNG 或 JPEG',
                instructionEn: 'generate each image as PNG or JPEG',
                outputFormats: <String>['png', 'jpeg'],
                requiredSkills: <String>['image'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'batch-preview',
                titleZh: '批量产出并在边栏网格预览',
                titleEn: 'Batch output with sidebar grid preview',
                instructionZh: '支持批量制作，全部生成后在右侧边栏提供预览',
                instructionEn:
                    'support batch output and preview all images in the '
                    'artifact sidebar',
              ),
              BuiltinPluginWorkflowStep(
                id: 'redo',
                titleZh: '可单张指定重做',
                titleEn: 'Redo individual images on request',
                instructionZh: '之后我会指定某张图片继续修改',
                instructionEn:
                    'I will pick individual images for follow-up edits',
              ),
            ],
          ),
        ),
        BuiltinPluginDescriptor(
          id: videoId,
          kind: BuiltinPluginKind.video,
          icon: Icons.movie_outlined,
          nameZh: '视频',
          nameEn: 'Video',
          descriptionZh:
              '将对话内容编排为分镜脚本，经 hyperframe 或 '
              'it-infra-evolution-video-v2 输出预设模板格式的视频（字幕、口播、BGM）。',
          descriptionEn:
              'Turn the conversation into a storyboard and compose a '
              'template-based video (subtitles, narration, BGM) via '
              'hyperframe or it-infra-evolution-video-v2.',
          workflow: BuiltinPluginWorkflow(
            goalZh: '请将本次对话内容制作成视频：',
            goalEn: 'Produce a video from this conversation:',
            inputPromptZh: '视频主题与补充要求：',
            inputPromptEn: 'Topic and requirements:',
            steps: <BuiltinPluginWorkflowStep>[
              BuiltinPluginWorkflowStep(
                id: 'storyboard',
                titleZh: '整理成结构化输入（分镜脚本：镜头、时长、旁白/口播稿、字幕）',
                titleEn:
                    'Structure the input (storyboard: shots, durations, '
                    'narration script, subtitles)',
                instructionZh: '先整理成结构化输入：分镜脚本（镜头、时长、旁白/口播稿、字幕）',
                instructionEn:
                    'structure the input first: a storyboard with shots, '
                    'durations, narration script, and subtitles',
              ),
              BuiltinPluginWorkflowStep(
                id: 'frames',
                titleZh: '生成一组分镜图，或获取输入的上下文图片',
                titleEn: 'Generate storyboard frames or reuse context images',
                instructionZh: '生成一组分镜图，或使用对话中已有的图片',
                instructionEn:
                    'generate storyboard frames or reuse images from the '
                    'conversation',
              ),
              BuiltinPluginWorkflowStep(
                id: 'compose',
                titleZh: '调用插件 hyperframe 或技能包 it-infra-evolution-video-v2',
                titleEn:
                    'Compose via hyperframe or it-infra-evolution-video-v2',
                instructionZh:
                    '调用插件 hyperframe 或技能包 it-infra-evolution-video-v2 合成视频',
                instructionEn:
                    'compose the video via the hyperframe plugin or the '
                    'it-infra-evolution-video-v2 skill',
                requiredSkills: <String>[
                  'hyperframe',
                  'it-infra-evolution-video-v2',
                ],
              ),
              BuiltinPluginWorkflowStep(
                id: 'audio-template',
                titleZh: '输出预设模板格式：字幕 + 口播；BGM 默认自动生成，可按提示词覆盖',
                titleEn:
                    'Preset template output: subtitles + narration; '
                    'auto-generated BGM unless overridden',
                instructionZh:
                    '输出预设模板格式：带字幕与口播；背景音乐默认自动生成，'
                    '如我在需求中指定了音乐则覆盖替换',
                instructionEn:
                    'output in the preset template format with subtitles and '
                    'narration; auto-generate background music unless my '
                    'prompt specifies music to use instead',
              ),
              BuiltinPluginWorkflowStep(
                id: 'render',
                titleZh: '产出 mp4，边栏预览后可按分镜修改重渲染',
                titleEn: 'Output mp4 with per-shot revision support',
                instructionZh: '产出 mp4，在右侧边栏提供预览，后续我会按分镜提出修改',
                instructionEn:
                    'output mp4 with sidebar preview for per-shot revisions',
                outputFormats: <String>['mp4'],
              ),
            ],
          ),
        ),
      ];

  /// E-commerce scenario pack.
  ///
  /// These three share one shape: the conversation alone is not enough input,
  /// so each declares typed slots. The product shot is always required; the
  /// styling references (model, scene, lighting, print, colorway) are optional
  /// and each carries exactly one attribute across — that constraint is what
  /// [BuiltinPluginInputSlot.roleZh] encodes.
  static const List<BuiltinPluginDescriptor> ecommerceGroup =
      <BuiltinPluginDescriptor>[
        BuiltinPluginDescriptor(
          id: ecommerceHeroId,
          kind: BuiltinPluginKind.image,
          group: BuiltinPluginGroup.ecommerce,
          icon: Icons.photo_size_select_actual_outlined,
          nameZh: '电商头图',
          nameEn: 'Hero Images',
          descriptionZh: '按模特、场景、光影、印花、配色分别指定参考图，批量产出多视角头图。',
          descriptionEn:
              'Generate hero images from separately specified model, scene, '
              'lighting, print, and colorway references, in batch.',
          workflow: BuiltinPluginWorkflow(
            goalZh: '请为该商品制作一组电商头图：',
            goalEn: 'Produce a set of e-commerce hero images for this product:',
            inputPromptZh: '商品信息与本次头图的额外要求：',
            inputPromptEn: 'Product details and extra requirements:',
            inputSlots: <BuiltinPluginInputSlot>[
              BuiltinPluginInputSlot(
                id: 'product',
                labelZh: '商品图',
                labelEn: 'Product shot',
                type: BuiltinPluginSlotType.referenceImage,
                required: true,
                maxCount: 4,
                roleZh: '商品本体的唯一事实来源。版型、材质纹理、五金与比例必须与它一致，不得美化或改形',
                roleEn:
                    'the single source of truth for the product itself — cut, '
                    'material texture, hardware, and proportions must match it '
                    'exactly; do not beautify or reshape',
              ),
              BuiltinPluginInputSlot(
                id: 'model',
                labelZh: '模特参考',
                labelEn: 'Model reference',
                type: BuiltinPluginSlotType.referenceImage,
                roleZh: '只取人物姿态、身形比例与镜头取景；不要沿用其服装、妆容与面部特征',
                roleEn:
                    'take pose, body proportion, and framing only; do not '
                    'carry over its clothing, makeup, or facial identity',
              ),
              BuiltinPluginInputSlot(
                id: 'scene',
                labelZh: '场景参考',
                labelEn: 'Scene reference',
                type: BuiltinPluginSlotType.referenceImage,
                roleZh: '只取环境、陈设与空间纵深；商品不得被场景元素遮挡',
                roleEn:
                    'take environment, props, and spatial depth only; the '
                    'product must never be occluded by scene elements',
              ),
              BuiltinPluginInputSlot(
                id: 'lighting',
                labelZh: '光影参考',
                labelEn: 'Lighting reference',
                type: BuiltinPluginSlotType.referenceImage,
                roleZh: '只取光源方向、色温、明暗对比与阴影硬度；不要沿用其构图与物体',
                roleEn:
                    'take light direction, colour temperature, contrast, and '
                    'shadow hardness only; ignore its composition and objects',
              ),
              BuiltinPluginInputSlot(
                id: 'print',
                labelZh: '印花图案',
                labelEn: 'Print pattern',
                type: BuiltinPluginSlotType.referenceImage,
                maxCount: 3,
                roleZh: '只取图案母题与循环单元，贴合到商品面料上并跟随褶皱与透视形变；不要把参考图本身画进画面',
                roleEn:
                    'take the motif and repeat unit only, mapped onto the '
                    'fabric so it follows folds and perspective; never render '
                    'the reference image itself into the frame',
              ),
              BuiltinPluginInputSlot(
                id: 'colorway',
                labelZh: 'B 版配色',
                labelEn: 'Alternate colorway',
                type: BuiltinPluginSlotType.referenceImage,
                maxCount: 4,
                roleZh: '只取色板。每个配色单独出一版，版型、构图、光影与 A 版严格一致，仅颜色不同',
                roleEn:
                    'take the palette only. Render one variant per colorway '
                    'with cut, composition, and lighting identical to the base '
                    'version — colour is the only difference',
              ),
              BuiltinPluginInputSlot(
                id: 'views',
                labelZh: '视角',
                labelEn: 'Views',
                type: BuiltinPluginSlotType.choice,
                roleZh: '需要产出的机位。每个视角一张，同一套光影与场景下保持连续',
                roleEn:
                    'camera setups to produce — one image each, kept '
                    'consistent under the same lighting and scene',
                choices: <String>['正面', '45°侧', '侧面', '背面', '细节特写', '平铺'],
              ),
              BuiltinPluginInputSlot(
                id: 'ratio',
                labelZh: '画幅比例',
                labelEn: 'Aspect ratio',
                type: BuiltinPluginSlotType.choice,
                roleZh: '输出画幅。主图默认 1:1，竖版种草图用 3:4',
                roleEn:
                    'output framing — 1:1 for the main listing image, 3:4 for '
                    'vertical social placements',
                choices: <String>['1:1', '3:4', '4:5', '9:16', '16:9'],
              ),
            ],
            steps: <BuiltinPluginWorkflowStep>[
              BuiltinPluginWorkflowStep(
                id: 'resolve-slots',
                titleZh: '核对参考图槽位，缺项按缺省处理不臆造',
                titleEn: 'Resolve reference slots; never invent missing ones',
                instructionZh:
                    '先逐条核对上面的参考输入：说明每张图将贡献什么、忽略什么；'
                    '未提供的槽位直接留空，不要用想象补全',
                instructionEn:
                    'first walk the reference inputs above: state what each '
                    'image contributes and what is ignored; leave unprovided '
                    'slots empty instead of inventing them',
              ),
              BuiltinPluginWorkflowStep(
                id: 'base-shot',
                titleZh: '先出一张 A 版基准图并等我确认',
                titleEn: 'Produce one base image and wait for confirmation',
                instructionZh:
                    '先只生成一张 A 版基准图，确认商品形态、光影与构图无误后再继续，'
                    '避免整批返工',
                instructionEn:
                    'generate a single base image first and confirm product '
                    'shape, lighting, and composition before continuing, so a '
                    'whole batch is never wasted',
                outputFormats: <String>['png'],
                requiredSkills: <String>['image'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'multi-view',
                titleZh: '按视角槽位扩展多机位，保持同一套光影',
                titleEn: 'Expand to the requested views under one lighting set',
                instructionZh:
                    '以基准图为锚，按「视角」槽位逐个机位出图，'
                    '保持商品、光影与场景连续一致',
                instructionEn:
                    'anchored on the base image, render each requested view, '
                    'keeping product, lighting, and scene consistent',
                outputFormats: <String>['png'],
                requiredSkills: <String>['image'],
                maxRetries: 2,
                fallbackZh: '某个视角连续失败时跳过该机位并在结果中标注，不阻塞其余视角',
                fallbackEn:
                    'skip a view that keeps failing, flag it in the result, '
                    'and continue with the rest',
              ),
              BuiltinPluginWorkflowStep(
                id: 'colorway-batch',
                titleZh: '按 B 版配色批量复制，仅换色不改版',
                titleEn: 'Batch the colorways — recolour only',
                instructionZh:
                    '对每个 B 版配色重复上述机位，仅替换颜色，'
                    '版型、构图与光影必须与 A 版逐像素级对齐',
                instructionEn:
                    'repeat the views for each colorway, changing colour only; '
                    'cut, composition, and lighting must stay aligned with the '
                    'base version',
                outputFormats: <String>['png'],
                requiredSkills: <String>['image'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'copy-layer',
                titleZh: '文案用矢量层叠加，不画进图里',
                titleEn: 'Overlay copy as a vector layer, never painted in',
                instructionZh:
                    '标题与角标一律用 SVG 文字层叠加后导出，'
                    '不要让生图模型把中文直接画进画面',
                instructionEn:
                    'overlay titles and badges as an SVG text layer before '
                    'export; never let the image model paint the copy in',
                outputFormats: <String>['png'],
                requiredSkills: <String>['image-svg-pptx-pro-skill'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'review',
                titleZh: '边栏网格预览，可指定单张局部重做',
                titleEn: 'Sidebar grid preview with per-image local redo',
                instructionZh: '全部产出后在右侧边栏网格预览，之后我会指定某张图的局部继续修改',
                instructionEn:
                    'preview everything as a sidebar grid; I will then point '
                    'at individual images for local edits',
              ),
            ],
          ),
        ),
        BuiltinPluginDescriptor(
          id: ecommerceDetailId,
          kind: BuiltinPluginKind.image,
          group: BuiltinPluginGroup.ecommerce,
          icon: Icons.view_day_outlined,
          nameZh: '商品详情页',
          nameEn: 'Detail Pages',
          descriptionZh: '模块化生成详情页长图：生图只做产品与背景，文字与版式走矢量层，拼接无缝。',
          descriptionEn:
              'Modular detail-page long image: generation handles product and '
              'backdrop, copy and layout ride a vector layer, seams aligned.',
          workflow: BuiltinPluginWorkflow(
            goalZh: '请制作一张商品详情页长图：',
            goalEn: 'Build a product detail-page long image:',
            inputPromptZh: '商品卖点与本次详情页的额外要求：',
            inputPromptEn: 'Selling points and extra requirements:',
            inputSlots: <BuiltinPluginInputSlot>[
              BuiltinPluginInputSlot(
                id: 'product',
                labelZh: '商品图',
                labelEn: 'Product shot',
                type: BuiltinPluginSlotType.referenceImage,
                required: true,
                maxCount: 8,
                roleZh: '商品本体的唯一事实来源，含结构与细节特写。形态不得改动',
                roleEn:
                    'the single source of truth for the product, including '
                    'structure and detail shots; its form must not be altered',
              ),
              BuiltinPluginInputSlot(
                id: 'selling-points',
                labelZh: '卖点文案',
                labelEn: 'Selling points',
                type: BuiltinPluginSlotType.text,
                required: true,
                roleZh: '每个卖点一行，作为各模块的主标题与副标题来源。文字必须逐字使用，不得改写',
                roleEn:
                    'one selling point per line, used verbatim as each module '
                    'headline and subhead — never paraphrased',
              ),
              BuiltinPluginInputSlot(
                id: 'brand-color',
                labelZh: '品牌色',
                labelEn: 'Brand colour',
                type: BuiltinPluginSlotType.text,
                roleZh: '十六进制色值。用于标题、图标与分区底色，全页统一',
                roleEn:
                    'hex value used for headings, icons, and section fills, '
                    'applied consistently across the page',
              ),
              BuiltinPluginInputSlot(
                id: 'modules',
                labelZh: '模块编排',
                labelEn: 'Module layout',
                type: BuiltinPluginSlotType.choice,
                roleZh: '按顺序编排的内容模块，每个模块一屏',
                roleEn: 'content modules in order, one screen each',
                choices: <String>[
                  '场景主图',
                  '卖点罗列',
                  '结构分区图',
                  '材质特写',
                  '工艺流程',
                  '参数对比',
                  '尺码表',
                  '洗护说明',
                ],
              ),
              BuiltinPluginInputSlot(
                id: 'style',
                labelZh: '版式风格',
                labelEn: 'Layout style',
                type: BuiltinPluginSlotType.choice,
                roleZh: '整页的排版调性，决定留白、字重与分割线处理',
                roleEn:
                    'page-wide typographic tone driving whitespace, weights, '
                    'and dividers',
                choices: <String>['极简留白', '杂志编辑', '科技参数', '自然温和'],
              ),
            ],
            steps: <BuiltinPluginWorkflowStep>[
              BuiltinPluginWorkflowStep(
                id: 'module-plan',
                titleZh: '把卖点映射成模块清单，定死每屏尺寸',
                titleEn: 'Map selling points to modules with fixed screen size',
                instructionZh:
                    '先把卖点映射成模块清单：每个模块的标题、正文、配图类型与像素高度；'
                    '全页统一宽度 750px，这样各屏才能无缝拼接',
                instructionEn:
                    'map the selling points into a module list first — per '
                    'module headline, body, image type, and pixel height; fix '
                    'page width at 750px so screens stitch seamlessly',
              ),
              BuiltinPluginWorkflowStep(
                id: 'backdrops',
                titleZh: '生图只产出产品与背景，画面内不含任何文字',
                titleEn: 'Generate product and backdrop only — no text in-frame',
                instructionZh:
                    '逐模块生成产品图与背景。画面里不允许出现任何文字、标签或水印，'
                    '文字一律留给下一步的矢量层',
                instructionEn:
                    'generate product and backdrop per module. No text, label, '
                    'or watermark may appear in the rendered frame — copy is '
                    'the next step\'s job',
                outputFormats: <String>['png'],
                requiredSkills: <String>['image'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'text-layer',
                titleZh: '文字与图示走 SVG 矢量层，保证逐字准确',
                titleEn: 'Copy and diagrams as an SVG layer, character-exact',
                instructionZh:
                    '标题、正文、参数表、分区标注与图标全部用 SVG 排版后叠加，'
                    '文案逐字对应输入，不得由模型改写或臆造',
                instructionEn:
                    'lay out headings, body, spec tables, callouts, and icons '
                    'as SVG and composite them on top; copy must match the '
                    'input character for character',
                outputFormats: <String>['svg'],
                requiredSkills: <String>['image-svg-pptx-pro-skill'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'compose',
                titleZh: '合成各模块并纵向拼成整页长图',
                titleEn: 'Composite modules and stitch the full-page long image',
                instructionZh:
                    '把背景层与文字层合成为单模块图，再按模块顺序纵向拼接成整页长图；'
                    '相邻模块的底色与留白必须对齐，不能出现接缝色差',
                instructionEn:
                    'composite backdrop and text layers per module, then stack '
                    'the modules into one long image; adjacent fills and '
                    'margins must align so no seam is visible',
                outputFormats: <String>['png'],
                maxRetries: 2,
                fallbackZh: '整页拼接失败时改为逐模块单图交付，并附拼接顺序说明',
                fallbackEn:
                    'if stitching fails, deliver per-module images plus the '
                    'intended stacking order',
              ),
              BuiltinPluginWorkflowStep(
                id: 'proof',
                titleZh: '逐模块回读文案与透视自检',
                titleEn: 'Proofread copy and sanity-check perspective',
                instructionZh:
                    '交付前逐模块自检：文案是否与输入逐字一致、'
                    '产品透视与投影方向是否统一、模块高度是否符合规划',
                instructionEn:
                    'before delivery check each module: copy matches the input '
                    'verbatim, product perspective and shadow direction are '
                    'consistent, and module heights match the plan',
              ),
            ],
          ),
        ),
        BuiltinPluginDescriptor(
          id: ecommerceVideoId,
          kind: BuiltinPluginKind.video,
          group: BuiltinPluginGroup.ecommerce,
          icon: Icons.auto_awesome_motion_outlined,
          nameZh: '爆款视频复刻',
          nameEn: 'Viral Video Remake',
          descriptionZh: '拆解 TikTok / 抖音爆款的脚本与高光节点，换成自家商品重新生成短视频。',
          descriptionEn:
              'Deconstruct a TikTok / Douyin hit into script and beat sheet, '
              'then regenerate it around your own product.',
          workflow: BuiltinPluginWorkflow(
            goalZh: '请参考这条爆款视频，为我的商品复刻一条短视频：',
            goalEn:
                'Remake a short video for my product, referencing this hit:',
            inputPromptZh: '商品信息与本次视频的额外要求：',
            inputPromptEn: 'Product details and extra requirements:',
            inputSlots: <BuiltinPluginInputSlot>[
              BuiltinPluginInputSlot(
                id: 'source',
                labelZh: '爆款视频链接',
                labelEn: 'Source video link',
                type: BuiltinPluginSlotType.url,
                required: true,
                roleZh: 'TikTok / 抖音链接。只复刻其节奏结构、镜头语言与叙事顺序，不得复制其画面内容或音轨',
                roleEn:
                    'TikTok / Douyin link. Reproduce its pacing, camera '
                    'grammar, and narrative order only — never its footage or '
                    'audio track',
              ),
              BuiltinPluginInputSlot(
                id: 'product',
                labelZh: '商品图',
                labelEn: 'Product shot',
                type: BuiltinPluginSlotType.referenceImage,
                required: true,
                maxCount: 6,
                roleZh: '出镜商品的唯一事实来源，替换掉原片中的商品',
                roleEn:
                    'the single source of truth for the on-screen product, '
                    'replacing whatever the source video featured',
              ),
              BuiltinPluginInputSlot(
                id: 'hook',
                labelZh: '开场钩子文案',
                labelEn: 'Hook line',
                type: BuiltinPluginSlotType.text,
                roleZh: '前三秒的字幕与口播。留空则按原片钩子的结构重写一条',
                roleEn:
                    'first-three-seconds subtitle and voiceover; leave empty '
                    'to rewrite one following the source hook\'s structure',
              ),
              BuiltinPluginInputSlot(
                id: 'duration',
                labelZh: '目标时长',
                labelEn: 'Target duration',
                type: BuiltinPluginSlotType.choice,
                roleZh: '成片时长，决定高光节点的取舍密度',
                roleEn:
                    'final runtime, which decides how densely the beats are '
                    'kept or dropped',
                choices: <String>['15s', '30s', '45s', '60s'],
              ),
            ],
            steps: <BuiltinPluginWorkflowStep>[
              BuiltinPluginWorkflowStep(
                id: 'ingest',
                titleZh: '拉取源视频并逐镜理解画面',
                titleEn: 'Fetch the source and read it shot by shot',
                instructionZh:
                    '拉取链接对应的视频，逐镜识别画面内容、镜头运动、转场方式与音画节奏',
                instructionEn:
                    'fetch the linked video and read it shot by shot: on-screen '
                    'content, camera movement, transitions, and audio-visual '
                    'rhythm',
                requiredSkills: <String>['video-understanding'],
                maxRetries: 2,
                fallbackZh: '拉取失败时要求我改为直接上传视频文件，不要凭标题猜测内容',
                fallbackEn:
                    'if the fetch fails, ask me to upload the file directly '
                    'rather than guessing the content from the title',
              ),
              BuiltinPluginWorkflowStep(
                id: 'beat-sheet',
                titleZh: '拆出脚本与高光节点时间轴',
                titleEn: 'Extract the script and beat sheet',
                instructionZh:
                    '输出原片的脚本与高光节点时间轴：钩子、痛点、卖点展示、'
                    '转折、行动号召各落在第几秒，以及每个节点起作用的原因',
                instructionEn:
                    'output the source script and beat sheet: at which second '
                    'the hook, pain point, feature reveal, turn, and CTA land, '
                    'and why each beat works',
                outputFormats: <String>['md'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'rewrite',
                titleZh: '按节点结构改写成我的商品脚本',
                titleEn: 'Rewrite the beats around my product',
                instructionZh:
                    '保留节点结构与时长分配，把内容整体换成我的商品：'
                    '重写口播与字幕，逐镜给出画面描述。不要照搬原片台词',
                instructionEn:
                    'keep the beat structure and timing, swap the content to '
                    'my product: rewrite voiceover and subtitles, and describe '
                    'each shot. Never copy the source script verbatim',
                outputFormats: <String>['md'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'frames',
                titleZh: '按分镜生成画面，商品形态锁定',
                titleEn: 'Generate frames with the product locked',
                instructionZh:
                    '按分镜逐镜生成画面，商品形态严格锁定在商品图上，跨镜头保持一致',
                instructionEn:
                    'generate each shot, locking product form to the supplied '
                    'product images and keeping it consistent across shots',
                outputFormats: <String>['png'],
                requiredSkills: <String>['image'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'compose',
                titleZh: '合成 mp4：字幕 + 口播 + BGM',
                titleEn: 'Compose the mp4: subtitles + voiceover + BGM',
                instructionZh:
                    '调用 hyperframe 合成 mp4，带字幕与口播；背景音乐自动生成，'
                    '不要使用原片音轨',
                instructionEn:
                    'compose the mp4 via hyperframe with subtitles and '
                    'voiceover; auto-generate background music and never reuse '
                    'the source audio track',
                outputFormats: <String>['mp4'],
                requiredSkills: <String>['hyperframe'],
              ),
              BuiltinPluginWorkflowStep(
                id: 'compare',
                titleZh: '与原片节点对照，标出偏差供我按镜修改',
                titleEn: 'Diff against the source beats for per-shot revision',
                instructionZh:
                    '交付时附上与原片的节点对照表，标出时长与节奏偏差；'
                    '之后我会按镜头提出修改',
                instructionEn:
                    'deliver with a beat-by-beat comparison against the source, '
                    'flagging timing and pacing drift; I will then revise per '
                    'shot',
              ),
            ],
          ),
        ),
      ];

  /// Every built-in plugin, general group first.
  static const List<BuiltinPluginDescriptor> all = <BuiltinPluginDescriptor>[
    ...firstBatch,
    ...ecommerceGroup,
  ];

  /// Groups that actually have plugins, in display order.
  static List<BuiltinPluginGroup> get groups => BuiltinPluginGroup.values
      .where((group) => byGroup(group).isNotEmpty)
      .toList(growable: false);

  static List<BuiltinPluginDescriptor> byGroup(BuiltinPluginGroup group) => all
      .where((plugin) => plugin.group == group)
      .toList(growable: false);

  static BuiltinPluginDescriptor? byId(String id) {
    final normalized = id.trim();
    for (final plugin in all) {
      if (plugin.id == normalized) {
        return plugin;
      }
    }
    return null;
  }
}
