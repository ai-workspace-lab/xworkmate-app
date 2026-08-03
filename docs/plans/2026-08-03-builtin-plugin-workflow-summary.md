# 内置插件工作流一览

日期：2026-08-03
数据来源：`lib/features/plugins/builtin_plugin_catalog.dart`（唯一事实来源，本文档是快照，改动以代码为准）
相关：`docs/plans/2026-07-04-builtin-plugins-batch-1.md`（通用五个插件的原始设计）、
`docs/plans/2026-08-03-ecommerce-plugin-group.md`（电商三个插件的设计）

八个内置插件，两个分组（`BuiltinPluginGroup`）。每条只写步骤链与那条链里唯一不能丢的约束——
约束是从 workflow 的 `fallbackZh`、`instructionZh` 里摘出来的，不是我总结的意图。

---

## 通用分组（general）

### 文档 `builtin.document`
`outline → markdown → export → preview`
先出结构化大纲，用户确认框架后再落 Markdown，最后调用 `docx`/`pdf` 技能包导出。

### 电子表格 `builtin.spreadsheet`
`headers → export-open → upgrade-xlsx → preview`
先定表头与字段类型再产出，默认给 CSV + ODS（开放格式）；只有需要公式或多工作表时才升级到 `.xlsx`。

### PPT 演示 `builtin.presentation`
`structure → page-images → reconstruct → merge`
先出结构化大纲，生成/复用页面图后调用 `image-svg-pptx-pro-skill` + `xiaobei-skill-image-to-vba`
把图片**还原成可编辑元素**（文本框、形状、矢量图），不是简单地把图片贴进 PPT。
**`reconstruct` 允许重试 2 次，失败降级为整页图片占位，不阻塞整份文件**——这是唯一带
`maxRetries`/`fallback` 的通用插件步骤，因为图生 PPT 元素这一步最容易失败。

### 图片 `builtin.image`
`requirements → generate → batch-preview → redo`
先列需求清单（数量/主题/尺寸/风格）再批量生成，支持事后指定单张重做。

### 视频 `builtin.video`
`storyboard → frames → compose → audio-template → render`
先出分镜脚本（镜头/时长/口播稿/字幕），再生成分镜图，调用 `hyperframe` 或
`it-infra-evolution-video-v2` 合成；字幕+口播是预设模板，BGM 默认自动生成，
用户指定音乐时才覆盖。

---

## 电商分组（ecommerce）

三个插件在产物类型轴上（`BuiltinPluginKind`）分别是 image / image / video，与上面的
通用图片、视频插件重合——分组轴 `BuiltinPluginGroup.ecommerce` 才是把它们和「泛用生成」
区分开的维度。三个都新增了结构化输入槽位（`BuiltinPluginInputSlot`），这是通用五个插件
没有的东西：自由文本描述不出「这张图只取印花、那张图只取光影」这种角色绑定。

### 电商头图 `builtin.ecommerce.hero`
`resolve-slots → base-shot → multi-view → colorway-batch → copy-layer → review`

- **先核对槽位再生成**：逐条说明每张参考图贡献什么、忽略什么；未提供的槽位留空，不臆造。
- **先出一张基准图，等确认后再展开批量**——多参考图生图一旦一次性铺开多视角×多配色，
  错了就是整批返工。`multi-view` 允许重试 2 次，单个视角持续失败时跳过并标注，不阻塞其余视角。
- **B 版配色只换色不改版**：`colorway-batch` 要求版型、构图、光影与 A 版逐像素对齐。
- **文字不进生成模型**：`copy-layer` 用 `image-svg-pptx-pro-skill` 做矢量文字叠加，
  不让生图模型直接画中文。

### 商品详情页 `builtin.ecommerce.detail`
`module-plan → backdrops → text-layer → compose → proof`

- **生图只出产品与背景，画面里不允许出现任何文字**——这是详情页最重要的一条约束，直接对应
  「文字清晰」这一验收要求；文字全部留给 `text-layer`（同一个 `image-svg-pptx-pro-skill`）。
- **全页固定 750px 宽**，是「多图拼接无违和」的前提：宽度不统一，拼接必然错位。
- `compose`（模块合成+纵向拼接）允许重试 2 次，失败时降级为逐模块单图交付+拼接顺序说明，
  不强行输出一张有接缝色差的坏图。

### 爆款视频复刻 `builtin.ecommerce.video`
`ingest → beat-sheet → rewrite → frames → compose → compare`

- **理解必须先于生成**：`ingest`（拉取并逐镜理解源视频）在 `frames`（生成画面）之前，
  `beat-sheet`（拆节点时间轴）在 `rewrite`（改写脚本）之前——步骤顺序本身就是这条约束，
  不是靠文字提醒 Agent。
- **拉取失败降级为要求用户直接上传视频文件，不靠标题/封面猜内容**：`ingest` 允许重试 2 次，
  用尽后不编造，直接问用户要文件。
- **只复刻结构，不复制内容**：源视频只取节奏结构、镜头语言、叙事顺序，明确不得复制其画面
  内容或音轨；`rewrite` 明确不得照搬原片台词；`compose` 的 BGM 自动生成，不使用原片音轨。
- 依赖新增技能包 `video-understanding`（已落地于
  `xworkspace-core-skills/skills/video-production/video-understanding/`），承担 `ingest` 的
  拉取+场景切分+逐镜理解职责，产出 `script.md` + `beat-sheet.md` 供本插件消费。

---

## 跨插件的共性模式

把八条工作流并排看，能看出三条反复出现的设计模式——不是巧合，是同一套约束在不同插件里的具体化：

1. **先出一个最小样本，确认后再批量**：文档先出大纲、电子表格先定表头、头图先出基准图、
   详情页先出模块清单。批量生成的返工成本远高于生成前确认的成本，五个通用插件和三个电商
   插件在这条上完全一致。
2. **易失败的步骤才有重试预算与降级路径**：`maxRetries` + `fallback` 只出现在 PPT 的
   `reconstruct`、头图的 `multi-view`、详情页的 `compose`、视频复刻的 `ingest`——都是依赖
   外部服务或复杂还原逻辑的步骤。线性的整理/分类步骤（大纲、表头、需求清单）不需要重试语义，
   它们本身不太会"失败"，只会"做得不够好"，那是靠用户确认环节兜底，不是靠重试。
3. **能画成图的内容交给生成模型，能用逐字文本表达的内容交给矢量层**：PPT 的图片还原、
   头图与详情页的 `copy-layer`/`text-layer` 都在做同一件事——生图模型负责它擅长的（图像、
   氛围、构图），文字负责它必须精确的（标题、参数、卖点），两者合成而不是让一个模型
   同时干两件事。这也是详情页「文字清晰」这个验收要求唯一站得住脚的实现路径。

## 已知缺口

- 头图与详情页的「多视角/多配色批量」目前靠 step 的 `instructionZh` 文字描述让 Gateway 自己
  循环，workflow 模型本身仍是严格线性单产物，没有真正的扇出（fan-out）语义，因此也没有
  「单个视角失败只重试那一个」之外的批量级可观测性。详见
  `docs/plans/2026-08-03-ecommerce-plugin-group.md` §3.3。
- 槽位模型（`BuiltinPluginInputSlot`）目前只做到「声明 + 渲染进提示词」，composer 侧还没有
  对应的上传表单 UI，用户仍要靠手动附图+读模板文字来对应槽位。详见同文档 §3.2。
