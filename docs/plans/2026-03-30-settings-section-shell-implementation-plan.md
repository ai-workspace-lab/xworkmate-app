# Settings Section Shell Implementation Status

## 状态

已完成公共壳层收口。

## 当前共享层

Desktop 与 Web 设置页当前共用以下结构层：

- `lib/widgets/settings_page_shell.dart`
  - `SettingsPageBodyShell`
  - `SettingsGlobalApplyCard`
  - `buildOrderedSettingsSections`

这意味着两端已经统一：

- 顶部 `TopBar` 承载方式
- 全局 apply bar 结构
- overview section 的排序装配方式

## 当前仍保留的平台差异

- Desktop：`lib/features/settings/settings_page_core.dart`
  - 持有 detail flow、navigation context、gateway profile hints
- Web：`lib/web/web_settings_page_core.dart`
  - 持有浏览器 persistence、Web gateway 子页和 Web 专属 copy

## 结论

第二批不再需要重复执行“抽共享壳层”本身。后续如继续清理，应只处理：

- Web / Desktop 剩余的业务 section 重复
- 已无价值的旧路径引用
- 测试和文档守护的一致性
