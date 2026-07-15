import '../plugins/builtin_plugin_catalog.dart';

class MobileBuiltinPluginSceneSpec {
  const MobileBuiltinPluginSceneSpec({
    required this.plugin,
    required this.sceneLabel,
    required this.prefillPrompt,
  });

  final BuiltinPluginDescriptor plugin;
  final String sceneLabel;
  final String prefillPrompt;
}

final List<MobileBuiltinPluginSceneSpec> mobileBuiltinPluginScenes =
    <MobileBuiltinPluginSceneSpec>[
      MobileBuiltinPluginSceneSpec(
        plugin: BuiltinPluginCatalog.firstBatch[0],
        sceneLabel: '整理文档',
        prefillPrompt: '请把当前内容整理成一份可编辑文档，输出 Markdown、PDF 和 Word。',
      ),
      MobileBuiltinPluginSceneSpec(
        plugin: BuiltinPluginCatalog.firstBatch[1],
        sceneLabel: '整理表格',
        prefillPrompt: '请把当前内容结构化为可编辑表格，输出 CSV、ODS 和 XLSX。',
      ),
      MobileBuiltinPluginSceneSpec(
        plugin: BuiltinPluginCatalog.firstBatch[2],
        sceneLabel: '制作 PPT',
        prefillPrompt: '请把当前内容制作成一份可编辑 PPT，适合汇报展示。',
      ),
      MobileBuiltinPluginSceneSpec(
        plugin: BuiltinPluginCatalog.firstBatch[3],
        sceneLabel: '生成图片',
        prefillPrompt: '请围绕当前主题生成一组图片，适合封面、配图和海报。',
      ),
      MobileBuiltinPluginSceneSpec(
        plugin: BuiltinPluginCatalog.firstBatch[4],
        sceneLabel: '制作视频',
        prefillPrompt: '请把当前内容整理成分镜脚本，并生成成片视频。',
      ),
    ];
