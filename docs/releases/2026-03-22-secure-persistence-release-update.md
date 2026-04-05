# 2026-03-22 Secure Persistence Release Update

## 摘要

这次补丁修复的是一个发版级问题：

- `XWorkmate.app` 在某些机器上重启后会丢失本地 Gateway 配置和已保存凭证
- Assistant 本地任务线程和恢复快照的持久化链路存在明文残留和竞态风险

本次发布不改 UI，只修正持久层与恢复链路。

## 用户可感知变化

### 1. 重启后本地配置不应再消失

修复后：

- Gateway host / port / TLS 等本地配置继续恢复
- 已保存的 shared token / password 不再因为一次 secure storage 超时而只留在内存里

### 2. 覆盖安装后本地状态仍应保留

修复后：

- `/Applications/XWorkmate.app` 覆盖安装不会清掉本地配置和任务会话
- Assistant 最后活动线程与消息历史应继续可恢复

### 3. 本地快照不再明文持久化

修复后：

- `SettingsSnapshot`
- Assistant thread records
- `assistant-state-backup.json`

都改为 sealed local state，而不是明文 JSON/SQLite。

## 核心修复点

- `SecureConfigStore` 的 secure storage 超时从 `400ms` 调整到 `5s`
- secure storage 超时/异常时，secret 改为 durable fallback，而不是“只存内存”
- 本地配置与任务线程统一做 AES-GCM sealed persistence
- `assistant-state-backup.json` 升级为 schema v2，使用 `sealedState`
- legacy plaintext prefs / local-state key fallback 增加迁移与清理
- Assistant 线程持久化改为串行队列，避免异步晚到覆盖新状态

## 自动化验收

已执行结果：

- `flutter analyze`：通过
- `flutter test`：未作为整套 baseline 通过，当前在 `test/features/ai_gateway_page_test.dart` 的 `Settings external agents detail shows Codex bridge runtime states` case 后挂住，未产生断言失败，但进程不退出
- `flutter test test/runtime/secure_config_store_test.dart test/runtime/app_controller_execution_target_switch_test.dart test/runtime/app_controller_ai_gateway_chat_test.dart test/features/settings_ai_gateway_persistence_test.dart test/runtime/app_controller_gateway_token_state_test.dart`：通过
- `flutter test integration_test/desktop_navigation_flow_test.dart -d macos`：通过
- `flutter test integration_test/desktop_settings_flow_test.dart -d macos`：通过
- `flutter build macos --release`：通过
- `flutter build ios --simulator`：通过
- `make install-mac`：通过

补充说明：

- 两个 macOS integration 都出现 `Failed to foreground app; open returned 1`，但设备跑断言本身通过，输出包含 `All tests passed!`
- 当前未把挂住的 `ai_gateway_page_test` 假定为通过；它被保留为现有测试阻塞项

## 当前机器实机复测

已在当前机器完成两轮宿主级复测。

第一轮，重启恢复：

1. 配置本地 Gateway
2. 退出 App
3. 重新打开确认配置和任务会话仍在

第二轮，覆盖安装恢复：

1. 再次执行 `make install-mac`
2. 重新打开 `/Applications/XWorkmate.app`
3. 复查本地状态持久化产物

结果：

- `/Applications/XWorkmate.app` 可正常重新打开
- 本地 SQLite 状态仍为 sealed payload，没有回退成明文
- `assistant-state-backup.json` 仍为 `schemaVersion = 2` 且包含 `sealedState`
- legacy `SharedPreferences` 中的 `flutter.xworkmate.settings.snapshot` 在新版 App 启动后一轮迁移后被清理
- `gateway-auth/` 目录下未再残留 `local-state-key.txt`
- 第二次覆盖安装后，上述状态保持不变

## 宿主级检查

需要确认：

- `config-store.sqlite3` 中的本地状态是 sealed payload，而不是明文 JSON
- `assistant-state-backup.json` 为 schema v2 且包含 `sealedState`
- `settings-snapshot.json` / `assistant-threads.json` 如果存在，内容也应为 sealed payload
- 不出现明文 token / password
- 旧版 `local-state-key.txt` 若存在，应完成一次迁移并被清理

当前机器检查结果：

- `config-store.sqlite3`：通过
- `assistant-state-backup.json`：通过
- `settings-snapshot.json` / `assistant-threads.json`：存在且为 sealed payload
- 明文 `token/password`：未发现
- `local-state-key.txt`：未发现，说明旧文件已迁移并清理

## 兼容与边界

- `.env` 仍然只是 Settings -> Integrations -> Gateway 的预填来源，不会变成持久化真值源
- 用户发起连接时，仍然使用当前表单值做即时握手，不依赖 secure-store 回读
- UI 布局不变，只修改持久化和恢复逻辑

## 相关文档

- [Secure Local Persistence Architecture](../architecture/secure-local-persistence-architecture.md)
