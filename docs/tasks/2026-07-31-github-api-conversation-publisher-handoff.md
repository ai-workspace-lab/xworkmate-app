# GitHub API 对话发布连接器交接记录

更新时间：2026-07-31  
当前分支：`main`  
最近提交：`85f5fd2 feat: add GitHub API conversation publisher`

## 目标

为 XWorkmate 增加 GitHub 仓库连接器，优先支持商店版：使用 GitHub HTTPS REST API 发布对话 Markdown，不启动本机 `git`、`ssh` 或其他外部进程。

## 已完成

1. 设置 → 连接器中新增“GitHub 仓库（API）”卡片。
2. 点击“连接”后展示交互表单：
   - GitHub 仓库（支持 `owner/repository`、GitHub HTTPS URL、GitHub SSH URL 作为标识输入）。
   - Fine-grained token（密码输入框）。
   - 分支。
   - 对话发布目录。
3. “验证连接”调用 `GET /repos/{owner}/{repo}`，只通过 HTTPS 请求 GitHub。
4. 新增 `publishConversationToGitHub()`，通过 `PUT /repos/{owner}/{repo}/contents/{path}` 创建 Markdown 文件。
5. Token 只从当前表单请求传入，不打印、不写日志；当前尚未做持久化。
6. `config/feature_flags.yaml` 增加 `desktop.settings.github_repository`，并接入 UI feature manifest。
7. 移除“本地工作空间默认已连接”的伪状态；本地/自托管工作空间仍必须显式连接。

## 关键文件

- `lib/features/settings/settings_account_panel.dart`：连接器卡片与表单。
- `lib/features/settings/local_git_repository_connection.dart`：GitHub 仓库解析、连接验证、Contents API 发布。
- `lib/features/settings/settings_page_core.dart`：将 feature flag 传入连接器页面。
- `lib/app/ui_feature_manifest_core.dart`：`settings.github_repository` 能力。
- `config/feature_flags.yaml`：桌面版连接器开关。
- `test/features/settings/local_git_repository_connection_test.dart`：HTTP 请求和 Markdown 编码测试。
- `test/app/app_store_policy_test.dart`：确认 Apple App Store 策略下 GitHub API 连接器可用。

## 验证记录

- `flutter test test/features/settings/settings_account_panel_test.dart test/features/settings/local_git_repository_connection_test.dart test/app/app_store_policy_test.dart`：通过（14 tests）。
- `flutter analyze`：通过，无 issue。
- `git diff --check`：通过。
- `flutter test` 全量执行时，仓库已有的 mobile golden/page 测试出现失败（找不到 `mobile-assistant-page` 等 key）；该失败与本次 GitHub API 文件无直接调用关系，后续 agent 需要单独确认基线或测试环境。

## 安全与上架边界

- 当前实现不使用 `dart:io Process`，不执行 shell，不读取 SSH 私钥。
- macOS Release entitlement 已有 `com.apple.security.network.client`，GitHub HTTPS 请求可复用该能力；未新增 entitlement。
- GitHub token 应使用 Fine-grained token，最小授权为目标仓库的 `Contents: write`。
- 不要把 token 放入 `SettingsSnapshot`、SharedPreferences、普通日志或任务 Markdown。

## 待完成（下一位 code agent）

1. 将 `publishConversationToGitHub()` 接到对话页面的“发布/分享”入口，生成稳定的 Markdown 文件名和正文。
2. 将 token 通过现有 `SecretStore`/Keychain 持久化，设置页面只展示脱敏状态；连接动作可以使用当前表单值即时验证。
3. 更新已有文件时先 `GET /contents/{path}?ref={branch}` 取得 `sha`，再将 `sha` 放入 PUT body；当前实现只覆盖新文件创建路径。
4. 增加网络错误、401/403、分支不存在、仓库不存在、重复文件更新的 UI 回归测试。
5. 在 App Store profile/release 构建中验证：仅使用 HTTPS API，不出现 Git/SSH 子进程路径。

## 交接原则

所有后续修改都应先更新本文件的“已完成/待完成/验证记录”，再提交代码，确保多个 code agent 能从同一份文档恢复上下文。
