# 04. 设计系统规范（MacOS AI Workspace 基准）

## 1. 设计目标

这套设计系统以当前 XWorkmate macOS APP UI 为主基准，并吸收 Notion 与 Linear 的两类优点：

- Notion 的平静、中性、低打扰信息组织
- Linear 的紧凑、精准、状态清晰、专业工具感

但本系统不直接复制两者，而是服务于“MacOS 风格 AI 工作台”：

- 更强调线程、Agent、连接、结果渲染等工作流对象
- 更强调长时间停留的低疲劳阅读体验
- 更强调分栏、底部 dock、快捷面板、系统设置等桌面工作台语义

因此，这套视觉语言应满足三个目标：

- Calm：低噪音、可持续停留
- Compact：适合高密度工作区
- Tactile：按钮、面板、sheet 都要有轻微但明确的可操作反馈

## 2. 视觉基调

### A. 总体风格

建议定义为：

- calm compact workspace
- border-first 但不过度描边
- 系统字体优先
- 低饱和中性色 + 单一品牌蓝强调
- 光感和层级主要依靠 tonal layering，而不是高对比色块

### B. 气质关键词

- 安静
- 精准
- 专业
- 编辑式
- 工具化
- 长时工作友好

### C. 使用规则

- 主色只用于主 CTA、选中态、关键状态，不大面积铺底
- 层级优先靠 spacing、字号、权重、surface tone 建立
- 大部分卡片使用 ghost border + soft shadow，而不是强边框
- Web 与 macOS 使用同一套语言，只调整密度，不切换视觉流派

## 3. 颜色体系

## Light Theme

### A. Background

- App Background: `#F8F9FA`
- Workspace Chrome Background: `#F4F7FA`
- Sidebar Background: `#F1F4F8`
- Inset Background: `#EFF3F7`

### B. Surface

- Primary Surface: `#FFFFFF`
- Secondary Surface: `#F2F5F8`
- Tertiary Surface: `#E9EEF4`
- Pressed Surface: `#F1F5F9`
- Highlight Surface: `#FFFFFF`

### C. Text

- Text Primary: `#1C1B1F`
- Text Secondary: `#667085`
- Text Muted: `#98A1B2`
- Text Inverse: `#FFFFFF`

### D. Accent

- Accent Primary: `#0058BD`
- Accent Hover: `#1A6CCE`
- Accent Soft: `#E8F0FB`
- Accent Strong Fill: `#0058BD`

### E. Semantic

- Success: `#34A853`
- Warning: `#8F4A00`
- Danger: `#C3655C`
- Idle: `#98A1B2`
- Info Banner Tint: `#EEF4FB`
- Warning Banner Tint: `#FFF3CD`
- Error Banner Tint: `#FBEDEC`

### F. Border

- Default Border: `rgba(166, 180, 200, 0.20)`
- Soft Border: `rgba(166, 180, 200, 0.15)`
- Strong Border: `rgba(166, 180, 200, 0.32)`

## Dark Theme

### A. Background

- App Background: `#141422`
- Workspace Chrome Background: `#161A26`
- Sidebar Background: `#1A1D2A`
- Inset Background: `#1A1F2C`

### B. Surface

- Primary Surface: `#171C28`
- Secondary Surface: `#1E2433`
- Tertiary Surface: `#262D3F`
- Pressed Surface: `#23293A`
- Highlight Surface: `#2A3145`

### C. Text

- Text Primary: `#E6E1E5`
- Text Secondary: `#B0B8C8`
- Text Muted: `#8B95A8`
- Text Inverse: `#0F1117`

### D. Accent

- Accent Primary: `#4B8FE8`
- Accent Hover: `#78AFFF`
- Accent Soft: `#1C3355`
- Accent Strong Fill: `#4B8FE8`

### E. Semantic

- Success: `#5CB978`
- Warning: `#E0AE5A`
- Danger: `#EF9A9A`
- Idle: `#8B95A8`
- Info Banner Tint: `#1B2940`
- Warning Banner Tint: `#3A3118`
- Error Banner Tint: `#3A2527`

