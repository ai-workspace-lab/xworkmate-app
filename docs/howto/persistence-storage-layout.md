# Persistence Storage Layout

## 目标

本文定义桌面端持久化层的唯一落地规则。`XWorkmate.svc.plus` 后续必须只认这一套目录和文件约定，不再引入 SQLite、本地 secret fallback、或第二套临时持久化路径。

## 存储原则

- 非敏感配置只写 `settings.yaml`
- 任务线程会话按 `sessionKey` 单文件保存
- 敏感信息只写固定 `secret path`
- 首次启动必须自动建目录
- 重启和升级不能主动删除配置或会话文件
- 文件写入使用临时文件后替换的原子写策略
- 磁盘路径不可用时，只允许退回内存，不再切换到另一套本地 fallback 持久化

## 默认目录结构

默认根目录位于应用支持目录下的 `xworkmate` 子目录。

macOS 示例：

```text
~/Library/Application Support/<App Support>/xworkmate/
```

运行时布局：

```text
xworkmate/
  config/
    settings.yaml
    secret-audit.json
  tasks/
    index.json
    <sessionKey-encoded>.json
  secrets/
    <key-encoded>.secret
```

## 文件职责

### `config/settings.yaml`

- 唯一非敏感配置源
- 内容对应 `SettingsSnapshot.toJson()`
- 不保存 token、password、API key、device private key 等敏感字段

### `config/secret-audit.json`

- 保存 `SecretAuditEntry` 列表
- 属于本地非敏感审计信息
- 最大长度由运行时控制

### `tasks/index.json`

- 保存线程会话顺序
- 当前格式：

```json
{
  "version": 1,
  "sessions": ["session-a", "session-b"]
}
```

### `tasks/<sessionKey-encoded>.json`

- 每个线程会话一个文件
- 文件内容为 `AssistantThreadRecord.toJson()`
- 文件名不直接使用原始 `sessionKey`，而是稳定编码后的结果，避免跨平台文件名问题
- 记录内容里的 `sessionKey` 仍保持原值，不修改模型

### `secrets/<key-encoded>.secret`

- 固定 secret path
- 每个 secret key 一个文件
- 保存 Gateway token、Gateway password、AI Gateway API key、Vault token、device identity、device token 等敏感信息
- 文件名使用稳定编码，避免泄露原始 key 名并规避非法字符

## 初始化规则

- `SecureConfigStore.initialize()` 必须先准备目录结构
- 不要求用户先保存一次配置，目录应在首次运行时就存在
- 如果外部显式传入测试路径覆盖，仍然遵守相同布局

## 清理规则

- `clearAssistantLocalState()` 只清理：
  - `settings.yaml`
  - `tasks/index.json`
  - `tasks/*.json`
- 不清理 `secrets/*.secret`
- 不主动清理 `secret-audit.json`

## 恢复规则

- 启动时先读 `settings.yaml`
- 再读 `tasks/index.json` 与对应 task 文件
- `index.json` 缺失时，允许扫描 `tasks/*.json` 进行恢复
- `secret path` 中某个 key 缺失时，只影响该 key，不应拖垮整个 store

## 禁止事项

- 禁止重新引入 SQLite 作为桌面持久化主存储
- 禁止把 secret 写入 `SharedPreferences`
- 禁止把 `.env` 自动导入为持久化配置
- 禁止在 secret path 不可用时偷偷切换到另一套磁盘 fallback 路径
- 禁止在升级或启动时主动删除已有配置与会话文件

## 测试建议

- 验证首次启动自动建目录
- 验证重启后 `settings.yaml` 可恢复
- 验证 `tasks/<session>.json` 跨实例可恢复
- 验证 `clearAssistantLocalState()` 不删 secrets
- 验证磁盘不可用时保留内存态，不发生崩溃
