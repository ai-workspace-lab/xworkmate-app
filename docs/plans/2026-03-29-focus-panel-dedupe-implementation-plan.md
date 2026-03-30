# Focus Panel Dedupe Implementation Status

## 状态

已完成。

## 当前事实

- 共享实现唯一来源为：
  - `lib/widgets/assistant_focus_panel.dart`
  - `lib/widgets/assistant_focus_panel_core.dart`
  - `lib/widgets/assistant_focus_panel_previews.dart`
  - `lib/widgets/assistant_focus_panel_support.dart`
- Web 侧旧的 `web_focus_panel_core.dart`、`web_focus_panel_previews.dart`、`web_focus_panel_support.dart` 已不再存在。
- 本轮进一步移除了 `lib/web/web_focus_panel.dart` 这一层兼容导出，Web Assistant 侧不再保留旧入口。

## 验收关注点

- `test/widgets/assistant_focus_panel_suite.dart`
- `test/web/web_ui_browser_test.dart`
- Web Assistant 页面不再引用旧 Focus Panel 文件路径

## Residual Risks

- `SettingsPage` / `WebSettingsPage` 仍然是双容器实现，但公共壳层已共享
- Web Assistant 页面内部仍保留自己的页面分层，后续可继续评估是否值得继续收口