### F. Border

- Default Border: `rgba(202, 196, 208, 0.22)`
- Soft Border: `rgba(202, 196, 208, 0.15)`
- Strong Border: `rgba(202, 196, 208, 0.30)`

## 4. Spacing / Radius / Shadow

## A. Spacing

建议继续沿用当前家族的紧凑节奏：

- 4: micro gap
- 6: compact gap
- 8: standard gap
- 12: section inner gap
- 16: card inner padding / block gap
- 20: pane padding
- 24: page section gap
- 32: large layout gap

使用规则：

- 控件之间优先 `6` 或 `8`
- 卡片内部优先 `12` 或 `16`
- 大模块之间优先 `24`
- 页面级横向 padding 建议 `20` 到 `24`

## B. Radius

基于 MacOS 工作台语义，保持柔和但不臃肿：

- Card Radius: `16`
- Panel Radius: `18`
- Sidebar Radius: `20`
- Button Radius: `12`
- Icon Button Radius: `12`
- Input Radius: `14`
- Chip Radius: `12`
- Bottom Sheet Radius: `18`
- Badge Radius: `999`

Web 紧凑版本可收紧，但不建议低于：

- card `12`
- input `10`
- button `10`

## C. Shadow

阴影必须是“柔和、带轻微蓝灰偏色”的工作台阴影，而不是通用黑灰阴影。

### Light

- Ambient Shadow: `0 12 40 -14 rgba(0, 88, 189, 0.08)`
- Lift Shadow: `0 10 24 -12 rgba(0, 88, 189, 0.10)`

### Dark

- Ambient Shadow: `0 12 36 -14 rgba(0, 8, 20, 0.30)`
- Lift Shadow: `0 8 22 -12 rgba(0, 88, 189, 0.28)`

使用规则：

- 卡片默认只用 ambient
- 可点击卡片 hover 时追加 lift
- sidebar 与 sheet 使用更柔和、更大范围的阴影，不用锐利投影

## 5. Typography

## A. 字体策略

优先使用系统字体：

- macOS / iOS: SF Pro
- Web: `system-ui`, `-apple-system`, sans-serif
- Monospace: 系统等宽字体，仅用于 token、ID、日志、endpoint

不引入自定义 UI 字体。

## B. 字号体系

### Workspace Display

- 28 / 32 / 700
- 用于少量登录、欢迎、全屏态标题

### Dialog Title

- 20 / 24 / 600
- 用于弹窗与设置大卡标题

### Section Title

- 13 / 14 / 600
- 用于工作区 section、侧栏分组、卡片标题

### Body

- 13 / 15 / 400
- 默认正文

### Emphasized Body

- 13 / 14 / 600
- 重要标签、按钮文字、关键值

### Caption

- 12 / 16 / 400
- 辅助文字、meta、时间、helper text

### Caption Strong

- 12 / 16 / 600
- 状态标签、breadcrumb、chip 文案

## C. 字体使用规则

- 不在工作区内使用大而营销化的 hero heading
- 大部分文字应保持在 12 到 13 范围
- 主要层级靠字重与间距，而不是大字号跳跃
- 线程标题、卡片标题、section 标题允许 600，不建议更重
- 技术值、endpoint、token key 才使用 monospace

## 6. 核心组件规范

## A. Card

适用：摘要卡、设置卡、Focus 卡、任务卡。

规则：

- 默认使用 primary 或 secondary surface
- 带 soft border
- 16 圆角
- 内边距 16
- hover 只抬升一点，不做明显放大
- 选中态优先用 accent soft 背景 + 轻描边，不直接大面积纯蓝铺底

## B. Panel

适用：线程栏、Focus pane、设置大面板、详情面板。

规则：

- 比 card 更强调容器感
- panel 内允许嵌套 card，但 panel 自身应更克制
- 通常使用 chrome background 或 secondary surface
- 应具备清晰的 header / content / footer 区域
- 在桌面大屏中应优先承担结构层级，而非视觉重点

## C. Sidebar

