import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';

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
/// Built-in plugins are not a new execution channel. Each descriptor bundles
/// a structured composer template plus the skill packages the task should
/// orchestrate on the gateway side. Selecting a plugin in the composer inserts
/// [composerTemplateZh]/[composerTemplateEn] into the input; generated files
/// flow back through the existing artifact sidebar for preview and follow-up
/// edits.
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
    required this.outputFormats,
    required this.composerTemplateZh,
    required this.composerTemplateEn,
    this.requiredSkills = const <String>[],
    this.pipelineStepsZh = const <String>[],
    this.status = BuiltinPluginStatus.preview,
  });

  final String id;
  final BuiltinPluginKind kind;
  final IconData icon;
  final String nameZh;
  final String nameEn;
  final String descriptionZh;
  final String descriptionEn;

  /// Output file formats, e.g. `['md', 'pdf', 'docx']`.
  final List<String> outputFormats;

  /// Skill packages / plugins this pipeline depends on (gateway workspace).
  final List<String> requiredSkills;

  /// Human-readable pipeline steps, surfaced in the settings plugins panel.
  final List<String> pipelineStepsZh;

  /// Structured prompt inserted into the composer when the plugin is picked.
  final String composerTemplateZh;
  final String composerTemplateEn;

  final BuiltinPluginStatus status;

  String get name => appText(nameZh, nameEn);

  String get description => appText(descriptionZh, descriptionEn);

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
          outputFormats: <String>['md', 'pdf', 'docx'],
          requiredSkills: <String>['docx', 'pdf'],
          pipelineStepsZh: <String>[
            '整理对话内容为结构化大纲',
            '生成 Markdown 源文件',
            '调用 docx / pdf 技能包导出 Word 与 PDF',
            '右侧边栏预览，可继续对话修改',
          ],
          composerTemplateZh:
              '请将本次对话的关键内容整理成一份可编辑文档：\n'
              '1. 先给出结构化大纲（标题、章节、要点）；\n'
              '2. 产出 Markdown 源文件（.md）；\n'
              '3. 再导出 PDF 与 Word (.docx) 两个版本；\n'
              '4. 文件生成后在右侧边栏提供预览，后续我会继续提出修改。\n'
              '主题与补充要求：',
          composerTemplateEn:
              'Turn the key content of this conversation into an editable '
              'document: 1) structured outline first; 2) produce a Markdown '
              'source file; 3) export PDF and Word (.docx) versions; '
              '4) surface files in the artifact sidebar for preview and '
              'follow-up edits. Topic and extra requirements:',
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
          outputFormats: <String>['csv', 'ods', 'xlsx'],
          requiredSkills: <String>['xlsx'],
          pipelineStepsZh: <String>[
            '从对话中提炼表头与行数据',
            '产出 CSV 与 ODS（开放电子表格）',
            '含公式或多工作表时升级为 xlsx',
            '右侧边栏预览，可继续对话修改',
          ],
          composerTemplateZh:
              '请将本次对话中的数据整理成可编辑电子表格：\n'
              '1. 先确认表头与字段类型；\n'
              '2. 产出 CSV 与开放电子表格 (.ods) 两种格式；\n'
              '3. 如需要公式或多个工作表，请改用 .xlsx；\n'
              '4. 文件生成后在右侧边栏提供预览。\n'
              '数据范围与补充要求：',
          composerTemplateEn:
              'Organize the data in this conversation into an editable '
              'spreadsheet: 1) confirm headers and field types; 2) produce '
              'CSV and OpenDocument (.ods) files; 3) upgrade to .xlsx when '
              'formulas or multiple sheets are needed; 4) preview in the '
              'artifact sidebar. Data scope and extra requirements:',
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
          outputFormats: <String>['pptx'],
          requiredSkills: <String>[
            'image-svg-pptx-pro-skill',
            'xiaobei-skill-image-to-vba',
          ],
          pipelineStepsZh: <String>[
            '整理成结构化输入（页面大纲、每页要点、视觉风格）',
            '生成一组页面图，或获取上下文中的已有图片',
            '调用 image-svg-pptx-pro-skill 与 xiaobei-skill-image-to-vba',
            '把图片还原成可编辑 PPT 元素（文本框、形状、矢量图）',
            '合并成完整 .pptx，右侧边栏阅览后可继续修改',
          ],
          composerTemplateZh:
              '请将本次对话内容制作成一份可编辑 PPT：\n'
              '1. 先整理成结构化输入：页面大纲、每页要点与视觉风格；\n'
              '2. 生成一组页面图，或使用对话中已有的图片；\n'
              '3. 调用技能包 image-svg-pptx-pro-skill 与 '
              'xiaobei-skill-image-to-vba，把图片还原成可编辑的 PPT 元素；\n'
              '4. 某页还原失败时用整页图片占位，不要阻塞整份文件；\n'
              '5. 最后合并成完整 .pptx，在右侧边栏提供预览，后续我会继续修改。\n'
              '主题与补充要求：',
          composerTemplateEn:
              'Build an editable deck from this conversation: 1) structured '
              'input first (outline, per-slide points, visual style); '
              '2) generate page images or reuse images from context; '
              '3) invoke image-svg-pptx-pro-skill and '
              'xiaobei-skill-image-to-vba to reconstruct images into editable '
              'pptx elements; 4) fall back to a full-page image when a slide '
              'cannot be reconstructed; 5) merge into a complete .pptx and '
              'preview it in the artifact sidebar. Topic and requirements:',
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
          outputFormats: <String>['png', 'jpeg'],
          requiredSkills: <String>['image'],
          pipelineStepsZh: <String>[
            '提炼图片需求清单（数量、主题、尺寸、风格）',
            '逐张生成 PNG / JPEG',
            '批量产出并在边栏网格预览',
            '可单张指定重做',
          ],
          composerTemplateZh:
              '请根据本次对话内容制作图片：\n'
              '1. 先列出图片需求清单（数量、每张主题、尺寸、风格）；\n'
              '2. 逐张生成，输出 PNG 或 JPEG；\n'
              '3. 支持批量制作，全部生成后在右侧边栏提供预览；\n'
              '4. 之后我会指定某张图片继续修改。\n'
              '图片需求：',
          composerTemplateEn:
              'Create images from this conversation: 1) list the image '
              'requirements first (count, subject, size, style); 2) generate '
              'each as PNG or JPEG; 3) support batch output with sidebar '
              'preview; 4) I will pick individual images for follow-up '
              'edits. Requirements:',
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
          outputFormats: <String>['mp4'],
          requiredSkills: <String>[
            'hyperframe',
            'it-infra-evolution-video-v2',
          ],
          pipelineStepsZh: <String>[
            '整理成结构化输入（分镜脚本：镜头、时长、旁白/口播稿、字幕）',
            '生成一组分镜图，或获取输入的上下文图片',
            '调用插件 hyperframe 或技能包 it-infra-evolution-video-v2',
            '输出预设模板格式的视频：字幕 + 口播',
            'BGM 默认自动生成，可按用户提示词覆盖替换',
            '产出 mp4，边栏预览后可按分镜修改重渲染',
          ],
          composerTemplateZh:
              '请将本次对话内容制作成视频：\n'
              '1. 先整理成结构化输入：分镜脚本（镜头、时长、旁白/口播稿、字幕）；\n'
              '2. 生成一组分镜图，或使用对话中已有的图片；\n'
              '3. 调用插件 hyperframe 或技能包 it-infra-evolution-video-v2 '
              '合成视频；\n'
              '4. 输出预设模板格式：带字幕与口播；背景音乐默认自动生成，'
              '如我在需求中指定了音乐则覆盖替换；\n'
              '5. 产出 mp4，在右侧边栏提供预览，后续我会按分镜提出修改。\n'
              '视频主题与补充要求：',
          composerTemplateEn:
              'Produce a video from this conversation: 1) structured input '
              'first (storyboard with shots, durations, narration script, '
              'subtitles); 2) generate storyboard frames or reuse images '
              'from context; 3) compose via the hyperframe plugin or the '
              'it-infra-evolution-video-v2 skill; 4) output in the preset '
              'template format with subtitles and narration; auto-generate '
              'background music unless my prompt specifies music to use '
              'instead; 5) output mp4 with sidebar preview for per-shot '
              'revisions. Topic and requirements:',
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
