# 第一批内置插件扩展规划（Batch 1 Built-in Plugins）

- 日期：2026-07-04
- 状态：规划 + 脚手架落地（本 PR）
- 关联界面：对话框（assistant composer）、设置页（settings）
- 约束：**不破坏现有 UI 整体布局**，所有新入口均为增量挂载点，并由 feature flag 控制

## 1. 目标

让任意对话内容都可以一键转化为可编辑的交付物。第一批内置 5 个插件：

| # | 插件 | 输出格式 | 依赖技能包 / 插件 | 说明 |
| - | ---- | -------- | ----------------- | ---- |
| 1 | 文档 Document | Markdown / PDF / Word (docx) | docx-skill、pdf-skill（xworkspace-core-skills） | 任意对话内容整理为可编辑文档，三种格式同步导出 |
| 2 | 电子表格 Spreadsheet | CSV / ODS（开放电子表格）/ xlsx | xlsx-skill | 任意对话内容结构化为可编辑表格 |
| 3 | PPT Presentation | pptx（可编辑元素） | image-svg-pptx-pro-skill、xiaobei-skill-image-to-vba | 见 §3 PPT 流水线 |
| 4 | 图片 Image | JPEG / PNG，支持批量 | image-skill（生成/处理） | 批量制作、右侧边栏预览、可再修改 |
| 5 | 视频 Video | mp4（预设模板格式，含字幕/口播/BGM） | hyperframe（插件）或 it-infra-evolution-video-v2（技能包） | 见 §3 视频流水线 |

## 2. 架构与接入点

沿用现有单一执行路径：`Flutter → GoTaskServiceClient → ACP Transport → xworkmate-bridge → Remote Provider`。

内置插件**不是新的执行通道**，而是「结构化提示词模板 + 技能包编排 + 产物预览」三层组合：

1. **催化层（App 内）**：`BuiltinPluginCatalog` 描述符（id、名称、输出格式、依赖技能包、composer 模板）。用户在对话框选择插件后，模板注入输入框，随任务下发。
2. **执行层（Gateway/Bridge）**：任务执行时按模板调用对应技能包（与现有 skill picker 相同的技能加载机制，来源 openclaw-workspace / xworkspace-core-skills）。
3. **产物层（App 内）**：生成的文件走现有 artifact 通道，在右侧边栏（assistant_artifact_sidebar）阅览，可继续对话修改。

### UI 接入点（本 PR 脚手架）

| 接入点 | 位置 | 方式 | 布局影响 |
| ------ | ---- | ---- | -------- |
| 对话框插件入口 | composer 顶部工具行，「+」附件按钮右侧 | 新增一个 `PopupMenuButton`（扩展图标），列出已启用内置插件；点选后将该插件的结构化模板插入输入框光标处 | 仅新增一个 28px 图标按钮，与现有按钮同规格；由 `assistant.builtin_plugins` flag 控制 |
| 设置页「插件」标签页 | 设置页 SegmentedButton 标签选择器 | 新增 `SettingsTab.plugins`，渲染 `SettingsPluginsPanel`（插件卡片列表：状态、格式、依赖技能包） | 复用现有 tab 机制，多一个 segment；由 `settings.plugins` flag 控制 |

### Feature flags（config/feature_flags.yaml）

- `desktop.assistant.builtin_plugins`：enabled，`release_tier: stable`（默认开启，debug/profile/release 全部可见，2026-07-04 决定跳过 beta 门槛直接放开）
- `desktop.settings.plugins`：同上
- mobile / web：本批次 `enabled: false`（移动端 settings 的 tab 分支与 composer 结构不同，放入 M3）

## 3. 各插件流水线

### 3.1 文档 / 电子表格（直通型）

```
对话上下文 → 结构化整理（大纲/表头） → 调用 docx/pdf/xlsx 技能包 → 产出文件 → 右侧边栏预览 → 对话继续修改
```

- 文档默认产出 `.md` 源文件（single source of truth），再由技能包导出 PDF 与 docx。
- 表格默认产出 CSV + ODS；数据含公式/多 sheet 时升级为 xlsx。

### 3.2 PPT（图像还原型）

