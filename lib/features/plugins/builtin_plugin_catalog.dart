import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import 'builtin_plugin_workflow.dart';

/// First-batch built-in plugin kinds.
///
/// See docs/plans/2026-07-04-builtin-plugins-batch-1.md for the full plan.
enum BuiltinPluginKind { document, spreadsheet, presentation, image, video }

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
    this.status = BuiltinPluginStatus.preview,
  });

  final String id;
  final BuiltinPluginKind kind;
  final IconData icon;
  final String nameZh;
  final String nameEn;
  final String descriptionZh;
  final String descriptionEn;

  /// The plugin's workflow state machine — single source of truth for the
  /// composer template, output formats, pipeline list, and skill deps.
  final BuiltinPluginWorkflow workflow;

  final BuiltinPluginStatus status;

  String get name => appText(nameZh, nameEn);

  String get description => appText(descriptionZh, descriptionEn);

  /// Output file formats, derived from workflow steps (first-seen order).
  List<String> get outputFormats => workflow.outputFormats;

  /// Skill packages / plugins this pipeline depends on (gateway workspace).
  List<String> get requiredSkills => workflow.requiredSkills;

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

  static BuiltinPluginDescriptor? byId(String id) {
    final normalized = id.trim();
    for (final plugin in firstBatch) {
      if (plugin.id == normalized) {
        return plugin;
      }
    }
    return null;
  }
}
