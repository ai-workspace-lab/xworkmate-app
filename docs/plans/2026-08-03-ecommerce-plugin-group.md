# 电商插件分组：把「多参考图动态提示」做成插件能力

日期：2026-08-03
工作仓库：`ai-workspace-lab/xworkmate-app`
前置：`docs/plans/2026-07-04-builtin-plugins-batch-1.md`、`docs/plans/2026-08-02-platform-ops-actions-connector.md`
相关代码：`lib/features/plugins/builtin_plugin_input_slot.dart`（新增）、`builtin_plugin_catalog.dart`、`builtin_plugin_workflow.dart`

---

## 〇、结论先行

三个电商能力（头图、详情页、爆款视频复刻）落进插件目录，需要给插件模型补**两个维度**：

1. **分组轴** `BuiltinPluginGroup` —— 现有的 `BuiltinPluginKind` 是「产物类型」轴，装不下场景包。
2. **输入槽位** `BuiltinPluginInputSlot` —— 现有 workflow 只有一句自由文本输入，表达不了「这张图只取印花、那张图只取光影」。

第 2 条是本次的真正价值。没有它，「精细化多参考生图的动态提示工程」只是提示词里的一句措辞，
不构成插件能力，第四个电商插件仍然要从零写一遍提示词。

---

## 一、为什么现有模型装不下

### 1.1 产物类型轴装不下场景包

`BuiltinPluginKind` 的取值是 document / spreadsheet / presentation / image / video —— 它回答的是
**「产出什么文件」**。三个电商插件的产物分别是 image / image / video，在这条轴上与既有的「图片」
「视频」插件完全重合，无法区分。

场景包需要的是另一条正交的轴：**「这是给哪件事用的」**。因此新增 `BuiltinPluginGroup { general, ecommerce }`，
`firstBatch` 保持不动归入 `general`，新增 `ecommerceGroup`，`all = firstBatch + ecommerceGroup`。

`byId` 改为在 `all` 上查找；四个 UI 消费点（桌面 composer 菜单、设置插件面板、移动端对话快捷条、
移动端 composer 面板）改为按分组渲染。既有测试对 `firstBatch` 的断言全部不变。

### 1.2 自由文本输入表达不了参考图的角色

改造前，一个插件的全部输入是 `inputPromptZh` 这一句话。要表达「模特图只取姿态、印花图只取图案」，
只能写进 step 的 `instructionZh` 散文里。这有三个问题：

- **无法校验**：应用侧不知道哪些输入是必需的，用户少传一张图，直到生成失败才发现。
- **无法复用**：下一个电商插件要重新把同一段约束再抄一遍。
- **无法做表单**：composer 无从知道该让用户上传几张图、每张图是什么。

所以新增 `BuiltinPluginInputSlot`：

```dart
BuiltinPluginInputSlot(
  id: 'print',
  labelZh: '印花图案',
  type: BuiltinPluginSlotType.referenceImage,
  maxCount: 3,
  roleZh: '只取图案母题与循环单元，贴合到商品面料上并跟随褶皱与透视形变；'
          '不要把参考图本身画进画面',
)
```

四种槽位类型：`referenceImage` / `text` / `choice` / `url`。

**`roleZh` 是整个设计的重心。** 它不只说「这张图是印花参考」，还必须说清**不要带过来什么**。
多参考图生图最典型的失败就是参考图整体串味——模特参考把自己的衣服也带进来了、印花参考被
整张贴进画面。负向约束不写死，模型就会带。所以测试里有一条硬断言：所有参考图槽位的 `roleZh`
必须包含否定约束。

槽位在 `renderComposerTemplateZh()` 里渲染成一段带必填标记的清单，并附一句
「未提供的条目直接忽略，不要凭空补全」——防止模型给空槽位编造内容。

### 1.3 兼容性

`inputSlots` 是可选字段，schema 从 v2 升到 v3。v1/v2 manifest 解析出空槽位列表，
渲染结果与改造前逐字节相同。既有五个插件一个字未动。

---

## 二、三个插件的设计要点

### 2.1 电商头图

八个槽位：商品图（必填，最多 4 张）+ 模特 / 场景 / 光影 / 印花 / B 版配色 + 视角 / 画幅比例。

两个关键决策：

- **先出一张基准图再批量。** `base-shot` 步骤只生成一张，确认商品形态、光影、构图之后才展开
  多视角与多配色。多参考图生图的返工成本极高，一次性铺开 6 视角 × 4 配色 = 24 张，错了全废。
