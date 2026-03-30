# XWorkmate Web UI 规划索引

更新时间：2026-03-24

## 目标

本文档集以当前已完善的 macOS APP UI 为基准，为 Flutter Web 版本建立长期可维护的前端信息架构与目录组织方案。

目标不是一次性把截图翻译成页面，而是明确：

- Web 端应该对齐哪些桌面基准能力
- 哪些能力属于壳层、页面层、模块层、组件层
- 哪些状态应当全局持有，哪些状态应当局部封装
- Flutter Web 代码目录应当如何组织，才能支撑持续迭代
- 组件与模块应如何复用，避免 Assistant / Settings / Focus 等区域重复造轮子

## 基准来源

本文档以当前桌面实现的以下结构为基准，而不是以历史 Web 简化版为基准：

- `lib/app/app_shell_desktop.dart`
- `lib/app/workspace_page_registry.dart`
- `lib/widgets/sidebar_navigation.dart`
- `lib/widgets/assistant_focus_panel.dart`
- `lib/features/settings/settings_page.dart`
- `lib/widgets/desktop_workspace_scaffold.dart`
- `lib/widgets/section_tabs.dart`

## 文档列表

- `01-information-architecture-and-pages.md`
  - 整体信息架构
  - 页面域划分
  - Assistant / Settings / Focus 的职责边界
- `02-layout-modules-components-and-state.md`
  - Layout / modules / components 分层
  - 全局状态、路由状态、局部状态划分
  - 状态边界与维护规则
- `03-flutter-web-directory-and-reuse-strategy.md`
  - Flutter Web 目录设计
  - feature-first 组织方式
  - 组件、模块、状态机复用策略
- `04-design-system-spec.md`
  - light / dark 颜色体系
  - spacing / radius / shadow / typography
  - card / panel / sidebar / button / input 规范
  - hover / active / disabled 等状态规则

## 规划原则

- Web 不是桌面版的缩略图，而是桌面工作台在浏览器中的平台化裁剪。
- 产品语义先对齐桌面基准，再决定 Web 的能力裁剪。
- Assistant 是执行平面；Settings 是控制平面；Focus 是快捷聚合层；资源域是能力资产层。
- 页面文件保持轻，模块承接业务交互，组件尽量保持纯展示。
- Save / Apply、线程会话、连接状态、Focus 入口等交互语义必须跨页面复用，不能散落重写。