```
1️⃣ 对话上下文
2️⃣ 整理成结构化输入（页面大纲、每页要点、视觉风格）
3️⃣ 生成一组页面图 或 获取上下文中已有图片
4️⃣ 调用技能包：image-svg-pptx-pro-skill（图→SVG→pptx 矢量元素）
   调用技能包：xiaobei-skill-image-to-vba（图→VBA 绘制指令→可编辑形状）
5️⃣ 把图片还原成可编辑 PPT 元素（文本框、形状、矢量图）
6️⃣ 合并成完整 .pptx → 右侧边栏阅览 → 可继续对话修改
```

失败降级：某页还原失败时以整页图片占位插入，不阻塞整份文件生成。

### 3.3 图片（批量型）

```
对话上下文 → 提炼图片需求清单（N 张：主题/尺寸/风格） → 逐张生成（PNG/JPEG） → 批量产出 → 边栏网格预览 → 单张指定重做
```

### 3.4 视频（编排型）

```
1️⃣ 对话上下文
2️⃣ 整理成结构化输入（分镜脚本：镜头、时长、旁白/口播稿、字幕）
3️⃣ 生成一组分镜图 或 获取输入的上下文图片
4️⃣ 调用插件 hyperframe 或 技能包 it-infra-evolution-video-v2
5️⃣ 输出预设模板格式的视频：字幕 + 口播；背景音乐默认自动生成，
   也可根据用户提示词的需求输入覆盖替换
6️⃣ 产出 mp4 → 边栏预览 → 按分镜修改重渲染
```

- 音轨规则：口播由旁白稿 TTS 合成；BGM 默认自动生成，用户在提示词中指定
  曲风/参考音乐/静音时覆盖默认行为。
- 模板规则：输出遵循预设模板（片头/转场/字幕样式/结尾板式），模板 id 可在
  结构化输入中指定。

## 4. 数据模型（本 PR 落地）

`lib/features/plugins/builtin_plugin_catalog.dart`：

- `BuiltinPluginKind`：document / spreadsheet / presentation / image / video
- `BuiltinPluginStatus`：preview（脚手架）→ beta → stable
- `BuiltinPluginDescriptor`：id、双语名称与描述、图标、`outputFormats`、`requiredSkills`、`pipelineSteps`、`composerTemplate`
- `BuiltinPluginCatalog.firstBatch`：上述 5 个插件的静态描述符；`byId()` 查询

后续（M2）插件启用状态与自定义模板持久化进 `SettingsSnapshot`。

## 5. 里程碑

- **M1（本 PR）**：规划文档 + 目录/描述符 + 设置页「插件」标签页 + composer 插件入口（模板注入）+ 单元测试。desktop flag 为 stable 档，debug/profile/release 均默认开启；mobile/web 仍禁用。
- **M2**：插件启用状态持久化；文档/表格插件端到端打通（依赖 xworkspace-core-skills 的 docx/pdf/xlsx 技能包）；产物在 artifact 边栏归类展示。
- **M3**：PPT 流水线打通（image-svg-pptx-pro-skill + xiaobei-skill-image-to-vba，失败降级）；图片批量生成与网格预览；mobile/web 开放入口。
- **M4**：视频流水线（hyperframe / it-infra-evolution-video-v2 集成，预设模板 + 字幕口播 + BGM 覆盖）；插件市场化（第三方插件清单、安装管理）；flag 切 stable。

## 6. 风险与对策

- **技能包缺失**：Gateway 未安装对应技能包时，模板中要求执行端显式报告缺失项（沿用 skill picker 的「技能来源于 Gateway 工作区」提示语义）；设置页插件卡片展示依赖清单便于排查。
- **PPT 还原保真度**：双技能包互补（SVG 矢量优先，VBA 形状兜底），页级降级为图片占位。
- **release 构建污染**：desktop flag 已切 stable，随 release 构建默认开启（2026-07-04 决定）；若后续需要收紧，可随时回退 `release_tier` 到 `beta`。
- **移动端布局**：本批次不启用，避免 mobile settings else 分支误落入账号面板。

## 7. 测试

- `test/runtime/builtin_plugin_catalog_test.dart`：目录完整性（5 个插件、id 唯一、PPT/视频依赖技能包正确、模板非空）。
- `test/runtime/ui_feature_manifest_plugins_tab_test.dart`：desktop debug 暴露 plugins tab、release 隐藏、mobile 不暴露；`sanitizeSettingsTab` 回退正确。
- 手动回归：设置页 tab 切换不影响既有面板；composer 顶部按钮行溢出滚动正常。