- **B 版配色只换色不改版。** 槽位的 `roleZh` 明确要求版型、构图、光影与 A 版严格一致。
  这是电商上架的硬要求——同款不同色必须看起来是同一件衣服。

### 2.2 商品详情页

**生图不画字。** 这是详情页最重要的一条，也是需求里「文字清晰」唯一能兑现的做法：

| 步骤 | 职责 | 约束 |
|---|---|---|
| `backdrops` | 生图产出产品与背景 | 画面内不允许出现任何文字、标签、水印 |
| `text-layer` | SVG 矢量层排版文字 | 文案逐字对应输入，不得改写 |
| `compose` | 合成 + 纵向拼接 | 全页固定 750px 宽，相邻模块底色对齐 |

理由：生图模型画中文长句的准确率不可控，且每次重生成文字都会变，做不了模版批量。矢量层方案
让文字 100% 可控、可复用、可批量。这与 PPT 插件已经验证过的思路一致
（`image-svg-pptx-pro-skill` 把图还原成可编辑元素），本次直接复用同一个技能包。

固定 750px 宽度是「多图拼接无违和」的前提——宽度不统一，拼接必然出现错位。

### 2.3 爆款视频复刻

槽位：源视频链接（url，必填）+ 商品图（必填）+ 开场钩子文案 + 目标时长。

步骤顺序被测试锁死：`ingest → beat-sheet → rewrite → frames → compose → compare`。
**理解必须先于生成**，否则就是照着标题瞎编。

两条合规约束写进提示词并被测试断言：

- 源视频**只复刻节奏结构、镜头语言与叙事顺序**，不得复制画面内容或音轨。
- 口播台词重写，不照搬原片；BGM 自动生成，不使用原片音轨。

`ingest` 步骤失败时降级为「要求用户直接上传视频文件」，而不是猜测——猜测产出的复刻是无价值的。

---

## 三、已知缺口

### 3.1 `video-understanding` 技能包不存在

爆款视频复刻的 `ingest` 步骤声明了 `requiredSkills: ['video-understanding']`，但这个技能包
**当前仓库里没有**。插件描述符可以先合入（`requiredSkills` 本来就是对 Gateway 侧的声明），
但在技能包落地前该插件跑不通。

需要的能力：拉取 TikTok / 抖音公开视频 → 抽帧 → 逐镜识别内容与镜头运动 → 输出带时间戳的结构化描述。
建议按 `2026-08-02` 那份文档的技能包形态在 Gateway 侧新建，不要写进 Dart。

### 3.2 槽位还没有表单 UI

本次只做到「声明 + 渲染进提示词」。composer 里还没有对应的上传表单，用户仍然靠手动附图 +
模板文字说明哪张是什么。表单 UI 是下一步：遍历 `plugin.inputSlots` 生成上传位，必填未填时禁用发送。

模型已经为此准备好了——`required` / `maxCount` / `choices` 都是给表单用的，现在只是没人读。

### 3.3 没有扇出语义

「多视角生图」「B 版配色批量」目前靠 step 的 `instructionZh` 文字描述让 Gateway 自己循环，
workflow 模型本身仍是严格线性单产物。真正的批量应当是 step 上的 `fanOut`（按某个 choice
槽位的取值展开），让 `BuiltinPluginWorkflowRun` 能逐个跟踪、失败只重试单个而不是整批。

这一项影响的是**可观测性与重试粒度**，不影响功能可用性，可以延后。

---

## 四、验收

```bash
flutter analyze
flutter test test/runtime/builtin_plugin_ecommerce_group_test.dart
flutter test   # 既有插件测试须全绿且未修改断言
```

新增测试覆盖：分组轴与产物轴正交、`byId` 跨组解析、槽位唯一性与必填性、负向约束存在性、
槽位渲染进模板、choice 取值渲染、无槽位插件渲染不变、v3 JSON 往返、v2 manifest 向下兼容、
详情页文字层顺序、视频复刻步骤顺序与合规约束。

---

## 五、后续插件接入成本

分组与槽位就位后，新增第四个电商插件（如「场景图批量换背景」）只需要：

1. 在 `ecommerceGroup` 加一个 `BuiltinPluginDescriptor`；
2. 声明自己的槽位与步骤。

不需要动注册表以外的任何公共代码，也不需要碰 UI。**如果需要改到公共代码，说明槽位类型没抽够，
应当回到 §1.2 补类型，而不是在插件里开特例。**