适用：主导航、Focus 左侧面板、线程导航区域。

规则：

- 使用 sidebar background
- 分组信息采用 caption strong
- 导航项高度建议 32 到 36
- 选中项使用 accent soft + subtle border
- 收藏/星标属于辅助交互，不要抢主导航焦点
- collapse 后仍要保留清晰的 icon-only 语义

## D. Button

### Primary Button

- 用于主行动作，如发送、应用、创建
- 使用 accent fill
- 白字
- hover 稍微变亮
- active 稍微压暗并减小阴影

### Secondary Button

- 用于次级动作，如保存、测试、打开详情
- 使用 secondary surface 或 ghost border
- 文字保持 primary text

### Tertiary / Ghost Button

- 用于工具栏、icon action、内嵌操作
- 背景默认透明
- hover 出现 secondary surface

### 尺寸建议

- Desktop utility button height: `30`
- Toolbar / input-affiliated button: `30` 到 `32`
- 大型单独 CTA 不建议超过 `36`

## E. Input

适用：搜索、配置输入、endpoint 输入、composer 之外的表单输入。

规则：

- 高度默认 40
- 圆角 14
- 背景用 primary surface
- 边框默认 soft border
- focus 使用 accent border + very soft glow
- placeholder 使用 muted text
- helper / error text 使用 caption

### Search Input

- 左侧 icon 固定
- hover 只提升表面亮度，不改变布局
- 不做过重投影

### Composer Input

- 作为特殊输入容器，不完全套用普通 input
- 更像 bottom dock panel
- 应支持更大高度、附件、模式切换、发送动作

## 7. 交互状态规范

## A. Hover

目标：给出触感，而不是制造噪音。

规则：

- surface 稍微提亮或切到 pressed surface
- 阴影轻微增强
- icon 与文字颜色不剧烈变化
- 不使用明显 scale 动画

## B. Active / Pressed

规则：

- 背景比 hover 更实一点
- 阴影减弱，模拟按下
- 主按钮允许稍微压暗
- 卡片点击态优先表现为“压下”，而不是“发光”

## C. Selected

规则：

- 优先使用 accent soft background
- 边框轻微增强
- 文字使用 emphasized body 或 accent text
- 不建议用纯色大面积填充，除非是 primary CTA

## D. Disabled

规则：

- 背景不应完全消失，应保留轮廓
- 文字降到 muted
- border 保持 soft
- 对可用区域和不可用区域保持几何一致，避免跳版

## E. Focus

规则：

- 键盘 focus 必须有清晰 focus ring
- focus ring 使用 accent，并保持较低扩散半径
- sidebar item、button、input、chip 都要支持 focus state

## 8. 组件状态矩阵建议

以下组件必须具备完整状态：

- button: default / hover / active / disabled / focus
- input: default / hover / focus / error / disabled
- card: default / hover / selected / disabled
- sidebar item: default / hover / selected / focus
- chip: default / hover / selected / disabled
- panel: default / pinned / collapsed / active

## 9. 与当前产品的对应关系

这套设计系统应直接映射到当前 XWorkmate 家族 token：

- 颜色基于现有 `AppPalette.light` / `AppPalette.dark`
- spacing / radius / typography 基于现有 `SimpleSpacing`、`SimpleRadius`、`SimpleTypography`
- Web 版本采用同一家族语言，但在高密度区域可轻微收紧几何

因此，后续实现建议遵循：

- 不重新发明一套 Web token
- 先让 Web 继承 macOS 家族 token，再在 shell、sidebar、input、tabs、sheet 上做 Web 密度微调
- 任何 Notion / Linear 风格借鉴，都应服务于现有产品家族，而不是覆盖现有品牌语言

## 10. 一句话结论

这套设计系统的最终目标，不是把 XWorkmate 做成“像某个 SaaS 后台”，而是把它做成：

- 具有 MacOS 原生工作台气质
- 适合长时间停留
- 适合高密度 AI 任务调度
- 视觉克制但交互明确
- Web 与 macOS 同源而不割裂
